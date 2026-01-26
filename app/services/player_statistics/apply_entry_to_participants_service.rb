module PlayerStatistics
  class ApplyEntryToParticipantsService
    def initialize(game:, actor:, data:, source: "telegram", recorded_at: Time.current, include_creator: true)
      @game = game
      @actor = actor
      @data = data
      @source = source.to_s
      @recorded_at = recorded_at
      @include_creator = include_creator
    end

    def call
      users = []

      users << @game.user if @include_creator
      users.concat(@game.participations.includes(:user).map(&:user))

      users = users.compact.uniq { |u| u.id }

      users.map do |u|
        ApplyEntryService.new(
          user: u,
          game: @game,
          actor: @actor,
          data: @data,
          source: @source,
          recorded_at: @recorded_at
        ).call
      end
    end
  end
end
