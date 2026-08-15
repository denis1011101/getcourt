class GameMediaController < ApplicationController
  before_action :set_game

  # Прикладывать может организатор, админ и любой записавшийся участник:
  # снимает обычно не тот, кто игру создал.
  def create
    medium = @game.game_media.new(user: current_user, file: params[:file])

    unless contributor?
      redirect_to @game, alert: t("game_media.not_allowed"), status: :see_other and return
    end

    if medium.save
      redirect_to @game, notice: t("game_media.uploaded")
    else
      redirect_to @game, alert: medium.errors.full_messages.to_sentence.presence || t("game_media.failed"),
                  status: :see_other
    end
  end

  # Автор убирает своё вложение совсем; админ прячет чужое, оставляя запись —
  # так видно, что модерация была, и файл не пропадает у автора из-под ног.
  def destroy
    medium = @game.game_media.find(params[:id])

    if medium.user_id == current_user.id
      medium.destroy
      redirect_to @game, notice: t("game_media.removed"), status: :see_other
    elsif current_user.admin?
      medium.hide!
      redirect_to @game, notice: t("game_media.hidden"), status: :see_other
    else
      redirect_to @game, alert: t("game_media.not_allowed"), status: :see_other
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def contributor?
    return true if can_manage?(@game)

    @game.participations.approved.exists?(user_id: current_user.id)
  end
end
