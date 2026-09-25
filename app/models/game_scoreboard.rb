# Живое табло матча в игре. Счёт — это список розыгрышей (actions), из
# которого Scoreboard::TennisState каждый раз собирает сеты, геймы и очки.
# Смотрят все, кто открыл страницу: каждое нажатие рассылается через Turbo
# Streams. По «Завершить» счёт уходит в статистику игры тем же путём, что и
# форма статистики.
class GameScoreboard < ApplicationRecord
  STATUSES = %w[live finished].freeze

  belongs_to :game
  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validate :teams_are_playable
  validate :game_keeps_scores, on: :create

  scope :live, -> { where(status: "live") }

  after_update_commit :broadcast_refresh

  def state
    Scoreboard::TennisState.new(settings, actions)
  end

  def live?
    status == "live"
  end

  def mode
    team_size(team_a) >= 2 || team_size(team_b) >= 2 ? "doubles" : "singles"
  end

  UNITS = %w[main set].freeze

  # «+» у стороны. unit "main" — розыгрыш (в полном счёте) или гейм (в режиме
  # геймов), "set" — закрыть текущий сет в её пользу. Замок — на случай двух
  # телефонов: нажатия встают в очередь, а не теряются.
  def score!(side, unit = "main")
    token = unit == "set" ? "s:#{side}" : side
    change_actions { |list| list + [ token ] unless state.finished? }
  end

  # «−» у стороны. "main" снимает её последний розыгрыш или гейм — остальная
  # история проигрывается заново, так что откатывается и гейм, и сет, если
  # надо. "set" убирает её последний выигранный сет целиком.
  def unscore!(side, unit = "main")
    change_actions do |list|
      if unit == "set"
        range = state.last_set_range(side)
        range && (list[0...range.begin] + list[(range.end + 1)..])
      else
        # «g:» — гейм, замороженный при смене настроек: тоже её последнее
        # очко или гейм, если после него она ничего не выигрывала.
        index = list.rindex { |token| token == side || token == "g:#{side}" }
        index && without_game(list, index)
      end
    end
  end

  # Счёт тай-брейка для сета 7:6, закрытого в режиме геймов. Очки даны по
  # сторонам, как на табло; у победителя сета должно быть не меньше семи и на
  # два больше. Новый токен встаёт сразу за действием, закрывшим сет, — так
  # «− сет» уберёт его вместе с сетом; уже записанный — заменяется на месте.
  # Возвращает nil, если записали, иначе причину отказа для подсказки:
  # :wrong_winner — тай-брейк отдан стороне, проигравшей сет; :invalid_score —
  # нет семи очков или разницы в два (либо разница больше двух после 7).
  def record_tiebreak!(a_points, b_points)
    error = nil
    # Сет и позицию токена ищем под замком, по свежей истории: иначе сброс с
    # другого телефона сдвинет индекс, и замена попадёт в чужой гейм.
    change_actions do |list|
      board = state
      index = board.tiebreak_editable_set
      next error = :invalid_score unless index

      set = board.sets[index]
      winner = set["a"] > set["b"] ? "a" : "b"
      points = { "a" => a_points.to_i, "b" => b_points.to_i }
      loser_points = points[winner == "a" ? "b" : "a"]
      lead = points[winner] - loser_points
      next error = :wrong_winner if lead.negative?
      next error = :invalid_score unless points[winner] >= 7 && lead >= 2 && (points[winner] == 7 || lead == 2)

      token = "tb:#{loser_points}"
      if set["tb_token"]
        list.dup.tap { |copy| copy[set["tb_token"]] = token }
      else
        at = set["range"].end + 1
        list[0...at] + [ token ] + list[at..]
      end
    end
    error
  end

  # Сбросить записанный счёт тай-брейка: сет остаётся 7:6, без скобок.
  def reset_tiebreak!
    change_actions do |list|
      board = state
      index = board.tiebreak_editable_set
      token_index = index && board.sets[index]["tb_token"]
      next nil unless token_index

      list[0...token_index] + list[(token_index + 1)..]
    end
  end

  # Правка настроек посреди матча: стороны и правила меняются, счёт остаётся.
  # Историю пересобираем при любой смене правил (TennisState#rebuilt_actions):
  # сыгранные геймы и сеты замораживаются и по новым правилам не
  # переигрываются.
  def update_setup!(settings:, team_a:, team_b:)
    with_lock do
      return false unless live?

      current = state
      rebuilt = Scoreboard::TennisState.new(settings).settings == current.settings ? actions : current.rebuilt_actions(settings)
      assign_attributes(settings: settings, team_a: team_a, team_b: team_b, actions: rebuilt)
      return false unless save
    end
    true
  end

  # Счёт уходит в статистику игры, табло закрывается. Ноль розыгрышей —
  # записывать нечего, просто закрываем.
  def finish!(actor)
    with_lock do
      return false unless live?

      board = state
      if board.score_string.present?
        Telegram::Flows::StatsScore::MatchUpserter.call(
          game: game,
          actor: actor,
          mode: mode,
          team_a_ids: user_ids(team_a),
          team_b_ids: user_ids(team_b),
          team_a_guest_names: guest_names(team_a),
          team_b_guest_names: guest_names(team_b),
          result: board.result,
          played_at: game.start_at_for_ui || Time.current,
          score: board.score_string,
          force_new: true
        )
      end
      update!(status: "finished", finished_at: Time.current)
    end
    true
  end

  # Игроки стороны в порядке выбора: зарегистрированные (User), потом гости
  # (строки). Подпись собирает вьюха.
  def players(side)
    team = side.to_s == "a" ? team_a : team_b
    users = User.where(id: user_ids(team)).index_by(&:id)
    user_ids(team).filter_map { |id| users[id] } + guest_names(team)
  end

  private

  def change_actions
    with_lock do
      return false unless live?

      updated = yield(Array(actions).dup)
      return false unless updated.is_a?(Array)

      update!(actions: updated)
    end
    true
  end

  # Всем открытым табло — сигнал перезапросить страницу. Не готовый HTML:
  # у каждого свои язык и права (кнопки видит только тот, кто ведёт счёт), а
  # после чужого «−» кнопки и плашка «Матч окончен» должны ожить у всех.
  # Нажавший сам себя не перезагружает — Turbo узнаёт свой запрос по id.
  # Убираем гейм, а если он из замороженного сета — и закрытие этого сета
  # («fs:») с его тай-брейком: сет был закрыт потому, что сыгран, и без
  # гейма он снова открыт. Сет, закрытый кнопкой («s:»), остаётся закрытым.
  def without_game(list, index)
    set = state.sets.find { |candidate| candidate["range"].cover?(index) }
    positions = set ? set["range"].to_a : []
    frozen = positions.any? { |position| list[position].start_with?("fs:") }
    dependent = frozen ? positions.select { |position| list[position].start_with?("fs:", "tb:") } : []
    list.each_with_index.filter_map { |token, position| token unless position == index || dependent.include?(position) }
  end

  def broadcast_refresh
    broadcast_refresh_to [ game, :scoreboard ]
  end

  def user_ids(team)
    Array(team.to_h["user_ids"]).map(&:to_i).reject(&:zero?)
  end

  def guest_names(team)
    Array(team.to_h["guest_names"]).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def team_size(team)
    user_ids(team).size + guest_names(team).size
  end

  # Те же правила, что у формы статистики: один на один или двое на двое, и
  # хотя бы один зарегистрированный игрок — иначе в статистику писать некому.
  def teams_are_playable
    a = team_size(team_a)
    b = team_size(team_b)
    errors.add(:base, :unbalanced_teams) unless a == b && [ 1, 2 ].include?(a)
    errors.add(:base, :no_registered_players) if (user_ids(team_a) + user_ids(team_b)).empty?
    errors.add(:base, :same_player_twice) if (user_ids(team_a) & user_ids(team_b)).any?
  end

  def game_keeps_scores
    errors.add(:base, :training) if game&.training?
  end
end
