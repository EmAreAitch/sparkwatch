# frozen_string_literal: true

module Dashboard
  class PlatformOverviewService
    VALID_WIDGETS = %w[
      kpis
      weekly_engagement_trend
      risk_distribution
      weekly_activity_breakdown
      program_performance
      at_risk_students
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
        weekly_engagement_trend: weekly_engagement_trend,
        risk_distribution: risk_distribution,
        weekly_activity_breakdown: weekly_activity_breakdown,
        program_performance: program_performance,
        at_risk_students: at_risk_students
      }
    end

    def kpis
      @current_eng ||= EngagementScore.weekly_average_percent(last_week_start) || 0
      @prev_eng    ||= EngagementScore.weekly_average_percent(last_week_start - 1.week) || 0

      current_risk_count = Prediction.for_month(previous_month_start).at_risk.count
      prev_risk_count    = Prediction.for_month(previous_month_start.prev_month).at_risk.count

      {
        total_students: Student.count,
        active_cohorts: Cohort.count,
        avg_engagement_percent: @current_eng,
        avg_engagement_change: @current_eng - @prev_eng,
        at_risk_students: current_risk_count,
        at_risk_change: current_risk_count - prev_risk_count
      }
    end

    def weekly_engagement_trend(weeks: 8)
      EngagementScore.weekly_trend_percent(recent_week_starts(weeks))
    end

    def risk_distribution
      Prediction
        .for_month(previous_month_start)
        .risk_bucketed
        .count
        .transform_keys(&:to_s)
    end

    def weekly_activity_breakdown
      Activity.weekly_breakdown(last_week_start)
    end

    def program_performance
      EngagementScore.program_average_percent(last_week_start)
    end

    def at_risk_students(limit: 10)
      rows = Prediction
               .for_month(previous_month_start)
               .at_risk
               .ordered_by_risk_desc
               .joins(student: :cohort)
               .select(
                 "students.id AS student_id",
                 "students.name AS student_name",
                 "students.email AS student_email",
                 "cohorts.name AS cohort_name",
                 "predictions.risk_score",
                 Activity.last_activity_subquery_sql,
                 EngagementScore.latest_score_subquery_sql
               )
               .limit(limit).to_a

      rows.map do |r|
        eng_raw = r.attributes["latest_engagement_score"]
        
        {
          id: r.student_id,
          name: r.student_name,
          email: r.student_email,
          cohort: r.cohort_name,
          risk_score_percent: EngagementScore.to_percent(r.risk_score),
          engagement_score: eng_raw ? EngagementScore.to_percent(eng_raw) : nil,
          last_activity_at: r.attributes["last_activity_at"]
        }
      end
    end

    def previous_month_start
      @previous_month_start ||= reference_date.prev_month.beginning_of_month
    end

    def last_week_start
      @last_week_start ||= reference_date.beginning_of_week - 1.week
    end

    def recent_week_starts(n)
      (1..n).map { |i| reference_date.beginning_of_week - i.weeks }.reverse
    end
  end
end
