class PostToThreadsJob < ApplicationJob
  queue_as :default

  def perform(game_id, locale)
    return unless ThreadsPostingService.configured?
    return if ENV["APP_HOST"].to_s.strip.blank?

    game = Game.find_by(id: game_id)
    return unless game
    return if game.threads_post_id.present?
    return unless game.urgent_player_search?

    builder = ThreadsPostBuilder.new(game, locale: locale)
    post_id = ThreadsPostingService.new(
      text: builder.text,
      image_url: builder.image_url
    ).call

    if post_id
      game.update_columns(threads_post_id: post_id, threads_posted_at: Time.current)
    end
  end
end
