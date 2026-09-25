class ApplicationCable::Connection < ActionCable::Connection::Base
  identified_by :current_user

  # Через кабель идут только Turbo Streams, а имена их стримов подписаны: на
  # живое табло подпишется лишь тот, кому страница его отдала. Поэтому гостей
  # не отклоняем — табло матча, как и страница игры, открыто всем.
  def connect
    self.current_user = find_user
  end

  private

  # Вход живёт в сессии (session[:user_id], см. ApplicationController), а не
  # в отдельной подписанной куке.
  def find_user
    session = cookies.encrypted[Rails.application.config.session_options[:key]]
    user_id = session.is_a?(Hash) ? session["user_id"] : nil
    User.find_by(id: user_id) if user_id.present?
  end
end
