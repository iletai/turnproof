#!/usr/bin/env ruby
# Create the in-app purchases of an ASC app from the project's .storekit file (single source of truth).
# Idempotent: a product that already exists is skipped. Each new product gets availability (all territories),
# the USD base price and every localization from the storekit file. It never submits anything for review.
# Usage: bundle exec ruby scripts/asc/create_iaps.rb <asc_app_id> <env_bundle_id> <path/to/App.storekit> [--dry-run]
# Types: NonConsumable and Consumable only (subscriptions need a group: do those by hand).
# Limits enforced by ASC: display name <= 35 chars, description <= 55 chars (the script stops before writing).
# Credentials come from ./.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT_BASE64); nothing is printed.
require "base64"
require "faraday"
require "json"
require "spaceship"

dry_run = ARGV.delete("--dry-run")
app_id, bundle_id, storekit_path = ARGV
abort "usage: #{$PROGRAM_NAME} <asc_app_id> <env_bundle_id> <path/to/App.storekit> [--dry-run]" unless app_id && bundle_id && storekit_path

env = File.read(File.expand_path("../../.env", __dir__)).scan(/^(ASC_[A-Z0-9_]+)=(.*)$/).to_h.transform_values { |v| v.delete('"') }
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

def pages(conn, token, path)
  rows = []
  while path
    status, json = call(conn, token, :get, path)
    abort "GET #{path} failed: #{status} #{json}" unless status == 200
    rows += json["data"]
    path = json.dig("links", "next")&.sub(API, "")
  end
  rows
end

TYPES = { "NonConsumable" => "NON_CONSUMABLE", "Consumable" => "CONSUMABLE" }.freeze
dev_prefix = "#{bundle_id.sub(/\.(dev|staging)\z/, '')}.dev."
products = JSON.parse(File.read(storekit_path))["products"]

# Validate everything first so a bad file never leaves half-created products.
products.each do |p|
  abort "#{p['productID']}: unsupported type #{p['type']}" unless TYPES[p["type"]]
  abort "#{p['productID']}: id must start with #{dev_prefix}" unless p["productID"].start_with?(dev_prefix)
  p["localizations"].each do |l|
    abort "#{p['productID']} #{l['locale']}: name > 35 chars" if l["displayName"].length > 35
    abort "#{p['productID']} #{l['locale']}: description > 55 chars (#{l['description'].length})" if l["description"].length > 55
  end
end

existing = pages(conn, token, "/v1/apps/#{app_id}/inAppPurchasesV2?limit=200&fields%5BinAppPurchases%5D=productId").to_h { |i| [i.dig("attributes", "productId"), i["id"]] }
territories = pages(conn, token, "/v1/territories?limit=200").map { |t| t["id"] }

products.each do |p|
  product_id = p["productID"].sub(dev_prefix, "#{bundle_id}.")
  if dry_run
    puts "would #{existing.key?(product_id) ? 'complete' : 'create'} #{product_id} $#{p['displayPrice']}"
    next
  end

  iap_id = existing[product_id]
  unless iap_id
    status, created = call(conn, token, :post, "/v2/inAppPurchases", { data: {
      type: "inAppPurchases",
      attributes: { name: p["referenceName"], productId: product_id, inAppPurchaseType: TYPES[p["type"]], familySharable: p["familyShareable"] || false },
      relationships: { app: { data: { type: "apps", id: app_id } } }
    } })
    abort "create #{product_id}: #{status} #{created}" unless status == 201
    iap_id = created.dig("data", "id")
  end

  # Each step below only runs when its piece is missing, so a half-created product is completed on re-run.
  have_locales = pages(conn, token, "/v2/inAppPurchases/#{iap_id}/inAppPurchaseLocalizations").map { |l| l.dig("attributes", "locale") }
  p["localizations"].each do |l|
    locale = l["locale"].tr("_", "-")
    next if have_locales.include?(locale)

    status, body = call(conn, token, :post, "/v1/inAppPurchaseLocalizations", { data: {
      type: "inAppPurchaseLocalizations",
      attributes: { locale: locale, name: l["displayName"], description: l["description"] },
      relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap_id } } }
    } })
    abort "localization #{product_id} #{locale}: #{status} #{body}" unless status == 201
  end

  # ASC answers 200 with an empty object for a missing availability/price schedule, so count the contents.
  _, avail = call(conn, token, :get, "/v2/inAppPurchases/#{iap_id}/inAppPurchaseAvailability")
  avail_id = avail.dig("data", "id")
  have_territories = avail_id ? pages(conn, token, "/v1/inAppPurchaseAvailabilities/#{avail_id}/availableTerritories?limit=200").size : 0
  if have_territories.zero?
    status, body = call(conn, token, :post, "/v1/inAppPurchaseAvailabilities", { data: {
      type: "inAppPurchaseAvailabilities",
      attributes: { availableInNewTerritories: true },
      relationships: {
        inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } },
        availableTerritories: { data: territories.map { |t| { type: "territories", id: t } } }
      }
    } })
    abort "availability #{product_id}: #{status} #{body}" unless status == 201
  end

  _, sched = call(conn, token, :get, "/v2/inAppPurchases/#{iap_id}/iapPriceSchedule")
  sched_id = sched.dig("data", "id")
  have_prices = sched_id ? pages(conn, token, "/v1/inAppPurchasePriceSchedules/#{sched_id}/manualPrices?limit=200").size : 0
  if have_prices.zero?
    points = pages(conn, token, "/v2/inAppPurchases/#{iap_id}/pricePoints?filter%5Bterritory%5D=USA&limit=200")
    point = points.find { |pt| (pt.dig("attributes", "customerPrice").to_f - p["displayPrice"].to_f).abs < 0.001 }
    abort "#{product_id}: no USD price point for #{p['displayPrice']}" unless point
    status, body = call(conn, token, :post, "/v1/inAppPurchasePriceSchedules", {
      data: {
        type: "inAppPurchasePriceSchedules",
        relationships: {
          inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } },
          baseTerritory: { data: { type: "territories", id: "USA" } },
          manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${price}" }] }
        }
      },
      included: [{ type: "inAppPurchasePrices", id: "${price}", attributes: { startDate: nil },
                   relationships: { inAppPurchasePricePoint: { data: { type: "inAppPurchasePricePoints", id: point["id"] } } } }]
    })
    abort "price #{product_id}: #{status} #{body}" unless status == 201
  end

  puts "ok   #{product_id} $#{p['displayPrice']}"
end
