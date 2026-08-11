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

module API
  module V3
    ##
    # Translates the +query_props+ JSON blob the Angular frontend keeps in browser URLs
    # into the v3 query parameters ParseQueryParamsService understands, so the backend
    # can rebuild the very list a user is looking at.
    #
    # It mirrors UrlParamsHelper#buildV3GetQueryFromJsonParams
    # (frontend/src/app/features/work-packages/components/wp-query/url-params-helper.ts)
    # but only for the properties deciding *which* work packages a query returns and in
    # *which order*. Presentation-only properties - columns, sums, timeline, highlighting,
    # display representation - are deliberately dropped: nothing server side consumes them
    # and skipping them keeps this translation small.
    #
    # Pagination (+pa+/+pp+) is dropped as well. Callers rebuilding a list want the whole
    # result set, not the page the user happened to be on.
    class ParseQueryPropsService
      # Operator ids are written into the JSON verbatim by the frontend (see
      # UrlParamsHelper#encodeFilters) and Rails has already percent-decoded the
      # +query_props+ parameter by the time we see it, so no further unescaping happens
      # here. Do not add any: operators such as "t+" would lose their "+".
      def call(query_props)
        props = parse(query_props)

        ServiceResult.success(result: to_v3_params(props))
      rescue JSON::ParserError => e
        result = ServiceResult.failure
        result.errors.add(:base, e.message)
        result
      end

      private

      def parse(query_props)
        return {} if query_props.blank?

        parsed = query_props.is_a?(String) ? JSON.parse(query_props) : query_props.to_h.deep_stringify_keys

        unless parsed.is_a?(Hash)
          raise JSON::ParserError, "query_props must be a JSON object, got #{parsed.class}"
        end

        parsed
      end

      def to_v3_params(props)
        { filters: filters_param(props["f"]),
          sortBy: sort_by_param(props["t"]),
          groupBy: group_by_param(props),
          showHierarchies: boolean_param(props["hi"]),
          includeSubprojects: boolean_param(props["is"]),
          timestamps: props["ts"].presence }
          .compact
      end

      # [{ "n" => "status", "o" => "o", "v" => [] }] becomes
      # [{ "status" => { "operator" => "o", "values" => [] } }]
      def filters_param(raw)
        return if raw.nil?

        unless raw.is_a?(Array)
          raise JSON::ParserError, "query_props filters must be an array, got #{raw.class}"
        end

        JSON.dump(raw.map { |filter| filter_param(filter) })
      end

      def filter_param(filter)
        unless filter.is_a?(Hash)
          raise JSON::ParserError, "query_props filter must be an object, got #{filter.class}"
        end

        attributes = { "operator" => filter["o"].to_s }
        attributes["values"] = Array.wrap(filter["v"]) if filter.key?("v")

        { filter["n"].to_s => attributes }
      end

      # "id:asc,status:desc" becomes [["id", "asc"], ["status", "desc"]]
      def sort_by_param(raw)
        return if raw.blank?

        JSON.dump(raw.to_s.split(",").map { |sort| sort.split(":") })
      end

      # An empty grouping has to survive as "", as that is what tells the query to
      # drop whatever grouping it was saved with.
      def group_by_param(props)
        props["g"].to_s if props.key?("g")
      end

      # ParseQueryParamsService#boolearize only understands the string form the
      # frontend sends over the wire, while query_props carries real JSON booleans.
      def boolean_param(value)
        case value
        when true, "true" then "true"
        when false, "false" then "false"
        end
      end
    end
  end
end
