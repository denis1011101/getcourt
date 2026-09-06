class PagesController < ApplicationController
  # public pages
  skip_before_action :authenticate_user!, only: %i[contacts mission partnership partnership_inquiry tennis_formats_and_rules ntrp_level_guide api_and_mcp privacy_policy]

  def contacts
  end

  def mission
  end

  def partnership
  end

  def partnership_inquiry
    # honeypot: bots fill hidden fields
    if params[:website].present?
      flash[:notice] = "Thank you! We will get back to you soon."
      redirect_to partnership_path and return
    end

    # rate limit: 3 submissions per IP per hour
    cache_key = "partnership_inquiry:#{request.remote_ip}"
    count = Rails.cache.read(cache_key).to_i
    if count >= 3
      flash[:alert] = "Too many submissions. Please try again later."
      redirect_to partnership_path and return
    end

    name  = params[:name].to_s.strip.first(200)
    org   = params[:organization].to_s.strip.first(200)
    email = params[:email].to_s.strip.first(200)
    msg   = params[:message].to_s.strip.first(1000)

    if name.blank? || email.blank?
      flash[:alert] = "Please fill in your name and email."
      redirect_to partnership_path and return
    end

    text = "Partnership inquiry from #{name}" \
           "#{org.present? ? " (#{org})" : ""}\n" \
           "Email: #{email}\n" \
           "Message: #{msg.presence || '—'}"

    Telegram::AdminNotifier.notify_partnership(text)
    Rails.cache.write(cache_key, count + 1, expires_in: 1.hour)
    flash[:notice] = "Thank you! We will get back to you soon."
    redirect_to partnership_path
  end

  def privacy_policy
  end

  def tennis_formats_and_rules
  end

  def ntrp_level_guide
  end

  def api_and_mcp
  end
end
