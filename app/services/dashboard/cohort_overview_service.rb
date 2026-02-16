# frozen_string_literal: true
module Dashboard
  class CohortOverviewService
    VALID_WIDGETS = %w[
      kpis
      program_distribution
      instructor_performance
      size_engagement
      completion_projections
      high_performing_cohorts
      needs_attention_cohorts
      most_active_cohorts
    ].freeze

    def initialize(reference_date: Date.current, widgets: nil)
      @reference_date = reference_date.to_date
      @widgets =
        widgets&.map(&:to_s)&.select { |w| VALID_WIDGETS.include?(w) } ||
        VALID_WIDGETS
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      @widgets.each_with_object({}) do |widget, out|
        out[widget.to_sym] = send(widget)
      end
    end

    # ========== WIDGET METHODS (High-level) ==========

    def kpis
      total_cohorts = cohorts.size
      total_students = student_counts.values.sum
      avg_cohort_size = total_cohorts.positive? ? (total_students / total_cohorts) : 0

      cohort_avgs = cohort_avg_percent.values
      avg_of_avgs = cohort_avgs.empty? ? 0 : (cohort_avgs.sum / cohort_avgs.size)

      {
        total_cohorts: total_cohorts,
        avg_cohort_size: avg_cohort_size,
        avg_engagement_percent: avg_of_avgs,
        unique_programs: Cohort.distinct.count(:program)
      }
    end

    def program_distribution
      Student.program_distribution
    end

    def instructor_performance
      EngagementScore.instructor_avg_percent(last_week_start).map do |name, pct|
        { instructor_name: name, avg_engagement_percent: pct }
      end.sort_by { |h| -h[:avg_engagement_percent] }
    end

    def size_engagement
      cohort_ids.map do |cid|
        {
          size: student_counts[cid] || 0,
          engagement_percent: cohort_avg_percent[cid] || 0
        }
      end
    end

    def completion_projections
      Prediction.program_avg_risk_percent(previous_month_start).map do |program, avg_risk|
        { program: program, projected_completion_percent: 100 - avg_risk }
      end.sort_by { |h| -h[:projected_completion_percent] }
    end

    def high_performing_cohorts(threshold = 80)
      cohort_avg_percent
        .select { |_cid, pct| pct >= threshold }
        .map do |cid, pct|
          cohort_data = cohorts[cid]
          {
            id: cid,
            cohort_name: cohort_data[1] || 'Unknown',
            program: cohort_data[2],
            instructor_name: cohort_data[3],
            avg_engagement_percent: pct,
            student_count: student_counts[cid] || 0
          }
        end
        .sort_by { |h| -h[:avg_engagement_percent] }
    end

    def needs_attention_cohorts(eng_threshold = 75, risk_threshold = 65)
      cohort_ids.map do |cid|
        cohort_data = cohorts[cid]
        eng = cohort_avg_percent[cid] || 0
        prog = cohort_data[2]
        risk = prog && (program_avg_risk_percent[prog] || 0)
        
        next unless (eng < eng_threshold) || (risk && risk >= risk_threshold)
        
        {
          id: cid,
          cohort_name: cohort_data[1],
          program: prog,
          instructor_name: cohort_data[3],
          engagement_percent: eng,
          risk_percent: risk || 0,
          student_count: student_counts[cid] || 0
        }
      end.compact.sort_by { |h| [h[:risk_percent], -h[:engagement_percent]] }.reverse
    end

    def most_active_cohorts(limit = 3)
      activity_by_cohort_name.first(limit).map do |(cohort_name, activity_count)|
        cohort_data = cohorts_by_name[cohort_name]
        {
          id: cohort_data ? cohort_data[0] : nil,
          cohort_name: cohort_name,
          program: cohort_data&.dig(2),
          instructor_name: cohort_data&.dig(3),
          student_count: cohort_data ? (student_counts[cohort_data[0]] || 0) : 0,
          activity_count: activity_count
        }
      end
    end

    private

    # ========== MEMOIZED DATA GETTERS (Low-level helpers) ==========

    def cohorts
      @cohorts ||=
        Cohort.pluck(:id, :name, :program, :instructor_name)
              .index_by(&:first)
    end

    def cohort_ids
      @cohort_ids ||= cohorts.keys
    end

    def cohorts_by_name
      @cohorts_by_name ||= cohorts.values.index_by { |data| data[1] }
    end

    def student_counts
      @student_counts ||= Cohort.student_counts
    end

    def cohort_avg_percent
      @cohort_avg_percent ||= EngagementScore.cohort_avg_percent(last_week_start)
    end

    def instructor_avg_percent
      @instructor_avg_percent ||= EngagementScore.instructor_avg_percent(last_week_start)
    end

    def program_avg_risk_percent
      @program_avg_risk_percent ||= Prediction.program_avg_risk_percent(previous_month_start)
    end

    def activity_by_cohort_name
      @activity_by_cohort_name ||= Activity.count_by_cohort_name
    end

    def last_week_start
      @last_week_start ||= @reference_date.beginning_of_week - 1.week
    end

    def previous_month_start
      @previous_month_start ||= @reference_date.prev_month.beginning_of_month
    end
  end
end
