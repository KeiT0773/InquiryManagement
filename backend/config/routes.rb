Rails.application.routes.draw do
  # 死活確認。200 なら起動している（API 設計書 3.）
  get "up" => "rails/health#show", as: :rails_health_check

  # API はすべて /api で始まる（API 設計書 2.・3.）
  scope :api do
    resources :lists, only: :index
    # 編集は PATCH だけを受け付ける（resources の update は PUT も受け付けるため、別に書く）
    resources :inquiries, only: %i[index show create destroy] do
      post :sort, on: :collection
      put :position, on: :member
    end
    patch "inquiries/:id", to: "inquiries#update"
  end
end
