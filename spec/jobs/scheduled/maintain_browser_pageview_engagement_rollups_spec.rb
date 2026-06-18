# frozen_string_literal: true

RSpec.describe Jobs::MaintainBrowserPageviewEngagementRollups do
  describe "#execute" do
    before do
      freeze_time(Time.utc(2026, 6, 20, 12, 0, 0))
      SiteSetting.persist_browser_pageview_events = true
    end

    it "does nothing when persist_browser_pageview_events is disabled" do
      SiteSetting.persist_browser_pageview_events = false
      Fabricate(:browser_pageview_session_engagement, created_at: Time.utc(2026, 6, 10))
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 10, 9),
      )

      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagementDailyRollup.count).to eq(0)
    end

    it "aggregates nothing until the first engagement row exists" do
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 10, 9),
      )

      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagementDailyRollup.count).to eq(0)
    end

    it "floors aggregation at the earliest engagement row's date" do
      Fabricate(:browser_pageview_session_engagement, created_at: Time.utc(2026, 6, 10, 8))
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 9, 9),
      )
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 10, 9),
      )
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 11, 9),
      )

      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagementDailyRollup.order(:date).pluck(:date)).to eq(
        [Date.new(2026, 6, 10), Date.new(2026, 6, 11)],
      )
    end

    it "backfills from the floor forward on the first run" do
      Fabricate(:browser_pageview_session_engagement, created_at: Time.utc(2026, 6, 12, 8))
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 12, 9),
      )
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 18, 9),
      )

      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagementDailyRollup.sum(:sessions)).to eq(2)
    end

    it "re-aggregates days a multi-day failure skipped, not only the previous day" do
      Fabricate(:browser_pageview_session_engagement, created_at: Time.utc(2026, 6, 10, 8))
      Fabricate(:browser_pageview_session_engagement_daily_rollup, date: Date.new(2026, 6, 10))
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 15, 9),
      )

      described_class.new.execute({})

      expect(
        BrowserPageviewSessionEngagementDailyRollup.where(date: Date.new(2026, 6, 15)).sum(
          :sessions,
        ),
      ).to eq(1)
    end

    it "does not reach back for a late event on a day behind the last rolled-up day" do
      Fabricate(:browser_pageview_session_engagement, created_at: Time.utc(2026, 6, 18, 8))
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 19, 9),
      )
      described_class.new.execute({})

      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 18, 9),
      )
      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagementDailyRollup.pluck(:date)).to eq(
        [Date.new(2026, 6, 19)],
      )
    end
  end
end
