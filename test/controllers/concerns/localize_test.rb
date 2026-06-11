require "test_helper"

class LocalizeTest < ActionDispatch::IntegrationTest
  test "uses default locale on login even when Accept-Language is supported" do
    get new_session_url, headers: { "Accept-Language" => "fr-CA,fr;q=0.9" }
    assert_response :success
    assert_select "button", text: /登录/i
  end

  test "uses locale param on login when provided" do
    get new_session_url(locale: "fr"), headers: { "Accept-Language" => "zh-CN,zh;q=0.9" }
    assert_response :success
    assert_select "button", text: /Se connecter/i
  end

  test "falls back to Chinese when Accept-Language is unsupported" do
    get new_session_url, headers: { "Accept-Language" => "ru-RU,ru;q=0.9" }
    assert_response :success
    assert_select "button", text: /登录/i
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
end
