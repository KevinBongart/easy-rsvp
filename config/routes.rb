Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest",
    as: :pwa_manifest,
    defaults: { format: :json },
    constraints: { format: :json }
  post "/rails/active_storage/direct_uploads" => "rich_text_direct_uploads#create", as: :rich_text_direct_uploads

  resources :events, path: '/', only: [:new, :create, :show] do
    resources :admin,
      controller: :events_admin,
      param: :admin_token,
      only: [:show, :edit, :update, :destroy] do

      post :toggle_publish, on: :member

      scope module: 'admin' do
        resources :email_requests, only: [:create]
        resources :rsvps, only: [:update, :destroy]
      end
    end

    resources :rsvps, only: [:create, :destroy]
  end

  namespace :admin do
    resources :events, only: [:index]
  end

  root to: "events#new"
end
