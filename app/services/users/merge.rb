module Users
  class Merge
    def self.call(source:, target:)
      new(source: source, target: target).call
    end

    def initialize(source:, target:)
      @source = source
      @target = target
    end

    def call
      validate!
      affected_modes = affected_match_modes

      User.transaction do
        merge_profile!
        transfer_owned_records!
        transfer_participations!
        transfer_favorite_courts!
        transfer_court_suggestions!
        transfer_tournament_participations!
        transfer_player_statistic_entries!
        transfer_matches!
        merge_player_statistics!
        archive_source!
      end

      RecalculateEloJob.perform_later(affected_modes) if affected_modes.any?
      target.reload
    end

    private

    attr_reader :source, :target

    def validate!
      raise ArgumentError, "source and target must differ" if source.id == target.id
      raise ArgumentError, "source must be a Telegram-generated account" unless source.telegram_generated_email?
      raise ArgumentError, "source was already merged" if source.merged_at.present?
    end

    def merge_profile!
      attributes = {}
      %i[name city_name about_me court_preferences_note skill_level timezone telegram_locale telegram_username].each do |field|
        source_value = source.public_send(field)
        attributes[field] = source_value if target.public_send(field).blank? && source_value.present?
      end
      attributes[:preferred_sports] = (target.preferred_sports.to_a + source.preferred_sports.to_a).uniq
      attributes[:skill_levels] = source.skill_levels.to_h.merge(target.skill_levels.to_h)
      attributes[:notify_nearby] = target.notify_nearby? || source.notify_nearby?
      attributes[:coach] = target.coach? || source.coach?
      target.update!(attributes)
    end

    def transfer_owned_records!
      Game.where(user_id: source.id).update_all(user_id: target.id)
      Court.where(user_id: source.id).update_all(user_id: target.id)
      Tournament.where(user_id: source.id).update_all(user_id: target.id)
      Prebooking.where(user_id: source.id).update_all(user_id: target.id)
      PrebookingCancellation.where(user_id: source.id).update_all(user_id: target.id)
    end

    def transfer_participations!
      Participation.where(user_id: source.id).find_each do |participation|
        existing = Participation.find_by(user_id: target.id, game_id: participation.game_id)
        if existing
          existing.update_columns(status: "approved", approved_at: participation.approved_at || Time.current) if participation.approved? && !existing.approved?
          participation.destroy!
        else
          participation.update_columns(user_id: target.id)
        end
      end
    end

    def transfer_favorite_courts!
      FavoriteCourt.where(user_id: source.id).find_each do |favorite|
        if FavoriteCourt.exists?(user_id: target.id, court_id: favorite.court_id)
          favorite.destroy!
        else
          favorite.update_columns(user_id: target.id)
        end
      end
    end

    def transfer_court_suggestions!
      CourtSuggestion.where(reviewed_by_id: source.id).update_all(reviewed_by_id: target.id)
      CourtSuggestion.where(user_id: source.id).find_each do |suggestion|
        conflict = suggestion.status == "pending" &&
          CourtSuggestion.exists?(user_id: target.id, court_id: suggestion.court_id, status: "pending")
        conflict ? suggestion.destroy! : suggestion.update_columns(user_id: target.id)
      end
    end

    def transfer_tournament_participations!
      TournamentParticipant.where(user_id: source.id).find_each do |participant|
        existing = TournamentParticipant.find_by(user_id: target.id, tournament_id: participant.tournament_id)
        if existing
          existing.update_columns(status: "approved") if participant.status == "approved"
          participant.destroy!
        else
          participant.update_columns(user_id: target.id)
        end
      end
    end

    def transfer_player_statistic_entries!
      PlayerStatisticEntry.where(actor_id: source.id).update_all(actor_id: target.id)

      PlayerStatisticEntry.where(user_id: source.id).find_each do |entry|
        existing = PlayerStatisticEntry.find_by(user_id: target.id, game_id: entry.game_id, source: entry.source)
        if existing
          if entry.recorded_at > existing.recorded_at
            existing.update_columns(actor_id: entry.actor_id, data: entry.data, recorded_at: entry.recorded_at, updated_at: Time.current)
          end
          entry.destroy!
        else
          entry.update_columns(user_id: target.id)
        end
      end
    end

    def transfer_matches!
      Match.where(user_id: source.id, opponent_id: target.id)
        .or(Match.where(user_id: target.id, opponent_id: source.id))
        .delete_all
      Match.where(user_id: source.id).update_all(user_id: target.id)
      Match.where(opponent_id: source.id).update_all(opponent_id: target.id)
      %i[player_a_id player_a2_id player_b_id player_b2_id].each do |column|
        TournamentMatch.where(column => source.id).update_all(column => target.id)
      end
    end

    def affected_match_modes
      Match.where(user_id: source.id)
        .or(Match.where(opponent_id: source.id))
        .distinct
        .pluck(:mode)
    end

    def merge_player_statistics!
      source_stats = source.player_statistic
      return unless source_stats

      target_stats = target.player_statistic || target.create_player_statistic!
      sums = PlayerStatistic::RESET_TO_ZERO_COLUMNS.index_with do |column|
        target_stats.public_send(column).to_f + source_stats.public_send(column).to_f
      end
      sums.each do |column, value|
        sums[column] = value.to_i if PlayerStatistic.type_for_attribute(column.to_s).type == :integer
      end
      sums[:first_serve_percent] = target_stats.first_serve_percent || source_stats.first_serve_percent
      sums[:stats_reset_at] = [ target_stats.stats_reset_at, source_stats.stats_reset_at ].compact.max
      target_stats.update!(sums)
    end

    def archive_source!
      source.update_columns(
        email: "merged-#{source.id}-#{SecureRandom.hex(6)}@telegram.getcourt",
        telegram_chat_id: nil,
        telegram_username: nil,
        telegram_registration_token: nil,
        login_code: nil,
        login_code_sent_at: nil,
        login_via: nil,
        notification_channel: "email",
        notify_nearby: false,
        merged_into_id: target.id,
        merged_at: Time.current,
        updated_at: Time.current
      )
    end
  end
end
