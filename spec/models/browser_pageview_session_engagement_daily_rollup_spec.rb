# frozen_string_literal: true

RSpec.describe BrowserPageviewSessionEngagementDailyRollup do
  describe ".aggregate" do
    let(:start_date) { Date.new(2026, 6, 1) }
    let(:end_date) { Date.new(2026, 6, 30) }

    before { freeze_time(Time.utc(2026, 6, 20, 12, 0, 0)) }

    it "bounces a single-pageview session with fewer than 10 engaged seconds" do
      session_id = SecureRandom.alphanumeric(32)
      Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 10, 9))
      Fabricate(:browser_pageview_session_engagement, session_id:, engaged_seconds: 9)

      described_class.aggregate(start_date:, end_date:)

      row = described_class.sole
      expect(row.sessions).to eq(1)
      expect(row.bounced).to eq(1)
    end

    it "bounces a single-pageview session that has no engagement row" do
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 10, 9),
      )

      described_class.aggregate(start_date:, end_date:)

      row = described_class.sole
      expect(row.sessions).to eq(1)
      expect(row.bounced).to eq(1)
      expect(row.engaged_seconds_total).to eq(0)
    end

    it "does not bounce a single-pageview session with 10 or more engaged seconds" do
      session_id = SecureRandom.alphanumeric(32)
      Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 10, 9))
      Fabricate(:browser_pageview_session_engagement, session_id:, engaged_seconds: 10)

      described_class.aggregate(start_date:, end_date:)

      row = described_class.sole
      expect(row.sessions).to eq(1)
      expect(row.bounced).to eq(0)
    end

    it "does not bounce a multi-pageview session even with fewer than 10 engaged seconds" do
      session_id = SecureRandom.alphanumeric(32)
      Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 10, 9, 0))
      Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 10, 9, 1))
      Fabricate(:browser_pageview_session_engagement, session_id:, engaged_seconds: 2)

      described_class.aggregate(start_date:, end_date:)

      row = described_class.sole
      expect(row.sessions).to eq(1)
      expect(row.bounced).to eq(0)
    end

    it "splits sessions and bounced counts by the session's logged-in state" do
      user = Fabricate(:user)
      logged_in_session = SecureRandom.alphanumeric(32)
      anon_session = SecureRandom.alphanumeric(32)
      Fabricate(
        :browser_pageview_event,
        session_id: logged_in_session,
        user_id: user.id,
        created_at: Time.utc(2026, 6, 10, 9),
      )
      Fabricate(
        :browser_pageview_event,
        session_id: anon_session,
        created_at: Time.utc(2026, 6, 10, 9),
      )

      described_class.aggregate(start_date:, end_date:)

      rows =
        described_class.order(:logged_in).pluck(
          :logged_in,
          :sessions,
          :bounced,
          :engaged_seconds_total,
        )
      expect(rows).to eq([[false, 1, 1, 0], [true, 1, 1, 0]])
    end

    it "attributes a session spanning midnight to its first pageview date" do
      Time.use_zone("Pacific/Kiritimati") do
        session_id = SecureRandom.alphanumeric(32)
        Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 10, 23, 30))
        Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 11, 0, 30))

        described_class.aggregate(start_date:, end_date:)

        expect(described_class.pluck(:date)).to eq([Date.new(2026, 6, 10)])
      end
    end

    it "sums engaged seconds per date and logged-in state" do
      first_session = SecureRandom.alphanumeric(32)
      second_session = SecureRandom.alphanumeric(32)
      Fabricate(
        :browser_pageview_event,
        session_id: first_session,
        created_at: Time.utc(2026, 6, 10, 9),
      )
      Fabricate(
        :browser_pageview_event,
        session_id: second_session,
        created_at: Time.utc(2026, 6, 10, 9),
      )
      Fabricate(
        :browser_pageview_session_engagement,
        session_id: first_session,
        engaged_seconds: 30,
      )
      Fabricate(
        :browser_pageview_session_engagement,
        session_id: second_session,
        engaged_seconds: 70,
      )

      described_class.aggregate(start_date:, end_date:)

      row = described_class.sole
      expect(row.engaged_seconds_total).to eq(100)
    end

    it "excludes engagement rows whose session has no pageview events" do
      Fabricate(
        :browser_pageview_session_engagement,
        session_id: SecureRandom.alphanumeric(32),
        engaged_seconds: 120,
      )

      described_class.aggregate(start_date:, end_date:)

      expect(described_class.count).to eq(0)
    end

    it "only aggregates sessions whose first pageview falls in the requested range" do
      in_range = SecureRandom.alphanumeric(32)
      out_of_range = SecureRandom.alphanumeric(32)
      Fabricate(:browser_pageview_event, session_id: in_range, created_at: Time.utc(2026, 6, 10, 9))
      Fabricate(
        :browser_pageview_event,
        session_id: out_of_range,
        created_at: Time.utc(2026, 5, 10, 9),
      )

      described_class.aggregate(start_date:, end_date:)

      expect(described_class.sum(:sessions)).to eq(1)
    end

    it "excludes a session whose first pageview is before the range but continues inside it" do
      session_id = SecureRandom.alphanumeric(32)
      Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 5, 31, 23, 30))
      Fabricate(:browser_pageview_event, session_id:, created_at: Time.utc(2026, 6, 1, 0, 30))

      described_class.aggregate(start_date:, end_date:)

      expect(described_class.count).to eq(0)
    end

    it "updates existing rows when re-aggregating with new sessions" do
      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 10, 9),
      )
      described_class.aggregate(start_date:, end_date:)

      Fabricate(
        :browser_pageview_event,
        session_id: SecureRandom.alphanumeric(32),
        created_at: Time.utc(2026, 6, 10, 9),
      )
      described_class.aggregate(start_date:, end_date:)

      expect(described_class.sum(:sessions)).to eq(2)
    end
  end
end
