module Social
  # Выбирает материал для ежедневного поста. Варианты перебираются от того, что
  # дольше всех не постился: так «каждый раз новый» соблюдается само собой, а
  # пустой вариант (вчера не было ни одного матча) не съедает день.
  class DailyPlanner
    # Хватает с запасом: вариантов три, фактов семь, пост один в день.
    LOOKBACK = 200
    # Тот же факт третий раз за неделю читается как спам — и людьми, и
    # automated-labeling у модерации Bluesky.
    FACT_COOLDOWN = 7.days
    # Вариант, которого ещё не было ни разу, должен идти первым.
    EPOCH = Time.at(0).utc

    def initialize(date: Date.current)
      @date = date
    end

    def pick
      ordered_variants.each do |variant|
        content = candidate(variant)
        return content if content
      end

      nil
    end

    private

    attr_reader :date

    def ordered_variants
      Content::Daily::VARIANTS.each_with_index.sort_by do |variant, index|
        [ last_posted_at[variant] || EPOCH, index ]
      end.map(&:first)
    end

    def candidate(variant)
      case variant
      when "upcoming" then upcoming_candidate
      when "result" then result_candidate
      when "fact" then fact_candidate
      end
    end

    def upcoming_candidate
      target = date + 1

      games = Game.where(urgent_player_search: false)
        .where("games.date = ? OR games.recurring = ?", target, true)
        .includes(:court, :participations)
        .select { |game| game.occurrence_date?(target) && !game.cancelled_on?(target) }

      game = games.select { |candidate| candidate.spots_left.positive? }
        .max_by { |candidate| [ candidate.spots_left, candidate.id ] }
      return nil unless game

      build("upcoming", game.id)
    end

    def result_candidate
      relation = Match.where(played_at: (date - 1).all_day)
        .where.not(score: [ nil, "" ])
        .order(played_at: :desc, id: :desc)

      # Одна игра лежит в matches дважды, от обоих игроков — без схлопывания
      # зеркальной пары один матч вышел бы постом два дня подряд.
      TennisLife::Feed::Sources::Matches.representatives(relation)
        .lazy
        .map { |match| build("result", match.id) }
        .find(&:itself)
    end

    def fact_candidate
      cooled = Time.current - FACT_COOLDOWN

      TennisLife::Feed::Sources::Facts::KEYS
        .each_with_index
        .reject { |key, _| last_fact_at[key] && last_fact_at[key] > cooled }
        .sort_by { |key, index| [ last_fact_at[key] || EPOCH, index ] }
        .lazy
        .map { |key, _| build("fact", key) }
        .find(&:itself)
    end

    def build(variant, subject)
      content = Content::Daily.new(variant: variant, subject: subject, date: date)
      content if content.available?
    end

    def last_posted_at
      @last_posted_at ||= first_seen(recent_daily_posts) { |key| key.split(":").first }
    end

    def last_fact_at
      @last_fact_at ||= first_seen(recent_daily_posts.select { |key, _| key.start_with?("fact:") }) { |key| key.split(":")[1] }
    end

    def recent_daily_posts
      @recent_daily_posts ||= SocialPost.for_kind("daily")
        .where.not(posted_at: nil)
        .order(posted_at: :desc)
        .limit(LOOKBACK)
        .pluck(:dedup_key, :posted_at)
    end

    # Записи уже отсортированы по убыванию времени, поэтому первое попадание
    # ключа и есть самый свежий пост этого варианта.
    def first_seen(rows)
      rows.each_with_object({}) do |(dedup_key, posted_at), acc|
        group = yield(dedup_key)
        acc[group] ||= posted_at if group
      end
    end
  end
end
