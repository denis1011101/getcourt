class OutreachMailer < ApplicationMailer
  UNSUBSCRIBE_MAILTO = "mailto:hello@getcourt.co?subject=Unsubscribe".freeze

  # Письмо всегда на английском: список холодный, языка получателя мы не знаем.
  def court_booking_pitch(contact)
    @partnership_url = partnership_url

    I18n.with_locale(:en) do
      mail(
        to: contact.email,
        subject: t("outreach_mailer.court_booking_pitch.subject"),
        "List-Unsubscribe" => "<#{UNSUBSCRIBE_MAILTO}>"
      )
    end
  end
end
