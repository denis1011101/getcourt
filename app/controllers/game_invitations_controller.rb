class GameInvitationsController < ApplicationController
  before_action :set_game
  before_action :authorize_manage_game!

  def create
    handles = invite_handles
    return redirect_to @game, alert: "Enter at least one Telegram username." if handles.empty?

    result = send_invitations(handles)
    if result[:sent].any?
      current_user.remember_invite_handles(handles)
      redirect_to @game, notice: invitation_notice(result)
    else
      redirect_to @game, alert: invitation_notice(result)
    end
  end

  private

  def set_game
    @game = Game.find(params[:game_id])
  end

  def authorize_manage_game!
    head :forbidden unless can_manage?(@game)
  end

  def invite_handles
    params[:usernames].to_s.scan(/@?[A-Za-z0-9_]{5,32}/).map { |handle| handle.delete_prefix("@").downcase }.uniq
  end

  def send_invitations(handles)
    result = { sent: [], not_found: [], skipped_self: [], ambiguous: [], failed: [] }
    resolve_users_by_handles(handles).each do |handle, candidates|
      if candidates.empty?
        result[:not_found] << "@#{handle}"
        next
      end

      user = pick_recipient(candidates)
      if user.nil?
        result[:ambiguous] << "@#{handle}"
        next
      end

      if user.id == current_user.id
        result[:skipped_self] << "@#{handle}"
        next
      end

      response = deliver_invitation(user)
      if response == false || (response.is_a?(Hash) && response["ok"] == false)
        result[:failed] << "@#{handle}"
      else
        result[:sent] << "@#{handle}"
      end
    end
    result
  end

  # Один ник может висеть на нескольких записях: старая ботовая учётка и живая
  # веб-регистрация. Берём ту, до которой сообщение дойдёт, — с привязанным
  # чатом. Если таких несколько, это разные люди с одинаковым ником в базе:
  # выбирать за пользователя нельзя, честнее сказать, что ник неоднозначный.
  def pick_recipient(candidates)
    return candidates.first if candidates.one?

    with_chat = candidates.select { |candidate| candidate.telegram_chat_id.present? }
    with_chat.one? ? with_chat.first : nil
  end

  def deliver_invitation(user)
    GameInvitationDelivery.new(
      game: @game,
      inviter: current_user,
      game_url: invitation_game_url(@game)
    ).deliver(user: user)
  end

  def invitation_game_url(game)
    Rails.application.routes.url_helpers.game_url(game, host: request.host_with_port, protocol: request.protocol)
  end

  def invitation_notice(result)
    parts = []
    parts << "Sent: #{result[:sent].join(', ')}" if result[:sent].any?
    parts << "Not found: #{result[:not_found].join(', ')}" if result[:not_found].any?
    parts << "Skipped self: #{result[:skipped_self].join(', ')}" if result[:skipped_self].any?
    parts << "Several accounts match: #{result[:ambiguous].join(', ')}" if result[:ambiguous].any?
    parts << "Failed: #{result[:failed].join(', ')}" if result[:failed].any?
    parts.presence&.join(". ") || "No invitations sent."
  end

  # Возвращает все совпадения по нику, а не последнее: раньше запись, найденная
  # позже, молча затирала предыдущую, и приглашение уходило в случайную из них.
  def resolve_users_by_handles(handles)
    users_by_handle = Hash.new { |hash, key| hash[key] = [] }
    db_handles = handles + handles.map { |handle| "@#{handle}" }
    username_scopes(db_handles).each do |scope, column|
      scope.find_each do |user|
        value = user.public_send(column).to_s.delete_prefix("@").downcase
        users_by_handle[value] << user if value.present?
      end
    end
    User.where(telegram_chat_id: handles).find_each do |user|
      users_by_handle[user.telegram_chat_id.to_s] << user
    end

    handles.index_with { |handle| users_by_handle[handle].uniq }
  end

  def username_scopes(handles)
    [
      [ users_matching_telegram_usernames(handles), :telegram_username ],
      [ users_matching_usernames(handles), :username ]
    ]
  end

  def users_matching_telegram_usernames(handles)
    users_matching_lowered_column(:telegram_username, handles)
  end

  def users_matching_usernames(handles)
    return User.none unless User.column_names.include?("username")

    users_matching_lowered_column(:username, handles)
  end

  def users_matching_lowered_column(column, handles)
    lowered_column = Arel::Nodes::NamedFunction.new("LOWER", [ User.arel_table[column] ])
    User.where(lowered_column.in(handles))
  end
end
