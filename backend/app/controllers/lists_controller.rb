# GET /api/lists（API 設計書 5.）
class ListsController < ApplicationController
  def index
    render json: List.ordered.map { |list| { id: list.id, name: list.name, displayOrder: list.display_order } }
  end
end
