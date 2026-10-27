require "test_helper"

class PlaidItem::AccountsSnapshotTest < ActiveSupport::TestCase
  setup do
    @plaid_item = plaid_items(:one)
    @plaid_item.plaid_accounts.destroy_all # Clean slate

    @plaid_provider = mock
    @snapshot = PlaidItem::AccountsSnapshot.new(@plaid_item, plaid_provider: @plaid_provider)
  end

  test "fetches accounts" do
    @plaid_provider.expects(:get_item_accounts).with(@plaid_item.access_token).returns(
      OpenStruct.new(accounts: [])
    )
    @snapshot.accounts
  end

  test "fetches transactions data if item supports transactions and any accounts present" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "depository"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@plaid_item.access_token, next_cursor: nil).returns(
      OpenStruct.new(
        added: [],
        modified: [],
        removed: [],
        cursor: "test_cursor_1"
      )
    ).once
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "does not fetch transactions if no accounts" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "updates next_cursor when fetching transactions" do
    @plaid_item.update!(available_products: [ "transactions" ], billed_products: [], next_cursor: "test_cursor_1")

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "depository"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).with(@plaid_item.access_token, next_cursor: "test_cursor_1").returns(
      OpenStruct.new(
        added: [],
        modified: [],
        removed: [],
        cursor: "test_cursor_2"
      )
    ).once

    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "fetches investments data if item supports investments and investment accounts present" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "investment"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).with(@plaid_item.access_token).once
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "keeps securities for an investment account with holdings but no investment transactions" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])
    @snapshot.stubs(:accounts).returns([ OpenStruct.new(account_id: "123", type: "investment") ])

    security = OpenStruct.new(security_id: "sec_1", ticker_symbol: "VTI")
    @plaid_provider.expects(:get_item_investments).with(@plaid_item.access_token).returns(
      OpenStruct.new(
        holdings: [ OpenStruct.new(account_id: "123", security_id: "sec_1") ],
        transactions: [],
        securities: [ security ]
      )
    )

    investments = @snapshot.get_account_data("123").investments_data

    assert_equal [ "sec_1" ], investments.holdings.map(&:security_id)
    assert_equal [ security ], investments.securities
  end

  test "imports holdings and identifies brokerage cash without investment transactions" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])
    @snapshot.stubs(:accounts).returns([
      OpenStruct.new(account_id: "123", type: "investment", subtype: "brokerage", name: "Investment", mask: "1234",
        balances: OpenStruct.new(current: 250, available: 250, iso_currency_code: "USD"))
    ])
    @plaid_provider.expects(:get_item_investments).with(@plaid_item.access_token).returns(
      OpenStruct.new(
        transactions: [],
        holdings: [
          Plaid::Holding.new(account_id: "123", security_id: "stock", quantity: 2, institution_price: 100,
            iso_currency_code: "USD", institution_price_as_of: Date.current),
          Plaid::Holding.new(account_id: "123", security_id: "cash", quantity: 50, institution_price: 1,
            iso_currency_code: "USD", institution_price_as_of: Date.current)
        ],
        securities: [
          Plaid::Security.new(security_id: "stock", ticker_symbol: "AAPL", market_identifier_code: "XNAS", type: "equity"),
          Plaid::Security.new(security_id: "cash", ticker_symbol: "CUR:USD", type: "cash")
        ]
      )
    )
    data = @snapshot.get_account_data("123")
    plaid_account = @plaid_item.plaid_accounts.build(plaid_id: "123")
    PlaidAccount::Importer.new(plaid_account, account_snapshot: data).import
    account = @plaid_item.family.accounts.create!(name: "Investment", accountable: Investment.new,
      currency: "USD", balance: 250, cash_balance: 50)
    AccountProvider.create!(account: account, provider: plaid_account)

    upstream_resolver = mock
    Security::Resolver.expects(:new).with("AAPL", exchange_operating_mic: "XNAS").returns(upstream_resolver)
    upstream_resolver.expects(:resolve).returns(securities(:aapl))
    resolver = PlaidAccount::Investments::SecurityResolver.new(plaid_account)

    assert_difference "Holding.count", 1 do
      PlaidAccount::Investments::HoldingsProcessor.new(plaid_account, security_resolver: resolver).process
    end

    holding = account.holdings.find_by!(security: securities(:aapl))
    assert_equal 2, holding.qty
    assert_equal 200, holding.amount
    assert_equal "USD", holding.currency
    assert_equal 50, PlaidAccount::Investments::BalanceCalculator.new(plaid_account, security_resolver: resolver).cash_balance
    assert_empty plaid_account.reload.raw_holdings_payload["transactions"]
  end

  test "has no securities for an investment account with neither holdings nor transactions" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])
    @snapshot.stubs(:accounts).returns([ OpenStruct.new(account_id: "123", type: "investment") ])

    @plaid_provider.expects(:get_item_investments).with(@plaid_item.access_token).returns(
      OpenStruct.new(
        holdings: [ OpenStruct.new(account_id: "other", security_id: "sec_1") ],
        transactions: [],
        securities: [ OpenStruct.new(security_id: "sec_1") ]
      )
    )

    assert_empty @snapshot.get_account_data("123").investments_data.securities
  end

  test "does not fetch investments if no investment accounts" do
    @plaid_item.update!(available_products: [ "investments" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end

  test "fetches liabilities data if item supports liabilities and liabilities accounts present" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([
      OpenStruct.new(
        account_id: "123",
        type: "loan",
        subtype: "student"
      )
    ]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).with(@plaid_item.access_token).once

    @snapshot.get_account_data("123")
  end

  test "does not fetch liabilities if no liabilities accounts" do
    @plaid_item.update!(available_products: [ "liabilities" ], billed_products: [])

    @snapshot.expects(:accounts).returns([]).at_least_once

    @plaid_provider.expects(:get_transactions).never
    @plaid_provider.expects(:get_item_investments).never
    @plaid_provider.expects(:get_item_liabilities).never

    @snapshot.get_account_data("123")
  end
end
