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

  # The feed prints one line per match, so both sides have to fit into it: a
  # doubles team is named in full, and the guests who have no account stand
  # next to the registered players instead of turning the side anonymous.
  def match_feed_sides(match, names_by_id:)
    own, other = match_side_parts(match)

    [
      match_side_label(own, names_by_id, fallback: names_by_id[match.user_id] || t("tennis_life.user_fallback", id: match.user_id)),
      match_side_label(other, names_by_id, fallback: t("tennis_life.anonymous_player"))
    ]
  end

  # Cards are rendered one by one, so the names are looked up lazily and kept
  # for the rest of the render rather than re-queried for every match.
  def match_names_by_id(ids)
    @match_names_by_id ||= {}
    missing = match_user_ids(ids) - @match_names_by_id.keys
    return @match_names_by_id if missing.empty?

    User.where(id: missing).find_each do |user|
      @match_names_by_id[user.id] = user.name.presence ||
        Telegram::Helpers::UserLookup.display_name(user, fallback: t("tennis_life.user_fallback", id: user.id))
    end

    @match_names_by_id
  end

  def match_related_user_ids(match)
    stats = match.stats.to_h

    [
      match.user_id, match.opponent_id, stats["partner_id"],
      *Array(stats["opponent_ids"]), *Array(stats["team_a_ids"]), *Array(stats["team_b_ids"])
    ]
  end

  def match_guest_names(value)
    Array(value).map(&:to_s).map(&:strip).reject(&:blank?).map { |name| "#{name} (guest)" }
  end

  private

  # Which team the match belongs to decides the order: the row's own player is
  # always named first, so the score that follows reads from the same side.
  def match_side_parts(match)
    stats = match.stats.to_h
    team_a = match_user_ids(stats["team_a_ids"])
    team_b = match_user_ids(stats["team_b_ids"])

    if team_a.include?(match.user_id)
      [ [ team_a, stats["team_a_guest_names"] ], [ team_b, stats["team_b_guest_names"] ] ]
    elsif team_b.include?(match.user_id)
      [ [ team_b, stats["team_b_guest_names"] ], [ team_a, stats["team_a_guest_names"] ] ]
    else
      # Rows recorded before the teams were kept carry only a partner and the
      # opponents.
      [
        [ match_user_ids([ match.user_id, stats["partner_id"] ]), stats["team_a_guest_names"] ],
        [ match_user_ids([ match.opponent_id, *Array(stats["opponent_ids"]) ]), stats["team_b_guest_names"] ]
      ]
    end
  end

  def match_side_label((ids, guest_names), names_by_id, fallback:)
    names = ids.map { |id| names_by_id[id] || t("tennis_life.user_fallback", id: id) }
    names += match_feed_guest_names(guest_names)

    names.any? ? names.join(" + ") : fallback
  end

  def match_feed_guest_names(value)
    Array(value).map { |name| name.to_s.strip }.reject(&:blank?).map do |name|
      t("tennis_life.feed.match.guest", name: name)
    end
  end

  def match_user_ids(values)
    Array(values).map(&:to_i).reject(&:zero?).uniq
  end

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
