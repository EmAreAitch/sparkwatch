class Activity < ApplicationRecord
  belongs_to :student
  
  enum :activity_type, [
    :class_attended,
    :assignment_submitted,
    :quiz_taken,
    :question_asked,
    :parent_login
  ]
end