# frozen_string_literal: true

require "test_helper"

class Api::V1::HoldingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @family = @admin.family
    @investment_account = accounts(:investment)
    @private_holding = holdings(:one)
    @member = users(:family_member)

    @admin.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @admin,
      name: "Admin Read Key",
      scopes: [ "read" ],
      display_key: "test_admin_ro_#{SecureRandom.hex(8)}",
      source: "web"
    )
    Redis.new.del("api_rate_limit:#{@api_key.id}")
  end

  test "admin can list and show holdings on family investment account" do
    get api_v1_holdings_url, headers: api_headers(@api_key)
    assert_response :success

    holding_ids = JSON.parse(response.body)["holdings"].map { |holding| holding["id"] }
    assert_includes holding_ids, @private_holding.id

    get api_v1_holding_url(@private_holding), headers: api_headers(@api_key)
    assert_response :success
    assert_equal @private_holding.id, JSON.parse(response.body)["id"]
  end

  test "limited member cannot list holdings for inaccessible account" do
    member_key = member_api_key(scopes: [ "read" ])

    get api_v1_holdings_url, headers: api_headers(member_key)
    assert_response :success

    holding_ids = JSON.parse(response.body)["holdings"].map { |holding| holding["id"] }
    assert_not_includes holding_ids, @private_holding.id
  end

  test "limited member cannot show holding from inaccessible account" do
    member_key = member_api_key(scopes: [ "read" ])

    get api_v1_holding_url(@private_holding), headers: api_headers(member_key)
    assert_response :not_found
    assert_equal "not_found", JSON.parse(response.body)["error"]
  end

  test "filter by inaccessible account_id returns empty list for limited member" do
    member_key = member_api_key(scopes: [ "read" ])

    get api_v1_holdings_url,
        params: { account_id: @investment_account.id },
        headers: api_headers(member_key)
    assert_response :success

    assert_empty JSON.parse(response.body)["holdings"]
  end

  test "limited member can list shared investment holdings after read only share" do
    @investment_account.share_with!(@member, permission: "read_only")
    member_key = member_api_key(scopes: [ "read" ])

    get api_v1_holdings_url, headers: api_headers(member_key)
    assert_response :success

    holding_ids = JSON.parse(response.body)["holdings"].map { |holding| holding["id"] }
    assert_includes holding_ids, @private_holding.id
  end

  private

    def member_api_key(scopes:)
      @member.api_keys.active.destroy_all
      key = ApiKey.create!(
        user: @member,
        name: "Member API Key",
        scopes: scopes,
        display_key: "test_member_#{SecureRandom.hex(8)}",
        source: "mobile"
      )
      Redis.new.del("api_rate_limit:#{key.id}")
      key
    end

    def api_headers(api_key)
      { "X-Api-Key" => api_key.display_key }
    end
end
