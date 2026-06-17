namespace :coconique do
  namespace :sms do
    desc "Check Coconique SMS/Twilio Verify configuration without sending SMS"
    task doctor: :environment do
      provider = CoconiquePhoneVerificationAttempt.default_provider
      puts "Coconique SMS provider: #{provider}"
      puts "fake_provider?: #{CoconiquePhoneVerificationAttempt.fake_provider?}"

      if provider == "twilio_verify"
        puts "Twilio Verify configured?: #{Coconique::SmsVerifications::TwilioVerifyProvider.configured?}"
        %w[
          TWILIO_ACCOUNT_SID
          TWILIO_AUTH_TOKEN
          TWILIO_VERIFY_SERVICE_SID
          TWILIO_VERIFY_CHANNEL
          TWILIO_VERIFY_LOCALE
          TWILIO_VERIFY_API_BASE_URL
        ].each do |key|
          value = ENV[key].to_s
          masked = if value.blank?
            "(missing)"
          elsif key.include?("TOKEN")
            "#{value[0, 4]}...#{value[-4, 4]}"
          else
            value
          end
          puts "#{key}: #{masked}"
        end
      else
        puts "Twilio Verify is not active. Set COCONIQUE_SMS_PROVIDER=twilio_verify when you are ready."
      end
    end
  end
end
