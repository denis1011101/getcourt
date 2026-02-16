class ResetParticipationsJob < ApplicationJob
  queue_as :default

  def perform
    Game.where(recurring: true).find_each do |game|
      nd = game.next_date
      next unless nd

      if game.should_reset_participations?(Date.today)
        if game.prebooking_enabled?
          apply_prebookings_for_occurrence!(game, nd)
          game.mark_participations_reset!(nd)
          Rails.logger.info "Reset participations from prebookings for Game##{game.id} for occurrence #{nd}"
        else
          game.participations.delete_all
          game.mark_participations_reset!(nd)
          Rails.logger.info "Reset participations for Game##{game.id} for occurrence #{nd}"
        end
      end
    end
  end

  private

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
