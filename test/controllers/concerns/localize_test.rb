require "test_helper"

class LocalizeTest < ActionDispatch::IntegrationTest
  # Production defaults to zh-CN (config/application.rb), but the test env runs
  # with :en so upstream tests keep passing. Restore zh-CN here to verify the
  # production default behavior.
  def with_chinese_default_locale
    original = I18n.default_locale
    I18n.default_locale = :"zh-CN"
    yield
  ensure
    I18n.default_locale = original
  end

  test "uses default locale on login even when Accept-Language is supported" do
    with_chinese_default_locale do
      get new_session_url, headers: { "Accept-Language" => "fr-CA,fr;q=0.9" }
      assert_response :success
      assert_select "button", text: /登录/i
    end
  end

  test "uses locale param on login when provided" do
    get new_session_url(locale: "fr"), headers: { "Accept-Language" => "zh-CN,zh;q=0.9" }
    assert_response :success
    assert_select "button", text: /Se connecter/i
  end

  test "falls back to Chinese when Accept-Language is unsupported" do
    with_chinese_default_locale do
      get new_session_url, headers: { "Accept-Language" => "zz-ZZ,zz;q=0.9" }
      assert_response :success
      assert_select "button", text: /登录/i
    end
  end

  test "uses family locale for onboarding when user locale is not set" do
    user = users(:family_admin)
    user.family.update!(locale: "zh-CN")
    sign_in user

    get preferences_onboarding_url, headers: { "Accept-Language" => "es-ES,es;q=0.9" }
    assert_response :success
    assert_select "h1", text: /配置您的偏好设置/i
  end

  test "uses family locale when it differs from default locale" do
    user = users(:family_admin)
    user.family.update!(locale: "en")
    sign_in user

    get preferences_onboarding_url, headers: { "Accept-Language" => "ru-RU,ru;q=0.9" }
    assert_response :success
    assert_select "h1", text: /Configure your preferences/i
  end

  test "respects user locale override even when Accept-Language differs" do
    user = users(:family_admin)
    user.update!(locale: "fr")
    sign_in user

    get preferences_onboarding_url, headers: { "Accept-Language" => "es-ES,es;q=0.9" }
    assert_response :success
    assert_select "h1", text: /Configurez vos préférences/i
  end

  test "switches locale when locale param is provided" do
    sign_in users(:family_admin)

    get preferences_onboarding_url(locale: "fr")
    assert_response :success
    assert_select "h1", text: /Configurez vos préférences/i
  end

  test "ignores invalid locale param and uses family locale" do
    user = users(:family_admin)
    user.family.update!(locale: "zh-CN")
    sign_in user

    get preferences_onboarding_url(locale: "invalid_locale")
    assert_response :success
    assert_select "h1", text: /配置您的偏好设置/i
  end

  test "falls back to default timezone and logs a warning when family timezone is unrecognized" do
    user = users(:family_admin)
    # A deliberately nonexistent zone name, standing in for a stale/renamed IANA
    # value slipping past validation (e.g. the historical "Europe/Kiev" ->
    # "Europe/Kyiv" rename, or a migration that never ran). We can't use a real
    # legacy alias like "Europe/Kiev" here: whether tzinfo still recognizes it
    # depends on the host's installed tzdata version, which would make this
    # test non-deterministic across machines/CI.
    user.family.update_column(:timezone, "Invalid/Timezone")
    sign_in user

    assert_difference "DebugLogEntry.count", 1 do
      get root_url
    end

    assert_response :success

    entry = DebugLogEntry.order(:created_at).last
    assert_equal "warn", entry.level
    assert_includes entry.message, "Invalid/Timezone"
    assert_equal user.family, entry.family
  end

  test "does not log when family timezone is valid" do
    user = users(:family_admin)
    user.family.update_column(:timezone, "America/New_York")
    sign_in user

    assert_no_difference "DebugLogEntry.count" do
      get root_url
    end

    assert_response :success
  end

  test "does not log again on a second request within the debounce window" do
    user = users(:family_admin)
    user.family.update_column(:timezone, "Invalid/Timezone")
    sign_in user

    # The test environment's cache store is :null_store (config/environments/test.rb),
    # which never actually caches anything -- every write is a no-op and every
    # key looks nonexistent. Swap in a real store for this test so the
    # debounce lease (Rails.cache.write unless_exist:) is meaningfully
    # exercised instead of trivially passing.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    assert_difference "DebugLogEntry.count", 1 do
      get root_url
      get root_url
      get root_url
    end

    assert_response :success
  ensure
    Rails.cache = original_cache
  end
end
