class CreatePredictions < ActiveRecord::Migration[8.1]
  def change
    create_table :predictions do |t|
      t.references :student, null: false, foreign_key: true
      t.integer :risk_score
        t.jsonb :breakdown, default: {}
      t.integer :confidence
      t.date :month_start
      t.timestamps
    end
    
    add_index :predictions, [:student_id, :month_start], unique: true
  end
end
