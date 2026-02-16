class CreateStudents < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      t.string :name
      t.string :email
      t.references :cohort, null: false, foreign_key: true

      t.timestamps
    end
  end
end
