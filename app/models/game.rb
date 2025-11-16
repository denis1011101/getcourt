class Game < ApplicationRecord
  belongs_to :court
  belongs_to :user
  has_many :participations, dependent: :destroy

  validates :date, presence: { message: "must be present" }

  def date
    d = read_attribute(:date)
    begin
      Date.parse(d.to_s) if d.present?
    rescue
      nil
    end
  end

  def time
    read_attribute(:time)
  end

  def next_date
    d = date
    return nil unless d
    if recurring?
      d += 7 while d < Date.today
      d
    else
      d
    end
  end

  def next_time
    time
  end

  def should_reset_participations?(as_of = Date.today)
    return false unless recurring?
    nd = next_date
    return false unless nd
    last_participations_reset_at.nil? || last_participations_reset_at < nd
  end

  def mark_participations_reset!(date = next_date)
    update_column(:last_participations_reset_at, date)
  end
end
