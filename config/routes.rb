Rails.application.routes.draw do
  resources :events, path: '/', only: [:new, :create, :show] do
    resources :admin,
      controller: :events_admin,
      param: :admin_token,
      only: [:show, :edit, :update, :destroy] do

      resources :admin_email_requests, only: [:create]
    end

    resources :rsvps, only: [:create, :destroy]
  end

  resources :image_uploads, only: [:create]

  root to: "events#new"
end
