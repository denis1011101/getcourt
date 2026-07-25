class Tournament < ApplicationRecord
  FORMATS = %w[singles doubles].freeze

  enum :tournament_type, { bracket: "bracket", round_robin: "round_robin" }

  belongs_to :user, optional: true
  has_many :games, dependent: :nullify
  has_many :tournament_matches, dependent: :destroy
  has_many :tournament_courts, dependent: :destroy
  has_many :courts, through: :tournament_courts
  has_many :tournament_dates, dependent: :destroy

  # participants who joined the tournament
  has_many :tournament_participants, dependent: :destroy

  validates :name, presence: true
  validates :players_count, numericality: { only_integer: true, greater_than: 1 }, allow_nil: true
  validates :games_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :format, inclusion: { in: FORMATS }, allow_blank: true
  validate :end_date_on_or_after_start_date

  def doubles?
    format.to_s == "doubles"
  end

  def players_per_game
    doubles? ? 4 : 2
  end

  def approved_participants
    tournament_participants.approved
  end

  def pending_participants
    tournament_participants.pending
  end

  # Uses the loaded association when the caller preloaded it (index cards), a query otherwise.
  def approved_participants_count
    if tournament_participants.loaded?
      tournament_participants.count(&:approved?)
    else
      tournament_participants.approved.count
    end
  end

  def spots_left
    if players_count.to_i.positive?
      [ players_count - approved_participants_count, 0 ].max
    end
  end

  def full?
    spots_left == 0
  end

  def organizer?(other_user)
    other_user.present? && (other_user.id == user_id || other_user.admin?)
  end

  def participant_for(other_user)
    tournament_participants.find_by(user: other_user) if other_user.present?
  end

  def default_court
    courts.first
  end

  def starts_at
    return nil if start_date.blank?

    hours, minutes = start_hour_and_minute
    Time.zone.local(start_date.year, start_date.month, start_date.day, hours, minutes, 0)
  rescue ArgumentError, RangeError
    nil
  end

  def started?
    starts_at.present? && Time.current >= starts_at
  end

  def finished?
    cutoff = end_date.presence || start_date
    cutoff.present? && cutoff < Date.current
  end

  def days
    if start_date.present?
      (start_date..(end_date.presence || start_date)).to_a
    else
      []
    end
  end

  # An open-ended tournament (no end date) covers everything from its start on.
  def covers?(day)
    return true if day.blank? || start_date.blank?

    day >= start_date && (end_date.blank? || day <= end_date)
  end

  # Dates for +count+ games, spread evenly over the days the tournament runs.
  def schedule_dates_for(count)
    return [] unless count.to_i.positive?
    return Array.new(count) { Date.current } if days.empty?

    Array.new(count) { |index| days[index * days.size / count] }
  end

  # A match played now belongs to the day it was played, kept inside the tournament window.
  def date_for_played_match
    not_before_start = [ Date.current, start_date.presence ].compact.max
    [ not_before_start, end_date.presence ].compact.min
  end

  # Tournament matches are mirrored as regular games, so they show up in the games
  # list next to everything else players organize.
  def create_game!(organizer:, player_ids: [], date: nil)
    game = games.create!(
      court: default_court,
      user: organizer,
      date: date || start_date || Date.current,
      time: time,
      sport: "tennis",
      players_count: players_per_game
    )

    player_ids.compact.uniq.each do |player_id|
      participation = Participation.find_or_initialize_by(game_id: game.id, user_id: player_id)
      participation.status = "approved"
      participation.save!
    end

    game
  end

  private
    def start_hour_and_minute
      value = read_attribute(:time)
      if value.blank?
        [ 0, 0 ]
      elsif value.respond_to?(:strftime)
        [ value.strftime("%H").to_i, value.strftime("%M").to_i ]
      else
        parts = value.to_s.split(":")
        [ parts[0].to_i, parts[1].to_i ]
      end
    end

    def end_date_on_or_after_start_date
      return if start_date.blank? || end_date.blank?

      if end_date < start_date
        errors.add(:end_date, :on_or_after_start_date)
      end
    end
end
