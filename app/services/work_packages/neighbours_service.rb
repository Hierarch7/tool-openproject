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

module WorkPackages
  ##
  # Finds the work packages sitting immediately before and after a given one, so the
  # full view can offer "previous"/"next" navigation.
  #
  # The preferred order is the list the user came from: the saved view (+?query_id=+)
  # or the ad-hoc view (+?query_props=+) carried along in the URL. Running that query
  # reproduces the exact filters, grouping and sorting of the work package table, so
  # the arrows walk the table row by row.
  #
  # When the URL carries no view - a work package opened from a notification, a search
  # result or a bare link - or when the work package is not part of the view's results,
  # we fall back to the neighbouring work packages of the same project, ordered the way
  # their identifiers read: by sequence number in semantic mode ("PROJ-41" -> "PROJ-42"),
  # by primary key in classic mode ("#41" -> "#42").
  #
  # Known limitation: in hierarchy mode the arrows walk the flat order the query
  # returns, not the nested order the table displays. Nesting is a purely client side
  # affair - the API hands out a flat, sorted page and each work package's ancestors,
  # and HierarchyRenderPass (frontend/src/app/features/work-packages/components/
  # wp-fast-table/builders/modes/hierarchy) assembles the tree from those, inserting
  # ancestors that do not match the filters as context rows. Reproducing that here
  # would mean porting the render pass; until then the two orders coincide whenever
  # parents sort before their children (the common id/created_at sortings) and drift
  # apart otherwise.
  class NeighboursService
    Neighbours = Data.define(:previous, :next) do
      def self.none = new(previous: nil, next: nil)
    end

    attr_reader :work_package, :user, :query_id, :query_props

    def initialize(work_package:, user:, query_id: nil, query_props: nil)
      @work_package = work_package
      @user = user
      @query_id = query_id
      @query_props = query_props
    end

    def call
      return Neighbours.none if work_package.nil?

      from_view || from_project
    end

    private

    # Returns nil - rather than an empty Neighbours - whenever the view cannot be used,
    # so that #call falls through to the project order instead of showing dead arrows.
    def from_view
      query = view_query
      return if query.nil?

      ids = ordered_ids(query)
      index = ids.index(work_package.id)
      return if index.nil?

      Neighbours.new(
        previous: index.zero? ? nil : find_visible(ids[index - 1]),
        next: find_visible(ids[index + 1])
      )
    end

    def ordered_ids(query)
      # Query::Results eager loads the associations its sorting, grouping and filters
      # need, and a has_many among them makes the join emit a row per associated
      # record. #uniq keeps the first occurrence of every id, and with it the order.
      query.results.work_packages.pluck(:id).uniq
    end

    def view_query
      return if query_id.blank? && query_props.blank?

      query = base_query
      return if query.nil?
      return query if query_props.blank?

      apply_query_props(query)
    end

    def base_query
      if query_id.present?
        # A saved view may well be opened from a project other than the one it belongs to,
        # which is why this is not scoped to the work package's project.
        Query.visible(user).find_by(id: query_id)
      else
        Query.new_default(project: work_package.project)
      end
    end

    def apply_query_props(query)
      parsed = ::API::V3::ParseQueryPropsService.new.call(query_props)
      return unless parsed.success?

      updated = ::API::V3::UpdateQueryFromV3ParamsService
                  .new(query, user)
                  .call(parsed.result, valid_subset: true)

      query if updated.success?
    end

    def from_project
      column = order_column
      value = work_package.public_send(column)
      return Neighbours.none if value.nil?

      attribute = WorkPackage.arel_table[column]

      Neighbours.new(
        previous: project_neighbour(attribute.lt(value), { column => :desc }),
        next: project_neighbour(attribute.gt(value), { column => :asc })
      )
    end

    def project_neighbour(condition, order)
      WorkPackage
        .visible(user)
        .where(project_id: work_package.project_id)
        .where(condition)
        .reorder(order)
        .first
    end

    def order_column
      if Setting::WorkPackageIdentifier.semantic? && work_package.sequence_number.present?
        :sequence_number
      else
        :id
      end
    end

    def find_visible(id)
      return if id.nil?

      WorkPackage.visible(user).find_by(id:)
    end
  end
end
