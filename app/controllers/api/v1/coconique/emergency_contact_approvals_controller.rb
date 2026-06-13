module Api
  module V1
    module Coconique
      class EmergencyContactApprovalsController < ApplicationController
        def show
          contact = find_contact_by_token!
          render_success({ approval: serialize_approval(contact) })
        end

        def create
          contact = find_contact_by_token!
          contact.approve!

          AuditLog.record!(
            user: contact.user,
            action: "coconique.emergency_contact.approved_by_contact",
            request: request,
            target: contact,
            metadata: { contact_email_domain: contact.email.split("@").last }
          )

          render_success({ approval: serialize_approval(contact) })
        end

        private

        def find_contact_by_token!
          token = params[:token].to_s
          raise ActiveRecord::RecordNotFound if token.blank?

          CoconiqueEmergencyContact.find_usable_approval_token!(token)
        end

        def serialize_approval(contact)
          user = contact.user
          profile = user.user_profile

          {
            "contactName" => contact.name,
            "contactEmail" => contact.email,
            "status" => contact.status,
            "requesterDisplayName" => profile&.display_name.presence || user.email.to_s.split("@").first,
            "requestedAt" => contact.last_invited_at&.iso8601,
            "approvedAt" => contact.approved_at&.iso8601
          }
        end
      end
    end
  end
end
