class Dashboard::OverviewController < ApplicationController
  def platform
    render_widgets_json(Dashboard::PlatformOverviewService)
  end

  def student
    render_widgets_json(Dashboard::StudentOverviewService)
  end

  def cohort
    render_widgets_json(Dashboard::CohortOverviewService)
  end

  def ml_pipeline
  end

  private

  def render_widgets_json(service)
    widgets = params.expect(widgets: []) if params[:widgets].present?
    if widgets.present?
      @data = service.call(widgets:)
      render json: @data
    end
  end
end

