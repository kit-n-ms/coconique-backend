module Api
  module V1
    module Coconique
      class SafetyCheckSettingsController < BaseController
        def show
          setting = current_setting
          render_success({ safety_check_setting: serialize_safety_check_setting(setting) })
        end

        def update
          setting = current_setting
          setting.assign_attributes(setting_params)
          setting.save!

          AuditLog.record!(
            user: current_user,
            action: "coconique.safety_check_setting.updated",
            request: request,
            target: setting
          )

          render_success({ safety_check_setting: serialize_safety_check_setting(setting) })
        end

        private

        def current_setting
          setting = CoconiqueSafetyCheckSetting.default_for(current_user)
          setting.save! if setting.new_record?
          setting
        end

        def setting_params
          permitted = safety_check_setting_param_source.permit(
            :enabled,
            :mode,
            :startDelayMinutes,
            :start_delay_minutes,
            :reminderIntervalMinutes,
            :reminder_interval_minutes,
            :maxReminders,
            :max_reminders,
            :notifyContactsOnNoResponse,
            :notify_contacts_on_no_response,
            :notifyContactsOnHelp,
            :notify_contacts_on_help,
            :shareEventTitle,
            :share_event_title,
            :shareEventArea,
            :share_event_area
          )

          enabled_value = permitted.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(permitted[:enabled]) : nil
          mode_value = first_present(permitted[:mode]).to_s.presence
          mode_value = "off" if enabled_value == false
          mode_value = "standard" if enabled_value == true && mode_value == "off"
          mode_value = nil unless mode_value.blank? || CoconiqueSafetyCheckSetting.modes.key?(mode_value)

          normalized = {
            enabled: enabled_value,
            mode: mode_value,
            start_delay_minutes: integer_param(permitted, :startDelayMinutes, :start_delay_minutes),
            reminder_interval_minutes: integer_param(permitted, :reminderIntervalMinutes, :reminder_interval_minutes),
            max_reminders: integer_param(permitted, :maxReminders, :max_reminders),
            notify_contacts_on_no_response: boolean_param(permitted, :notifyContactsOnNoResponse, :notify_contacts_on_no_response),
            notify_contacts_on_help: boolean_param(permitted, :notifyContactsOnHelp, :notify_contacts_on_help),
            share_event_title: boolean_param(permitted, :shareEventTitle, :share_event_title),
            share_event_area: boolean_param(permitted, :shareEventArea, :share_event_area)
          }.compact

          normalize_timing_defaults(normalized)
        end

        # 画面側は現状トップレベルJSONで送るが、将来/テストで
        # { safety_check_setting: {...} } になっても受けられるようにしておく。
        def safety_check_setting_param_source
          value = params[:safety_check_setting] || params[:safetyCheckSetting]
          value.is_a?(ActionController::Parameters) ? value : params
        end

        def normalize_timing_defaults(values)
          mode = values[:mode]

          case mode
          when "standard"
            values[:start_delay_minutes] = 60
            values[:reminder_interval_minutes] = 30
            values[:max_reminders] = 3
          when "careful"
            values[:start_delay_minutes] = 30
            values[:reminder_interval_minutes] = 20
            values[:max_reminders] = 5
          when "off"
            # オフでもDB制約/バリデーションを満たせるよう、既定値を保持する。
            values[:start_delay_minutes] ||= 60
            values[:reminder_interval_minutes] ||= 30
            values[:max_reminders] ||= 3
          else
            values[:start_delay_minutes] ||= 60
            values[:reminder_interval_minutes] ||= 30
            values[:max_reminders] ||= 3
          end

          values[:start_delay_minutes] = values[:start_delay_minutes].clamp(5, 24 * 60) if values[:start_delay_minutes].present?
          values[:reminder_interval_minutes] = values[:reminder_interval_minutes].clamp(5, 24 * 60) if values[:reminder_interval_minutes].present?
          values[:max_reminders] = values[:max_reminders].clamp(1, 10) if values[:max_reminders].present?

          values
        end

        def integer_param(permitted, camel_key, snake_key)
          key = permitted.key?(camel_key) ? camel_key : snake_key
          return nil unless permitted.key?(key)

          Integer(permitted[key])
        rescue ArgumentError, TypeError
          nil
        end

        def boolean_param(permitted, camel_key, snake_key)
          key = permitted.key?(camel_key) ? camel_key : snake_key
          return nil unless permitted.key?(key)

          ActiveModel::Type::Boolean.new.cast(permitted[key])
        end
      end
    end
  end
end
