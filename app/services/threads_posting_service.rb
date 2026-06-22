require "net/http"
require "json"

class ThreadsPostingService
  HOST = "https://graph.threads.net".freeze
  VERSION = "v1.0".freeze

  def self.configured?
    ENV["THREADS_ACCESS_TOKEN"].to_s.strip.present? &&
      ENV["THREADS_USER_ID"].to_s.strip.present?
  end

  def initialize(text:, image_url: nil)
    @text = text
    @image_url = image_url
  end

  def call
    return nil unless self.class.configured?

    creation_id = create_container
    return nil unless creation_id

    publish(creation_id)
  end

  private

  def create_container
    params = { text: @text, access_token: ENV["THREADS_ACCESS_TOKEN"] }
    if @image_url.present?
      params[:media_type] = "IMAGE"
      params[:image_url] = @image_url
    else
      params[:media_type] = "TEXT"
    end

    response = Net::HTTP.post_form(URI("#{HOST}/#{VERSION}/#{ENV["THREADS_USER_ID"]}/threads"), params)
    JSON.parse(response.body)["id"]
  rescue => e
    Rails.logger.error("Threads create_container failed: #{e.message}")
    nil
  end

  def publish(creation_id)
    response = Net::HTTP.post_form(
      URI("#{HOST}/#{VERSION}/#{ENV["THREADS_USER_ID"]}/threads_publish"),
      creation_id: creation_id,
      access_token: ENV["THREADS_ACCESS_TOKEN"]
    )
    JSON.parse(response.body)["id"]
  rescue => e
    Rails.logger.error("Threads publish failed: #{e.message}")
    nil
  end
end
