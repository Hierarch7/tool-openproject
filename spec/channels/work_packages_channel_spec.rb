# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkPackagesChannel do
  shared_let(:project) { create(:project) }
  shared_let(:other_project) { create(:project) }
  shared_let(:member) do
    create(:user, member_with_permissions: { project => %i[view_work_packages] })
  end
  shared_let(:outsider) { create(:user) }

  before do
    stub_connection(current_user: user)
  end

  context "when the user may see work packages in the project" do
    let(:user) { member }

    it "streams the project" do
      subscribe(project_id: project.id)

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_for(project)
    end

    # Membership in one project must not open a stream into another one.
    it "rejects a project the user is not a member of" do
      subscribe(project_id: other_project.id)

      expect(subscription).to be_rejected
    end
  end

  context "when access is revoked after subscribing" do
    let(:user) { member }

    # The periodic re-check is what keeps a live stream from outliving the permission that
    # opened it, so it is exercised directly rather than waited on.
    def run_access_recheck
      callable, = described_class.periodic_timers.first
      subscription.instance_exec(&callable)
    end

    it "stops streaming once the membership is gone" do
      subscribe(project_id: project.id)
      expect(subscription).to have_stream_for(project)

      Members::DeleteService
        .new(user: create(:admin), model: Member.find_by(principal: member, project:))
        .call

      run_access_recheck

      expect(subscription.streams).to be_empty
    end

    it "keeps streaming while the membership stands" do
      subscribe(project_id: project.id)

      run_access_recheck

      expect(subscription).to have_stream_for(project)
    end
  end

  context "when the user has no access to the project" do
    let(:user) { outsider }

    it "rejects the subscription" do
      subscribe(project_id: project.id)

      expect(subscription).to be_rejected
    end
  end

  context "with an unknown project" do
    let(:user) { member }

    it "rejects the subscription" do
      subscribe(project_id: 0)

      expect(subscription).to be_rejected
    end
  end
end
