class CreateEngagementScores < ActiveRecord::Migration[8.1]
  def change
    create_table :engagement_scores do |t|
      t.references :student, null: false, foreign_key: true
      t.integer :score
      t.json :breakdown
      t.date :week_start
      t.timestamps
    end
    
    add_index :engagement_scores, [:student_id, :week_start], unique: true
  end
end
