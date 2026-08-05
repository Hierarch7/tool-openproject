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

RSpec.describe TwoFactorAuthentication::Devices::TotpQrCodeComponent, type: :component do
  let(:user) { build_stubbed(:user, login: "jsmith") }
  let(:device) { TwoFactorAuthentication::Device::Totp.new(user:, default: false) }

  before do
    render_inline(described_class.new(device:))
  end

  # The code used to be drawn client-side into a <canvas> by the lazily loaded Stimulus
  # controller, which left an empty box whenever canvas drawing or the chunk was unavailable.
  it "renders the code as inline SVG, without relying on the browser" do
    svg = page.find("svg")

    expect(svg["role"]).to eq("img")
    expect(svg["aria-label"]).to be_present
    expect(svg.native.css("path").first["d"]).to be_present
  end

  it "sizes the viewBox to the code plus its quiet zone" do
    extent = RQRCode::QRCode.new(device.provisioning_url, level: described_class::ERROR_CORRECTION_LEVEL)
                            .qrcode
                            .module_count + (2 * described_class::QUIET_ZONE)

    # Parsed as HTML, so the attribute name arrives lowercased; browsers case-correct it back.
    expect(page.find("svg")["viewbox"]).to eq("0 0 #{extent} #{extent}")
  end

  # Without an opaque backdrop the dark modules are invisible on a dark theme.
  it "draws an opaque light background behind the modules" do
    expect(page).to have_css("svg rect[fill='#ffffff']", visible: :all)
  end

  it "still offers the details needed to enrol the device by hand" do
    expect(page).to have_text(device.otp_secret)
    expect(page).to have_text(device.provisioning_url)
  end

  it "leaves no client-side rendering hooks behind" do
    expect(page).to have_no_css("[data-two-factor-authentication-target='qrCodeElement']", visible: :all)
    expect(page).to have_no_css("[data-value]", visible: :all)
  end
end
