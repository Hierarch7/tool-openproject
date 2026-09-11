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

RSpec.describe Grids::TeamPerformance do
  shared_let(:project) { create(:project_with_types) }
  shared_let(:other_project) { create(:project_with_types) }

  shared_let(:backlog) { create(:status, name: "Backlog") }
  shared_let(:in_progress) { create(:status, name: "In progress") }
  shared_let(:blocked) { create(:status, name: "Blocked") }
  shared_let(:done) { create(:closed_status, name: "Done") }
  shared_let(:closed) { create(:closed_status, name: "Closed") }
  shared_let(:cancelled) { create(:closed_status, name: "Cancelled") }

  shared_let(:alice) { create(:user, firstname: "Alice") }
  shared_let(:bob) { create(:user, firstname: "Bob") }
  shared_let(:viewer) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }

  let(:since) { 7.days.ago }

  subject(:performance) { described_class.new(project:, user: viewer, since:) }

  before do
    with_settings(team_performance_done_statuses: [done.id.to_s, closed.id.to_s],
                  team_performance_in_progress_statuses: [in_progress.id.to_s],
                  team_performance_blocked_statuses: [blocked.id.to_s])
  end

  # Each step is [time, status, assignee]; the work package ends up in the state of the last one.
  def create_with_history(*steps, project: self.project)
    journals = steps.to_h { |time, status, assignee| [time, { status_id: status.id, assigned_to_id: assignee&.id }] }
    _, status, assignee = steps.last

    create(:work_package, project:, status:, assigned_to: assignee, journals:)
  end

  def row_for(principal)
    performance.rows.find { |row| row.principal == principal }
  end

  describe "#rows" do
    context "for a work package done within the period" do
      let!(:work_package) do
        create_with_history([10.days.ago, backlog, alice], [3.days.ago, done, alice], [1.day.ago, done, bob])
      end

      it "credits whoever was assigned when it got done", :aggregate_failures do
        expect(row_for(alice)).to have_attributes(done: [work_package.id], in_progress: [], blocked: [])
        expect(row_for(bob)).to be_nil
      end
    end

    context "for a work package created in a done status within the period" do
      let!(:work_package) { create_with_history([3.days.ago, done, alice]) }

      it "counts it" do
        expect(row_for(alice).done).to eq [work_package.id]
      end
    end

    context "for a work package done before the period" do
      let!(:work_package) { create_with_history([20.days.ago, backlog, alice], [10.days.ago, done, alice]) }

      it "does not count it" do
        expect(performance.rows).to be_empty
      end

      context "when the period reaches back far enough" do
        let(:since) { 14.days.ago }

        it "counts it" do
          expect(row_for(alice).done).to eq [work_package.id]
        end
      end
    end

    context "for a work package done before the period and changed within it" do
      before do
        create_with_history([10.days.ago, done, alice], [2.days.ago, done, bob])
        create_with_history([10.days.ago, done, alice], [2.days.ago, closed, alice])
      end

      it "does not count them, moving between done statuses included" do
        expect(performance.rows).to be_empty
      end
    end

    context "for a work package reopened after being done" do
      before do
        create_with_history([5.days.ago, done, alice], [2.days.ago, backlog, alice])
      end

      it "does not count it" do
        expect(performance.rows).to be_empty
      end
    end

    context "for a work package done again after being reopened" do
      let!(:work_package) do
        create_with_history([20.days.ago, done, bob], [10.days.ago, backlog, bob], [2.days.ago, done, alice])
      end

      it "credits the latest time it got done", :aggregate_failures do
        expect(row_for(alice).done).to eq [work_package.id]
        expect(row_for(bob)).to be_nil
      end
    end

    context "for a work package in a closed status that does not count as done" do
      before do
        create_with_history([3.days.ago, cancelled, alice])
      end

      it "does not count it" do
        expect(performance.rows).to be_empty
      end
    end

    context "for work packages in progress and blocked" do
      let!(:started) { create(:work_package, project:, status: in_progress, assigned_to: alice) }
      let!(:stuck) { create(:work_package, project:, status: blocked, assigned_to: alice) }
      let!(:orphan) { create(:work_package, project:, status: blocked) }

      it "counts their current state per assignee", :aggregate_failures do
        expect(row_for(alice)).to have_attributes(done: [], in_progress: [started.id], blocked: [stuck.id])
        expect(row_for(nil)).to have_attributes(done: [], in_progress: [], blocked: [orphan.id])
      end
    end

    context "for work packages the user cannot see" do
      before do
        create_with_history([3.days.ago, done, alice], project: other_project)
        create(:work_package, project: other_project, status: in_progress, assigned_to: alice)
      end

      it "does not count them" do
        expect(performance.rows).to be_empty
      end
    end

    context "with several assignees" do
      before do
        create_with_history([3.days.ago, done, alice])
        create_with_history([3.days.ago, done, bob])
        create_with_history([2.days.ago, done, bob])
        create(:work_package, project:, status: in_progress)
      end

      it "orders them by work done, the unassigned row last" do
        expect(performance.rows.map(&:principal)).to eq [bob, alice, nil]
      end
    end
  end

  describe "#totals" do
    before do
      create_with_history([3.days.ago, done, alice])
      create_with_history([2.days.ago, done, bob])
      create(:work_package, project:, status: in_progress, assigned_to: alice)
    end

    it "sums up every group" do
      expect(performance.totals).to eq(done: 2, in_progress: 1, blocked: 0)
    end
  end

  describe "#configured?" do
    it "is true with statuses in any group" do
      expect(performance).to be_configured
    end

    context "without statuses in any group" do
      before do
        with_settings(team_performance_done_statuses: [],
                      team_performance_in_progress_statuses: [],
                      team_performance_blocked_statuses: [])
      end

      it "is false" do
        expect(performance).not_to be_configured
      end
    end
  end
end
