class AddDashboardIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :engagement_scores, [:week_start, :score], name: "idx_eng_scores_on_date_and_val"
    add_index :predictions, [:month_start, :risk_score], name: "index_predictions_on_month_start_and_risk_score" unless index_exists?(:predictions, [:month_start, :risk_score])
    add_index :activities, [:student_id, :created_at], name: "index_activities_on_student_id_and_created_at" unless index_exists?(:activities, [:student_id, :created_at])
    add_index :activities, :created_at unless index_exists?(:activities, :created_at)
  end
end
