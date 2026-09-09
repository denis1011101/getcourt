# Что происходит при сбросе, в одном месте.
#
# Состав, чат, комментарий и медиа принадлежат одному занятию серии и живут до
# момента, когда их место занимает следующее. Момент этот — 20:00, ближайшие к
# середине промежутка между концом отыгранного занятия и началом следующего
# неотменённого: у серии «пн + чт» это вечер вторника, а после четверга —
# вечер субботы; у серии раз в неделю — вечер четверга. Вечер, а не ночь:
# письмо о закрытом чате и о новом составе человек получает бодрствующим, и до
# следующего занятия у него остаётся день-два, чтобы собраться заново.
#
# Отсюда все вопросы про эту границу: какому занятию принадлежит нынешний
# состав (его же показывает карточка и по нему выбираются адресаты
# напоминания), пора ли сбрасывать и до какого момента открыт чат.
class Game::OccurrenceCycle
  RESET_HOUR = 20

  # Разовой игре делить нечего: её состав и чат живут до той же ночи с пятницы
  # на субботу, в которую CleanupPastOneOffGamesJob сносит саму игру.
  WEEKLY_RESET_WDAY = 6
  WEEKLY_RESET_HOUR = 4

  # Отменить можно хоть год вперёд, но не бесконечно: цикл ищет живое занятие,
  # а не перебирает даты до скончания веков.
  MAX_SKIPPED_OCCURRENCES = 520

  def self.next_weekly_reset_at(from = Time.current)
    from = from.in_time_zone
    reset = from.beginning_of_day.change(hour: WEEKLY_RESET_HOUR)
    reset += 1.day while reset <= from || reset.wday != WEEKLY_RESET_WDAY
    reset
  end

  def initialize(game)
    @game = game
  end

  # Занятие, которому принадлежит нынешний состав: отыгранное — пока состав не
  # сменили, дальше — следующее. Считаем по отметке о сбросе, а не по одному
  # лишь времени: между наступившим моментом и заходом задачи (а если уборка
  # упала — и дольше) в игре ещё лежит прежний состав, и карточка с чатом
  # должны показывать именно его.
  def roster_occurrence(now = Time.current)
    played = played_occurrence(now)
    upcoming = upcoming_occurrence(now)
    return upcoming || game.date if played.blank?
    return played if upcoming.blank?

    reset_done_for?(upcoming) ? upcoming : played
  end

  # Последнее занятие, которое уже началось.
  def played_occurrence(now = Time.current)
    day = occurrence_on_or_before(game_day(now))
    return nil if day.blank?
    return day if game.occurrence_starts_at(day) <= now

    previous_occurrence(day)
  end

  # Ближайшее занятие, которое ещё не началось.
  def upcoming_occurrence(now = Time.current)
    day = occurrence_on_or_after(game_day(now))
    return nil if day.blank?
    return day if game.occurrence_starts_at(day) > now

    following_occurrence(day)
  end

  # Момент, когда состав этого занятия уступит место следующему.
  def reset_at(occurrence)
    return Time.current if occurrence.blank?

    in_game_zone do
      following = following_occurrence(occurrence)
      return self.class.next_weekly_reset_at(occurrence.end_of_day) if following.blank?

      evening_between(game.occurrence_ends_at(occurrence), game.occurrence_starts_at(following))
    end
  end

  # Пора: момент смены состава наступил, а сброс на это занятие ещё не отмечен.
  def due?(now = Time.current)
    return false unless game.recurring?

    played = played_occurrence(now)
    return false unless played && reset_at(played) <= now

    upcoming = upcoming_occurrence(now)
    return false if upcoming.blank?

    marker = game.last_participations_reset_at
    marker.nil? || marker.to_date < upcoming
  end

  # Чат живёт ровно столько же, сколько состав, которому человек пишет: до
  # сброса того занятия, к которому этот состав относится.
  def chat_open_until
    occurrence = roster_occurrence
    return nil if occurrence.blank?

    closes_at = reset_at(occurrence)
    closes_at > Time.current ? closes_at : nil
  end

  private
    attr_reader :game

    # Все расчёты — в поясе игры: «20:00» это восемь вечера там, где выходят на
    # корт, а сутки заканчиваются тогда же, когда у играющих.
    def in_game_zone(&block)
      Time.use_zone(game.creator_time_zone, &block)
    end

    def game_day(now)
      now.in_time_zone(game.creator_time_zone).to_date
    end

    def reset_done_for?(occurrence)
      marker = game.last_participations_reset_at

      marker.present? && marker.to_date >= occurrence
    end

    # Середину промежутка сдвигаем к ближайшим 20:00. Если ни одни в промежуток
    # не попадают — занятия стоят впритык, — сбрасываем сразу, как первое
    # закончилось: пока оно идёт, состав трогать нельзя.
    def evening_between(ends_at, starts_at)
      midpoint = ends_at + (starts_at - ends_at) / 2
      evenings = (-1..1).map { |shift| (midpoint.to_date + shift).in_time_zone.change(hour: RESET_HOUR) }

      evenings.select { |evening| evening > ends_at && evening < starts_at }
              .min_by { |evening| (evening - midpoint).abs } || ends_at
    end

    def occurrence_on_or_before(day)
      return nil if game.date.blank?
      return (game.date if game.date <= day) unless game.recurring?
      return nil if day < game.date

      candidate = day
      candidate -= 1 until game.recurrence_weekdays.include?(candidate.wday)
      game.cancelled_on?(candidate) ? previous_occurrence(candidate) : candidate
    end

    def occurrence_on_or_after(day)
      return nil if game.date.blank?
      return (game.date if game.date >= day && !game.cancelled_on?(game.date)) unless game.recurring?

      candidate = game.occurrence_on_or_after(day)
      game.cancelled_on?(candidate) ? following_occurrence(candidate) : candidate
    end

    def previous_occurrence(day)
      candidate = game.occurrence_before(day)
      MAX_SKIPPED_OCCURRENCES.times do
        break if candidate.blank? || !game.cancelled_on?(candidate)

        candidate = game.occurrence_before(candidate)
      end
      candidate
    end

    def following_occurrence(day)
      return nil unless game.recurring? && game.date.present?

      candidate = game.occurrence_after(day)
      MAX_SKIPPED_OCCURRENCES.times do
        break if candidate.blank? || !game.cancelled_on?(candidate)

        candidate = game.occurrence_after(candidate)
      end
      candidate
    end
end
