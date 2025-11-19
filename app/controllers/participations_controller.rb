class ParticipationsController < ApplicationController
  before_action :set_game, only: [:create, :destroy]

  def create
    @participation = @game.participations.build(user: current_user)

    if @participation.save
      if @game.user&.telegram_chat_id.present?
        user_name = current_user.try(:name) || current_user.try(:email) || "User ##{current_user.id}"
        date_str = (@game.respond_to?(:next_date) ? (@game.next_date || @game.date) : @game.date)
        time_str = (@game.respond_to?(:next_time) ? (@game.next_time || @game.time) : @game.time)
        game_url = "https://getcourt.co/games/#{@game.id}"
        text = "#{user_name} joined your game on #{date_str&.strftime('%Y-%m-%d')} at #{time_str&.strftime('%H:%M')}\n#{game_url}"
        SendTelegramNotificationJob.perform_later(@game.user.telegram_chat_id, text)
      end
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @game, notice: 'Successfully joined the game.' }
      end
    else
      msg = @participation.errors.full_messages.to_sentence.presence || 'Failed to join the game.'
      respond_to do |format|
        format.turbo_stream { render plain: msg, status: :unprocessable_entity }
        format.html { redirect_to @game, alert: msg }
      end
    end
  rescue ActiveRecord::RecordNotUnique
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to @game, alert: 'You have already joined this game.' }
    end
  end

  def destroy
    @participation = @game.participations.find_by(user: current_user)
    @participation_id = @participation&.id

    @participation&.destroy

    if @participation_id && @game.user&.telegram_chat_id.present?
      user_name = current_user.try(:name) || current_user.try(:email) || "User ##{current_user.id}"
      date_str = (@game.respond_to?(:next_date) ? (@game.next_date || @game.date) : @game.date)
      time_str = (@game.respond_to?(:next_time) ? (@game.next_time || @game.time) : @game.time)
      game_url = "https://getcourt.co/games/#{@game.id}"
      text = "#{user_name} left your game on #{date_str&.strftime('%Y-%m-%d')} at #{time_str&.strftime('%H:%M')}\n#{game_url}"
      SendTelegramNotificationJob.perform_later(@game.user.telegram_chat_id, text)
    end

    respond_to do |format|
      format.turbo_stream do
        if @participation_id
          render :destroy
        else
          head :ok
        end
      end
      format.html { redirect_to @game, notice: 'Successfully left the game.' }
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end
end
