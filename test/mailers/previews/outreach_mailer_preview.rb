# Preview the outreach email at http://localhost:3000/rails/mailers/outreach_mailer
class OutreachMailerPreview < ActionMailer::Preview
  def court_booking_pitch
    OutreachMailer.court_booking_pitch(OutreachContact.new(email: "preview@example.com", name: "Ace Tennis Club"))
  end
end
