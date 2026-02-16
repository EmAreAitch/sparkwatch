class Dashboard::CohortsController < ApplicationController
  def index
    respond_to do |format|
      format.html
      format.json do
        data = Dashboard::CohortListService.call
        render json: data
      end
    end
  end

  def show
    respond_to do |format|
      format.html
      format.json do
        widgets = params[:widgets] || []
        render json: Dashboard::CohortDetailsService.call(cohort_id: params[:id], widgets: widgets)
      end
    end
  end
end
