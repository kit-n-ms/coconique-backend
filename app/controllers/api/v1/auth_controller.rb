module Api
  module V1
    class AuthController < ApplicationController
      rate_limit(
        to: 60,
        within: 1.minute,
        only: :csrf,
        by: -> { request.remote_ip },
        with: -> { render_rate_limited },
        name: "auth_csrf"
      )

      rate_limit(
        to: 5,
        within: 10.minutes,
        only: :signup,
        by: -> { request.remote_ip },
        with: -> { render_rate_limited },
        name: "auth_signup"
      )

      rate_limit(
        to: 10,
        within: 3.minutes,
        only: :login,
        by: -> {
          email = params[:email].to_s.strip.downcase
          "#{request.remote_ip}:#{email}"
        },
        with: -> { render_rate_limited },
        name: "auth_login"
      )

      before_action :require_login!, only: [:me]

      def csrf
        issue_session_csrf_cookie!

        render_success(
          {
            csrf_header_name: "X-CSRF-Token",
            csrf_cookie_name: ENV.fetch("CSRF_COOKIE_NAME", "km_auth_starter_csrf")
          }
        )
      end

      def signup
        user = User.create!(
          email: signup_params[:email],
          password: signup_params[:password],
          password_confirmation: signup_params[:password_confirmation]
        )

        sign_in!(user)

        verification, token = EmailVerification.create_for!(user: user)
        AuthMailer.email_verification(user, token).deliver_later

        AuditLog.record!(
          user: user,
          action: "email_verification.created",
          request: request,
          target: verification,
          metadata: { source: "signup" }
        )

        render_success(
          {
            user: user_json(user)
          },
          status: :created
        )
      rescue ActiveRecord::RecordInvalid
        render_error(
          code: "SIGNUP_FAILED",
          message: "登録できませんでした。入力内容を確認してください。",
          status: :unprocessable_entity
        )
      end

      def login
        email = params.require(:email).to_s.strip.downcase
        password = params.require(:password).to_s

        user = User.find_by(email: email)
        authenticated_user = user&.authenticate(password)

        unless authenticated_user
          AuditLog.record!(
            user: user,
            action: "auth.login_failed",
            request: request,
            metadata: {
              email_sha256: OpenSSL::Digest::SHA256.hexdigest(email)
            }
          )

          return render_error(
            code: "INVALID_CREDENTIALS",
            message: "メールアドレスまたはパスワードが正しくありません。",
            status: :unauthorized
          )
        end

        if user.banned?
          AuditLog.record!(
            user: user,
            action: "auth.login_blocked_banned",
            request: request,
            metadata: {
              email_sha256: OpenSSL::Digest::SHA256.hexdigest(email)
            }
          )

          return render_error(
            code: "ACCOUNT_BANNED",
            message: "このアカウントはご利用いただけません。コミュニティガイドラインおよび利用規約への重大な違反が確認されたため、本アカウントは停止されました。※この措置に関する個別のお問い合わせにはお答えいたしかねますので、予めご了承ください。",
            status: :forbidden
          )
        end

        if user.withdrawn?
          AuditLog.record!(
            user: user,
            action: "auth.login_blocked_withdrawn",
            request: request,
            metadata: {
              email_sha256: OpenSSL::Digest::SHA256.hexdigest(email)
            }
          )

          return render_error(
            code: "ACCOUNT_WITHDRAWN",
            message: "このアカウントは退会済みのためログインできません。",
            status: :forbidden
          )
        end

        # 一時凍結中のユーザーには凍結中画面を表示するため、認証だけは許可する。
        unless user.active? || user.suspended?
          AuditLog.record!(
            user: user,
            action: "auth.login_failed",
            request: request,
            metadata: {
              email_sha256: OpenSSL::Digest::SHA256.hexdigest(email)
            }
          )

          return render_error(
            code: "INVALID_CREDENTIALS",
            message: "メールアドレスまたはパスワードが正しくありません。",
            status: :unauthorized
          )
        end

        sign_in!(user)

        render_success(
          {
            user: user_json(user)
          }
        )
      end

      def logout
        sign_out!

        render_success(
          {
            message: "ログアウトしました。"
          }
        )
      end

      def me
        render_success(
          {
            user: user_json(current_user)
          }
        )
      end

      private

      def signup_params
        params.permit(:email, :password, :password_confirmation)
      end

      def user_json(user)
        {
          id: user.id,
          email: user.email,
          email_verified: user.email_verified_at.present?,
          status: user.status,
          role: user.role,
          last_login_at: user.last_login_at,
          withdrawn_at: user.respond_to?(:withdrawn_at) ? user.withdrawn_at : nil,
          created_at: user.created_at,
          user_profile: user_profile_json(user.user_profile)
        }
      end

      def user_profile_json(profile)
        return nil if profile.blank?

        {
          id: profile.id,
          display_name: profile.display_name,
          full_name: profile.full_name,
          legal_last_name: profile.legal_last_name,
          legal_first_name: profile.legal_first_name,
          legal_middle_name: profile.legal_middle_name,
          legal_last_name_kana: profile.legal_last_name_kana,
          legal_first_name_kana: profile.legal_first_name_kana,
          legal_middle_name_kana: profile.legal_middle_name_kana,
          legal_full_name_raw: profile.legal_full_name_raw,
          locale: profile.locale,
          timezone: profile.timezone,
          marketing_opt_in: profile.marketing_opt_in,
          identity_birth_date: profile.identity_birth_date&.iso8601,
          identity_gender: profile.identity_gender,
          home_prefecture: profile.home_prefecture,
          home_city: profile.home_city,
          public_age_label: profile.public_age_label,
          profile_headline: profile.profile_headline,
          bio: profile.bio,
          interest_category_keys: profile.interest_category_keys || [],
          participation_style_keys: profile.participation_style_keys || [],
          preferred_areas: profile.preferred_areas || [],
          conversation_topics: profile.conversation_topics || [],
          communication_preferences: profile.communication_preferences || [],
          avatar_url: profile.avatar_url,
          club_love_levels: profile.club_love_levels || {},
          created_at: profile.created_at,
          updated_at: profile.updated_at
        }
      end
    end
  end
end