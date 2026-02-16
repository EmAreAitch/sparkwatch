class Cohort < ApplicationRecord
  has_many :students
  validates :name, :instructor_name, :program, presence: true

  # Engagement tier classification — uses method params with defaults
  # so callers can override thresholds without changing constants
  def self.tier_for_engagement(percent, thriving: 85, steady: 50)
    percent = percent.to_i
    if percent >= thriving
      :thriving
    elsif percent >= steady
      :steady
    else
      :needs_support
    end
  end

  def self.student_counts
    Student.group(:cohort_id).count
  end
end