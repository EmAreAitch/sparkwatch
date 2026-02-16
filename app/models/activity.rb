class Activity < ApplicationRecord
  belongs_to :student
  
  enum :activity_type, [
    :class_attended,
    :assignment_submitted,
    :quiz_taken,
    :question_asked,
    :parent_login
  ]

  DISPLAY_LABELS = {
    class_attended:       'Attended class',
    assignment_submitted: 'Submitted assignment',
    quiz_taken:           'Completed quiz',
    question_asked:       'Asked question',
    parent_login:         'Parent logged in'
  }.freeze

  scope :for_time_range, ->(range) {
    where(created_at: range)
  }

  scope :for_week, ->(week_start_date) {
    start_time = week_start_date.to_date.beginning_of_day
    end_time   = week_start_date.to_date.end_of_week.end_of_day
    where(created_at: start_time..end_time)
  }

  scope :grouped_by_type, -> {
    group(:activity_type)
  }

  scope :count_by_type, -> {
    grouped_by_type.count
  }

  scope :for_students, ->(student_ids) {
    where(student_id: student_ids)
  }

  def self.weekly_breakdown(week_start)
    for_week(week_start)
      .grouped_by_type
      .count
  end

  def self.last_activity_at_for_students(student_ids)
    where(student_id: student_ids)
      .group(:student_id)
      .maximum(:created_at)
  end

  # Reusable SQL subquery for last activity per student (correlated subquery form)
  def self.last_activity_subquery_sql
    where("activities.student_id = students.id")
      .select("MAX(activities.created_at)")
      .to_sql
      .then { |sql| "(#{sql}) AS last_activity_at" }
  end

  # Reusable SQL subquery for last activity per student (lateral join form)
  def self.last_activity_lateral_join_sql
    <<~SQL
      LEFT JOIN LATERAL (
        SELECT activities.created_at AS last_active_at
        FROM activities
        WHERE activities.student_id = students.id
        ORDER BY activities.created_at DESC
        LIMIT 1
      ) last_activity ON true
    SQL
  end

  def display_label
    DISPLAY_LABELS[activity_type.to_sym] || activity_type.to_s.titleize
  end

  def self.count_by_cohort_name
    joins(student: :cohort)
      .group('cohorts.name')
      .order('COUNT(activities.id) DESC')
      .pluck('cohorts.name, COUNT(activities.id)')
  end
end
