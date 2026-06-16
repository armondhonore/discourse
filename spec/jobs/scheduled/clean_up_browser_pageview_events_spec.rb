# frozen_string_literal: true

RSpec.describe Jobs::CleanUpBrowserPageviewEvents do
  describe "#execute" do
    before { SiteSetting.clean_up_browser_pageview_events = true }

    it "prunes engagement rows past the retention horizon and keeps recent ones" do
      old_session = SecureRandom.alphanumeric(32)
      recent_session = SecureRandom.alphanumeric(32)
      Fabricate(
        :browser_pageview_session_engagement,
        session_id: old_session,
        created_at: 4.months.ago,
      )
      Fabricate(
        :browser_pageview_session_engagement,
        session_id: recent_session,
        created_at: 1.day.ago,
      )

      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagement.pluck(:session_id)).to contain_exactly(recent_session)
    end

    it "keeps engagement rows when clean_up_browser_pageview_events is disabled" do
      SiteSetting.clean_up_browser_pageview_events = false
      Fabricate(:browser_pageview_session_engagement, created_at: 4.months.ago)

      described_class.new.execute({})

      expect(BrowserPageviewSessionEngagement.count).to eq(1)
    end
  end
end
