Rails.application.routes.draw do
  post "/rails/active_storage/direct_uploads", to: "image_uploads#direct_upload_disabled"

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

  resources :image_uploads, only: [:create]

  namespace :admin do
    resources :events, only: [:index]
  end

  root to: "events#new"
end
