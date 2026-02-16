class EngagementScore < ApplicationRecord
  belongs_to :student

  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10000 }
  validates :breakdown, presence: true
  validates :week_start, presence: true, uniqueness: { scope: :student_id }

  WEIGHTS = {
    attendance: 3000,
    assignments: 3000,
    quizzes: 2000,
    questions: 1000,
    parent: 1000
  }.freeze

  ACTIVITY_TYPES = {
    attendance: 'class_attended',
    assignments: 'assignment_submitted',
    quizzes: 'quiz_taken',
    questions: 'question_asked',
    parent: 'parent_login'
  }.freeze

  EXPECTED_WEEKLY = {
    ACTIVITY_TYPES[:attendance] => 3,
    ACTIVITY_TYPES[:assignments] => 2,
    ACTIVITY_TYPES[:quizzes] => 1,
    ACTIVITY_TYPES[:questions] => 2,
    ACTIVITY_TYPES[:parent] => 2
  }.freeze

  ENGAGEMENT_RANGES = {
    high:   8500..,
    medium: 5000...8500,
    low:    ...5000
  }.freeze

  scope :for_week, ->(week_start) { where(week_start: week_start) }
  scope :for_weeks, ->(week_starts) { where(week_start: week_starts) }
  scope :grouped_by_week, -> { group(:week_start) }
  scope :with_student_and_cohort, -> { joins(student: :cohort) }
  scope :grouped_by_program, -> { group("cohorts.program") }
  scope :for_engagement_level, ->(level) {
    range = ENGAGEMENT_RANGES[level.to_sym]
    range ? where(score: range) : none
  }

  def self.distribution_for_week(week_start)
    inner = for_week(week_start)
      .select(Arel.sql(<<~SQL.squish))
        CASE 
          WHEN score < 2000 THEN '0-20%'
          WHEN score < 4000 THEN '21-40%'
          WHEN score < 6000 THEN '41-60%'
          WHEN score < 8000 THEN '61-80%'
          ELSE '81-100%'
        END as range
      SQL
    
    from(inner, :t)
      .group(:range)
      .count
      .transform_keys(&:to_s)
      .reverse_merge('0-20%' => 0, '21-40%' => 0, '41-60%' => 0, '61-80%' => 0, '81-100%' => 0)
  end

  def self.momentum_for_weeks(current_week)
    prev_week = current_week - 1.week
    
    inner = where(week_start: prev_week)
      .with(curr_week: where(week_start: current_week))
      .joins("INNER JOIN curr_week ON curr_week.student_id = #{table_name}.student_id")
      .where("#{table_name}.score > 0")
      .select(Arel.sql(<<~SQL.squish))
        CASE 
          WHEN curr_week.score - #{table_name}.score <= -2000 THEN 'Declining Fast'
          WHEN curr_week.score - #{table_name}.score <= -500 THEN 'Declining'
          WHEN curr_week.score - #{table_name}.score <= 500 THEN 'Stable'
          WHEN curr_week.score - #{table_name}.score <= 2000 THEN 'Improving'
          ELSE 'Improving Fast'
        END as momentum
      SQL
    
    from(inner, :t)
      .group(:momentum)
      .count
      .transform_keys(&:to_s)
      .reverse_merge('Declining Fast' => 0, 'Declining' => 0, 'Stable' => 0, 'Improving' => 0, 'Improving Fast' => 0)
  end

  def self.high_performer_count(week_start, month_start)
    for_week(week_start)
      .where("score >= ?", ENGAGEMENT_RANGES[:high].begin)
      .joins(student: :predictions)
      .where("predictions.month_start = ? AND predictions.risk_score < ?", month_start, Prediction::RISK_RANGES[:low].end)
      .count
  end

  def self.high_performer_list(week_start, month_start, limit: 50)
    for_week(week_start)
      .where("score >= ?", ENGAGEMENT_RANGES[:high].begin)
      .joins(student: [:cohort, :predictions])
      .where("predictions.month_start = ? AND predictions.risk_score < ?", month_start, Prediction::RISK_RANGES[:low].end)
      .includes(student: :activities)
      .order(score: :desc)
      .limit(limit)
      .map { |es| format_performer(es) }
  end

  def self.format_performer(engagement_score)
    student = engagement_score.student
    {
      id: student.id,
      name: student.name,
      email: student.email,
      cohort: student.cohort.name,
      engagement_score: to_percent(engagement_score.score),
      risk_score_percent: student.predictions.first.risk_score_percent,
      last_activity_at: student.activities.maximum(:created_at)
    }
  end

  # Single source of truth for internal score → display percent conversion
  def self.to_percent(raw_score)
    (raw_score.to_i + 50) / 100
  end

  # SQL expression equivalent of to_percent — DRYs inline SQL projections
  def self.to_percent_sql(column, as: nil)
    expr = "((#{column}) + 50) / 100"
    as ? "#{expr} AS #{as}" : expr
  end

  def self.weekly_average_percent(week_start)
    avg = for_week(week_start).average(:score)
    avg ? to_percent(avg) : nil
  end

  def self.weekly_trend_percent(week_starts)
    for_weeks(week_starts)
      .grouped_by_week
      .average(:score)
      .transform_values { |v| to_percent(v) }
  end

  def self.program_average_percent(week_start)
    with_student_and_cohort
      .for_week(week_start)
      .grouped_by_program
      .average(:score)
      .transform_values { |v| to_percent(v) }
  end

  # Reusable: CohortListService, CohortOverviewService
  def self.cohort_avg_percent(week_start)
    joins(:student)
      .for_week(week_start)
      .group('students.cohort_id')
      .average(:score)
      .transform_values { |avg| to_percent(avg) }
  end

  # Reusable SQL subquery for the latest engagement score per student
  def self.latest_score_subquery_sql
    where("engagement_scores.student_id = students.id")
      .order(week_start: :desc)
      .select(:score)
      .limit(1)
      .to_sql
      .then { |sql| "(#{sql}) AS latest_engagement_score" }
  end

  def self.instructor_avg_percent(week_start)
    joins(student: :cohort)
      .for_week(week_start)
      .group('cohorts.instructor_name')
      .average(:score)
      .transform_values { |avg| to_percent(avg) }
  end

  def self.generate_for(students, weeks_back: 8)
    weeks = (1..weeks_back).map { |w| w.weeks.ago.beginning_of_week.to_date }
    cutoff = weeks.last
    inserted = 0

    students.in_batches(of: 500) do |batch|
      existing = existing_scores(batch, cutoff)
      activities = activity_counts(batch, cutoff)

      scores = build_scores(batch, weeks, existing, activities)
      next if scores.empty?

      insert_all(scores)
      inserted += scores.size
    end

    inserted
  end

  def display_score
    self.class.to_percent(score)
  end

  private

  def self.existing_scores(students, cutoff)
    where(student_id: students, week_start: cutoff..)
      .pluck(:student_id, :week_start)
      .to_set
  end

  def self.activity_counts(students, cutoff)
    Activity
      .where(student_id: students, created_at: cutoff..)
      .group(:student_id, Arel.sql("DATE_TRUNC('week', created_at)"), :activity_type)
      .count
      .transform_keys { |(sid, week_timestamp, type)| [sid, week_timestamp.to_date.beginning_of_week, type] }
  end

  def self.build_scores(students, weeks, existing, activities)
    students.flat_map do |student|
      sid = student.id
      weeks.filter_map do |week_start|
        next if existing.include?([sid, week_start])

        percentages = ACTIVITY_TYPES.transform_values do |activity_type|
          percent(activities[[sid, week_start, activity_type]], EXPECTED_WEEKLY[activity_type])
        end

        calculated_score = WEIGHTS.sum { |key, weight| percentages[key] * weight } / 100

        {
          student_id: sid,
          week_start: week_start,
          score: calculated_score,
          breakdown: percentages,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    end
  end

  def self.percent(actual, expected)
    [((actual || 0) * 100) / expected, 100].min
  end
end
