class EngagementScore < ApplicationRecord
  belongs_to :student
  validates :score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :breakdown, presence: true
end