module PlayerStatistics
  class ApplyEntryService
    def initialize(user:, game:, actor:, data:, source: "telegram", recorded_at: Time.current)
      @user = user
      @game = game
      @actor = actor
      @data = (data || {}).stringify_keys # важно: nil значения тоже сохраняем как намерение "удалить"
      @source = source.to_s
      @recorded_at = recorded_at
    end

    def call
      allowed = StatisticsPresenter.allowed_keys
      patch = @data.slice(*allowed) # НЕ compact — nil нужен, чтобы уметь "снимать" значение

      PlayerStatisticEntry.transaction do
        entry = find_or_init_entry
        stale = stale_entry?(entry)
        old_data = if entry.persisted? && !stale
          (entry.data || {}).stringify_keys
        else
          {}
        end
        new_data = old_data.merge(patch)
        new_data.delete_if { |_k, v| v.nil? } # nil = удалить ключ из source of truth

        entry.actor = @actor
        entry.data = new_data
        entry.recorded_at = stale ? [ @recorded_at, last_reset_time ].compact.max : @recorded_at
        entry.save!

        ps = @user.player_statistic || @user.create_player_statistic

        ps.with_lock do
          allowed.each do |key|
            old_v = old_data[key]
            new_v = new_data[key]
            next if old_v == new_v

            if PlayerStatistic.numeric_field_type(key) == :float
              delta = new_v.to_f - old_v.to_f
              ps[key] = (ps[key] || 0).to_f + delta
            else
              delta = new_v.to_i - old_v.to_i
              ps[key] = (ps[key] || 0).to_i + delta
            end
          end

          ps.save!
        end

        entry
      end
    end

    private

    def find_or_init_entry
      PlayerStatisticEntry.lock
        .find_or_initialize_by(user: @user, game: @game, source: @source)
    end

    def stale_entry?(entry)
      lr = last_reset_time
      lr.present? && entry.recorded_at.present? && entry.recorded_at < lr
    end

    def last_reset_time
      @last_reset_time ||= [
        (@game.current_cycle_start if @game.respond_to?(:current_cycle_start)),
        @user.player_statistic&.stats_reset_at
      ].compact.max
    end
  end
end
