#!/usr/bin/env ruby
# Fill TestFlight "Test Information" (en-US + vi descriptions, feedback email, URLs) and the beta review contact.
# Usage: bundle exec ruby scripts/asc/testflight_info.rb <asc_app_id>
# Texts and URLs come from fastlane/metadata/<locale>/{promotional_text,marketing_url,privacy_url}.txt.
# Credentials and contact details come from ./.env (ASC_*, APP_REVIEW_*); nothing secret is printed.
require "base64"
require "faraday"
require "json"
require "spaceship"

app_id = ARGV[0] or abort "usage: #{$PROGRAM_NAME} <asc_app_id>"
root = File.expand_path("../..", __dir__)
env = File.read(File.join(root, ".env")).scan(/^([A-Z][A-Z0-9_]*)=(.*)$/).to_h.transform_values { |v| v.delete('"') }
token = Spaceship::ConnectAPI::Token.create(
  key_id: env.fetch("ASC_KEY_ID"), issuer_id: env.fetch("ASC_ISSUER_ID"),
  key: Base64.decode64(env.fetch("ASC_KEY_CONTENT_BASE64"))
)

API = "https://api.appstoreconnect.apple.com"
conn = Faraday.new(API)
def call(conn, token, verb, path, body = nil)
  res = conn.run_request(verb, path, body && JSON.generate(body), "Authorization" => "Bearer #{token.text}", "Content-Type" => "application/json")
  [res.status, res.body.to_s.empty? ? {} : JSON.parse(res.body)]
end

# Per locale, read the beta description and URLs from the same fastlane metadata the store listing uses.
meta = File.join(root, "fastlane/metadata")
read = ->(locale, name) { f = File.join(meta, locale, name); File.file?(f) ? File.read(f).strip : nil }
locales = Dir.children(meta).select { |d| File.file?(File.join(meta, d, "promotional_text.txt")) }
abort "no fastlane/metadata/<locale>/promotional_text.txt found" if locales.empty?

_, existing = call(conn, token, :get, "/v1/apps/#{app_id}/betaAppLocalizations?limit=50")
by_locale = (existing["data"] || []).to_h { |l| [l.dig("attributes", "locale"), l["id"]] }
locales.each do |locale|
  attrs = { locale: locale, description: read.call(locale, "promotional_text.txt"), feedbackEmail: env.fetch("APP_REVIEW_EMAIL"),
            marketingUrl: read.call(locale, "marketing_url.txt"), privacyPolicyUrl: read.call(locale, "privacy_url.txt") }.compact
  if by_locale[locale]
    status, = call(conn, token, :patch, "/v1/betaAppLocalizations/#{by_locale[locale]}",
                   { data: { type: "betaAppLocalizations", id: by_locale[locale], attributes: attrs.reject { |k, _| k == :locale } } })
  else
    status, = call(conn, token, :post, "/v1/betaAppLocalizations",
                   { data: { type: "betaAppLocalizations", attributes: attrs,
                             relationships: { app: { data: { type: "apps", id: app_id } } } } })
  end
  puts "#{locale}: #{status}"
end

_, detail = call(conn, token, :get, "/v1/apps/#{app_id}/betaAppReviewDetail")
detail_id = detail.dig("data", "id")
status, = call(conn, token, :patch, "/v1/betaAppReviewDetails/#{detail_id}", {
  data: { type: "betaAppReviewDetails", id: detail_id, attributes: {
    contactFirstName: env.fetch("APP_REVIEW_FIRST_NAME"), contactLastName: env.fetch("APP_REVIEW_LAST_NAME"),
    contactPhone: env.fetch("APP_REVIEW_PHONE"), contactEmail: env.fetch("APP_REVIEW_EMAIL"),
    demoAccountRequired: false, notes: "No login or demo account required."
  } }
})
puts "review detail: #{status}"
