Rails.application.routes.draw do
  resources :events, path: '/', only: [:new, :create, :show] do
    resources :admin,
      controller: :events_admin,
      param: :admin_token,
      only: [:show, :edit, :update, :destroy]

    resources :rsvps, only: [:create, :destroy]
  end

  root to: "events#new"
end
