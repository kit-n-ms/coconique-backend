Rails.application.routes.draw do
  get "up", to: "health#up"
  get "healthz", to: "health#healthz"
  get "readiness", to: "health#readiness"

  post "webhooks/stripe", to: "webhooks/stripe#create"
  post "webhooks/didit", to: "webhooks/didit#create"
  post "webhooks/quick_trust", to: "webhooks/quick_trust#create"
  post "webhooks/resend", to: "webhooks/resend#create"

  namespace :api do
    namespace :v1 do
      get "health", to: "health#index"

      get "auth/csrf", to: "auth#csrf"

      post "auth/signup", to: "auth#signup"
      post "auth/login", to: "auth#login"
      delete "auth/logout", to: "auth#logout"
      get "auth/me", to: "auth#me"

      post "auth/email_verifications", to: "auth/email_verifications#create"
      post "auth/email_verifications/confirm", to: "auth/email_verifications#confirm"
      post "auth/email_change_requests", to: "auth/email_change_requests#create"

      post "auth/password_resets", to: "auth/password_resets#create"
      patch "auth/password_resets/confirm", to: "auth/password_resets#confirm"

      get "user_profile", to: "user_profiles#show"
      patch "user_profile", to: "user_profiles#update"

      get "onboarding/status", to: "onboarding_status#show"

      post "terms_acceptances", to: "terms_acceptances#create"

      get "app_memberships", to: "app_memberships#index"
      post "app_memberships", to: "app_memberships#create"

      namespace :admin do
        resources :users, only: [:index, :show] do
          patch :status, on: :member
          post :notes, on: :member, action: :add_note
          resources :auth_sessions, only: [:index]
        end

        resources :auth_sessions, only: [:destroy]
        resources :audit_logs, only: [:index]

        namespace :billing do
          resources :credit_transactions, only: [:index]
          resources :checkout_sessions, only: [:index, :show]
          resources :credit_balances, only: [:index]
        end

        resources :stripe_webhook_events, only: [:index, :show]
        resources :email_webhook_events, only: [:index, :show]
        resources :email_suppressions, only: [:index, :destroy]
        resources :coconique_safety_check_sessions, only: [:index, :show]
        resources :coconique_reports, only: [:index, :show] do
          patch :status, on: :member
          post :actions, on: :member, action: :add_action
        end
        resources :coconique_user_restrictions, only: [:index, :create] do
          patch :lift, on: :member
        end

        post "coconique/events/:public_id/host_ticket/release", to: "coconique_host_tickets#release_event"
        post "coconique/events/:public_id/host_ticket/forfeit", to: "coconique_host_tickets#forfeit_event"
      end

      namespace :billing do
        resources :credit_products, only: [:index]
        resource :balance, only: [:show], controller: "balances"
        resources :credit_transactions, only: [:index]
        resources :checkout_sessions, only: [:create] do
          post :sync, on: :collection
          post :fake_complete, on: :member
        end
        resource :portal_session, only: [:create], controller: "portal_sessions"
      end

      namespace :coconique do
        get "dashboard", to: "dashboard#show"
        get "account/withdrawal", to: "accounts#withdrawal_summary"
        delete "account/withdrawal", to: "accounts#withdraw"

        get "safety/registration_status", to: "safety_registrations#status"
        post "safety/intents", to: "safety_registrations#create_intent"
        post "safety/intents/:id/complete", to: "safety_registrations#complete_intent"
        post "safety/phone_verifications", to: "safety_registrations#create_phone_verification"
        post "safety/phone_verifications/confirm", to: "safety_registrations#confirm_phone_verification"
        post "safety/identity_verifications", to: "safety_registrations#create_identity_verification"
        post "safety/identity_verifications/sync", to: "safety_registrations#sync_identity_verification"
        post "safety/identity_verifications/didit/session", to: "safety_registrations#create_identity_verification"
        post "safety/identity_verifications/quick_trust/session", to: "safety_registrations#create_identity_verification"
        post "safety/identity_verifications/fake_complete", to: "safety_registrations#fake_complete_identity_verification"
        post "safety/promo_code_redemptions", to: "safety_registrations#redeem_promo_code"
        post "safety/payment_method/fake_complete", to: "safety_registrations#fake_complete_payment_method"

        resources :emergency_contacts, only: [:index, :create, :update, :destroy] do
          post :request_approval, on: :member
        end
        resource :safety_check_setting, only: [:show, :update]
        resources :safety_check_sessions, only: [:index, :show] do
          patch :respond, on: :member
        end
        resources :reports, only: [:create]
        resources :feedbacks, only: [:index, :create]
        resources :notifications, only: [:index, :update, :destroy] do
          patch :read_all, on: :collection
        end
        resources :user_blocks, only: [:index, :create, :destroy]
        get "emergency_contact_approval", to: "emergency_contact_approvals#show"
        post "emergency_contact_approval", to: "emergency_contact_approvals#create"

        resources :events, only: [:index, :show, :create, :update], param: :public_id do
          patch :publish, on: :member
          patch :close, on: :member
          patch :reopen, on: :member
          patch :cancel, on: :member
          patch :finish, on: :member

          resource :favorite, only: [:create, :destroy], controller: "event_favorites"
          get :participants, on: :member, to: "participation_requests#participants"
          resources :chat_messages, only: [:index, :create], controller: "event_chat_messages" do
            resource :reaction, only: [:create, :destroy], controller: "event_chat_message_reactions"
          end
          resources :participation_requests, only: [:index, :create]
        end

        resources :favorites, only: [:index]
        resources :hosted_events, only: [:index]
        resources :chat_rooms, only: [:index, :show], param: :event_id do
          resources :messages, only: [:index, :create], controller: "event_chat_messages" do
            resource :reaction, only: [:create, :destroy], controller: "event_chat_message_reactions"
          end
        end
        get "users/:id/profile", to: "user_profiles#show"

        resources :participation_requests, only: [:index, :show, :update] do
          patch :approve, on: :member
          patch :reject, on: :member
          patch :withdraw, on: :member
          patch :cancel, on: :member
          patch :host_cancel, on: :member
          patch :attendance, on: :member
        end
      end
    end
  end
end