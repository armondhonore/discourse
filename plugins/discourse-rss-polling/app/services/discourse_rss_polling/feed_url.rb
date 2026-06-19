# frozen_string_literal: true

module DiscourseRssPolling
  module FeedUrl
    CREDENTIAL_PARAMS = %w[api_key api_username]

    def self.redact(url)
      uri = URI.parse(url.to_s.strip)
      return url.to_s if uri.query.blank?

      params = CGI.parse(uri.query)
      CREDENTIAL_PARAMS.each { |param| params.delete(param) }
      uri.query = params.empty? ? nil : URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError
      url.to_s.split("?", 2).first.to_s
    end
  end
end
