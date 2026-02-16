# frozen_string_literal: true
module Dashboard
  class CohortListService
    def initialize(reference_date: Date.current)
      @reference_date = reference_date.to_date
      @last_completed_week = @reference_date.last_week.beginning_of_week
      @last_completed_month = @reference_date.last_month.beginning_of_month
    end
    
    def self.call(**args)
      new(**args).call
    end
    
    def call
      prepare_data_maps
      
      {
        cohorts: cohorts_data,
        summary: summary_stats
      }
    end
    
    private
    
    # ========== DATA PREPARATION ==========
    
    def prepare_data_maps
      @student_count_map = Cohort.student_counts
      @engagement_map = EngagementScore.cohort_avg_percent(@last_completed_week)
      @at_risk_count_map = Prediction.at_risk_count_by_cohort(@last_completed_month)
    end
    
    # ========== HIGH-LEVEL DATA METHODS ==========
    
    def cohorts_data
      Cohort.order(:name).map do |cohort| 
        engagement = @engagement_map[cohort.id] || 0
        
        {
          id: cohort.id,
          name: cohort.name,
          program: cohort.program,
          instructor_name: cohort.instructor_name,
          engagement_percent: engagement,
          student_count: @student_count_map[cohort.id] || 0,
          at_risk_count: @at_risk_count_map[cohort.id] || 0,
          tier: Cohort.tier_for_engagement(engagement)
        }
      end.sort_by { |c| [-c[:engagement_percent], c[:name]] }
    end
    
    def summary_stats
      cohorts = cohorts_data
      
      {
        total_cohorts: cohorts.size,
        total_students: cohorts.sum { |c| c[:student_count] },
        total_at_risk: cohorts.sum { |c| c[:at_risk_count] },
        average_engagement_percent: calculate_simple_average(cohorts),
        thriving_count: cohorts.count { |c| c[:tier] == :thriving },
        steady_count: cohorts.count { |c| c[:tier] == :steady },
        needs_support_count: cohorts.count { |c| c[:tier] == :needs_support }
      }
    end
    
    # ========== HELPER METHODS ==========
    
    def calculate_simple_average(cohorts)
      return 0 if cohorts.empty?
      
      (cohorts.sum { |c| c[:engagement_percent] } / cohorts.size.to_f).round
    end
  end
end
