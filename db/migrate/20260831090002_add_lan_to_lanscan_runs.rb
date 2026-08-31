class AddLanToLanscanRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :lanscan_runs, :lan, null: true, foreign_key: true
  end
end
