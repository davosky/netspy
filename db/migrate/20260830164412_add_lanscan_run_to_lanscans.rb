class AddLanscanRunToLanscans < ActiveRecord::Migration[8.1]
  def change
    # Nullable: rows written by a stand-alone run of the Go binary (no NetSpy
    # run record) keep it NULL.
    add_reference :lanscans, :lanscan_run, foreign_key: true
  end
end
