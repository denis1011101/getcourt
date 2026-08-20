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
      redirect_to @game, notice: upload_notice(medium)
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
    return true if can_send_training_video?(@game)

    @game.participations.approved.exists?(user_id: current_user.id)
  end

  # Один и тот же file input принимает и фото, и видео, а рассылать мы умеем
  # только ролики. Поэтому галочка на фотографии не проглатывается молча:
  # файл сохраняем, но честно говорим, что рассылки не будет.
  def upload_notice(medium)
    if notify_participants?(medium)
      SendTrainingVideoJob.perform_later(medium.id)
      t("game_media.uploaded_and_queued")
    elsif notify_requested? && can_send_training_video?(@game)
      t("game_media.uploaded_videos_only")
    else
      t("game_media.uploaded")
    end
  end

  def notify_participants?(medium)
    medium.video? && can_send_training_video?(@game) && notify_requested?
  end

  def notify_requested?
    ActiveModel::Type::Boolean.new.cast(params[:notify_participants])
  end
end
