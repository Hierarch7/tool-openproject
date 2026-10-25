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

RSpec.describe "custom_styles/_inline_css_logo" do
  before do
    allow(view).to receive(:apply_custom_styles?).and_return(false)
  end

  %i[en ru].each do |locale|
    context "with #{locale} locale" do
      it "uses the standard logos independently of language" do
        I18n.with_locale(locale) do
          render partial: "custom_styles/inline_css_logo"
        end

        expect(rendered).to include(view.asset_path("logo_openproject_white_big.png"))
        expect(rendered).to include(view.asset_path("logo_openproject.png"))
        expect(rendered).to include(view.asset_path("icon_logo_white.svg"))
        expect(rendered).not_to include("-bg-ua.png")
      end
    end
  end

  context "with a custom theme logo and Russian locale" do
    let(:custom_style) { build_stubbed(:custom_style) }

    before do
      allow(view).to receive(:apply_custom_styles?).and_return(true)
      allow(CustomStyle).to receive(:current).and_return(custom_style)
      allow(custom_style).to receive(:theme_logo).and_return("logo_openproject.png")
    end

    it "does not substitute the theme logo based on language" do
      I18n.with_locale(:ru) do
        render partial: "custom_styles/inline_css_logo"
      end

      expect(rendered).to include(view.asset_path("logo_openproject.png"))
      expect(rendered).not_to include("-bg-ua.png")
    end
  end
end
