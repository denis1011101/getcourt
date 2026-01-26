module Ratings
  class EloRatingService
    DEFAULT_K = 32.0

    def initialize(current_rating:, opponent_rating:, result:, k_factor: DEFAULT_K)
      @current_rating = current_rating.to_f
      @opponent_rating = opponent_rating.to_f
      @result = result.to_f # 1.0 win, 0.5 draw, 0.0 loss
      @k_factor = k_factor.to_f
    end

    def call
      expected = 1.0 / (1.0 + 10.0**((@opponent_rating - @current_rating) / 400.0))
      (@current_rating + @k_factor * (@result - expected)).round(1)
    end
  end
end
