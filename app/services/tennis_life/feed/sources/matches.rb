module TennisLife
  module Feed
    module Sources
      class Matches < Base
        class << self
          def representatives(relation)
            relation.to_a
              .group_by { |match| event_key(match) }
              .values
              .map { |group| select_representative(group) }
          end

          def event_key(match)
            stats = match.stats.to_h
            participants =
              if match.mode == "doubles"
                team_a_ids = normalize_ids(stats["team_a_ids"])
                team_b_ids = normalize_ids(stats["team_b_ids"])

                if team_a_ids.any? && team_b_ids.any?
                  [ team_a_ids, team_b_ids ].sort
                else
                  [
                    normalize_ids([ match.user_id, stats["partner_id"] ]),
                    normalize_ids(stats["opponent_ids"])
                  ].sort
                end
              else
                normalize_ids([ match.user_id, match.opponent_id, *Array(stats["opponent_ids"]) ])
              end

            [ match.game_id, match.mode, match.played_at&.to_i, match.score.to_s, participants ]
          end

          def select_representative(group)
            group.min_by do |match|
              stats = match.stats.to_h
              participants =
                if match.mode == "doubles"
                  normalize_ids([ *Array(stats["team_a_ids"]), *Array(stats["team_b_ids"]), match.user_id ])
                else
                  normalize_ids([ match.user_id, match.opponent_id, *Array(stats["opponent_ids"]) ])
                end

              [ participants.index(match.user_id) || participants.length, match.id ]
            end
          end

          def normalize_ids(values)
            Array(values).map(&:to_i).reject(&:zero?).uniq.sort
          end
        end

        def ids
          relation = snapshotted(Match).order(played_at: :desc, id: :desc)
          self.class.representatives(relation).map(&:id)
        end
      end
    end
  end
end
