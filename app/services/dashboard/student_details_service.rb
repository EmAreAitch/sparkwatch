# frozen_string_literal: true
module Dashboard
  class StudentDetailsService
    VALID_WIDGETS = %w[
      student_info
      kpis
      engagement_trend
      risk_trend
      recent_activities
      recommendations
      engagement_breakdown
      risk_factors
      engagement_analysis
    ].freeze

    def initialize(student_id:, reference_date: Date.current, widgets: nil)
      @student_id = student_id
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

    def student_info
      {
        name: student.name,
        email: student.email,
        cohort_name: cohort.name,
        instructor_name: cohort.instructor_name,
        program: cohort.program
      }
    end

    def kpis
      latest_prediction = latest_prediction_record
      {
        current_engagement_percent: current_engagement_percent,
        engagement_trend: engagement_trend_direction,
        engagement_trend_delta: engagement_trend_delta,
        risk_score_percent: current_risk_percent,
        risk_level: latest_prediction&.risk_level || 'low',
        attendance_rate_percent: attendance_rate_percent,
        last_active_days_ago: last_active_days_ago
      }
    end

    def engagement_breakdown
      last_week = @reference_date.beginning_of_week - 1.week
      score = scores_by_week[last_week]
      score&.breakdown || { attendance: 0, assignments: 0, quizzes: 0, questions: 0, parent: 0 }
    end

    def engagement_trend
      # Returns last 8 weeks of engagement data (excluding current week)
      week_starts = (1..12).map { |w| @reference_date.beginning_of_week - w.weeks }.reverse

      scores = scores_by_week_values(week_starts)
      cohort_scores = cohort_week_averages(week_starts)

      week_starts.map.with_index do |week_start, index|
        score_obj = scores[week_start]
        score = score_obj&.score
        cohort_score = cohort_scores[week_start]
        {
          week_label: "Week #{index + 1}",
          engagement_percent: score ? EngagementScore.to_percent(score) : 0,
          cohort_engagement_percent: EngagementScore.to_percent(cohort_score)
        }
      end
    end

    def risk_trend
      # Returns last 3 months of risk prediction data (excluding current month)
      month_starts = (1..3).map { |m| (@reference_date.beginning_of_month - m.months).to_date }.reverse

      predictions = predictions_by_month(month_starts)
      cohort_predictions = cohort_prediction_averages(month_starts)

      month_starts.map do |month_start|
        risk_score = predictions[month_start]
        cohort_risk = cohort_predictions[month_start]
        {
          month_label: month_start.strftime('%b %Y'),
          risk_percent: risk_score ? EngagementScore.to_percent(risk_score) : 0,
          cohort_risk_percent: cohort_risk ? EngagementScore.to_percent(cohort_risk) : 0
        }
      end
    end

    def recent_activities
      Activity
        .where(student_id: @student_id)
        .order(created_at: :desc)
        .limit(15)
        .map do |activity|
          {
            activity_type: activity.activity_type,
            activity_type_label: activity.display_label,
            days_ago: days_ago(activity.created_at)
          }
        end
    end

    def recommendations
      actions = []
      metrics = kpis

      # High risk recommendation (highest priority)
      if metrics[:risk_score_percent] >= 70
        actions << {
          priority: 1,
          action: 'Urgent: Intervention required - at high risk of dropping out'
        }
      end

      # Inactive student recommendation (high priority)
      if metrics[:last_active_days_ago] && metrics[:last_active_days_ago] > 7
        actions << {
          priority: 2,
          action: 'Reach out immediately - student has been inactive for over a week'
        }
      end

      # Low engagement recommendation
      if metrics[:current_engagement_percent] < 50
        actions << {
          priority: 3,
          action: 'Schedule one-on-one check-in with instructor'
        }
      end

      # Medium risk recommendation
      if metrics[:risk_score_percent] >= 40 && metrics[:risk_score_percent] < 70
        actions << {
          priority: 4,
          action: 'Monitor closely and provide additional support'
        }
      end

      # Poor attendance recommendation
      if metrics[:attendance_rate_percent] < 60
        missed_classes = missed_class_count
        actions << {
          priority: 5,
          action: "Review missed class recordings (#{missed_classes} pending)"
        }
        actions << {
          priority: 6,
          action: 'Encourage attendance at upcoming office hours'
        }
      end

      # Overdue assignments recommendation
      overdue_count = overdue_assignment_count
      if overdue_count > 0
        actions << {
          priority: 7,
          action: "Complete overdue assignments (#{overdue_count} pending)"
        }
      end

      # Inactive student reminder (lower priority)
      if metrics[:last_active_days_ago] && metrics[:last_active_days_ago] > 3 && metrics[:last_active_days_ago] <= 7
        actions << {
          priority: 8,
          action: 'Send engagement reminder - no activity in several days'
        }
      end

      actions.sort_by { |a| a[:priority] }
    end

    def risk_factors
      @risk_factors ||= begin
        metrics = kpis
        pred = latest_prediction_record

        # prefer prediction-provided breakdown (if present)
        pred_breakdown = if pred && pred.respond_to?(:has_attribute?) && pred.has_attribute?(:breakdown)
          pred.breakdown.presence
        end

        factors = []

        # If model breakdown exists, show all contributing features ranked by impact
        if pred_breakdown
          bd = pred_breakdown.transform_keys(&:to_s)

          contributions = []
          Prediction::ACTIVITY_TYPES.each do |atype|
            observed = bd[atype] || 0
            delta = (70 - observed).abs
            # include all activity types to show complete breakdown
            contributions << { name: atype.to_s.titleize, key: atype, observed: observed, delta: delta }
          end

          if bd.key?('score_trend')
            contributions << { name: 'Score Trend', key: 'score_trend', observed: bd['score_trend'], delta: bd['score_trend'].abs }
          end

          # sort by delta (impact) and show all top contributors
          sorted = contributions.sort_by { |c| -c[:delta] }
          sorted.each do |c|
            if c[:key] == 'score_trend'
              # same normalization formula as engagement/risk scores: (value + 50) / 100
              trend_percent = EngagementScore.to_percent(c[:observed]).clamp(-100, 100)
              severity = c[:observed] < -500 ? 'critical' : c[:observed] < 0 ? 'warning' : 'info'
              factors << {
                rank: factors.length + 1,
                factor: "#{c[:name]} (#{trend_percent}%)",
                description: "#{trend_percent}% (negative indicates decline)",
                severity: severity
              }
            else
              severity = c[:observed] < 40 ? 'critical' : c[:observed] < 70 ? 'warning' : 'info'
              factors << {
                rank: factors.length + 1,
                factor: "#{c[:name]} (#{c[:observed]}%)",
                description: "Target is 70%+",
                severity: severity
              }
            end
          end
        else
          breakdown = engagement_breakdown
          lowest = breakdown.min_by { |_k, v| v }
          if lowest && lowest[1] < 70
            factors << { rank: factors.length + 1, factor: "Low #{lowest[0].to_s.titleize}", description: "#{lowest[0].to_s.titleize} at #{lowest[1]}% - expected 70%+", severity: lowest[1] < 40 ? 'critical' : 'warning' }
          end

          if factors.length < 3 && metrics[:last_active_days_ago] && metrics[:last_active_days_ago] > 7
            factors << { rank: factors.length + 1, factor: 'Inactivity', description: "No activity for #{metrics[:last_active_days_ago]} days - needs re-engagement", severity: 'warning' }
          end
        end

        factors
      end
    end

    def engagement_analysis
      @engagement_analysis ||= begin
        breakdown = engagement_breakdown
        last_week = @reference_date.beginning_of_week - 1.week
        prev_week = last_week - 1.week

        last_score = scores_by_week[last_week]
        prev_score = scores_by_week[prev_week]

        trend_direction = if last_score && prev_score
          if last_score.score >= prev_score.score
            'improving'
          elsif last_score.score <= prev_score.score
            'declining'
          else
            'stable'
          end
        else
          'unknown'
        end

        {
          current_breakdown: breakdown,
          lowest_component: breakdown.min_by { |_k, v| v },
          highest_component: breakdown.max_by { |_k, v| v },
          cohort_average: cohort_engagement_average,
          vs_cohort: current_engagement_percent - cohort_engagement_average,
          trend: trend_direction,
          trend_delta: engagement_trend_delta,
          components: breakdown.map do |component, percent|
            {
              name: component.to_s.titleize,
              percent: percent,
              expected: EngagementScore::EXPECTED_WEEKLY[EngagementScore::ACTIVITY_TYPES[component]],
              status: percent >= 70 ? 'on_track' : percent >= 40 ? 'at_risk' : 'critical'
            }
          end
        }
      end
    end

    private

    # ========== MEMOIZED DATA GETTERS (Low-level helpers) ==========

    def student
      @student ||= Student.includes(:cohort).find(@student_id)
    end

    def cohort
      @cohort ||= student.cohort
    end

    def current_engagement_percent
      @current_engagement_percent ||= begin
        # Exclude current week - only get completed weeks
        last_completed_week = @reference_date.beginning_of_week - 1.week
        # Prefer preloaded weekly scores when available
        candidate = scores_by_week.select { |ws, _| ws <= last_completed_week }.max_by { |ws, _| ws }&.last
        candidate ||= EngagementScore
          .where(student_id: @student_id)
          .where('week_start <= ?', last_completed_week)
          .order(week_start: :desc)
          .first

        candidate ? EngagementScore.to_percent(candidate.score) : 0
      end
    end

    def current_risk_percent
      @current_risk_percent ||= begin
        pred = latest_prediction_record
        pred ? pred.risk_score_percent : 0
      end
    end

    def latest_prediction_record
      @latest_prediction_record ||= begin
        last_completed_month = (@reference_date.beginning_of_month - 1.month).to_date
        Prediction
          .where(student_id: @student_id)
          .where('month_start <= ?', last_completed_month)
          .order(month_start: :desc)
          .first
      end
    end

    def attendance_rate_percent
      breakdown = engagement_breakdown
      breakdown['attendance'] || breakdown[:attendance] || 0
    end

    def last_week_attendance_count
      @last_week_attendance_count ||= begin
        last_week = @reference_date.beginning_of_week - 1.week
        Activity
          .where(student_id: @student_id, activity_type: :class_attended)
          .where(created_at: last_week.beginning_of_day..last_week.end_of_week.end_of_day)
          .count
      end
    end

    def last_activity_time
      @last_activity_time ||= Activity
        .where(student_id: @student_id)
        .maximum(:created_at)
    end

    def last_active_days_ago
      return nil unless last_activity_time
      (@reference_date.to_time.end_of_day - last_activity_time).to_i / 1.day
    end

    def missed_class_count
      [3 - last_week_attendance_count, 0].max
    end

    def overdue_assignment_count
      @overdue_assignment_count ||= begin
        weeks_active = EngagementScore
          .where(student_id: @student_id)
          .where('week_start <= ?', @reference_date)
          .count
        expected_assignments = weeks_active * 2
        submitted_assignments = Activity
          .where(student_id: @student_id, activity_type: :assignment_submitted)
          .count

        [expected_assignments - submitted_assignments, 0].max
      end
    end

    # ========== HELPER METHODS ==========

    def days_ago(timestamp)
      ((@reference_date.to_time.end_of_day - timestamp).to_i / 1.day).to_i
    end

    def engagement_trend_direction
      @engagement_trend_direction ||= begin
        last_week = @reference_date.beginning_of_week - 1.week
        prev_week = last_week - 1.week

        last = scores_by_week[last_week]
        prev = scores_by_week[prev_week]

        if last && prev
          if last.score >= prev.score
            'improving'
          elsif last.score <= prev.score
            'declining'
          else
            'stable'
          end
        else
          'unknown'
        end
      end
    end

    def engagement_trend_delta
      @engagement_trend_delta ||= begin
        last_week = @reference_date.beginning_of_week - 1.week
        prev_week = last_week - 1.week

        last = scores_by_week[last_week]
        prev = scores_by_week[prev_week]

        if last && prev
          last_percent = EngagementScore.to_percent(last.score)
          prev_percent = EngagementScore.to_percent(prev.score)
          last_percent - prev_percent
        else
          nil
        end
      end
    end

    def cohort_engagement_average
      @cohort_engagement_average ||= begin
        last_week = @reference_date.beginning_of_week - 1.week
        avg = cohort_week_averages([last_week])[last_week]

        if avg.nil?
          avg = EngagementScore.joins(:student)
            .where(student: { cohort: @cohort }, week_start: last_week)
            .average(:score)
        end

        avg ? EngagementScore.to_percent(avg) : 0
      end
    end

    # ========== BATCHED/ CACHED QUERIES ==========

    def scores_by_week
      return @scores_by_week if defined?(@scores_by_week)
      week_starts = (1..12).map { |w| @reference_date.beginning_of_week - w.weeks }
      rows = EngagementScore.where(student_id: @student_id, week_start: week_starts).to_a
      @scores_by_week = rows.index_by(&:week_start)
    end

    def scores_by_week_values(week_starts)
      # ensure cache includes these week_starts
      missing = week_starts - scores_by_week.keys
      if missing.any?
        rows = EngagementScore.where(student_id: @student_id, week_start: missing).to_a
        rows.each { |r| @scores_by_week[r.week_start] = r }
      end
      @scores_by_week
    end

    def cohort_week_averages(week_starts)
      @cohort_week_averages ||= {}
      missing = week_starts - @cohort_week_averages.keys
      if missing.any?
        averages = EngagementScore.joins(:student)
          .where(student: { cohort: @cohort }, week_start: missing)
          .group(:week_start)
          .average(:score)
        averages.each { |k, v| @cohort_week_averages[k] = v }
      end
      @cohort_week_averages
    end

    def predictions_by_month(month_starts)
      @predictions_by_month ||= {}
      missing = month_starts - @predictions_by_month.keys
      if missing.any?
        preds = Prediction.where(student_id: @student_id, month_start: missing).pluck(:month_start, :risk_score).to_h
        preds.each { |k, v| @predictions_by_month[k] = v }
      end
      @predictions_by_month
    end

    def cohort_prediction_averages(month_starts)
      @cohort_prediction_averages ||= {}
      missing = month_starts - @cohort_prediction_averages.keys
      if missing.any?
        avgs = Prediction.joins(:student)
          .where(student: { cohort: @cohort }, month_start: missing)
          .group(:month_start)
          .average(:risk_score)
        avgs.each { |k, v| @cohort_prediction_averages[k] = v }
      end
      @cohort_prediction_averages
    end
  end
end
