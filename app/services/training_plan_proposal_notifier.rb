# Разносит правку плана по тем, от кого зависит её судьба: организатору — на
# подтверждение, составу — на голосование, всем — результат.
class TrainingPlanProposalNotifier
  PROGRAM_LIMIT = 600

  def self.approval_requested(proposal)
    new(proposal).approval_requested
  end

  def self.vote_started(proposal)
    new(proposal).vote_started
  end

  def self.settled(proposal)
    new(proposal).settled
  end

  def initialize(proposal)
    @proposal = proposal
  end

  # Судьбу правки решает организатор, поэтому просьба уходит ему одному.
  def approval_requested
    owner = game.user
    return false if owner.blank? || owner.id == proposal.user_id

    deliver(owner, notification(:plan_proposal_title, hint_key: :plan_proposal_approve_hint))
    true
  end

  # Бюллетень получают те, кто выйдет на корт: кнопки «за» и «против» приходят
  # прямо в чат, а тем, кто читает почту, остаётся ссылка на игру.
  def vote_started
    voters.each { |voter| deliver(voter, notification(:plan_proposal_vote_title, hint_key: :plan_proposal_vote_hint, vote_buttons: true)) }
    voters.any?
  end

  def settled
    return false if proposal.open?

    key = proposal.applied? ? :plan_proposal_applied_title : :plan_proposal_rejected_title
    (voters + [ proposal.user ]).uniq(&:id).each { |user| deliver(user, notification(key)) }
    true
  end

  private

  attr_reader :proposal

  def game
    proposal.game
  end

  def voters
    @voters ||= User.where(id: proposal.voter_ids).to_a
  end

  def deliver(user, notification)
    NotificationDelivery.deliver(user: user, notification: notification)
  rescue => error
    # Один недоступный адресат не должен ронять правку, из-за которой всё затевалось.
    Rails.logger.error("[TrainingPlanProposalNotifier] proposal=#{proposal.id} user=#{user.id}: #{error.class}: #{error.message}")
  end

  def notification(title_key, hint_key: nil, vote_buttons: false)
    NotificationDelivery::Notification.new(
      subject: ->(locale) { ::I18n.t("user_mailer.notification.training_plan_proposal_subject", locale: locale, game_id: game.id) },
      body: ->(locale, channel) { body_for(title_key, hint_key, locale, channel) },
      actions: ->(locale) { actions_for(locale, vote_buttons) }
    )
  end

  def body_for(title_key, hint_key, locale, channel)
    author = Telegram::Helpers::UserLookup.display_name(
      proposal.user,
      fallback: Telegram::I18n.t(:user_fallback, locale: locale),
      channel: channel
    )

    lines = [
      Telegram::I18n.t(title_key, locale: locale, name: author),
      Telegram::Handlers::GamesHandler.game_label(game, owner: game.user, locale: locale, channel: channel),
      Telegram::I18n.t(:plan_proposal_plan_label, locale: locale, items: plan_text(locale)),
      comment_line(locale),
      (Telegram::I18n.t(hint_key, locale: locale) if hint_key)
    ]

    "#{lines.compact.join("\n")}\n\n#{game_url}"
  end

  def comment_line(locale)
    text = proposal.comment.to_s.strip
    Telegram::I18n.t(:plan_proposal_comment_label, locale: locale, text: text) if text.present?
  end

  # Режем по целым блокам: длинный план не должен выбивать сообщение за предел
  # телеграма, а обрывок названия посреди слова всё равно не прочесть.
  def plan_text(locale)
    titles = proposal.blocks.map { |block| block.title.to_s.strip }
    kept = []
    titles.each do |title|
      break if kept.any? && (kept + [ title ]).join(", ").length > PROGRAM_LIMIT
      kept << title
    end

    text = kept.join(", ")
    dropped = titles.size - kept.size
    dropped.positive? ? "#{text} #{Telegram::I18n.t(:program_more, locale: locale, count: dropped)}" : text
  end

  def actions_for(locale, vote_buttons)
    actions = []
    if vote_buttons
      actions << { label: Telegram::I18n.t(:plan_vote_yes, locale: locale), callback_data: "game:plan_vote:#{proposal.id}:yes", row: 0 }
      actions << { label: Telegram::I18n.t(:plan_vote_no, locale: locale), callback_data: "game:plan_vote:#{proposal.id}:no", row: 0 }
    end
    actions << { label: ::I18n.t("user_mailer.notification.view_game", locale: locale), url: game_url, telegram: false }
    actions
  end

  def game_url
    @game_url ||= "#{ENV.fetch("APP_HOST", "https://getcourt.co")}/games/#{game.id}"
  end
end
