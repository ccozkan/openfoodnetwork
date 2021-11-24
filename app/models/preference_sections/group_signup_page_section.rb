# frozen_string_literal: true

module PreferenceSections
  class GroupSignupPageSection
    def name
      I18n.t('admin.contents.edit.group_signup_page')
    end

    def preferences
      %i[
        group_signup_pricing_table_html
        group_signup_case_studies_html
        group_signup_detail_html
      ]
    end
  end
end
