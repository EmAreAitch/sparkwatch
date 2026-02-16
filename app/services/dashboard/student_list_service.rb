module Dashboard
  class StudentListService
    VALID_ORDERS = %w[
      engagement_desc engagement_asc
      risk_desc risk_asc
      last_active_desc last_active_asc
    ].freeze

    def initialize(filters = {})
      @filters = filters
    end

    def call
      relation = base_relation
      relation = apply_filters(relation)
      materialized = Student.from("(#{relation.to_sql}) AS students")
      apply_order_on_materialized(materialized)
    end

    private

    attr_reader :filters

    def base_relation
      Student
        .joins(:cohort, :engagement_scores, :predictions)
        .where(engagement_scores: { week_start: week })
        .where(predictions: { month_start: month })
        .joins(Activity.last_activity_lateral_join_sql)
        .select(select_sql)
    end

    def apply_filters(relation)
      relation = relation.merge(Student.search_by_name_or_email(filters[:search]))
      relation = relation.where(cohort_id: filters[:cohort]) if filters[:cohort].present?

      if Prediction::RISK_RANGES.key?(filters[:risk_level]&.to_sym)
        relation = relation.merge(Prediction.for_risk_level(filters[:risk_level]))
      end

      if EngagementScore::ENGAGEMENT_RANGES.key?(filters[:engagement_level]&.to_sym)
        relation = relation.merge(EngagementScore.for_engagement_level(filters[:engagement_level]))
      end

      relation
    end

    def apply_order_on_materialized(relation)
      order_hash = case filters[:order]
      when 'engagement_desc' then { engagement_score: :desc, id: :asc }
      when 'engagement_asc' then { engagement_score: :asc, id: :asc }
      when 'risk_desc' then { risk_score: :desc, id: :asc }
      when 'risk_asc' then { risk_score: :asc, id: :asc }
      when 'last_active_desc' then { last_active_at: :desc, id: :asc }
      when 'last_active_asc' then { last_active_at: :asc, id: :asc }
      else { id: :asc }
      end

      relation.order(order_hash)
    end

    def select_sql
      [
        'students.*',
        'cohorts.name AS cohort_name',
        EngagementScore.to_percent_sql('engagement_scores.score', as: 'engagement_score'),
        EngagementScore.to_percent_sql('predictions.risk_score', as: 'risk_score'),
        "COALESCE(last_activity.last_active_at, '1970-01-01'::timestamp) AS last_active_at",
        'last_activity.last_active_at AS actual_last_active_at'
      ].join(', ')
    end

    def week
      Date.current.prev_week
    end

    def month
      Date.current.prev_month.beginning_of_month
    end
  end
end
