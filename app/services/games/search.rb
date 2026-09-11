module Games
  # Фильтры, общие для страницы игр и JSON-выдачи. Всё, что сужает выборку по
  # собственным полям игры, живёт здесь, иначе список на сайте и API разъедутся.
  # Пользовательские вещи (my_games, сортировка «поближе ко мне») остаются в
  # контроллере страницы — в API их нет.
  class Search
    DEFAULT_INCLUDES = [ :court, :tournament, :participations, :prebooking_cancellations ].freeze
    DEFAULT_LIMIT = 25
    MAX_LIMIT = 100

    # Сколько игр отдавать наружу. Ноль и мусор означают «по умолчанию».
    def self.limit_for(value)
      limit = value.to_i
      return DEFAULT_LIMIT unless limit.positive?

      [ limit, MAX_LIMIT ].min
    end

    def initialize(scope: Game.all, includes: DEFAULT_INCLUDES)
      @scope = includes.present? ? scope.includes(*includes) : scope
    end

    # Порядок как на сайте: сперва будущие и повторяющиеся (ближайшие сверху),
    # потом прошедшие (свежие сверху).
    def ordered
      today = ActiveRecord::Base.connection.quote(Date.current)
      # Тот же вопрос, что и у Game.still_running, но внутри ORDER BY: серия
      # идёт сверху, пока её расписание не кончилось.
      running_sql = "(games.recurring = 1 OR games.recurring_monthly = 1 OR games.ends_on >= #{today})"
      # А по сегодняшнему дню сортируются только те, чья ближайшая дата уже не
      # лежит в колонке: бесконечная серия и та, что идёт прямо сейчас. У
      # будущей игры — хоть разовой, хоть серии — ключ её собственная дата,
      # иначе октябрьская утренняя вставала бы выше сентябрьской вечерней.
      started_sql = "(games.recurring = 1 OR games.recurring_monthly = 1 OR " \
                    "(games.date < #{today} AND games.ends_on >= #{today}))"

      @scope.order(
        Arel.sql(
          "CASE WHEN #{running_sql} OR games.date IS NULL OR games.date >= #{today} THEN 0 ELSE 1 END, " \
          "CASE WHEN #{started_sql} OR games.date IS NULL THEN #{today} WHEN games.date >= #{today} THEN games.date END ASC NULLS LAST, " \
          "CASE WHEN NOT (#{running_sql}) AND games.date IS NOT NULL AND games.date < #{today} THEN games.date END DESC NULLS LAST, " \
          "games.time ASC"
        )
      )
    end

    def sport(value)
      chain(value.present? ? @scope.where(sport: value) : @scope)
    end

    def skill_level(value)
      chain(value.present? ? @scope.where(skill_level: value) : @scope)
    end

    def in_cities(city_names)
      names = Array(city_names).reject(&:blank?)
      chain(names.any? ? @scope.joins(:court).where(courts: { city_name: names }) : @scope)
    end

    def urgent_only(flag)
      chain(flag.present? ? @scope.where(urgent_player_search: true) : @scope)
    end

    def tournament_only(flag)
      chain(flag.present? ? @scope.where.not(tournament_id: nil) : @scope)
    end

    # Только игры, которые ещё впереди. Бесконечная серия идёт всегда, у
    # конечной впереди занятия, пока не прошла её последняя отметка.
    def upcoming_only(flag)
      chain(flag.present? ? @scope.merge(Game.still_running) : @scope)
    end

    def from_date(value)
      date = parse_date(value)
      chain(date ? @scope.merge(Game.still_running(date)) : @scope)
    end

    def to_date(value)
      date = parse_date(value)
      chain(date ? @scope.where("games.recurring = ? OR games.date <= ?", true, date) : @scope)
    end

    def relation
      @scope
    end

    # Свободные места считаются в руби: занятость зависит от статуса участия,
    # одним условием в SQL это не выражается без лишнего джойна с группировкой.
    def self.with_spots(games)
      games.select(&:spots_available?)
    end

    private

    def chain(scope)
      @scope = scope
      self
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
