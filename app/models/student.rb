class Student < ApplicationRecord
  belongs_to :cohort
  has_many :activities
  has_many :engagement_scores
  has_many :predictions
  
  enum :status, [:active, :at_risk, :disengaged]
  
  validates :name, :email, presence: true
end