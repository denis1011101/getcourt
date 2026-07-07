class Season
  def self.current_start
    Time.zone.now.beginning_of_year
  end

  def self.current_label
    Time.zone.now.year
  end
end
