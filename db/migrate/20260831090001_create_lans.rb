class CreateLans < ActiveRecord::Migration[8.1]
  def change
    create_table :lans do |t|
      t.string :lan, null: false
      t.string :ports, null: false, default: "1-1024"
      t.integer :timeout, null: false, default: 600
      t.boolean :primary, null: false, default: false
      t.boolean :secondary, null: false, default: false
      t.string :remote_client_ip
      t.string :remote_user
      t.string :binpath

      t.timestamps
    end

    add_index :lans, :lan, unique: true
  end
end
