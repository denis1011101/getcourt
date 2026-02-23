class Tournament < ApplicationRecord
  belongs_to :user, optional: true
  has_many :games
  has_many :tournament_courts
  has_many :courts, through: :tournament_courts

  # participants who joined the tournament
  has_many :tournament_participants, dependent: :destroy

  # bracket_data stores generated bracket structure (JSON), selected_variant stores index
  # add corresponding migrations (see db/migrate below)

  def started?
    return false unless start_date.present?

    t = read_attribute(:time)
    if t.present?
      hh = t.respond_to?(:strftime) ? t.strftime("%H").to_i : t.to_s.split(":").first.to_i
      mm = t.respond_to?(:strftime) ? t.strftime("%M").to_i : (t.to_s.split(":")[1] || 0).to_i
      start_at = Time.zone.local(start_date.year, start_date.month, start_date.day, hh, mm, 0)
      Time.current >= start_at
    else
      Date.current >= start_date
    end
  rescue
    false
  end
end
