Rails.application.routes.draw do
  # geocoding quota status and reset
  get  '/geocoding/status', to: 'geocoding#status',  as: :geocoding_status
  get  '/geocoding/reset',  to: 'geocoding#reset_form', as: :geocoding_reset_form
  post '/geocoding/reset',  to: 'geocoding#reset',   as: :geocoding_reset
  post "/bot_webhook", to: "bot_webhook#receive"

  # auth
  get  "/sign_in",  to: "sessions#new",    as: :new_session
  post "/sign_in",  to: "sessions#create", as: :sign_in
  delete "/sign_out", to: "sessions#destroy", as: :sign_out
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "courts#index"
  resources :courts
  resources :games do
    resources :participations, only: [:create, :destroy]
  end
  resources :searches, only: [:index]

  resource :account, only: %i[edit update], controller: :users

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
