class Cohort < ApplicationRecord
  has_many :students
  validates :name, :instructor_name, :program, presence: true
end