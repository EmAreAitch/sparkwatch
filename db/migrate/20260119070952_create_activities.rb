class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.references :student, null: false, foreign_key: true
      t.integer :activity_type
      t.timestamps
    end
  end
end
