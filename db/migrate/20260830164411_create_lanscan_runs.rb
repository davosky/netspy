class CreateLanscanRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :lanscan_runs do |t|
      t.references :user, foreign_key: true
      t.string :target, null: false
      t.string :ports, null: false
      t.integer :timeout, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :total_probes
      t.integer :hosts_found, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.string :error_message

      t.timestamps
    end

    add_index :lanscan_runs, :status
    add_index :lanscan_runs, :created_at
  end
end
