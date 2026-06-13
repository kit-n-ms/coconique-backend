module Api
  module V1
    class UserProfilesController < ApplicationController
      before_action :require_login!

      def show
        render_success(
          {
            user_profile: user_profile_json(current_user.user_profile)
          }
        )
      end

      def update
        profile = current_user.user_profile || current_user.build_user_profile

        permitted_params = user_profile_params
        profile.assign_attributes(permitted_params)
        validation_context = validation_context_for(permitted_params)
        if validation_context.present?
          profile.save!(context: validation_context)
        else
          profile.save!
        end

        AuditLog.record!(
          user: current_user,
          action: "user_profile.updated",
          request: request,
          target: profile
        )

        render_success(
          {
            user_profile: user_profile_json(profile)
          }
        )
      end

      private

      PROFILE_PARAM_KEYS = [
        :display_name,
        :full_name,
        :legal_last_name,
        :legal_first_name,
        :legal_middle_name,
        :legal_last_name_kana,
        :legal_first_name_kana,
        :legal_middle_name_kana,
        :legal_full_name_raw,
        :locale,
        :timezone,
        :marketing_opt_in,
        :identity_birth_date,
        :identity_gender,
        :home_prefecture,
        :home_city,
        :public_age_label,
        :profile_headline,
        :bio,
        :avatar_url,
        { interest_category_keys: [] },
        { participation_style_keys: [] },
        { preferred_areas: [] },
        { conversation_topics: [] },
        { communication_preferences: [] },
        { club_love_levels: {} }
      ].freeze

      IDENTITY_PARAM_KEYS = %w[
        full_name
        legal_last_name
        legal_first_name
        legal_middle_name
        legal_last_name_kana
        legal_first_name_kana
        legal_middle_name_kana
        legal_full_name_raw
        identity_birth_date
        identity_gender
        home_prefecture
        home_city
      ].freeze

      def user_profile_params
        source_params.permit(*PROFILE_PARAM_KEYS)
      end

      def source_params
        if params[:user_profile].is_a?(ActionController::Parameters)
          params.require(:user_profile)
        else
          params
        end
      end

      def validation_context_for(permitted_params)
        keys = permitted_params.keys.map(&:to_s)
        return nil if (keys & IDENTITY_PARAM_KEYS).present?

        :public_profile_update
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
