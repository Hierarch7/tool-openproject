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

require "rails_helper"

RSpec.describe Grids::Widgets::TeamPerformance, type: :component do
  include Rails.application.routes.url_helpers

  shared_let(:project) { create(:project) }
  shared_let(:alice) { create(:user) }

  let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  let(:period) { nil }
  let(:configured) { true }
  let(:rows) { [] }
  let(:totals) { { done: 0, in_progress: 0, blocked: 0 } }
  let(:performance) { instance_double(Grids::TeamPerformance, configured?: configured, rows:, totals:) }

  current_user { user }

  subject(:rendered_component) do
    render_inline(described_class.new(project, current_user: user, period:))
  end

  before do
    allow(Grids::TeamPerformance).to receive(:new).and_return(performance)
  end

  describe "period switch" do
    it "reloads the widget's own frame for every period", :aggregate_failures do
      described_class::PERIODS.each do |days|
        expect(rendered_component)
          .to have_css("a[data-turbo-frame='grids-widgets-team-performance']" \
                       "[href='#{project_widgets_team_performance_path(project, period: days)}']",
                       text: "#{days} days")
      end
    end

    it "shows the last 7 days by default", :aggregate_failures do
      expect(rendered_component).to have_css("a[aria-current='true']", text: "7 days")
      expect(Grids::TeamPerformance)
        .to have_received(:new)
        .with(project:, user:, since: be_within(1.minute).of(7.days.ago))
    end

    context "with a known period" do
      let(:period) { "21" }

      it "shows that period", :aggregate_failures do
        expect(rendered_component).to have_css("a[aria-current='true']", text: "21 days")
        expect(Grids::TeamPerformance)
          .to have_received(:new)
          .with(project:, user:, since: be_within(1.minute).of(21.days.ago))
      end
    end

    context "with an unknown period" do
      let(:period) { "365" }

      it "falls back to the last 7 days" do
        expect(rendered_component).to have_css("a[aria-current='true']", text: "7 days")
      end
    end
  end

  context "with rows" do
    let(:rows) do
      [
        Grids::TeamPerformance::Row.new(principal: alice, done: [11, 12], in_progress: [13], blocked: []),
        Grids::TeamPerformance::Row.new(principal: nil, done: [], in_progress: [], blocked: [14])
      ]
    end
    let(:totals) { { done: 2, in_progress: 1, blocked: 1 } }
    let(:helpers) { ApplicationController.helpers }

    it "links every counter to its work packages", :aggregate_failures do
      expect(rendered_component)
        .to have_link("2", href: helpers.project_work_packages_with_ids_path([11, 12], project))
      expect(rendered_component)
        .to have_link("1", href: helpers.project_work_packages_with_ids_path([13], project))
      expect(rendered_component)
        .to have_link("1", href: helpers.project_work_packages_with_ids_path([14], project))
    end

    it "lists the assignees, the unassigned row last", :aggregate_failures do
      expect(rendered_component).to have_css("tbody tr:first-child th opce-principal")
      expect(rendered_component).to have_css("tbody tr:last-child th", text: "Unassigned")
    end

    it "does not link empty counters", :aggregate_failures do
      expect(rendered_component.css("tbody tr:first-child td").map { |cell| cell.text.strip }).to eq %w[2 1 0]
      expect(rendered_component).to have_no_css("tbody tr:first-child td:last-child a")
    end

    it "sums up every column" do
      expect(rendered_component.css("tfoot td").map { |cell| cell.text.strip }).to eq %w[2 1 1]
    end
  end

  context "without rows" do
    it "renders an empty state" do
      expect(rendered_component).to have_test_selector("team-performance-widget-empty")
    end
  end

  context "without configured statuses" do
    let(:configured) { false }

    it "renders a hint without a way to configure", :aggregate_failures do
      expect(rendered_component).to have_test_selector("team-performance-widget-not-configured")
      expect(rendered_component).to have_no_link("Configure statuses")
    end

    context "for an admin" do
      let(:user) { create(:admin) }

      it "links to the settings" do
        expect(rendered_component).to have_link("Configure statuses", href: admin_settings_work_packages_general_path)
      end
    end
  end

  context "when the user cannot view work packages" do
    let(:user) { create(:user) }

    it "does not render" do
      expect(rendered_component.to_html).to be_blank
    end
  end
end
