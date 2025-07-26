Rails.application.routes.draw do
  resources :events, path: '/', only: %i[new create show] do
    resources :admin,
              controller: :events_admin,
              param: :admin_token,
              only: %i[show edit update destroy] do
      post :toggle_publish, on: :member

      scope module: 'admin' do
        resources :email_requests, only: [:create]
        resources :rsvps, only: %i[update destroy]
      end
    end

    resources :rsvps, only: %i[create destroy]
  end

  resources :image_uploads, only: [:create]

  namespace :admin do
    resources :events, only: [:index]
  end

  root to: "events#new"
end
