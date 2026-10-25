# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "Login language", type: :rails_request,
                                 with_settings: { available_languages: %w[en de], default_language: "en" } do
  def expect_login_language(language)
    expect(response).to have_http_status(:ok)
    expect(response.body).to have_css("#login-form h1", text: I18n.t(:label_login, locale: language))
    expect(response.body).to have_css("#login_language option[value='#{language}'][selected]")
  end

  it "switches language and keeps the choice on subsequent requests" do
    get signin_path, params: { language: "de", back_url: "/projects" }

    expect_login_language(:de)
    expect(response.body).to have_css('.auth-form--language input[name="back_url"][value="%2Fprojects"]', visible: :all)

    get signin_path

    expect_login_language(:de)
  end

  it "keeps the chosen language after invalid credentials" do
    get signin_path, params: { language: "de" }
    csrf_token = response.parsed_body.at_css('meta[name="csrf-token"]')["content"]
    post signin_path,
         params: { username: "nonexistent", password: "invalid" },
         headers: { "X-CSRF-Token" => csrf_token }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to have_css("#login-form h1", text: I18n.t(:label_login, locale: :de))
  end

  it "ignores unavailable languages and malformed values" do
    get signin_path, params: { language: "de" }

    ["fr", "invalid", { unexpected: "en" }].each do |language|
      get signin_path, params: { language: }

      expect_login_language(:de)
    end
  end

  it "ignores a saved language after it has been disabled" do
    get signin_path, params: { language: "de" }

    with_settings(available_languages: ["en"]) do
      get signin_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "en" }

      expect(response.body).to have_css("#login-form h1", text: I18n.t(:label_login, locale: :en))
      expect(response.body).to have_no_css("#login_language")
    end
  end

  context "when direct login is enabled",
          with_settings: { omniauth_direct_login_provider: "some_provider" } do
    it "keeps the internal login route when switching language" do
      get internal_signin_path, params: { language: "de" }

      expect_login_language(:de)
      expect(response.body).to have_css("form.auth-form--language[action='#{internal_signin_path}']")
    end
  end
end
