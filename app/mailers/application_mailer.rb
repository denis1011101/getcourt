class ApplicationMailer < ActionMailer::Base
  default from: -> {
    Rails.application.credentials.dig(:cloudflare_email, :from) ||
      ("no-reply@getcourt.co" unless Rails.env.production?)
  }
  layout "mailer"
end
