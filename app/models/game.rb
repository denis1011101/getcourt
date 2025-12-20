class Game < ApplicationRecord
  belongs_to :court
  belongs_to :user
  has_many :participations, dependent: :destroy
  has_many :prebookings, dependent: :destroy
  has_many :prebooking_cancellations, dependent: :destroy

  validates :date, presence: { message: "must be present" }

  validates :players_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :prebooking_requires_recurring

  def prebooking_requires_recurring
    if prebooking_enabled? && !recurring?
      errors.add(:prebooking_enabled, "can be enabled only for repeating (weekly) games")
    end
  end

  # return true if prebookings behaviour is enabled for this game
  def prebooking_enabled?
    if respond_to?(:prebooking) # legacy/possible boolean column :prebooking
      !!self.prebooking
    elsif respond_to?(:prebooking_enabled) # alternative column name
      !!self.prebooking_enabled
    else
      prebookings.exists?
    end
  end

  # Ensure prebooking slots exist for next n occurrences (default 4)
  def ensure_prebookings_for_next_weeks(n = 4)
    return unless prebooking_enabled?

    dates = []
    if recurring?
      d = next_date || date
      while dates.size < n
        dates << d
        d += 7
      end
    else
      dates << date if date.present?
    end

    # create slots for each date and slot index up to players_count
    dates.each do |d|
      (1..(players_count.to_i > 0 ? players_count.to_i : 4)).each do |slot|
        prebookings.find_or_create_by!(date: d, slot_index: slot)
      end
    end
  end

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
      # advance to first occurrence >= today
      d += 7 while d < Date.today

      # skip cancelled occurrences
      max_iters = 520 # safety cap (~10 years)
      iter = 0
      while prebooking_cancellations.exists?(date: d) && iter < max_iters
        d += 7
        iter += 1
      end

      return nil if prebooking_cancellations.exists?(date: d) # all skipped
      d
    else
      return nil if prebooking_cancellations.exists?(date: d)
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
