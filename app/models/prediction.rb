class Prediction < ApplicationRecord
  belongs_to :student

  validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10000 }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10000 }
  validates :month_start, presence: true, uniqueness: { scope: :student_id }

  ACTIVITY_TYPES = ['class_attended', 'assignment_submitted', 'parent_login'].freeze

  EXPECTED_MONTHLY = {
    'class_attended' => 12,
    'assignment_submitted' => 8,
    'parent_login' => 8
  }.freeze

  RISK_RANGES = {
    high:   9000..,
    medium: 7500...9000,
    low:    ...7500
  }.freeze

  MODEL_PATH = Rails.root.join('lib/ml/dropout_model.marshal').freeze

  scope :for_month, ->(month_start) { where(month_start: month_start) }
  scope :at_risk, ->(threshold = 9000) { where("risk_score >= ?", threshold) }
  scope :ordered_by_risk_desc, -> { order(risk_score: :desc) }
  scope :for_risk_level, ->(level) {
    range = RISK_RANGES[level.to_sym]
    range ? where(risk_score: range) : none
  }
  scope :risk_bucketed, -> {
    high_min = RISK_RANGES[:high].begin
    med_min  = RISK_RANGES[:medium].begin
    group("CASE 
      WHEN risk_score >= #{high_min} THEN 'high'
      WHEN risk_score >= #{med_min} THEN 'medium'
      ELSE 'low'
    END")
  }

  def self.at_risk_count_by_cohort(month_start, threshold: 9000)
    joins(:student)
      .for_month(month_start)
      .where('risk_score >= ?', threshold)
      .group('students.cohort_id')
      .count
  end

  def self.at_risk_list(month_start, threshold: 9000, limit: 50)
    for_month(month_start)
      .at_risk(threshold)
      .ordered_by_risk_desc
      .joins(student: :cohort)
      .includes(student: [:engagement_scores, :activities])
      .limit(limit)
      .map { |p| format_at_risk(p) }
  end

  def self.format_at_risk(prediction)
    student = prediction.student
    latest_score = student.engagement_scores.order(week_start: :desc).first
    last_activity = student.activities.maximum(:created_at)

    {
      id: student.id,
      name: student.name,
      email: student.email,
      cohort: student.cohort.name,
      risk_score_percent: prediction.risk_score_percent,
      engagement_score: latest_score ? EngagementScore.to_percent(latest_score.score) : nil,
      last_activity_at: last_activity
    }
  end

  def risk_score_percent
    EngagementScore.to_percent(risk_score)
  end

  def risk_level
    RISK_RANGES.each do |level, range|
      return level.to_s if range.cover?(risk_score)
    end
    'low'
  end

  def confidence_score
    EngagementScore.to_percent(confidence)
  end

  def self.program_avg_risk_percent(month_start)
    joins(student: :cohort)
      .for_month(month_start)
      .group('cohorts.program')
      .average(:risk_score)
      .transform_values { |avg| EngagementScore.to_percent(avg) }
  end

  def self.generate_for(students, months_back: 2)
    model = Marshal.load(File.binread(MODEL_PATH))
    months = (1..months_back).map { |m| m.months.ago.beginning_of_month.to_date }
    cutoff = months.last
    month_end = months.first.end_of_month
    inserted = 0

    students.in_batches(of: 500) do |batch|
      existing = existing_predictions(batch, cutoff)
      activities = activity_counts(batch, cutoff, month_end)
      scores = score_trends(batch, cutoff, month_end)

      predictions = build_predictions(batch, months, existing, activities, scores, model)
      next if predictions.empty?

      insert_all(predictions)
      inserted += predictions.size
    end

    inserted
  end

  private

  def self.existing_predictions(students, cutoff)
    where(student_id: students, month_start: cutoff..)
      .pluck(:student_id, :month_start)
      .to_set
  end

  def self.activity_counts(students, cutoff, month_end)
    Activity
      .where(student_id: students, created_at: cutoff..month_end)
      .group(:student_id, Arel.sql("DATE_TRUNC('month', created_at)"), :activity_type)
      .count
      .transform_keys { |(sid, month_timestamp, type)| [sid, month_timestamp.to_date.beginning_of_month, type] }
  end

  def self.score_trends(students, cutoff, month_end)
    scores = EngagementScore
      .where(student_id: students, week_start: cutoff..month_end)
      .order(:week_start)
      .group_by { |s| [s.student_id, s.week_start.beginning_of_month.to_date] }

    scores.transform_values do |month_scores|
      month_scores.any? ? month_scores.last.score - month_scores.first.score : 0
    end
  end

  def self.build_predictions(students, months, existing, activities, scores, model)
    feature_matrix = []
    metadata = []

    students.each do |student|
      sid = student.id
      months.each do |month|
        next if existing.include?([sid, month])

        features = ACTIVITY_TYPES.map do |activity_type|
          percent(activities[[sid, month, activity_type]], EXPECTED_MONTHLY[activity_type])
        end
        features << (scores[[sid, month]] || 0)

        feature_matrix << features
        metadata << [sid, month]
      end
    end

    return [] if feature_matrix.empty?

    scaled = model[:scaler].transform(Numo::DFloat.cast(feature_matrix))
    probs = model[:model].predict_proba(scaled)

    metadata.each_with_index.map do |(sid, month), i|
      # Build breakdown mapping activity types to observed percent for explainability
      breakdown = ACTIVITY_TYPES.each_with_index.each_with_object({}) do |(atype, idx), h|
        # Validation: feature_matrix[i][idx] is already the % value (0-100)
        h[atype] = feature_matrix[i][idx]
      end

      # include score trend (raw delta) as an explainability feature
      score_val = (scores[[sid, month]] || 0)
      breakdown['score_trend'] = score_val

      {
        student_id: sid,
        month_start: month,
        risk_score: (probs[i, 1] * 10000).round,
        confidence: (([probs[i, 0], probs[i, 1]].max - 0.5) * 20000).round,
        breakdown: breakdown,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end

  def self.percent(actual, expected)
    [((actual || 0) * 100) / expected, 100].min
  end
end
