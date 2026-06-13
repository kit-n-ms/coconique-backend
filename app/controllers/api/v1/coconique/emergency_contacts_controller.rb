module Api
  module V1
    module Coconique
      class EmergencyContactsController < BaseController
        before_action :set_contact, only: [:update, :destroy, :request_approval]

        def index
          contacts = current_user.coconique_emergency_contacts
            .where.not(status: :revoked)
            .ordered_recently

          render_success(
            {
              emergency_contacts: contacts.map { |contact| serialize_emergency_contact(contact) },
              max_contacts: CoconiqueEmergencyContact::MAX_ACTIVE_CONTACTS_PER_USER
            }
          )
        end

        def create
          contact = current_user.coconique_emergency_contacts.create!(contact_params)
          token = contact.issue_approval_token!
          CoconiqueSafetyMailer.emergency_contact_approval(contact, token).deliver_later

          AuditLog.record!(
            user: current_user,
            action: "coconique.emergency_contact.created",
            request: request,
            target: contact,
            metadata: { email_domain: contact.email.split("@").last }
          )

          render_success({ emergency_contact: serialize_emergency_contact(contact) }, status: :created)
        end

        def update
          attrs = contact_params
          email_changed = attrs[:email].present? && attrs[:email].to_s.strip.downcase != @contact.email

          @contact.assign_attributes(attrs)
          if email_changed
            @contact.status = :pending
            @contact.approved_at = nil
          end
          @contact.save!

          if email_changed
            token = @contact.issue_approval_token!
            CoconiqueSafetyMailer.emergency_contact_approval(@contact, token).deliver_later
          end

          AuditLog.record!(
            user: current_user,
            action: "coconique.emergency_contact.updated",
            request: request,
            target: @contact
          )

          render_success({ emergency_contact: serialize_emergency_contact(@contact) })
        end

        def destroy
          @contact.revoke!

          AuditLog.record!(
            user: current_user,
            action: "coconique.emergency_contact.revoked",
            request: request,
            target: @contact
          )

          render_success({ emergency_contact: serialize_emergency_contact(@contact) })
        end

        def request_approval
          token = @contact.issue_approval_token!
          CoconiqueSafetyMailer.emergency_contact_approval(@contact, token).deliver_later

          AuditLog.record!(
            user: current_user,
            action: "coconique.emergency_contact.approval_requested",
            request: request,
            target: @contact
          )

          render_success({ emergency_contact: serialize_emergency_contact(@contact) })
        end

        private

        def set_contact
          @contact = current_user.coconique_emergency_contacts.find_by!(public_id: params[:id])
        end

        def contact_params
          permitted = params.permit(:name, :email)
          {
            name: permitted[:name],
            email: permitted[:email]
          }.compact
        end
      end
    end
  end
end
