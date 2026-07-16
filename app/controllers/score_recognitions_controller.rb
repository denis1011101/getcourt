class ScoreRecognitionsController < ApplicationController
  MAX_PHOTO_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif].freeze

  def create
    photo = params[:photo]
    return render_error(:photo_required) unless photo.respond_to?(:content_type)
    return render_error(:invalid_photo_type) unless ALLOWED_CONTENT_TYPES.include?(photo.content_type)
    return render_error(:photo_too_large, :content_too_large) if photo.size > MAX_PHOTO_SIZE

    result = Ai::ScoreFromPhotoService.new.call(photo.tempfile.path)
    render json: result
  rescue JSON::ParserError, Timeout::Error, RubyLLM::Error, RubyLLM::UnsupportedAttachmentError => error
    Rails.logger.error("[ScoreRecognitionsController] #{error.class}: #{error.message}")
    render_error(:recognition_failed)
  end

  private

  def render_error(key, status = :unprocessable_entity)
    render json: { error: I18n.t("score_recognitions.errors.#{key}") }, status: status
  end
end
