class SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: %i[new create]

  def new
    # renders app/views/sessions/new.html.erb
  end

  def create
    email = params[:email].to_s.strip.downcase
    if email.blank?
      redirect_to new_session_path, alert: "Email required" and return
    end

    user = User.find_or_create_by(email: email) do |u|
      u.name = email.split("@").first.titleize
    end

    sign_in(user)
    redirect_to root_path, notice: "Signed in as #{user.email}"
  end

  def destroy
    sign_out
    redirect_to root_path, notice: "Signed out"
  end
end
