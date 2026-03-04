# frozen_string_literal: true

class CreateAssets < ActiveRecord::Migration[7.0]
  def change
    create_table :assets do |t|
      t.references :user, null: false, foreign_key: true
      t.references :generation_job, null: true, foreign_key: true
      t.string :filename
      t.string :content_type
      t.integer :byte_size
      t.json :metadata

      t.timestamps
    end

    add_index :assets, [:user_id, :created_at]
  end
end
