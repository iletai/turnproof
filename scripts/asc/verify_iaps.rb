#!/usr/bin/env ruby
# Read-only audit of every in-app purchase of an ASC app against the project .storekit file.
# Usage: bundle exec ruby scripts/asc/verify_iaps.rb <asc_app_id> <env_bundle_id> <path/to/App.storekit>
# The .storekit file uses the Dev bundle id as prefix; it is derived from <env_bundle_id>.
# Checks per product: exists, USD base price, availability territory count, vi + en localizations, review screenshot.
require "base64"
require "faraday"
require "json"
require "spaceship"

app_id, bundle_id, storekit_path = ARGV
abort "usage: #{$PROGRAM_NAME} <asc_app_id> <env_bundle_id> <path/to/App.storekit>" unless app_id && bundle_id && storekit_path

root = File.expand_path("../..", __dir__)
env = File.read(File.join(root, ".env")).scan(/^(ASC_[A-Z0-9_]+)=(.*)$/).to_h.transform_values { |v| v.delete('"') }
token = Spaceship::ConnectAPI::Token.create(
  key_id: env.fetch("ASC_KEY_ID"),
  issuer_id: env.fetch("ASC_ISSUER_ID"),
  key: Base64.decode64(env.fetch("ASC_KEY_CONTENT_BASE64"))
)

# Expected prices keyed by the product id suffix (storekit file uses the Dev prefix).
dev_prefix = "#{bundle_id.sub(/\.(dev|staging)\z/, '')}.dev."
storekit = JSON.parse(File.read(storekit_path))
expected = storekit["products"].to_h { |p| [p["productID"].sub(dev_prefix, ""), p["displayPrice"]] }

API = "https://api.appstoreconnect.apple.com"
conn = Faraday.new(API)
get = lambda do |path|
  res = conn.get(path, nil, "Authorization" => "Bearer #{token.text}")
  [res.status, res.body.to_s.empty? ? {} : JSON.parse(res.body)]
end

_, listing = get.call("/v1/apps/#{app_id}/inAppPurchasesV2?limit=200&fields%5BinAppPurchases%5D=productId,state")
iaps = listing["data"]
problems = 0
iaps.sort_by { |i| i.dig("attributes", "productId") }.each do |iap|
  pid = iap.dig("attributes", "productId")
  suffix = pid.sub("#{bundle_id}.", "")
  want = expected[suffix]

  _, sched = get.call("/v2/inAppPurchases/#{iap['id']}/iapPriceSchedule")
  sched_id = sched.dig("data", "id")
  price = nil
  if sched_id
    _, manual = get.call("/v1/inAppPurchasePriceSchedules/#{sched_id}/manualPrices?include=inAppPurchasePricePoint&limit=200")
    point = (manual["included"] || []).first
    price = point&.dig("attributes", "customerPrice")
  end

  _, avail = get.call("/v2/inAppPurchases/#{iap['id']}/inAppPurchaseAvailability")
  avail_id = avail.dig("data", "id")
  territories = 0
  if avail_id
    _, terr = get.call("/v1/inAppPurchaseAvailabilities/#{avail_id}/availableTerritories?limit=200")
    territories = terr.dig("meta", "paging", "total") || (terr["data"] || []).size
  end

  _, locs = get.call("/v2/inAppPurchases/#{iap['id']}/inAppPurchaseLocalizations")
  locales = (locs["data"] || []).map { |l| l.dig("attributes", "locale") }.sort
  status, shot = get.call("/v2/inAppPurchases/#{iap['id']}/appStoreReviewScreenshot")
  has_shot = status == 200 && shot["data"]

  ok_price = price && want && (price.to_f - want.to_f).abs < 0.001
  ok = ok_price && territories.to_i >= 170 && locales.include?("vi") && locales.include?("en-US") && has_shot
  problems += 1 unless ok
  puts format("%-4s %-46s price=%-6s want=%-6s territories=%-4s locales=%s shot=%s",
              ok ? "OK" : "FAIL", suffix, price.inspect, want, territories, locales.join("/"), has_shot ? "yes" : "no")
end
puts "#{iaps.size} products, #{problems} with problems"
exit(problems.zero? ? 0 : 1)
