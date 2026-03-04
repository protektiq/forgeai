# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActiveStorage::Engine => "/rails/active_storage"

  devise_for :users

  namespace :api do
    namespace :v1 do
      post "generate", to: "generate#create"
      resources :assets, only: [:index, :show], param: :id
    end
  end

  get "dashboard", to: "dashboard#index"
  post "dashboard", to: "dashboard#create"

  resources :assets, only: [:index, :show] do
    get "download", on: :member
  end

  root "dashboard#index"
end
