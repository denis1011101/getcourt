module GamesHelper
  def format_duration_minutes(minutes)
    minutes = minutes.to_i
    return "" if minutes <= 0

    hours = minutes / 60
    rest = minutes % 60
    parts = []
    parts << "#{hours}h" if hours > 0
    parts << "#{rest}m" if rest > 0
    parts.join(" ")
  end
end
