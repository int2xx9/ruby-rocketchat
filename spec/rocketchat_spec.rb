require 'spec_helper'
require 'uri'
require 'json'
require 'webmock/rspec'

SERVER_URI=URI.parse("http://www.example.com/")
ROOM_ID="AAAAAAAAAAAAAAAAA"
ROOM_NAME="room"
AUTH_TOKEN="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
USER_ID="AAAAAAAAAAAAAAAAA"
USERNAME="user"
PASSWORD="password"
UNAUTHORIZED_BODY={
  status: :error,
  data: {
    message: "You must be logged in to do this."
  }
}.to_json

describe RocketChat do
  before do
    # Stub for /api/version REST API
    stub_request(:get, SERVER_URI + "/api/version").to_return(
      body: {
        status: :success,
        versions: {
          api: "0.1",
          rocketchat: "0.5"
        }
      }.to_json,
      status: 200
    )

    # Stubs for /api/login REST API
    stub_request(:post, SERVER_URI + "/api/login").to_return(
      body: {
        status: :error,
        message: "Unauthorized"
      }.to_json,
      status: 401
    )
    stub_request(:post, SERVER_URI + "/api/login")
      .with(body: {user: USERNAME, password: PASSWORD})
      .to_return(
        body: {
          status: :success,
          data: {authToken: AUTH_TOKEN, userId: USER_ID}
        }.to_json,
        status: 200
      )

    # Stubs for /api/logout REST API
    stub_request(:post, SERVER_URI + "/api/logout")
      .to_return(body: UNAUTHORIZED_BODY, status: 401)
    stub_request(:post, SERVER_URI + "/api/logout")
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return(
        body: {
          status: :success,
          data: { message: "You've been logged out!" }
        }.to_json,
        status: 200
      )

    # Stubs for /api/publicRooms
    stub_request(:get, SERVER_URI + "/api/publicRooms")
      .to_return(body: UNAUTHORIZED_BODY, status: 401)
    stub_request(:get, SERVER_URI + "/api/publicRooms")
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return(
        body: {
          status: :success,
          rooms: [
            {
              _id: ROOM_ID,
              name: "room",
              t: "c",
              usernames: [
                "user1",
                "user2"
              ],
              msgs: 100,
              u: {
                _id: USER_ID,
                username: "user1"
              },
              ts: "2016-01-01T00:00:00.000Z",
              archived: false,
              lm: "2016-01-01T00:00:00.000Z"
            }
          ]
        }.to_json,
        status: 200,
      )
    
    # Stubs for /api/:id/join
    stub_request(:get, SERVER_URI + "/api/rooms/#{ROOM_ID}/join")
      .to_return(body: UNAUTHORIZED_BODY, status: 401)
    stub_request(:get, Addressable::Template.new("#{SERVER_URI.scheme}://#{SERVER_URI.host}:#{SERVER_URI.port}/api/rooms/{id}/join"))
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return( body: "Server error.", status: 500)
    stub_request(:get, SERVER_URI + "/api/rooms/#{ROOM_ID}/join")
      .with(headers: {"X-Auth-Token":AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return(body: { status: :success }.to_json, status: 200)
    
    # Stubs for /api/:id/leave
    stub_request(:get, SERVER_URI + "/api/rooms/#{ROOM_ID}/leave")
      .to_return(body: UNAUTHORIZED_BODY, status: 401)
    stub_request(:get, Addressable::Template.new("#{SERVER_URI.scheme}://#{SERVER_URI.host}:#{SERVER_URI.port}/api/rooms/{id}/leave"))
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return(body: "Server error.", status: 500)
    stub_request(:get, SERVER_URI + "/api/rooms/#{ROOM_ID}/leave")
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return(body: { status: :success, }.to_json, status: 200)
    
    # Stubs for /api/:id/send
    stub_request(:post, SERVER_URI + "/api/rooms/#{ROOM_ID}/send")
      .to_return(body: UNAUTHORIZED_BODY, status: 401)
    stub_request(:post, Addressable::Template.new("#{SERVER_URI.scheme}://#{SERVER_URI.host}:#{SERVER_URI.port}/api/rooms/{id}/send"))
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID})
      .to_return(body: "Server error.", status: 500)
    stub_request(:post, SERVER_URI + "/api/rooms/#{ROOM_ID}/send")
      .with(headers: {"X-Auth-Token": AUTH_TOKEN, "X-User-Id": USER_ID, "Content-Type": "application/json"})
      .to_return(body: { status: :success, }.to_json, status: 200)

    @rcs = RocketChat::Server.new(SERVER_URI)
    @token = RocketChat::Token.new({authToken: AUTH_TOKEN, userId: USER_ID})
  end

  it 'gets server version' do
    version = @rcs.version
    expect(version.api).to eq("0.1")
    expect(version.rocketchat).to eq("0.5")
  end

  describe 'login to server' do
    it 'should be success' do
      rc = @rcs.login(USERNAME, PASSWORD)
      expect(rc.token.auth_token).to eq(AUTH_TOKEN)
      expect(rc.token.user_id).to eq(USER_ID)
    end

    it 'should be failure' do
      expect{@rcs.login(USERNAME, PASSWORD+PASSWORD)}.to raise_error(RocketChat::LoginError)
    end
  end

  describe 'logoff from server' do
    it 'should be success' do
      rc = RocketChat::Session.new(@rcs, @token)
      expect(rc.logoff).to eq(nil)
    end
    it 'should be failure' do
      rc = RocketChat::Session.new(@rcs, RocketChat::Token.new({authToken: nil, userId: nil}))
      expect{rc.logoff}.to raise_error(RocketChat::Error)
    end
  end

  it 'gets list of public rooms' do
    rc = RocketChat::Session.new(@rcs, @token)
    rooms = rc.public_rooms
    expect(rooms.length).to eq(1)
  end

  describe 'gets a specific room' do
    it 'is exist' do
      rc = RocketChat::Session.new(@rcs, @token)
      expect(rc[ROOM_NAME]).not_to be_nil
    end

    it 'is not exist' do
      rc = RocketChat::Session.new(@rcs, @token)
      expect(rc[ROOM_NAME+ROOM_NAME]).to be_nil
    end
  end

  describe 'joins a room' do
    it 'join' do
      rc = RocketChat::Session.new(@rcs, @token)
      room = RocketChat::Room.new(rc, {
        _id: ROOM_ID,
        ts: "2016-01-01T00:00:00.000Z",
        lm: "2016-01-01T00:00:00.000Z"
      })
      expect(room.join).to be_nil
    end

    it 'is not exist' do
      rc = RocketChat::Session.new(@rcs, @token)
      room = RocketChat::Room.new(rc, {
        _id: ROOM_ID+ROOM_ID,
        ts: "2016-01-01T00:00:00.000Z",
        lm: "2016-01-01T00:00:00.000Z"
      })
      expect{room.join}.to raise_error(RocketChat::NoSuchRoomError)
    end
  end

  describe 'leaves a room' do
    it 'leave' do
      rc = RocketChat::Session.new(@rcs, @token)
      room = RocketChat::Room.new(rc, {
        _id: ROOM_ID,
        ts: "2016-01-01T00:00:00.000Z",
        lm: "2016-01-01T00:00:00.000Z"
      })
      expect(room.leave).to be_nil
    end

    it 'is not exist' do
      rc = RocketChat::Session.new(@rcs, @token)
      room = RocketChat::Room.new(rc, {
        _id: ROOM_ID+ROOM_ID,
        ts: "2016-01-01T00:00:00.000Z",
        lm: "2016-01-01T00:00:00.000Z"
      })
      expect{room.leave}.to raise_error(RocketChat::NoSuchRoomError)
    end
  end

  it 'gets all unread messages in a room' do
  end

  describe 'sends a message' do
    it 'send' do
      rc = RocketChat::Session.new(@rcs, @token)
      room = RocketChat::Room.new(rc, {
        _id: ROOM_ID,
        ts: "2016-01-01T00:00:00.000Z",
        lm: "2016-01-01T00:00:00.000Z"
      })
      expect(room.post("test")).to be_nil
    end

    it 'is not exist' do
      rc = RocketChat::Session.new(@rcs, @token)
      room = RocketChat::Room.new(rc, {
        _id: ROOM_ID+ROOM_ID,
        ts: "2016-01-01T00:00:00.000Z",
        lm: "2016-01-01T00:00:00.000Z"
      })
      expect{room.post("test")}.to raise_error(RocketChat::NoSuchRoomError)
    end
  end
end
