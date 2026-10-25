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

RSpec.describe APITokens::CreateContract, with_settings: { api_tokens_enabled: true } do
  let(:current_user) { create(:admin, login: "admin") }
  let(:token_name) { "my token name" }
  let(:token) { build_stubbed(:api_token, token_name:, user: current_user) }

  subject(:contract) { described_class.new(token, current_user) }

  def expect_valid(valid, symbols = {})
    expect(contract.validate).to eq(valid)

    symbols.each do |key, arr|
      expect(contract.errors.symbols_for(key)).to match_array arr
    end
  end

  describe "API token permissions" do
    context "with a regular user" do
      let(:current_user) { create(:user) }

      it "rejects token creation" do
        expect_valid(false, base: %i(error_unauthorized))
      end
    end

    context "with a different administrator" do
      let(:current_user) { create(:admin, login: "another-admin") }

      it "rejects token creation" do
        expect_valid(false, base: %i(error_unauthorized))
      end
    end

    context "when API tokens are disabled", with_settings: { api_tokens_enabled: false } do
      it "rejects token creation for admin too" do
        expect_valid(false, base: %i(error_unauthorized))
      end
    end

    context "with an iCalendar meeting token" do
      let(:current_user) { create(:user) }
      let(:token) { build_stubbed(:ical_meeting_token, token_name:, user: current_user) }

      it "does not restrict other token types" do
        expect_valid(true)
      end
    end

    context "when the token belongs to another user" do
      let(:token) { build_stubbed(:api_token, token_name:, user: create(:user)) }

      it "rejects creating a token for another account" do
        expect_valid(false, base: %i(error_unauthorized))
      end
    end
  end

  describe "validation" do
    context "when token_name is set" do
      it "is valid" do
        expect_valid(true)
      end
    end

    context "if the token_name is nil" do
      let(:token_name) { nil }

      it "is invalid" do
        expect_valid(false, token_name: %i(blank))
      end
    end

    context "if the token_name is taken for current user" do
      before do
        create(:api_token, token_name:, user: current_user)
      end

      it "is invalid" do
        expect_valid(false, token_name: %i(in_use))
      end
    end
  end
end
