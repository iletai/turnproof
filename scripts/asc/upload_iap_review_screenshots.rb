#!/usr/bin/env ruby
# Upload one review screenshot to every in-app purchase of an ASC app that has none yet.
# Usage: bundle exec ruby scripts/asc/upload_iap_review_screenshots.rb <asc_app_id> <image.png>
# Credentials come from ./.env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT_BASE64); nothing is printed.
require "base64"
require "digest"
require "faraday"
require "json"
require "spaceship"

app_id, image_path = ARGV
abort "usage: #{$PROGRAM_NAME} <asc_app_id> <image.png>" unless app_id && image_path && File.file?(image_path)

env = File.read(File.expand_path("../../.env", __dir__)).scan(/^(ASC_[A-Z0-9_]+)=(.*)$/).to_h.transform_values { |v| v.delete('"') }
token = Spaceship::ConnectAPI::Token.create(
  key_id: env.fetch("ASC_KEY_ID"),
  issuer_id: env.fetch("ASC_ISSUER_ID"),
  key: Base64.decode64(env.fetch("ASC_KEY_CONTENT_BASE64"))
)

API = "https://api.appstoreconnect.apple.com"
conn = Faraday.new(API)

def call(conn, token, verb, path, body = nil)
  res = conn.run_request(verb, path, body && JSON.generate(body), "Authorization" => "Bearer #{token.text}", "Content-Type" => "application/json")
  [res.status, res.body.to_s.empty? ? {} : JSON.parse(res.body)]
end

data = File.binread(image_path)
file_name = File.basename(image_path)

iaps = []
path = "/v1/apps/#{app_id}/inAppPurchasesV2?limit=200&fields%5BinAppPurchases%5D=productId,name"
loop do
  status, json = call(conn, token, :get, path)
  abort "list failed: #{status}" unless status == 200
  iaps += json["data"]
  next_url = json.dig("links", "next")
  break unless next_url

  path = next_url.sub(API, "")
end
puts "#{iaps.size} in-app purchases on app #{app_id}"

iaps.each do |iap|
  product_id = iap.dig("attributes", "productId")
  status, existing = call(conn, token, :get, "/v2/inAppPurchases/#{iap['id']}/appStoreReviewScreenshot")
  if status == 200 && existing["data"]
    puts "skip #{product_id} (has screenshot)"
    next
  end

  if ENV["DRY_RUN"]
    puts "would upload #{product_id}"
    next
  end

  status, reserved = call(conn, token, :post, "/v1/inAppPurchaseAppStoreReviewScreenshots", {
    data: {
      type: "inAppPurchaseAppStoreReviewScreenshots",
      attributes: { fileName: file_name, fileSize: data.bytesize },
      relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap["id"] } } }
    }
  })
  abort "reserve failed for #{product_id}: #{status} #{reserved}" unless status == 201

  shot_id = reserved.dig("data", "id")
  reserved.dig("data", "attributes", "uploadOperations").each do |op|
    headers = op["requestHeaders"].to_h { |h| [h["name"], h["value"]] }
    chunk = data.byteslice(op["offset"], op["length"])
    res = Faraday.new.run_request(op["method"].downcase.to_sym, op["url"], chunk, headers)
    abort "upload failed for #{product_id}: #{res.status}" unless res.status.between?(200, 299)
  end

  status, committed = call(conn, token, :patch, "/v1/inAppPurchaseAppStoreReviewScreenshots/#{shot_id}", {
    data: {
      type: "inAppPurchaseAppStoreReviewScreenshots",
      id: shot_id,
      attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(data) }
    }
  })
  abort "commit failed for #{product_id}: #{status} #{committed}" unless status == 200

  puts "ok   #{product_id} (#{committed.dig('data', 'attributes', 'assetDeliveryState', 'state')})"
end
