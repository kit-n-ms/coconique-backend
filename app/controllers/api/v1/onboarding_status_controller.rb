module Api
  module V1
    class OnboardingStatusController < ApplicationController
      before_action :require_login!

      def show
        app_key = params.fetch(:app_key, "coconique")
        app_keys = onboarding_app_keys(app_key)

        profile_completed = current_user.user_profile.present?

        terms_accepted = current_user.terms_acceptances.exists?(
          app_key: app_keys,
          terms_version: ENV.fetch("CURRENT_TERMS_VERSION", "2026-05-01"),
          privacy_version: ENV.fetch("CURRENT_PRIVACY_VERSION", "2026-05-01")
        )

        app_membership_started = current_user.app_memberships.exists?(
          app_key: app_keys,
          status: :active
        )

        render_success(
          {
            onboarding: {
              app_key: app_key,
              email_verified: current_user.email_verified?,
              profile_completed: profile_completed,
              terms_accepted: terms_accepted,
              app_membership_started: app_membership_started,
              next_step: next_step(
                email_verified: current_user.email_verified?,
                profile_completed: profile_completed,
                terms_accepted: terms_accepted,
                app_membership_started: app_membership_started
              )
            }
          }
        )
      end

      private

      # Step 6-2でフロントの既定APP_KEYを sample_app から coconique に変更したため、
      # ローカル開発DBに残っている旧 onboarding レコードもCoconiqueの完了済みとして扱う。
      # 新規作成されるレコードは引き続き coconique で保存する。
      def onboarding_app_keys(app_key)
        keys = [app_key.to_s]
        keys << "sample_app" if app_key.to_s == "coconique"
        keys.uniq
      end

      def next_step(email_verified:, profile_completed:, terms_accepted:, app_membership_started:)
        return "email_verification" unless email_verified
        return "profile" unless profile_completed
        return "terms" unless terms_accepted
        return "start" unless app_membership_started

        "dashboard"
      end
    end
  end
end
