# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkPackages::FullView::ShowComponent, type: :component do
  include OpenProject::StaticRouting::UrlHelpers

  shared_let(:project) { create(:project) }
  shared_let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:first_wp) { create(:work_package, project:, subject: "First") }
  shared_let(:second_wp) { create(:work_package, project:, subject: "Second") }
  shared_let(:third_wp) { create(:work_package, project:, subject: "Third") }

  let(:query_id) { nil }

  subject do
    with_controller_class(WorkPackagesController) do
      with_request_url("/projects/#{project.identifier}/work_packages/#{second_wp.display_id}/activity") do
        render_inline(described_class.new(id: second_wp.display_id, tab: "activity", query_id:))
      end
    end
  end

  before do
    login_as(user)
  end

  def angular_element
    page.find("opce-wp-full-view", visible: :all)
  end

  it "hands the neighbouring work packages to the angular component" do
    subject

    expect(angular_element["data-previous-work-package-path"])
      .to eq(project_work_package_path(project, first_wp.display_id, "activity").to_json)
    expect(angular_element["data-next-work-package-path"])
      .to eq(project_work_package_path(project, third_wp.display_id, "activity").to_json)
  end

  context "with a saved view" do
    let(:query) do
      create(:query, project:, user:, show_hierarchies: false, sort_criteria: [%w[id desc]])
    end
    let(:query_id) { query.id }

    it "walks that view and keeps it in the neighbour paths" do
      subject

      expect(angular_element["data-previous-work-package-path"])
        .to eq(project_work_package_path(project, third_wp.display_id, "activity", query_id: query.id).to_json)
      expect(angular_element["data-next-work-package-path"])
        .to eq(project_work_package_path(project, first_wp.display_id, "activity", query_id: query.id).to_json)
    end
  end

  context "on the last work package of the project" do
    subject do
      with_controller_class(WorkPackagesController) do
        with_request_url("/projects/#{project.identifier}/work_packages/#{third_wp.display_id}/activity") do
          render_inline(described_class.new(id: third_wp.display_id, tab: "activity"))
        end
      end
    end

    it "hands over no next path" do
      subject

      expect(angular_element["data-next-work-package-path"]).to eq("null")
    end
  end
end
