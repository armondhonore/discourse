# frozen_string_literal: true

class BrowserPageviewSessionEngagement < ActiveRecord::Base
  def self.record(session_id:, engaged_seconds:)
    DB.exec(
      <<~SQL,
        INSERT INTO browser_pageview_session_engagements (session_id, engaged_seconds, created_at)
        VALUES (:session_id, :engaged_seconds, :now)
        ON CONFLICT (session_id) DO UPDATE
        SET engaged_seconds =
              GREATEST(browser_pageview_session_engagements.engaged_seconds, EXCLUDED.engaged_seconds)
      SQL
      session_id: session_id,
      engaged_seconds: clamp(engaged_seconds, SiteSetting.browser_pageview_max_engaged_seconds),
      now: Time.zone.now,
    )
  end

  def self.clamp(value, cap)
    number = value.respond_to?(:to_i) ? value.to_i : 0
    return 0 if number.negative?

    [number, cap].min
  end
  private_class_method :clamp
end

# == Schema Information
#
# Table name: browser_pageview_session_engagements
#
#  id              :bigint           not null, primary key
#  engaged_seconds :integer          not null
#  created_at      :datetime         not null
#  session_id      :string(32)       not null
#
# Indexes
#
#  index_browser_pageview_session_engagements_on_created_at  (created_at)
#  index_browser_pageview_session_engagements_on_session_id  (session_id) UNIQUE
#
