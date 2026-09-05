class ResetParticipationsJob < ApplicationJob
  queue_as :default

  def perform
    Game.where(recurring: true).find_each do |game|
      nd = game.next_date
      next unless nd

      if game.should_reset_participations?(Date.current)
        # Снимок до сброса: кому чат закроется, видно только по разнице составов —
        # часть людей вернётся в состав из предзаписи и никуда не выбывает.
        chat_members = game.chat_members.to_a

        if game.prebooking_enabled?
          apply_prebookings_for_occurrence!(game, nd)
          game.mark_participations_reset!(nd)
          Rails.logger.info "Reset participations from prebookings for Game##{game.id} for occurrence #{nd}"
        else
          game.participations.delete_all
          game.mark_participations_reset!(nd)
          Rails.logger.info "Reset participations for Game##{game.id} for occurrence #{nd}"
        end

        reset_occurrence_content(game)
        close_chat_for_dropped(game, chat_members)
      end
    end
  end

  private

  # Комментарий и вложения принадлежат прошедшей встрече ровно так же, как
  # состав: «сегодня беру мячи» и ролик с прошлой субботы новой игре не нужны.
  # Вложения сносим по одному через destroy, а не delete_all: только так Active
  # Storage снимет файл с диска, а места на нём мало (см. GameMedium).
  # update_columns — мимо колбэков: after_commit игры зовёт рассылку об
  # изменениях, и сброс не должен будить ею людей в четыре утра.
  def reset_occurrence_content(game)
    game.update_columns(comment: nil, updated_at: Time.current) if game.comment.present?

    game.game_media.find_each do |medium|
      next if medium.destroy

      Rails.logger.warn("[ResetParticipationsJob] failed to destroy GameMedium##{medium.id}: #{medium.errors.full_messages.join(", ")}")
    end
  rescue StandardError => e
    Rails.logger.warn("[ResetParticipationsJob] content reset failed for Game##{game.id}: #{e.class}: #{e.message}")
  end

  # delete_all идёт мимо колбэков Participation, поэтому режим чата у выбывших
  # гасим здесь — иначе они продолжат писать в состав, из которого их убрали.
  # Сброс идёт ночью, и без письма человек заметил бы это, только когда его
  # сообщение уже никому не ушло.
  def close_chat_for_dropped(game, previous_members)
    game.participations.reset
    remaining = game.team_member_ids
    dropped = previous_members.reject { |user| remaining.include?(user.id) }
    Telegram::Chat::Closure.notify(game, :chat_closed_reset, dropped)
  rescue StandardError => e
    Rails.logger.warn("[ResetParticipationsJob] chat cleanup failed for Game##{game.id}: #{e.class}: #{e.message}")
  end

  # Promote users from prebookings on nd into participations, shift next prebookings up,
  # and append a new empty prebooking date at the end.
  def apply_prebookings_for_occurrence!(game, nd)
    players_needed = (game.players_count.to_i > 0 ? game.players_count.to_i : 4)

    # collect sorted future prebooking dates starting with nd
    dates = game.prebookings.where("date >= ?", nd).distinct.pluck(:date).sort
    # ensure current nd is present in dates (if no prebookings at nd, still include it)
    dates = [ nd ] | dates

    ActiveRecord::Base.transaction do
      # 1) create participations from prebookings on nd (up to players_needed)
      nd_prebooks = game.prebookings.where(date: nd).order(:slot_index)
      game.participations.delete_all
      nd_prebooks.limit(players_needed).each_with_index do |pb, idx|
        next unless pb.user_id
        game.participations.create!(user_id: pb.user_id)
        # remove user from that prebooking slot (moved to participation)
        pb.update!(user_id: nil)
      end

      # 2) shift users from next dates → current, cascading forward
      # iterate dates in order, for each date copy users from next date into current
      dates.each_with_index do |cur_date, i|
        next_date = dates[i + 1]
        (1..players_needed).each do |slot_index|
          src_user = nil
          if next_date
            src_pb = game.prebookings.find_by(date: next_date, slot_index: slot_index)
            src_user = src_pb&.user_id
          end
          dest_pb = game.prebookings.find_or_initialize_by(date: cur_date, slot_index: slot_index)
          dest_pb.user_id = src_user
          dest_pb.save!
        end
      end

      # 3) append a new empty date after the last known date
      last_date = dates.max || nd
      new_date = last_date + 1.week
      (1..players_needed).each do |slot_index|
        game.prebookings.find_or_create_by!(date: new_date, slot_index: slot_index) do |pb|
          pb.user_id = nil
        end
      end
    end
  end
end
