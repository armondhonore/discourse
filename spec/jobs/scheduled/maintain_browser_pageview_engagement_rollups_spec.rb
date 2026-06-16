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
  end
end
