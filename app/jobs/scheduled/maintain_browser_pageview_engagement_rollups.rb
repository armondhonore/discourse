# frozen_string_literal: true

module Jobs
  class MaintainBrowserPageviewEngagementRollups < ::Jobs::Scheduled
    every 10.minutes

    cluster_concurrency 1

    def execute(_args)
      return if !SiteSetting.persist_browser_pageview_events

      start_date, end_date = aggregation_window
      return if start_date.nil?

      BrowserPageviewSessionEngagementDailyRollup.aggregate(
        start_date: start_date,
        end_date: end_date,
      )
    end

    private

    def aggregation_window
      floor = BrowserPageviewSessionEngagement.minimum(:created_at)&.to_date
      return nil, nil if floor.nil?

      end_date = Time.zone.today
      start_date =
        BrowserPageviewSessionEngagementDailyRollup.none? ? floor : [floor, 1.day.ago.to_date].max

      [start_date, end_date]
    end
  end
end
