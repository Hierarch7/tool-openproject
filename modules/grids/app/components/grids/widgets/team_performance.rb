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
  module Widgets
    ##
    # Work packages done within the last days, and those in progress or blocked right now,
    # per assignee. Switching the period reloads the widget's turbo frame, see
    # Grids::Widgets::TeamPerformancesController.
    class TeamPerformance < Grids::WidgetComponent
      PERIODS = [7, 14, 21, 30].freeze

      param :project

      option :period, optional: true

      delegate :rows, :totals, :configured?, to: :performance

      def title
        t(".title")
      end

      def render?
        current_user.allowed_in_any_work_package?(:view_work_packages, in_project: project)
      end

      def selected_period
        PERIODS.include?(period.to_i) ? period.to_i : PERIODS.first
      end

      private

      def performance
        @performance ||= Grids::TeamPerformance.new(project:, user: current_user, since: selected_period.days.ago)
      end

      def period_path(days)
        project_widgets_team_performance_path(project, period: days)
      end

      def work_packages_path(ids)
        helpers.project_work_packages_with_ids_path(ids, project)
      end

      def can_configure_statuses?
        current_user.admin?
      end
    end
  end
end
