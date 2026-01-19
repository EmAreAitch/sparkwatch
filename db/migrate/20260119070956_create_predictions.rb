class CreatePredictions < ActiveRecord::Migration[8.1]
  def change
    create_table :predictions do |t|
      t.references :student, null: false, foreign_key: true
      t.decimal :risk_score
      t.integer :confidence
      t.timestamps
    end
  end
end
