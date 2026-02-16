# frozen_string_literal: true
module Dashboard
  class CohortDetailsService
    VALID_WIDGETS = %w[
      cohort_info kpis engagement_trend activity_breakdown
      risk_trend score_distribution student_roster
    ].freeze

    def initialize(cohort_id:, reference_date: Date.current, widgets: nil)
      @cohort_id = cohort_id
      @reference_date = reference_date.to_date
      @widgets = (widgets&.map(&:to_s) || VALID_WIDGETS) & VALID_WIDGETS
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      @widgets.each_with_object({}) do |widget, out|
        out[widget.to_sym] = send(widget)
      end
    end

    # ========== WIDGETS ==========

    def cohort_info
      {
        name: cohort.name,
        instructor: cohort.instructor_name,
        program: cohort.program,
        top_student: ranked_roster.first&.dig(:name) || "N/A",
        activity_volume: Activity.where(student_id: student_ids, created_at: 7.days.ago..).count
      }
    end

    def kpis
      scores = latest_scores.values
      {
        student_count: student_ids.size,
        avg_engagement: scores.any? ? EngagementScore.to_percent(scores.sum / scores.size) : 0,
        top_performers: scores.count { |s| EngagementScore::ENGAGEMENT_RANGES[:high].cover?(s) },
        risk_count: latest_risks.values.count { |v| Prediction::RISK_RANGES[:high].cover?(v) }
      }
    end

    def engagement_trend
      program_avgs = EngagementScore.joins(student: :cohort)
        .where(cohorts: { program: cohort.program }, week_start: historical_week_starts)
        .group(:week_start).average(:score)

      historical_week_starts.map.with_index do |week, idx|
        c_avg = historical_cohort_data[week]&.dig(:avg)
        {
          week_label: "W#{idx + 1}",
          cohort_avg: c_avg ? EngagementScore.to_percent(c_avg) : 0,
          program_avg: program_avgs[week] ? EngagementScore.to_percent(program_avgs[week]) : 0
        }
      end
    end

    def activity_breakdown
      dates = (0..6).map { |i| @reference_date - i.days }.reverse
      data = Activity.where(student_id: student_ids, created_at: dates.first.beginning_of_day..dates.last.end_of_day)
                     .group("DATE(created_at)").count
         
      dates.map { |d| { date: d.strftime("%a"), count: data[d] || 0 } }
    end

    def risk_trend
      historical_week_starts.map.with_index do |week, idx|
        d = historical_cohort_data[week] || { low: 0, medium: 0, high: 0 }
        { week: "W#{idx + 1}", low: d[:low], medium: d[:medium], high: d[:high] }
      end
    end
    
    def score_distribution
      buckets = { '0-20%'=>0, '21-40%'=>0, '41-60%'=>0, '61-80%'=>0, '81-100%'=>0 }
      latest_scores.values.each do |s|
        val = EngagementScore.to_percent(s)
        case val
        when 0..20   then buckets['0-20%'] += 1
        when 21..40  then buckets['21-40%'] += 1
        when 41..60  then buckets['41-60%'] += 1
        when 61..80  then buckets['61-80%'] += 1
        else              buckets['81-100%'] += 1
        end
      end
      buckets
    end

    def student_roster
      ranked_roster
    end

    private

    def cohort
      @cohort ||= Cohort.find(@cohort_id)
    end

    def student_ids
      @student_ids ||= cohort.students.pluck(:id)
    end

    def latest_scores
      @latest_scores ||= begin
        week = @reference_date.beginning_of_week - 1.week
        EngagementScore.where(student_id: student_ids, week_start: week).pluck(:student_id, :score).to_h
      end
    end
    
    def latest_risks
      @latest_risks ||= begin
        month = @reference_date.beginning_of_month - 1.month
        Prediction.where(student_id: student_ids, month_start: month).pluck(:student_id, :risk_score).to_h
      end
    end
    
    def last_activity_times
      @last_activity_times ||= Activity.where(student_id: student_ids).group(:student_id).maximum(:created_at)
    end

    def historical_week_starts
      @historical_week_starts ||= (1..8).map { |w| @reference_date.beginning_of_week - w.weeks }.reverse
    end

    def historical_cohort_data
      @historical_cohort_data ||= begin
        high_min = EngagementScore::ENGAGEMENT_RANGES[:high].begin
        med_min  = EngagementScore::ENGAGEMENT_RANGES[:medium].begin
        EngagementScore.where(student_id: student_ids, week_start: historical_week_starts)
          .group(:week_start).pluck(:week_start, Arel.sql("AVG(score), COUNT(CASE WHEN score >= #{high_min} THEN 1 END), COUNT(CASE WHEN score >= #{med_min} AND score < #{high_min} THEN 1 END), COUNT(CASE WHEN score < #{med_min} THEN 1 END)"))
          .each_with_object({}) { |r, o| o[r[0]] = { avg: r[1], low: r[2], medium: r[3], high: r[4] } }
      end
    end

    def ranked_roster
      @ranked_roster ||= begin
        data = cohort.students.pluck(:id, :name, :email).map do |id, name, email|
          eng, risk = latest_scores[id] || 0, latest_risks[id] || 0
          last_active = last_activity_times[id]
          days_ago = last_active ? (Date.current - last_active.to_date).to_i : nil
          
          {
            id: id, name: name, email: email,
            engagement: EngagementScore.to_percent(eng), risk_percent: EngagementScore.to_percent(risk),
            last_active_days_ago: days_ago,
            # Simple Composite Sort: Eng (0-100) + (100 - Risk) + Recency (0-1)
            sort_val: EngagementScore.to_percent(eng) + (100 - EngagementScore.to_percent(risk)) + (days_ago ? (1.0 / [days_ago, 1].max) : 0)
          }
        end.sort_by { |s| -s[:sort_val] }
        data.each_with_index { |s, i| s[:rank] = i + 1 }; data
      end
    end
  end
end
