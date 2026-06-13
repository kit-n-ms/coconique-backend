module Api
  module V1
    module Coconique
      class AccountsController < BaseController
        skip_before_action :finish_due_coconique_events!, only: [:withdrawal_summary, :withdraw]
        skip_before_action :sync_coconique_safety_check_sessions!, only: [:withdrawal_summary, :withdraw]

        def withdrawal_summary
          render_success({ withdrawal: CoconiqueAccountWithdrawalService.summary_for(current_user) })
        end

        def withdraw
          reason = params[:reason].to_s.strip

          unless ActiveModel::Type::Boolean.new.cast(params[:confirmed])
            return render_error(
              code: "WITHDRAWAL_CONFIRMATION_REQUIRED",
              message: "退会するには、注意事項への同意が必要です。",
              status: :unprocessable_entity,
              data: { fields: { confirmed: ["注意事項への同意が必要です。"] } }
            )
          end

          unless CoconiqueAccountWithdrawalService::REASON_KEYS.include?(reason)
            return render_error(
              code: "WITHDRAWAL_REASON_REQUIRED",
              message: "退会理由を選択してください。",
              status: :unprocessable_entity,
              data: { fields: { reason: ["退会理由を選択してください。"] } }
            )
          end

          summary = CoconiqueAccountWithdrawalService.withdraw!(
            current_user,
            reason: reason,
            note: params[:note],
            request: request
          )

          sign_out!

          render_success({ withdrawal: summary, message: "退会処理が完了しました。" })
        end
      end
    end
  end
end
