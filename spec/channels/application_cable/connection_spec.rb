# frozen_string_literal: true

require "spec_helper"

RSpec.describe ApplicationCable::Connection do
  shared_let(:user) { create(:user) }

  let(:cookie_name) { OpenProject::Configuration["session_cookie_name"] }

  # The store keeps rows under a digest of the session id while the cookie carries the public
  # one, so the fixture has to be written the same way the real session store writes it.
  def create_session(data)
    session_id = Rack::Session::SessionId.new(SecureRandom.hex(32))
    ActiveRecord::SessionStore::Session.create!(session_id: session_id.private_id, data:)
    session_id.public_id
  end

  it "identifies the user behind the session cookie" do
    cookies[cookie_name] = create_session("user_id" => user.id)

    connect "/cable"

    expect(connection.current_user).to eq(user)
  end

  it "rejects a connection without a session cookie" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a session id that matches no session" do
    cookies[cookie_name] = SecureRandom.hex(32)

    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects a session that carries no user" do
    cookies[cookie_name] = create_session("foo" => "bar")

    expect { connect "/cable" }.to have_rejected_connection
  end

  # A locked or invited account keeps its session row, but must not get a live connection.
  it "rejects a user who is no longer active" do
    cookies[cookie_name] = create_session("user_id" => user.id)
    user.locked!

    expect { connect "/cable" }.to have_rejected_connection
  end
end
