module Weather
  module Icons
    def self.for(condition_type)
      case condition_type.to_s.upcase
      when /THUNDER/
        "⛈️"
      when /SNOW|SLEET|ICE/
        "❄️"
      when /RAIN|SHOWERS/
        "🌧️"
      when /WIND/
        "💨"
      when /CLOUD/
        "⛅"
      when /CLEAR|SUNNY/
        "☀️"
      else
        "🌡️"
      end
    end
  end
end
