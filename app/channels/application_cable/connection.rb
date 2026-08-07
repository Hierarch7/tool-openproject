# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    # The session store keeps rows under a digest of the session id while the cookie carries
    # the public id in the clear, so the lookup has to go through Sessions::SqlBypass rather
    # than querying the table directly.
    def find_verified_user
      session_id = cookies[OpenProject::Configuration["session_cookie_name"]]
      reject_unauthorized_connection if session_id.blank?

      data = Sessions::SqlBypass.lookup_data(session_id)
      user_id = data && (data["user_id"] || data[:user_id])
      user = User.active.find_by(id: user_id) if user_id

      reject_unauthorized_connection if user.nil?

      user
    end
  end
end
