class CreateEngagementScores < ActiveRecord::Migration[8.1]
  def change
    create_table :engagement_scores do |t|
      t.references :student, null: false, foreign_key: true
      t.decimal :score
      t.json :breakdown
      t.timestamps
    end
  end
end
