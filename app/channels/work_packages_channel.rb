# frozen_string_literal: true

# Announces that a work package in the project changed, so open views can refresh it without
# a page reload.
#
# The broadcast carries an id and nothing else. Everyone streaming a project receives every
# message unfiltered, so putting attributes in the payload would hand them to subscribers
# regardless of what they are allowed to see — field permissions, and the work package
# visibility that a view might further restrict, are only applied by the API. Clients
# therefore treat a message as "this one is stale" and refetch it through the usual endpoint.
class WorkPackagesChannel < ApplicationCable::Channel
  ACCESS_RECHECK_INTERVAL = 5.minutes

  # A subscription outlives the check that opened it: roles get taken away, projects get
  # archived, accounts get locked. Without this the stream would keep running for whoever
  # happened to be allowed at subscribe time. Only ids leak in that window — the payload
  # carries nothing else, and refetching still goes through the API — but the stream should
  # not outlive the permission either.
  periodically every: ACCESS_RECHECK_INTERVAL do
    stop_all_streams unless permitted_project
  end

  def subscribed
    project = permitted_project

    return reject if project.nil?

    stream_for project
  end

  private

  def permitted_project
    project = Project.find_by(id: params[:project_id])
    return nil if project.nil?

    # Reloaded so a role or status change since the last check is actually seen.
    current_user.reload
    return nil unless current_user.allowed_in_project?(:view_work_packages, project)

    project
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
