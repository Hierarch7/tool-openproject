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

RSpec.describe "default query" do
  let(:query) { Query.new_default }

  describe "highlighting mode" do
    context "with highlighting mode setting" do
      describe "not set" do
        it "is inline" do
          expect(query.highlighting_mode).to eq :inline
        end
      end

      describe "set to inline", with_settings: { work_package_list_default_highlighting_mode: "inline" } do
        it "is inline" do
          expect(query.highlighting_mode).to eq :inline
        end
      end

      describe "set to none", with_settings: { work_package_list_default_highlighting_mode: "none" } do
        it "is none" do
          expect(query.highlighting_mode).to eq :none
        end
      end

      describe "set to status", with_settings: { work_package_list_default_highlighting_mode: "status" } do
        it "is status" do
          expect(query.highlighting_mode).to eq :status
        end
      end

      describe "set to priority", with_settings: { work_package_list_default_highlighting_mode: "priority" } do
        it "is priority" do
          expect(query.highlighting_mode).to eq :priority
        end
      end

      describe "set to invalid value", with_settings: { work_package_list_default_highlighting_mode: "fubar" } do
        it "is inline" do
          expect(query.highlighting_mode).to eq :inline
        end
      end
    end
  end

  describe "view settings" do
    context "with the view settings being set",
            with_settings: { work_package_list_default_group_by: "status",
                             work_package_list_default_open_filter: false } do
      it "does not apply them as they are meant for the default view only" do
        expect(query.group_by).to be_blank
        expect(query.show_hierarchies).to be true
        expect(query.filters.map(&:name)).to eq [:status_id]
      end
    end
  end

  describe "the query of the default view" do
    let(:query) { Query.new_default_view }

    describe "group by" do
      context "without the setting being set" do
        it "is not grouped and keeps the hierarchy mode" do
          expect(query.group_by).to be_blank
          expect(query.show_hierarchies).to be true
          expect(query).to be_valid
        end
      end

      context "with the setting being set", with_settings: { work_package_list_default_group_by: "status" } do
        it "is grouped by that attribute and disables the hierarchy mode" do
          expect(query.group_by).to eq "status"
          expect(query.show_hierarchies).to be false
          expect(query).to be_valid
        end
      end

      context "with the setting being set to an invalid value",
              with_settings: { work_package_list_default_group_by: "fubar" } do
        it "is not grouped" do
          expect(query.group_by).to be_blank
          expect(query.show_hierarchies).to be true
          expect(query).to be_valid
        end
      end
    end

    describe "default filter" do
      context "without the setting being disabled" do
        it "filters for open work packages" do
          expect(query.filters.map(&:name)).to eq [:status_id]
          expect(query.filters.first.operator).to eq "o"
        end
      end

      context "with the setting being disabled", with_settings: { work_package_list_default_open_filter: false } do
        it "has no filters" do
          expect(query.filters).to be_empty
          expect(query).to be_valid
        end
      end
    end

    describe "sortation and subprojects" do
      it "keeps the defaults of a plain default query" do
        expect(query.sort_criteria).to contain_exactly(["id", "asc"])
        expect(query.include_subprojects).to eq Setting.display_subprojects_work_packages?
      end
    end
  end
end
