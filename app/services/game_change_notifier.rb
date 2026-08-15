class GameChangeNotifier
  # What people plan around. Search toggles, prebooking flags and bookkeeping
  # columns (*_job_id, coach_invitation_status) are none of a participant's
  # business, so changing those wakes nobody.
  TRACKED_FIELDS = %w[
    date time court_id sport duration_minutes players_count with_coach surface environment comment
  ].freeze

  def self.notify(game:, actor:, changes:)
    new(game: game, actor: actor, changes: changes).notify
  end

  def initialize(game:, actor:, changes:)
    @game = game
    @actor = actor
    @changes = (changes || {}).slice(*TRACKED_FIELDS)
  end

  def notify
    return false if @changes.empty?

    recipients.each do |user|
      # One unreachable recipient must not break the edit that triggered this.
      NotificationDelivery.deliver(user: user, notification: notification)
    rescue => error
      Rails.logger.error("[GameChangeNotifier] game=#{@game.id} user=#{user.id}: #{error.class}: #{error.message}")
    end

    recipients.any?
  end

  private

  # Everyone who planned their evening around this game, except whoever made the
  # edit — they already know. Matched by id, not by channel: the organiser can
  # edit from the bot and read notifications by email.
  def recipients
    @recipients ||= begin
      participants = @game.participations.includes(:user).reject(&:guest?).map(&:user)
      participants << @game.coach if @game.coach_accepted?

      participants.compact.uniq(&:id).reject { |user| user.id == @actor&.id }
    end
  end

  def notification
    @notification ||= NotificationDelivery::Notification.new(
      subject: ->(locale) { I18n.t("user_mailer.notification.game_change_subject", locale: locale, game_id: @game.id) },
      body: ->(locale) { body_for(locale) },
      actions: lambda do |locale|
        [ { label: I18n.t("user_mailer.notification.view_game", locale: locale), url: game_url, telegram: false } ]
      end
    )
  end

  def body_for(locale)
    lines = [ Telegram::I18n.t(:game_changed_title, locale: locale) ]
    lines << Telegram::Handlers::GamesHandler.game_label(@game, owner: @game.user, locale: locale)
    lines << ""
    lines += @changes.map { |field, (from, to)| change_line(field, from, to, locale) }
    # A weekly game moves as a series, so say it — otherwise people read it as
    # "the nearest date moved" and keep the old time for the week after.
    lines << Telegram::I18n.t(:game_changed_series_note, locale: locale) if @game.recurring?

    "#{lines.compact.join("\n")}\n\n#{game_url}"
  end

  def change_line(field, from, to, locale)
    Telegram::I18n.t(
      :game_changed_line,
      locale: locale,
      field: Telegram::I18n.t("game_changed_field_#{field}".to_sym, locale: locale),
      from: format_value(field, from, locale),
      to: format_value(field, to, locale)
    )
  end

  def format_value(field, value, locale)
    return Telegram::I18n.t(:game_changed_blank, locale: locale) if value.nil? || value.to_s.strip.empty?

    case field
    when "date"
      I18n.l(value.to_date, format: :telegram, locale: locale)
    when "time"
      Telegram::Helpers::GameFormatting.format_time_hhmm(value, locale: locale) || value.to_s
    when "court_id"
      Court.find_by(id: value)&.name || "##{value}"
    when "sport"
      Telegram::Helpers::GameFormatting.sport_label(value, locale: locale) || value.to_s
    when "with_coach"
      Telegram::I18n.t(value ? :game_changed_yes : :game_changed_no, locale: locale)
    when "duration_minutes"
      Telegram::I18n.t(:game_changed_minutes, locale: locale, count: value)
    else
      value.to_s
    end
  end

  def game_url
    @game_url ||= "#{ENV.fetch("APP_HOST", "https://getcourt.co")}/games/#{@game.id}"
  end
end
