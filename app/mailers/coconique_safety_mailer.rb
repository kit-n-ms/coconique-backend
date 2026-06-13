require "cgi"

class CoconiqueSafetyMailer < ApplicationMailer
  def emergency_contact_approval(contact, token)
    @contact = contact
    @user = contact.user
    @profile = @user.user_profile
    @url = build_url(
      ENV.fetch(
        "FRONTEND_COCONIQUE_EMERGENCY_CONTACT_APPROVAL_URL",
        "http://localhost:5173/safety/emergency-contacts/approve"
      ),
      token
    )

    mail(
      to: @contact.email,
      subject: "【ココニーク】帰宅確認の連絡先承認のお願い"
    )
  end

  def safety_check_reminder(session)
    @session = session
    @user = session.user
    @event = session.coconique_event
    @profile = @user.user_profile
    @event_start_label = format_jst_datetime(@event&.starts_at)
    @url = ENV.fetch(
      "FRONTEND_COCONIQUE_SAFETY_CHECK_URL",
      "http://localhost:5173/app/safety/check"
    )

    mail(
      to: @user.email,
      subject: "【ココニーク】おでかけ後の帰宅確認をお願いします"
    )
  end

  def emergency_contact_notification(notification)
    @notification = notification
    @contact = notification.coconique_emergency_contact
    @session = notification.coconique_safety_check_session
    @user = @session.user
    @event = @session.coconique_event
    @profile = @user.user_profile
    @event_start_label = format_jst_datetime(@event&.starts_at)

    subject = if notification.help?
      "【ココニーク】登録連絡先への通知：相談したい確認がありました"
    else
      "【ココニーク】登録連絡先への通知：帰宅確認が取れていません"
    end

    mail(to: @contact.email, subject: subject)
  end

  private

  JAPAN_TIME_ZONE = "Asia/Tokyo"

  def format_jst_datetime(value)
    return "日時未定" if value.blank?

    value.in_time_zone(JAPAN_TIME_ZONE).strftime("%Y年%m月%d日 %H:%M")
  end

  def build_url(base_url, token)
    separator = base_url.include?("?") ? "&" : "?"
    "#{base_url}#{separator}token=#{CGI.escape(token)}"
  end
end
