# frozen_string_literal: true

RSpec.describe DiscourseRssPolling::FeedUrl do
  describe ".redact" do
    it "removes api_key and api_username from the query" do
      redacted =
        described_class.redact(
          "https://example.com/feed?api_key=secret&api_username=system&foo=bar",
        )

      expect(redacted).to eq("https://example.com/feed?foo=bar")
      expect(redacted).not_to include("secret")
      expect(redacted).not_to include("system")
    end

    it "drops the query entirely when only credentials are present" do
      expect(described_class.redact("https://example.com/feed?api_key=secret")).to eq(
        "https://example.com/feed",
      )
    end

    it "leaves a credential-free url untouched" do
      expect(described_class.redact("https://example.com/feed")).to eq("https://example.com/feed")
    end

    it "does not leak credentials when the url is malformed" do
      expect(described_class.redact("https://exa mple.com/feed?api_key=secret")).not_to include(
        "secret",
      )
    end

    it "handles blank input" do
      expect(described_class.redact(nil)).to eq("")
    end
  end
end
