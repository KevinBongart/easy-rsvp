Rails.application.routes.draw do
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

  root to: "events#new"
end
