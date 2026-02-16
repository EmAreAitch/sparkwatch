class Student < ApplicationRecord
  belongs_to :cohort
  has_many :activities
  has_many :engagement_scores
  has_many :predictions

  validates :name, :email, presence: true

  scope :with_cohort, -> { includes(:cohort) }
  scope :joined_with_cohort, -> { joins(:cohort) }
  scope :ids_only, -> { select(:id) }
  scope :for_cohorts, ->(cohort_ids) { where(cohort_id: cohort_ids) }
  scope :search_by_name_or_email, ->(query) {
    where("students.name ILIKE :q OR students.email ILIKE :q", q: "%#{query}%") if query.present?
  }

  attribute :cohort_name, :string
  attribute :engagement_score, :integer
  attribute :risk_score, :integer
  attribute :last_active_at, :datetime
  attribute :actual_last_active_at, :datetime

  def self.cohort_counts
    joins(:cohort).group("cohorts.name").order("count_all DESC").count
  end

  def self.inactive_list(cutoff_date, limit: 50)
    joins(:cohort)
      .includes(:engagement_scores, :activities)
      .where("NOT EXISTS (
        SELECT 1 FROM activities 
        WHERE activities.student_id = students.id 
        AND activities.created_at >= ?
      )", cutoff_date)
      .limit(limit)
      .map { |s| format_inactive(s) }
  end

  def self.format_inactive(student)
    latest_score = student.engagement_scores.order(week_start: :desc).first
    last_activity = student.activities.maximum(:created_at)

    {
      id: student.id,
      name: student.name,
      email: student.email,
      cohort: student.cohort.name,
      engagement_score: latest_score ? EngagementScore.to_percent(latest_score.score) : nil,
      last_activity_at: last_activity
    }
  end

  def self.with_last_activity_at
    left_joins(:activities)
      .group("students.id")
      .select("students.*", "MAX(activities.created_at) AS last_activity_at")
  end

  def self.at_risk_for_month(month_start, threshold: 7_000)
    joins(:predictions)
      .merge(Prediction.for_month(month_start).at_risk(threshold))
  end

  def self.program_distribution
    joins(:cohort).group('cohorts.program').count
  end
end
