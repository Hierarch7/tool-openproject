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

RSpec.describe "Work package neighbour navigation", :js do
  shared_let(:user) { create(:admin) }
  shared_let(:project) { create(:project) }
  shared_let(:first_wp) { create(:work_package, project:, subject: "First") }
  shared_let(:second_wp) { create(:work_package, project:, subject: "Second") }
  shared_let(:third_wp) { create(:work_package, project:, subject: "Third") }

  # The toolbar only exists once angular has booted and loaded the work package over
  # the API, which takes well beyond capybara's default wait time.
  let(:toolbar_wait) { 20 }

  # Unlike most of the work package UI, the arrows are plain links: every click is a
  # full page load that renders the show page and boots angular from scratch, which
  # outlives the driver's 10 second default on a loaded machine. Read before the
  # before hook overwrites it - and note that the driver is only picked once the
  # example starts, so none of this can move into an around hook.
  let(:default_driver_timeout) { page.driver.browser.timeout }

  def visit_full_view(work_package, **query_params)
    visit project_work_package_path(project, work_package.id, "activity", **query_params)
    expect_angular_frontend_initialized
  end

  def expect_identifier(work_package)
    expect(page)
      .to have_test_selector("op-wp-neighbours--id", text: work_package.formatted_id, wait: toolbar_wait)
  end

  before do
    page.driver.browser.timeout = [default_driver_timeout, 60].max

    login_as(user)
  end

  after do
    page.driver.browser.timeout = default_driver_timeout
  end

  it "shows the identifier and walks the surrounding work packages" do
    visit_full_view(second_wp)
    expect_identifier(second_wp)

    find_test_selector("op-wp-neighbours--next").click

    # Waiting for the identifier first means the reload has finished by the time
    # the path is compared
    expect_identifier(third_wp)
    expect(page).to have_current_path(project_work_package_path(project, third_wp.id, "activity"))
    # Nothing follows the last work package, so only a disabled button is left
    expect(page).to have_no_test_selector("op-wp-neighbours--next")
    expect(page).to have_test_selector("op-wp-neighbours--previous")
  end

  it "walks them with the g j / g k shortcuts" do
    visit_full_view(second_wp)
    expect_identifier(second_wp)
    # Mousetrap only binds the shortcuts once the angular application has resolved its
    # configuration, and it ignores keys typed into a field, so reset the focus and
    # keep typing until the binding is there.
    retry_block(args: { tries: 5, base_interval: 1 }) do
      page.evaluate_script("document.activeElement && document.activeElement.blur(); document.body.focus()")
      # Mousetrap needs the two keys of the sequence as separate key events
      page.driver.send_keys("g")
      page.driver.send_keys("j")

      # The url flips as soon as the reload starts, long before the toolbar is back
      expect(page)
        .to have_current_path(project_work_package_path(project, third_wp.id, "activity"), wait: 5)
    end

    expect_identifier(third_wp)
  end

  context "with a saved view sorting the other way round" do
    shared_let(:query) do
      create(:query, project:, user:, show_hierarchies: false, sort_criteria: [%w[id desc]])
    end

    it "follows the order of that view and keeps it in the URL" do
      visit_full_view(second_wp, query_id: query.id)
      expect_identifier(second_wp)

      find_test_selector("op-wp-neighbours--next").click

      expect_identifier(first_wp)
      expect(page)
        .to have_current_path(project_work_package_path(project, first_wp.id, "activity", query_id: query.id))
    end

    it "keeps the view when moving between the tabs of a work package" do
      visit_full_view(second_wp, query_id: query.id)
      expect_identifier(second_wp)

      expect(page).to have_css(".op-work-package-tabs a.op-tab-row--link", minimum: 2, wait: toolbar_wait)
      tab_links = page.all(".op-work-package-tabs a.op-tab-row--link").pluck(:href)

      expect(tab_links).to all(include("query_id=#{query.id}"))
    end
  end
end
