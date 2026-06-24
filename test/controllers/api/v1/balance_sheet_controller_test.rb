# frozen_string_literal: true

require "test_helper"

class Api::V1::BalanceSheetControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = families(:dylan_family)

    @user.api_keys.active.destroy_all

    @auth = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      display_key: "test_ro_#{SecureRandom.hex(8)}",
      source: "mobile"
    )

    Redis.new.del("api_rate_limit:#{@auth.id}")
  end

  test "should require authentication" do
    get "/api/v1/balance_sheet"
    assert_response :unauthorized
  end

  test "limited member balance sheet excludes inaccessible private accounts" do
    member = users(:family_member)
    member.api_keys.active.destroy_all
    member_key = ApiKey.create!(
      user: member,
      name: "Member Read Key",
      scopes: [ "read" ],
      display_key: "test_member_ro_#{SecureRandom.hex(8)}",
      source: "monitoring"
    )
    Redis.new.del("api_rate_limit:#{member_key.id}")

    get "/api/v1/balance_sheet", headers: api_headers(@auth)
    assert_response :success
    admin_net_worth = JSON.parse(response.body).dig("net_worth", "amount").to_d

    get "/api/v1/balance_sheet", headers: api_headers(member_key)
    assert_response :success
    member_net_worth = JSON.parse(response.body).dig("net_worth", "amount").to_d

    assert_operator member_net_worth, :<, admin_net_worth

    member_balance_sheet = @family.balance_sheet(user: member)
    expected_net_worth = member_balance_sheet.net_worth_money.amount
    assert_in_delta expected_net_worth, member_net_worth, 0.01
  end

  test "should return balance sheet with net worth data" do
    get "/api/v1/balance_sheet", headers: api_headers(@auth)

    assert_response :success
    response_body = JSON.parse(response.body)

    assert response_body.key?("currency")
    assert response_body.key?("net_worth")
    assert response_body.key?("assets")
    assert response_body.key?("liabilities")

    %w[net_worth assets liabilities].each do |field|
      assert response_body[field].key?("amount"), "#{field} should have amount"
      assert response_body[field].key?("currency"), "#{field} should have currency"
      assert response_body[field].key?("formatted"), "#{field} should have formatted"
    end
  end

  private

    def api_headers(auth)
      { "X-Api-Key" => auth.display_key }
    end
end
