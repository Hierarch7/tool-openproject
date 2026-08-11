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

RSpec.describe API::V3::ParseQueryPropsService, type: :model do
  let(:instance) { described_class.new }

  describe "#call" do
    subject { instance.call(query_props) }

    context "with a blank value" do
      let(:query_props) { nil }

      it "succeeds with no parameters" do
        expect(subject).to be_success
        expect(subject.result).to eq({})
      end
    end

    context "with filters" do
      let(:query_props) do
        { f: [{ n: "status", o: "o", v: [] },
              { n: "assignee", o: "=", v: %w[1 2] }] }.to_json
      end

      it "expands them into the v3 filter format" do
        expect(subject.result[:filters])
          .to eql(JSON.dump([{ "status" => { "operator" => "o", "values" => [] } },
                             { "assignee" => { "operator" => "=", "values" => %w[1 2] } }]))
      end
    end

    context "with a filter value that is not wrapped in an array" do
      let(:query_props) { { f: [{ n: "subject", o: "~", v: "needle" }] }.to_json }

      it "wraps it, as the frontend does for backwards compatibility" do
        expect(subject.result[:filters])
          .to eql(JSON.dump([{ "subject" => { "operator" => "~", "values" => ["needle"] } }]))
      end
    end

    context "with an operator carrying a plus sign" do
      let(:query_props) { { f: [{ n: "dueDate", o: "<t+", v: ["5"] }] }.to_json }

      it "keeps it verbatim" do
        expect(subject.result[:filters])
          .to eql(JSON.dump([{ "dueDate" => { "operator" => "<t+", "values" => ["5"] } }]))
      end
    end

    context "with sorting" do
      let(:query_props) { { t: "id:asc,status:desc" }.to_json }

      it "splits it into attribute/direction pairs" do
        expect(subject.result[:sortBy]).to eql(JSON.dump([%w[id asc], %w[status desc]]))
      end
    end

    context "with grouping" do
      let(:query_props) { { g: "status" }.to_json }

      it "passes it on" do
        expect(subject.result[:groupBy]).to eql("status")
      end
    end

    context "with an empty grouping" do
      let(:query_props) { { g: "" }.to_json }

      it "passes the empty string on, so the query ends up ungrouped" do
        expect(subject.result[:groupBy]).to eql("")
      end
    end

    context "with booleans" do
      let(:query_props) { { hi: true, is: false }.to_json }

      it "stringifies them the way ParseQueryParamsService expects" do
        expect(subject.result[:showHierarchies]).to eql("true")
        expect(subject.result[:includeSubprojects]).to eql("false")
      end
    end

    context "with timestamps" do
      let(:query_props) { { ts: "P-1Y,PT0S" }.to_json }

      it "passes them on" do
        expect(subject.result[:timestamps]).to eql("P-1Y,PT0S")
      end
    end

    context "with presentation only properties" do
      let(:query_props) { { c: %w[id subject], s: true, tv: true, hl: "inline", pp: 100, pa: 3 }.to_json }

      it "drops them" do
        expect(subject.result).to eq({})
      end
    end

    context "with a hash instead of a JSON string" do
      let(:query_props) { { "hi" => false } }

      it "accepts it" do
        expect(subject.result[:showHierarchies]).to eql("false")
      end
    end

    context "with malformed JSON" do
      let(:query_props) { "{not json" }

      it "fails" do
        expect(subject).to be_failure
        expect(subject.errors.full_messages.join).to be_present
      end
    end

    context "with JSON that is not an object" do
      let(:query_props) { "[1, 2]" }

      it "fails" do
        expect(subject).to be_failure
      end
    end

    context "with filters that are not an array" do
      let(:query_props) { { f: "status" }.to_json }

      it "fails" do
        expect(subject).to be_failure
      end
    end
  end
end
