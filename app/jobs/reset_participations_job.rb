class ResetParticipationsJob < ApplicationJob
  queue_as :default

  def perform
    Game.series.find_each do |game|
      next unless game.participations_reset_due?

      upcoming = game.upcoming_occurrence
      next if upcoming.blank?

      # Снимок до сброса: кому чат закроется, видно только по разнице составов —
      # часть людей вернётся в состав из предзаписи и никуда не выбывает.
      chat_members = game.chat_members.to_a

      # Контент чистим до маркера: маркер закрывает игре повторный заход, и
      # неудачная уборка должна дождаться следующего часа, а не пропасть.
      # Отсюда же и порядок: сброс предзаписей уносит людей с даты в состав,
      # повторить его вторым заходом нельзя.
      next unless reset_occurrence_content(game)

      if game.prebooking_enabled?
        apply_prebookings_for_occurrence!(game, upcoming)
        game.mark_participations_reset!(upcoming)
        Rails.logger.info "Reset participations from prebookings for Game##{game.id} for occurrence #{upcoming}"
      else
        game.participations.delete_all
        game.mark_participations_reset!(upcoming)
        Rails.logger.info "Reset participations for Game##{game.id} for occurrence #{upcoming}"
      end

      close_chat_for_dropped(game, chat_members)
      announce_chat_update(game)
    end
  end

  private

  # Комментарий и вложения принадлежат прошедшей встрече ровно так же, как
  # состав: «сегодня беру мячи» и ролик с прошлой субботы новой игре не нужны.
  # Вложения сносим по одному через destroy, а не delete_all: только так Active
  # Storage снимет файл с диска, а места на нём мало (см. GameMedium).
  # update_columns — мимо колбэков: after_commit игры зовёт рассылку об
  # изменениях, и сброс не должен будить ею людей в четыре утра.
  #
  # false — «эту игру в этот раз не трогаем»: упавшую уборку повторит следующий
  # запуск, а до тех пор состав остаётся на месте. Одна испорченная игра при
  # этом не должна останавливать остальные, поэтому исключение наружу не идёт.
  def reset_occurrence_content(game)
    game.update_columns(comment: nil, updated_at: Time.current) if game.comment.present?

    # map, а не all?: короткое замыкание на первой неудаче бросило бы остальные
    # ролики лежать на диске.
    dropped = game.game_media.to_a.map do |medium|
      next true if medium.destroy

      Rails.logger.warn("[ResetParticipationsJob] failed to destroy GameMedium##{medium.id}: #{medium.errors.full_messages.join(", ")}")
      false
    end
    dropped.all?
  rescue StandardError => e
    Rails.logger.warn("[ResetParticipationsJob] content reset failed for Game##{game.id}: #{e.class}: #{e.message}")
    false
  end

  # delete_all идёт мимо колбэков Participation, поэтому режим чата у выбывших
  # гасим здесь — иначе они продолжат писать в состав, из которого их убрали.
  # Без письма человек заметил бы это, только когда его сообщение уже никому
  # не ушло.
  def close_chat_for_dropped(game, previous_members)
    game.participations.reset
    remaining = game.team_member_ids
    dropped = previous_members.reject { |user| remaining.include?(user.id) }
    Telegram::Chat::Closure.notify(game, :chat_closed_reset, dropped)
  rescue StandardError => e
    Rails.logger.warn("[ResetParticipationsJob] chat cleanup failed for Game##{game.id}: #{e.class}: #{e.message}")
  end

  # Чат остаётся тем же, меняется занятие, к которому он относится: тем, кто в
  # составе, переписку продолжать, и они должны видеть, про какую игру она
  # теперь. Письмо уходит после закрытия — выбывшие своё уже получили.
  def announce_chat_update(game)
    Telegram::Chat::Announcement.notify(game, :chat_updated_reset)
  rescue StandardError => e
    Rails.logger.warn("[ResetParticipationsJob] chat update notice failed for Game##{game.id}: #{e.class}: #{e.message}")
  end

  # Кто записался на это занятие — тот и выходит на корт: людей с даты nd
  # переносим в состав, а брони на другие даты не трогаем. Раньше очередь после
  # переноса сдвигалась на занятие назад — бронь на 17-е становилась бронью на
  # 14-е, — но человек записывается на конкретный день, а не в очередь.
  def apply_prebookings_for_occurrence!(game, nd)
    players_needed = (game.players_count.to_i > 0 ? game.players_count.to_i : 4)

    ActiveRecord::Base.transaction do
      game.participations.delete_all

      # Заявка, которую организатор ещё не одобрил, в состав не идёт: иначе
      # предзапись обходила бы подтверждение, ради которого она и заведена.
      game.prebookings.approved.where(date: nd).where.not(user_id: nil).order(:slot_index).limit(players_needed).each do |prebooking|
        game.participations.create!(user_id: prebooking.user_id)
        prebooking.update!(user_id: nil)
      end

      # Горизонт едет вперёд вместе с игрой: место освободилось, и на дальние
      # даты снова есть куда записываться.
      game.ensure_prebookings_for_next_weeks
    end
  end
end
