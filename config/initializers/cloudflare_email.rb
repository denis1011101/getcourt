require Rails.root.join("app/mailers/delivery_methods/cloudflare_email_delivery").to_s

ActionMailer::Base.add_delivery_method(
  :cloudflare_email,
  DeliveryMethods::CloudflareEmailDelivery,
  account_id: Rails.application.credentials.dig(:cloudflare_email, :account_id),
  api_token: Rails.application.credentials.dig(:cloudflare_email, :api_token),
  from: Rails.application.credentials.dig(:cloudflare_email, :from)
)
