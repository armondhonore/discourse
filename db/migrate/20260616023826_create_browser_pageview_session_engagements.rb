# frozen_string_literal: true
class CreateBrowserPageviewSessionEngagements < ActiveRecord::Migration[8.0]
  def change
    create_table :browser_pageview_session_engagements do |t|
      t.string :session_id, limit: 32, null: false
      t.integer :engaged_seconds, null: false
      t.datetime :created_at, null: false
    end

    add_index :browser_pageview_session_engagements, :session_id, unique: true
    add_index :browser_pageview_session_engagements, :created_at
  end
end
