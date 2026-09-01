module Social
  # На /tennis_life имена игроков и так публичны, но внешняя лента — другой
  # контекст, поэтому наружу отдаём имя и первую букву фамилии. Правило живёт в
  # одном месте, чтобы не разъехалось между вариантами daily-поста.
  module Names
    def self.short(name)
      parts = name.to_s.strip.split(/\s+/)
      return "" if parts.empty?
      return parts.first if parts.size == 1

      "#{parts.first} #{parts[1][0].upcase}."
    end
  end
end
