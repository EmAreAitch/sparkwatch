class Dashboard::StudentsController < ApplicationController
  include Pagy::Method
  include ActionView::Helpers::DateHelper
  
  def index
    filters = student_filters
    
    if filters.present?
      service = Dashboard::StudentListService.new(filters)
      relation = service.call
      keyset = build_keyset(filters[:order])
      @pagy, @records = pagy(:keyset, relation, keyset: keyset, limit: 10)
      
      render json: {
        pagy: @pagy.page_url(:next),
        data: @records.map { |student| serialize_student(student) }
      }
    end
  end

  def show
    return unless params[:widgets].present?
    student_id, widgets = params.expect(:id, widgets: [])
    render json: Dashboard::StudentDetailsService.call(student_id:, widgets:)
  end

  private

  def build_keyset(order_param)
    case order_param
    when 'engagement_desc' then { engagement_score: :desc, id: :asc }
    when 'engagement_asc' then { engagement_score: :asc, id: :asc }
    when 'risk_desc' then { risk_score: :desc, id: :asc }
    when 'risk_asc' then { risk_score: :asc, id: :asc }
    when 'last_active_desc' then { last_active_at: :desc, id: :asc }
    when 'last_active_asc' then { last_active_at: :asc, id: :asc }
    else { id: :asc }
    end
  end

  def student_filters
    params.permit(:search, :cohort, :risk_level, :engagement_level, :order, :page).to_h.symbolize_keys
  end

  def serialize_student(student)
    {
      id: student.id,
      name: student.name,
      email: student.email,
      cohort: student.cohort_name,
      engagement: student.engagement_score,
      risk_score: student.risk_score,
      last_active: student.actual_last_active_at ? "#{time_ago_in_words(student.actual_last_active_at)} ago" : 'Never'
    }
  end
end
