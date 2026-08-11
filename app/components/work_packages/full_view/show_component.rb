# frozen_string_literal: true

module WorkPackages
  module FullView
    class ShowComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include OpTurbo::Streamable

      def self.wrapper_key = :"work-package-full-view"

      def initialize(id:, tab: "activity", query_id: nil, query_props: nil)
        super

        @id = id
        @tab = tab
        @query_id = query_id
        @query_props = query_props
        @work_package = WorkPackage.visible.find_by_display_id(id)
      end

      def wrapper_uniq_by
        @id
      end

      # Path of the work package preceding this one in the list the user came from,
      # or nil when there is none. See WorkPackages::NeighboursService for how that
      # list is determined.
      def previous_work_package_path
        neighbour_path(neighbours.previous)
      end

      def next_work_package_path
        neighbour_path(neighbours.next)
      end

      private

      def neighbours
        @neighbours ||= WorkPackages::NeighboursService
                          .new(work_package: @work_package,
                               user: User.current,
                               query_id: @query_id,
                               query_props: @query_props)
                          .call
      end

      # Keeps the tab and the list the user is navigating within, so the arrows stay
      # usable after the first click.
      def neighbour_path(work_package)
        return if work_package.nil?

        helpers.project_work_package_path(work_package.project,
                                          work_package.display_id,
                                          @tab,
                                          **list_context_params)
      end

      def list_context_params
        { query_id: @query_id.presence, query_props: @query_props.presence }.compact
      end
    end
  end
end
