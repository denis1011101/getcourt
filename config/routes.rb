Rails.application.routes.draw do
  get "/contacts", to: "pages#contacts", as: :contacts
  get "/mission",  to: "pages#mission",  as: :mission
  get "/partnership", to: "pages#partnership", as: :partnership
  get "/tennis-formats-and-rules", to: "pages#tennis_formats_and_rules", as: :tennis_formats_and_rules
  get "/ntrp-level-guide", to: "pages#ntrp_level_guide", as: :ntrp_level_guide
  get "/coaches",  to: "coaches#index", as: :coaches
  get "tennis_life/index"
  # geocoding quota status and reset
  get  "/geocoding/status", to: "geocoding#status",  as: :geocoding_status
  get  "/geocoding/reset",  to: "geocoding#reset_form", as: :geocoding_reset_form
  post "/geocoding/reset",  to: "geocoding#reset",   as: :geocoding_reset

  if Rails.env.production?
    post "/bot_webhook", to: "bot_webhook#create"
  else
    # In development/test we prefer polling. Keep webhook route commented for manual testing (ngrok).
  end

  get "/tennis_life", to: "tennis_life#index", as: :tennis_life

  resource :account, only: %i[edit update], controller: :users do
    post :regenerate_token
    post :clear_city, to: "users#clear_city", as: :clear_city
  end

  resources :users, only: [ :index, :show ] do
    resource :player_statistic, only: [ :show ]
  end

  post "/games/:game_id/player_statistics", to: "player_statistics#create_for_game", as: :game_player_statistics

  # auth
  get  "/sign_in",           to: "sessions#new",    as: :new_session
  post "/sign_in",           to: "sessions#create", as: :session
  get  "/sign_in/verify",    to: "sessions#verify", as: :verify_session
  post "/sign_in/verify",    to: "sessions#check"
  delete "/sign_out",        to: "sessions#destroy", as: :destroy_session
  delete "/sign_out",        to: "sessions#destroy", as: :sign_out

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :courts do
    member do
      post :approve
      post :reject
    end
  end
  root "games#index"
  resources :games, except: [ :index ] do
    collection do
      get :prebooking_fragment
    end

    resources :participations, only: [ :create, :destroy ] do
      member do
        post :approve
        post :reject
      end
    end

    resources :prebookings, only: [] do
      member do
        post :book
        post :cancel
        post :approve
        post :reject
      end
    end

    resources :prebooking_cancellations, only: [ :create, :destroy ]
  end
  resources :searches, only: [ :index ]

  resources :tournaments do
    member do
      post :join
      post :leave
      post :select_bracket
      post :reset_bracket
      post :add_match
    end

    collection do
      get :options
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
