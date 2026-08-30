class CreateLanscans < ActiveRecord::Migration[8.1]
  def change
    create_table :lanscans do |t|
      t.datetime :scanned_at, null: false
      t.string :target, null: false
      t.string :ip_address, null: false
      t.string :mac_address
      t.string :open_ports

      # Defaulted in the database so the Go lanscan binary can INSERT rows
      # without supplying them; ActiveRecord still sets them on its own writes.
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :lanscans, :scanned_at
    add_index :lanscans, :target
    add_index :lanscans, :ip_address
  end
end
