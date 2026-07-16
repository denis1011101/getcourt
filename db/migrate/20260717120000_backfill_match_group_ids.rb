require "securerandom"

class BackfillMatchGroupIds < ActiveRecord::Migration[8.0]
  def up
    say_with_time "backfilling stats.match_group_id for game matches" do
      rows = select_all("SELECT id, game_id, user_id, score, stats FROM matches WHERE game_id IS NOT NULL ORDER BY id")
      candidates = rows.map { |row| row.merge("stats" => parse_stats(row["stats"])) }
        .reject { |row| row["stats"]["match_group_id"].present? }

      groups = candidates.group_by do |row|
        stats = row["stats"]
        [
          row["game_id"], row["score"].to_s,
          stats["team_a_ids"].to_s, stats["team_b_ids"].to_s,
          stats["team_a_guest_names"].to_s, stats["team_b_guest_names"].to_s
        ]
      end

      updated = 0
      groups.each_value do |members|
        # One form submission inserts one row per user, so a repeated user
        # within the same signature starts a separate logical match.
        group_id = SecureRandom.uuid
        seen_users = {}
        members.each do |row|
          if seen_users[row["user_id"]]
            group_id = SecureRandom.uuid
            seen_users = {}
          end
          seen_users[row["user_id"]] = true

          stats = row["stats"].merge("match_group_id" => group_id)
          update("UPDATE matches SET stats = #{quote(stats.to_json)} WHERE id = #{row['id'].to_i}")
          updated += 1
        end
      end
      updated
    end
  end

  def down
    # Group ids are additive metadata; nothing to restore.
  end

  private

  def parse_stats(value)
    parsed = value.is_a?(String) ? JSON.parse(value) : value
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
