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

RSpec.describe WorkPackages::NeighboursService do
  shared_let(:project) { create(:project) }
  shared_let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:first_wp) { create(:work_package, project:, subject: "First") }
  shared_let(:second_wp) { create(:work_package, project:, subject: "Second") }
  shared_let(:third_wp) { create(:work_package, project:, subject: "Third") }

  let(:work_package) { second_wp }
  let(:query_id) { nil }
  let(:query_props) { nil }

  subject(:neighbours) do
    described_class
      .new(work_package:, user:, query_id:, query_props:)
      .call
  end

  before do
    login_as(user)
  end

  describe "without a view in the URL" do
    it "walks the project in identifier order" do
      expect(neighbours.previous).to eq(first_wp)
      expect(neighbours.next).to eq(third_wp)
    end

    context "on the first work package" do
      let(:work_package) { first_wp }

      it "has no previous one" do
        expect(neighbours.previous).to be_nil
        expect(neighbours.next).to eq(second_wp)
      end
    end

    context "on the last work package" do
      let(:work_package) { third_wp }

      it "has no next one" do
        expect(neighbours.previous).to eq(second_wp)
        expect(neighbours.next).to be_nil
      end
    end

    context "with a work package in another project" do
      let(:work_package) { third_wp }
      # Created last, so its id follows the ones of our project
      let!(:foreign_wp) { create(:work_package, project: create(:project)) }

      it "is not a neighbour" do
        expect(neighbours.previous).to eq(second_wp)
        expect(neighbours.next).to be_nil
      end
    end
  end

  describe "with a saved view" do
    let(:query) do
      create(:query,
             project:,
             user:,
             show_hierarchies: false,
             sort_criteria: [%w[id desc]])
    end
    let(:query_id) { query.id }

    it "walks the view in its own order" do
      expect(neighbours.previous).to eq(third_wp)
      expect(neighbours.next).to eq(first_wp)
    end

    context "when the view is not visible to the user" do
      let(:query) { create(:private_query, project:, user: create(:user)) }

      it "falls back to the project order" do
        expect(neighbours.previous).to eq(first_wp)
        expect(neighbours.next).to eq(third_wp)
      end
    end

    context "when the work package is filtered out of the view" do
      let(:query) do
        create(:query, project:, user:, show_hierarchies: false, sort_criteria: [%w[id asc]]).tap do |q|
          q.filters = []
          q.add_filter("id", "=", [first_wp.id.to_s, third_wp.id.to_s])
          q.save!
        end
      end

      it "falls back to the project order" do
        expect(neighbours.previous).to eq(first_wp)
        expect(neighbours.next).to eq(third_wp)
      end
    end
  end

  describe "with an ad-hoc view" do
    let(:query_props) { { t: "id:desc", hi: false }.to_json }

    it "applies the sorting from the URL" do
      expect(neighbours.previous).to eq(third_wp)
      expect(neighbours.next).to eq(first_wp)
    end

    context "with a filter narrowing the list down" do
      let(:query_props) do
        { t: "id:asc",
          hi: false,
          f: [{ n: "id", o: "=", v: [first_wp.id.to_s, second_wp.id.to_s] }] }.to_json
      end

      it "stops at the end of the filtered list" do
        expect(neighbours.previous).to eq(first_wp)
        expect(neighbours.next).to be_nil
      end
    end

    context "on top of a saved view" do
      let(:query) { create(:query, project:, user:, show_hierarchies: false, sort_criteria: [%w[id asc]]) }
      let(:query_id) { query.id }
      let(:query_props) { { t: "id:desc", hi: false }.to_json }

      it "lets the URL win over the stored sorting" do
        expect(neighbours.previous).to eq(third_wp)
        expect(neighbours.next).to eq(first_wp)
      end
    end

    context "with unparseable props" do
      let(:query_props) { "{not json" }

      it "falls back to the project order" do
        expect(neighbours.previous).to eq(first_wp)
        expect(neighbours.next).to eq(third_wp)
      end
    end
  end

  describe "without a work package" do
    let(:work_package) { nil }

    it "returns no neighbours" do
      expect(neighbours.previous).to be_nil
      expect(neighbours.next).to be_nil
    end
  end
end
