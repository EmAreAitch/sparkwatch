class Prediction < ApplicationRecord
  belongs_to :student
  validates :risk_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
end