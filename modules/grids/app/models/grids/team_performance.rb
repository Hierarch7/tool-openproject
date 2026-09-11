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

module Grids
  ##
  # Per assignee counters behind the team performance widget of the project overview.
  #
  # Which statuses make a work package done, in progress or blocked is configured instance
  # wide in the team_performance_*_statuses settings.
  #
  # Done covers the work packages that are done now and got there within the period. They
  # are credited to whoever was assigned at that moment, as recorded in the journal, so
  # reassigning a finished work package does not move the credit. Moving between two done
  # statuses does not restart the clock, and a reopened work package drops out.
  #
  # In progress and blocked are the current state: the period does not apply to them.
  #
  # Only work packages of the project itself that the user can see are counted.
  class TeamPerformance
    GROUPS = %i[done in_progress blocked].freeze

    # Each counter holds the ids of the work packages it counts. The principal is nil for
    # the work packages nobody is assigned to.
    Row = Data.define(:principal, :done, :in_progress, :blocked)

    attr_reader :project, :user, :since

    def self.status_ids(group)
      Array(Setting[:"team_performance_#{group}_statuses"]).compact_blank.map(&:to_i)
    end

    def initialize(project:, user:, since:)
      @project = project
      @user = user
      @since = since
    end

    def configured?
      GROUPS.any? { |group| status_ids(group).any? }
    end

    # Ordered by work done, the unassigned row last.
    def rows
      @rows ||= build_rows
    end

    def totals
      @totals ||= GROUPS.index_with { |group| rows.sum { |row| row.public_send(group).size } }
    end

    private

    def status_ids(group)
      (@status_ids ||= {})[group] ||= self.class.status_ids(group)
    end

    def build_rows
      pairs = { done: done_pairs, in_progress: current_pairs(:in_progress), blocked: current_pairs(:blocked) }
      principals = assignees(pairs)

      pairs
        .flat_map { |group, group_pairs| group_pairs.map { |id, assignee_id| [principals[assignee_id], group, id] } }
        .group_by(&:first)
        .map { |principal, entries| build_row(principal, entries) }
        .sort_by { |row| sort_key(row) }
    end

    def assignees(pairs)
      Principal.where(id: pairs.values.flatten(1).filter_map(&:last)).index_by(&:id)
    end

    # entries are [principal, group, work package id]
    def build_row(principal, entries)
      ids = entries.group_by(&:second).transform_values { |grouped| grouped.map(&:third) }

      Row.new(principal:, **GROUPS.index_with { |group| ids.fetch(group, []) })
    end

    def sort_key(row)
      [row.principal ? 0 : 1, -row.done.size, -row.in_progress.size, -row.blocked.size, row.principal.to_s]
    end

    # [work package id, assignee id] of the work packages currently in one of the group's statuses.
    def current_pairs(group)
      return [] if status_ids(group).empty?

      visible_work_packages.where(status_id: status_ids(group)).pluck(:id, :assigned_to_id)
    end

    # [work package id, assignee id] of the work packages that are done now and entered
    # a done status within the period, with the assignee of that moment.
    def done_pairs
      done_ids = status_ids(:done)
      return [] if done_ids.empty?

      Journal
        .from(status_history(done_ids), :history)
        .where("history.status_id IN (:done_ids) " \
               "AND (history.previous_status_id IS NULL OR history.previous_status_id NOT IN (:done_ids))",
               done_ids:)
        .where(history: { created_at: since.. })
        .order(Arel.sql("history.journable_id, history.created_at DESC"))
        .pluck(Arel.sql("DISTINCT ON (history.journable_id) history.journable_id"), Arel.sql("history.assigned_to_id"))
    end

    # Every journal of the work packages that may have been finished within the period,
    # along with the status it replaced. The previous status has to be looked up before
    # narrowing down to the period, hence the window over the whole history.
    #
    # A status change always bumps updated_at, so work packages untouched since the start
    # of the period cannot have been finished within it.
    def status_history(done_ids)
      candidates = visible_work_packages.where(status_id: done_ids).where(updated_at: since..)

      Journal
        .joins("INNER JOIN work_package_journals ON work_package_journals.id = journals.data_id")
        .where(journable_type: WorkPackage.name,
               data_type: Journal::WorkPackageJournal.name,
               journable_id: candidates.select(:id))
        .select("journals.journable_id",
                "journals.created_at",
                "work_package_journals.status_id",
                "work_package_journals.assigned_to_id",
                "LAG(work_package_journals.status_id) OVER " \
                "(PARTITION BY journals.journable_id ORDER BY journals.version) AS previous_status_id")
    end

    def visible_work_packages
      WorkPackage.visible(user).where(project_id: project.id)
    end
  end
end
