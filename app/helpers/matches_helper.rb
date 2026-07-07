module MatchesHelper
  def match_title_with_guests(match, names_by_id:)
    stats = match.stats.to_h

    if stats["team_a_ids"].present? || stats["team_b_ids"].present? ||
        stats["team_a_guest_names"].present? || stats["team_b_guest_names"].present?
      team_a = match_team_names(match, "team_a", names_by_id)
      team_b = match_team_names(match, "team_b", names_by_id)
      team_a = [ match_user_name(match.user, fallback: "User ##{match.user_id}") ] if team_a.empty?
      team_b = [ "Unknown opponent" ] if team_b.empty?

      "#{team_a.join(' / ')} vs #{team_b.join(' / ')}"
    elsif match.mode == "doubles"
      partner_name = stats["partner_id"].present? ? names_by_id[stats["partner_id"].to_i] : nil
      opponent_names = Array(stats["opponent_ids"]).filter_map { |id| names_by_id[id.to_i] }
      team_name = [ match_user_name(match.user, fallback: "User ##{match.user_id}"), partner_name ].compact.uniq.join(" / ")
      opponents_label = opponent_names.any? ? opponent_names.join(" / ") : "Unknown opponents"

      "#{team_name} vs #{opponents_label}"
    else
      fallback_opponent_name = Array(stats["opponent_ids"]).filter_map { |id| names_by_id[id.to_i] }.first
      opponent_name = match.opponent&.name.presence ||
        Telegram::Helpers::UserLookup.display_name(match.opponent, fallback: fallback_opponent_name || "Unknown opponent")

      "#{match_user_name(match.user, fallback: "User ##{match.user_id}")} vs #{opponent_name}"
    end
  end

  def match_guest_names(value)
    Array(value).map(&:to_s).map(&:strip).reject(&:blank?).map { |name| "#{name} (guest)" }
  end

  private

  def match_team_names(match, team_key, names_by_id)
    stats = match.stats.to_h
    ids = Array(stats["#{team_key}_ids"]).map(&:to_i).reject(&:zero?)
    registered_names = ids.map do |id|
      if id == match.user_id
        match_user_name(match.user, fallback: "User ##{id}")
      else
        names_by_id[id] || "User ##{id}"
      end
    end

    registered_names + match_guest_names(stats["#{team_key}_guest_names"])
  end

  def match_user_name(user, fallback:)
    user&.name.presence || Telegram::Helpers::UserLookup.display_name(user, fallback: fallback)
  end
end
