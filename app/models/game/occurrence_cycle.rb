# Что происходит при сбросе, в одном месте.
#
# Состав, чат, комментарий и медиа принадлежат одному занятию серии и живут до
# ночи, когда их место занимает следующее. Ночь эта — еженедельный сброс с
# пятницы на субботу (ResetParticipationsJob в recurring.yml, там же чистка
# прошедших разовых игр), а у серии, где занятий несколько в неделю, — ночь
# ближайшего следующего занятия, если она наступает раньше: иначе четверг вышел
# бы на корт с составом, комментарием и роликами понедельника.
#
# Отсюда все вопросы про эту границу: какому занятию принадлежит нынешний
# состав (его же показывает карточка и по нему выбираются адресаты
# напоминания), пора ли сбрасывать и до какого момента открыт чат.
class Game::OccurrenceCycle
  RESET_WDAY = 6
  RESET_HOUR = 4

  # Ближайшая ночь еженедельного сброса после указанного момента.
  def self.next_weekly_reset_at(from = Time.current)
    from = from.in_time_zone
    reset = from.beginning_of_day.change(hour: RESET_HOUR)
    reset += 1.day while reset <= from || reset.wday != RESET_WDAY
    reset
  end

  def initialize(game)
    @game = game
  end

  # Занятие, которому принадлежит нынешний состав: пока сброс не прошёл — уже
  # отыгранное вхождение, после — ближайшее. Прошедшую серию, у которой впереди
  # ничего не осталось, показываем последним вхождением.
  def roster_occurrence(as_of = Date.current)
    nd = game.next_date
    return game.date unless nd

    prev = game.previous_occurrence_before_next_date
    return prev if prev && (reset_marked_for?(prev) || (prev < as_of && pending?(as_of)))
    return nd if nd >= as_of

    prev || nd
  end

  # Состав ещё от отыгранного вхождения — сбросить его только предстоит.
  def pending?(as_of = Date.current)
    return false unless game.recurring?

    nd = game.next_date
    return false unless nd

    prev = game.previous_occurrence_before_next_date
    return false unless prev && prev < as_of

    marker = game.last_participations_reset_at
    marker.nil? || marker.to_date < nd
  end

  # Пора: ночь, в которую состав уступает место следующему занятию, наступила.
  def due?(as_of = Date.current)
    pending?(as_of) && reset_at(game.previous_occurrence_before_next_date).to_date <= as_of
  end

  # Ночь, в которую состав этого занятия уступит место следующему.
  def reset_at(occurrence)
    return Time.current if occurrence.blank?

    weekly = self.class.next_weekly_reset_at(occurrence.end_of_day)
    following = game.recurring? ? game.occurrence_after(occurrence) : nil
    return weekly if following.blank?

    [ weekly, following.in_time_zone.change(hour: RESET_HOUR) ].min
  end

  # Чат живёт ровно столько же, сколько состав, которому человек пишет. Считаем
  # не «ближайшую субботу вообще», а ту ночь, которая действительно разберёт
  # этот состав: игру, назначенную после ближайшей субботы, эта ночь не
  # касается, и гасить её чат в 4 утра не за что.
  def chat_open_until
    occurrence = game.recurring? ? (game.next_date || game.date) : game.date
    return nil if occurrence.blank?

    closes_at = reset_at(occurrence)
    closes_at > Time.current ? closes_at : nil
  end

  private
    attr_reader :game

    def reset_marked_for?(occurrence)
      marker = game.last_participations_reset_at
      marker.present? && marker.to_date == occurrence
    end
end
