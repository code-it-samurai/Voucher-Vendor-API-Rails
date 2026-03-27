require "sidekiq/web"

Sidekiq::Web.use ActionDispatch::Cookies
Sidekiq::Web.use ActionDispatch::Session::CookieStore, key: "_sidekiq_session"

Rails.application.routes.draw do
  mount Sidekiq::Web => "/sidekiq"

  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :accounts, only: [:create] do
        collection do
          get :me
          post :top_up
        end
      end
      resources :orders, only: [:create, :show] do
        member do
          post :cancel
        end
      end
      resources :products, only: [:index] do
        member do
          post :replenish
        end
      end
    end
  end
end
