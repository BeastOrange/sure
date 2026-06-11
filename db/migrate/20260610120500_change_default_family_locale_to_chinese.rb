class ChangeDefaultFamilyLocaleToChinese < ActiveRecord::Migration[7.2]
  def change
    change_column_default :families, :locale, from: "en", to: "zh-CN"
  end
end
