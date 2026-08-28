# Правка плана тренировки, которую предложил участник игры.
#
# Хозяин занятия — организатор: он решает, пускать ли правку. Дальше всё
# зависит от того, что выбрал автор: применить сразу или спросить остальных.
class TrainingPlanProposal < ApplicationRecord
  belongs_to :game
  belongs_to :user
  has_many :training_plan_votes, dependent: :destroy

  STATUSES = %w[pending voting applied rejected].freeze
  MODES = %w[vote direct].freeze

  before_validation :normalize_training_block_ids

  validates :status, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }
  validates :comment, length: { maximum: 500 }, allow_blank: true
  validate :plan_has_blocks
  validate :game_is_a_training

  scope :open, -> { where(status: %w[pending voting]) }
  scope :recent_first, -> { order(created_at: :desc) }

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  def open?
    pending? || voting?
  end

  def direct?
    mode == "direct"
  end

  # Блоки в том порядке, в каком их выстроил автор правки.
  def blocks
    by_id = TrainingBlock.where(id: training_block_ids).index_by(&:id)
    training_block_ids.filter_map { |id| by_id[id] }
  end

  # Без «да» организатора правка не идёт ни на голосование, ни в план.
  def approve!
    return false unless pending?

    if direct?
      apply!
    else
      update!(status: "voting")
      # Голосовать может быть некому: тренировка на одного — тоже тренировка.
      settle!
    end
    true
  end

  def reject!
    return false unless open?

    update!(status: "rejected")
  end

  def apply!
    # Блок могли удалить из библиотеки, пока правка ждала своей очереди: в план
    # ставим то, что уцелело, а если не уцелело ничего — применять нечего.
    ids = blocks.map(&:id)
    return update!(status: "rejected") if ids.empty?

    transaction do
      game.replace_training_plan!(ids)
      update!(status: "applied")
    end
  end

  # Голосуют те, кто выйдет на корт. Автор правки уже «за» — бюллетень ему не нужен.
  def voter_ids
    @voter_ids ||= game.team_member_ids - [ user_id ]
  end

  def voted?(voter)
    training_plan_votes.exists?(user_id: voter&.id)
  end

  def vote!(voter, in_favor)
    return false unless voting? && voter_ids.include?(voter&.id)

    training_plan_votes.find_or_initialize_by(user_id: voter.id).update!(in_favor: in_favor)
    @ballots = nil
    settle!
    true
  end

  def votes_in_favor
    ballots.count(&:in_favor?) + 1
  end

  def votes_against
    ballots.count { |ballot| !ballot.in_favor? }
  end

  def votes_expected
    voter_ids.size + 1
  end

  private

  # Голос того, кто уже вышел из игры, не считаем: иначе бюллетень ушедшего
  # решает за тех, кто на корт всё-таки выйдет.
  def ballots
    @ballots ||= training_plan_votes.where(user_id: voter_ids).to_a
  end

  # Ждать последний голос незачем: как только одна сторона взяла большинство,
  # остальные бюллетени ничего не меняют.
  def settle!
    if votes_in_favor * 2 > votes_expected
      apply!
    elsif votes_against * 2 >= votes_expected
      update!(status: "rejected")
    end
  end

  def normalize_training_block_ids
    self.training_block_ids = Array(training_block_ids).map(&:to_i).uniq.reject(&:zero?)
  end

  def plan_has_blocks
    errors.add(:training_block_ids, :blank) if training_block_ids.empty?
  end

  def game_is_a_training
    errors.add(:game, :invalid) unless game&.training?
  end
end
