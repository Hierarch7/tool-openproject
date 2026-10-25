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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "API tokens restricted to admin",
               with_settings: { api_tokens_enabled: true, login_required: true } do
  let(:user) { create(:admin, login: "admin") }
  let(:token) { create(:api_token, user:) }

  before do
    allow(OpenProject::Configuration).to receive(:apiv3_enable_basic_auth?).and_return(true)
  end

  %i[basic bearer].each do |authentication|
    context "with #{authentication} authentication" do
      before do
        authorization = if authentication == :basic
                          ActionController::HttpAuthentication::Basic.encode_credentials("apikey", token.plain_value)
                        else
                          "Bearer #{token.plain_value}"
                        end
        header "Authorization", authorization
        get "/api/v3/users/me"
      end

      it "authenticates admin" do
        expect(last_response).to have_http_status(:ok)
        expect(JSON.parse(last_response.body)["login"]).to eq("admin")
      end

      context "with a token previously issued to a regular user" do
        let(:user) { create(:user) }

        it "rejects the token" do
          expect(last_response).to have_http_status(:unauthorized)
        end
      end

      context "with a token previously issued to another administrator" do
        let(:user) { create(:admin, login: "another-admin") }

        it "rejects the token" do
          expect(last_response).to have_http_status(:unauthorized)
        end
      end

      context "with an account named admin without administrator privileges" do
        let(:user) { create(:user, login: "admin") }

        it "rejects the token" do
          expect(last_response).to have_http_status(:unauthorized)
        end
      end

      context "when admin is locked" do
        let(:user) { create(:admin, :locked, login: "admin") }

        it "rejects the token" do
          expect(last_response).to have_http_status(:unauthorized)
        end
      end

      context "when API tokens are disabled", with_settings: { api_tokens_enabled: false } do
        it "rejects the token" do
          expect(last_response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
