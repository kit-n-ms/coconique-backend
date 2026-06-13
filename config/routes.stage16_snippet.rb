# Add these routes inside:
# namespace :api do
#   namespace :v1 do
#     namespace :admin do

namespace :billing do
  resources :credit_transactions, only: [:index]
  resources :checkout_sessions, only: [:index, :show]
  resources :credit_balances, only: [:index]
end

resources :stripe_webhook_events, only: [:index, :show]
resources :email_webhook_events, only: [:index, :show]
resources :email_suppressions, only: [:index, :destroy]
