module Api
  # Наследуемся от ActionController::API, а не от ApplicationController: здесь не
  # нужны ни CSRF-токен, ни проверка браузера, ни баннер локали — это машинный
  # интерфейс, а не страница.
  class BaseController < ActionController::API
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not_found" }, status: :not_found
    end
  end
end
