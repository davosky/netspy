class ChangeLanscansTimestampsDefault < ActiveRecord::Migration[8.1]
  # The Go `vendor/lanscan` binary no longer writes to the database (NetSpy
  # persists the parsed results itself), so `lanscans` rows are created only by
  # ActiveRecord, which always sets the timestamps. Drop the DB-side default.
  def up
    change_column_default :lanscans, :created_at, from: -> { "CURRENT_TIMESTAMP" }, to: nil
    change_column_default :lanscans, :updated_at, from: -> { "CURRENT_TIMESTAMP" }, to: nil
  end

  def down
    change_column_default :lanscans, :created_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
    change_column_default :lanscans, :updated_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
  end
end
