Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
  defaults export: true do
    namespace :dashboard do
      namespace :overview do
        get :platform
        get :student
        get :cohort
        get :ml_pipeline
      end

      resources :students, only: [:index, :show]
      resources :cohorts, only: [:index, :show]
    end
    get "up" => "rails/health#show", as: :rails_health_check
    root to: redirect('/dashboard/overview/platform')
  end
end
