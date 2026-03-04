# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActiveStorage::Engine => "/rails/active_storage"

  devise_for :users

  get "dashboard", to: "dashboard#index"
  post "dashboard", to: "dashboard#create"

  resources :assets, only: [:index, :show] do
    get "download", on: :member
  end

  root "dashboard#index"
end
