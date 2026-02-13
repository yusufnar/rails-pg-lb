Rails.application.routes.draw do
  root "home#index"
  get "api/status", to: "home#index", defaults: { format: :json }
  get "up" => "rails/health#show", as: :rails_health_check
end
