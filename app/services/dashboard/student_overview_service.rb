# frozen_string_literal: true
module Dashboard
  class StudentOverviewService
    VALID_WIDGETS = %w[
      kpis
      engagement_distribution
      cohort_distribution
      momentum_distribution
      risk_engagement_quadrant
      at_risk_students
      high_performers
      inactive_students
    ].freeze

    def initialize(reference_date: Date.current, widgets: nil)
      @reference_date = reference_date.to_date
      @widgets = validate_widgets(widgets)
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      return all_data if @widgets.nil?

      @widgets.each_with_object({}) do |widget, result|
        result[widget.to_sym] = send(widget)
      end
    end

    private

    attr_reader :reference_date, :widgets

    def validate_widgets(widgets)
      return nil if widgets.nil? || widgets.empty?
      
      widgets.map(&:to_s).select { |w| VALID_WIDGETS.include?(w) }
    end

    def all_data
      {
        kpis: kpis,
        engagement_distribution: engagement_distribution,
        cohort_distribution: cohort_distribution,
        momentum_distribution: momentum_distribution,
        risk_engagement_quadrant: risk_engagement_quadrant,
        at_risk_students: at_risk_students,
        high_performers: high_performers,
        inactive_students: inactive_students
      }
    end

    def kpis
      {
        total_students: Student.count,
        active_this_week: Activity.where(created_at: last_week_start..).distinct.count(:student_id),
        at_risk: Prediction.for_month(previous_month_start).at_risk.count,
        high_performers: EngagementScore.high_performer_count(last_week_start, previous_month_start),
        inactive_students: inactive_student_count
      }
    end

    def engagement_distribution
      EngagementScore.distribution_for_week(last_week_start)
    end

    def cohort_distribution
      Student.cohort_counts
    end

    def momentum_distribution
      EngagementScore.momentum_for_weeks(last_week_start)
    end

    def at_risk_students
      Student
        .joins(:cohort, :predictions)
        .left_joins(:engagement_scores, :activities)
        .merge(Prediction.for_month(previous_month_start).at_risk)
        .merge(EngagementScore.for_week(last_week_start))
        .select(
          'DISTINCT ON (students.id) students.id',
          'students.name AS name',
          'students.email AS email',
          'cohorts.name AS cohort',
          EngagementScore.to_percent_sql('predictions.risk_score', as: 'risk_score_percent'),
          EngagementScore.to_percent_sql('COALESCE(engagement_scores.score, 0)', as: 'engagement_score'),
          'activities.created_at AS last_activity_at'
        )
        .order(
          'students.id',
          'activities.created_at DESC',
          'predictions.risk_score DESC'
        )
        .limit(50)
        .map(&:attributes)
    end

    def high_performers
      Student
        .joins(:cohort, :predictions, :engagement_scores)
        .left_joins(:activities)
        .where(engagement_scores: { week_start: last_week_start, score: EngagementScore::ENGAGEMENT_RANGES[:high] })
        .where(predictions: { month_start: previous_month_start, risk_score: Prediction::RISK_RANGES[:low] })
        .select(
          'DISTINCT ON (students.id) students.id',
          'students.name AS name',
          'students.email AS email',
          'cohorts.name AS cohort',
          'engagement_scores.score / 100 AS engagement_score',
          'predictions.risk_score / 100 AS risk_score_percent',
          'activities.created_at AS last_activity_at'
        )
        .order(
          'students.id',
          'activities.created_at DESC'
        )
        .limit(50)
        .map(&:attributes)
    end

    def inactive_students
      inactive_students_relation
        .left_joins(:predictions, :engagement_scores)
        .where(predictions: { month_start: previous_month_start })
        .where(engagement_scores: { week_start: last_week_start })
        .select(
          'students.name AS name',
          'students.email AS email',
          'students.id AS id',
          'cohorts.name AS cohort_name',
          EngagementScore.to_percent_sql('COALESCE(engagement_scores.score, 0)', as: 'engagement_score'),
          EngagementScore.to_percent_sql('predictions.risk_score', as: 'risk_score_percent'),
          'recent_activities.last_activity_at'
        )
        .order('recent_activities.last_activity_at DESC NULLS LAST')
        .map(&:attributes)
    end

    def inactive_student_count
      inactive_students_relation.count
    end

    def inactive_students_relation
      recent_activity_cte = Activity
        .select('student_id', 'MAX(created_at) as last_activity_at')
        .group(:student_id)

      Student
        .with(recent_activities: recent_activity_cte)
        .joins(:cohort)
        .joins('LEFT JOIN recent_activities ON recent_activities.student_id = students.id')
        .where.not("recent_activities.last_activity_at >= ?", reference_date - 7.days)
    end

    def risk_engagement_quadrant
      rows = Student
        .joins(:predictions)
        .left_joins(:engagement_scores)
        .where(predictions: { month_start: previous_month_start })
        .where(engagement_scores: { week_start: last_week_start })
        .group(
          EngagementScore.to_percent_sql('predictions.risk_score'),
          EngagementScore.to_percent_sql('COALESCE(engagement_scores.score, 0)')
        )
        .count

      rows.map do |(risk_bucket, engagement_bucket), count|
        {
          risk: risk_bucket,
          engagement: engagement_bucket,
          count: count,
          quadrant: quadrant_for(risk_bucket, engagement_bucket)
        }
      end
    end

    def quadrant_for(risk, engagement)
      case [risk >= 70, engagement >= 60]
      when [true, false] then 'crisis'
      when [true, true] then 'struggling'
      when [false, false] then 'coasting'
      else 'thriving'
      end
    end

    def previous_month_start
      @previous_month_start ||= reference_date.prev_month.beginning_of_month
    end

    def last_week_start
      @last_week_start ||= reference_date.beginning_of_week - 1.week
    end
  end
end
