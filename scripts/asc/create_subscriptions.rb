#!/usr/bin/env ruby
# Create the auto-renewable subscriptions of an ASC app from the project's .storekit file (single source of truth).
# Companion of create_iaps.rb, which only handles NonConsumable/Consumable. Idempotent: every step runs only when
# its piece is missing, so a half-created subscription is completed on re-run. Never submits anything for review.
# Each subscription gets localizations, availability (all territories) and the USD price from the storekit file
# equalised to every territory. Prints the subscription group id: copy it into SUBSCRIPTION_GROUP_ID.
# Usage: bundle exec ruby scripts/asc/create_subscriptions.rb <asc_app_id> <env_bundle_id> <path/to/App.storekit> [--dry-run]
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
  token.refresh! if token.expired? # a full run outlives the 20 minute JWT
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

def post(conn, token, path, body, what)
  status, json = call(conn, token, :post, path, body)
  abort "#{what}: #{status} #{json}" unless status == 201
  json
end

PERIODS = { "P1W" => "ONE_WEEK", "P1M" => "ONE_MONTH", "P2M" => "TWO_MONTHS", "P3M" => "THREE_MONTHS",
            "P6M" => "SIX_MONTHS", "P1Y" => "ONE_YEAR" }.freeze
dev_prefix = "#{bundle_id.sub(/\.(dev|staging)\z/, '')}.dev."
groups = JSON.parse(File.read(storekit_path))["subscriptionGroups"]

# Validate everything first so a bad file never leaves half-created products.
groups.each do |g|
  g["subscriptions"].each do |s|
    abort "#{s['productID']}: unsupported period #{s['recurringSubscriptionPeriod']}" unless PERIODS[s["recurringSubscriptionPeriod"]]
    abort "#{s['productID']}: id must start with #{dev_prefix}" unless s["productID"].start_with?(dev_prefix)
    s["localizations"].each do |l|
      abort "#{s['productID']} #{l['locale']}: name > 35 chars" if l["displayName"].length > 35
      abort "#{s['productID']} #{l['locale']}: description > 55 chars" if l["description"].length > 55
    end
  end
end

existing_groups = pages(conn, token, "/v1/apps/#{app_id}/subscriptionGroups?limit=200").to_h { |g| [g.dig("attributes", "referenceName"), g["id"]] }
territories = pages(conn, token, "/v1/territories?limit=200").map { |t| t["id"] }

groups.each do |g|
  if dry_run
    g["subscriptions"].each { |s| puts "would ensure #{s['productID'].sub(dev_prefix, "#{bundle_id}.")} $#{s['displayPrice']} in group #{g['name']}" }
    next
  end

  group_id = existing_groups[g["name"]] ||
    post(conn, token, "/v1/subscriptionGroups", { data: { type: "subscriptionGroups", attributes: { referenceName: g["name"] },
         relationships: { app: { data: { type: "apps", id: app_id } } } } }, "group #{g['name']}").dig("data", "id")
  have = pages(conn, token, "/v1/subscriptionGroups/#{group_id}/subscriptionGroupLocalizations").map { |l| l.dig("attributes", "locale") }
  (g["localizations"].empty? ? [{ "locale" => "en_US", "name" => g["name"] }] : g["localizations"]).each do |l|
    locale = l["locale"].tr("_", "-")
    next if have.include?(locale)

    post(conn, token, "/v1/subscriptionGroupLocalizations", { data: { type: "subscriptionGroupLocalizations",
         attributes: { locale: locale, name: l["name"] }, relationships: { subscriptionGroup: { data: { type: "subscriptionGroups", id: group_id } } } } },
         "group localization #{locale}")
  end
  existing = pages(conn, token, "/v1/subscriptionGroups/#{group_id}/subscriptions?limit=200").to_h { |s| [s.dig("attributes", "productId"), s["id"]] }

  g["subscriptions"].each do |s|
    product_id = s["productID"].sub(dev_prefix, "#{bundle_id}.")
    sub_id = existing[product_id] ||
      post(conn, token, "/v1/subscriptions", { data: { type: "subscriptions",
           attributes: { name: s["referenceName"], productId: product_id, subscriptionPeriod: PERIODS[s["recurringSubscriptionPeriod"]],
                         familySharable: s["familyShareable"] || false, groupLevel: s["groupNumber"] || 1 },
           relationships: { group: { data: { type: "subscriptionGroups", id: group_id } } } } }, "create #{product_id}").dig("data", "id")

    have = pages(conn, token, "/v1/subscriptions/#{sub_id}/subscriptionLocalizations").map { |l| l.dig("attributes", "locale") }
    s["localizations"].each do |l|
      locale = l["locale"].tr("_", "-")
      next if have.include?(locale)

      post(conn, token, "/v1/subscriptionLocalizations", { data: { type: "subscriptionLocalizations",
           attributes: { locale: locale, name: l["displayName"], description: l["description"] },
           relationships: { subscription: { data: { type: "subscriptions", id: sub_id } } } } }, "localization #{product_id} #{locale}")
    end

    # ASC answers 200 with an empty object for a missing availability, so check the id.
    _, avail = call(conn, token, :get, "/v1/subscriptions/#{sub_id}/subscriptionAvailability")
    unless avail.dig("data", "id")
      post(conn, token, "/v1/subscriptionAvailabilities", { data: { type: "subscriptionAvailabilities",
           attributes: { availableInNewTerritories: true },
           relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                            availableTerritories: { data: territories.map { |t| { type: "territories", id: t } } } } } }, "availability #{product_id}")
    end

    # Per-territory check so a run that died halfway (e.g. rate limit) is completed, not skipped.
    priced = pages(conn, token, "/v1/subscriptions/#{sub_id}/prices?limit=200").map { |pr| pr.dig("relationships", "territory", "data", "id") }
    usd = pages(conn, token, "/v1/subscriptions/#{sub_id}/pricePoints?filter%5Bterritory%5D=USA&limit=200")
            .find { |pt| (pt.dig("attributes", "customerPrice").to_f - s["displayPrice"].to_f).abs < 0.001 }
    abort "#{product_id}: no USD price point for #{s['displayPrice']}" unless usd
    points = [usd] + pages(conn, token, "/v1/subscriptionPricePoints/#{usd['id']}/equalizations?limit=200")
    points.each do |point|
      next if priced.include?(point.dig("relationships", "territory", "data", "id"))

      post(conn, token, "/v1/subscriptionPrices", { data: { type: "subscriptionPrices",
           attributes: { startDate: nil, preserveCurrentPrice: false },
           relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                            subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: point["id"] } } } } }, "price #{product_id}")
    end
    puts "ok   #{product_id} $#{s['displayPrice']} (group id #{g['name']} = #{group_id})"
  end
end
