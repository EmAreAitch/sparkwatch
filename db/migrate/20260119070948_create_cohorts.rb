class CreateCohorts < ActiveRecord::Migration[8.1]
  def change
    create_table :cohorts do |t|
      t.string :name
      t.string :instructor_name
      t.string :program

      t.timestamps
    end
  end
end
