#require "rocketchat/version"

require 'time'
require 'pp'
require 'uri'
require 'net/http'
require 'openssl'
require 'json'

module RocketChat
  module Util
    DEFAULT_REQUEST_OPTIONS = {
      method: :get,
      body: nil,
      headers: nil,
      ssl_verify_mode: OpenSSL::SSL::VERIFY_PEER,
      ssl_ca_file: nil,
    }.freeze

    def request(uri, options={})
      options = DEFAULT_REQUEST_OPTIONS.merge(options)
      headers = stringify_hashkeys(options[:headers]) if options[:headers]
      headers.delete_if{|key, value| key.nil? or value.nil?} if headers
      body = options[:body]

      uri = URI.parse(uri.to_s)
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = options[:ssl_verify_mode]
        http.ca_file = options[:ssl_ca_file] if options[:ssl_ca_file]
      end
      req = case options[:method]
            when :get
              Net::HTTP::Get.new(uri.to_s.sub(/^.+?\/\/.+?\//, "/"), headers)
            when :post
              Net::HTTP::Post.new(uri.to_s.sub(/^.+?\/\/.+?\//, "/"), headers)
            end
      raise InvalidMethodError.new unless req

      if not body.nil?
        if body.is_a?(Hash)
          req.body = body.map{|key, value| "#{URI.escape(key.to_s)}=#{URI.escape(value.to_s)}"}.join("&")
        else
          req.body = body.to_s
        end
      end

      http.start { http.request(req) }
    end
    module_function :request

    #
    # Stringify symbolized hashkeys
    # @param [Hash] hash A hash converted from
    # @return Stringified hash
    #
    def stringify_hashkeys(hash)
      newhash = {}
      hash.each do |key, value|
        newhash[key.to_s] = value
      end
      newhash
    end
    module_function :stringify_hashkeys
  end

  #
  # RocketChat Server
  #
  class Server
    DEFAULT_SERVER_OPTIONS = {
      ssl_verify_mode: OpenSSL::SSL::VERIFY_PEER,
      ssl_ca_file: nil,
    }.freeze

    # Server URI
    attr_reader :server
    # Server options
    attr_reader :options

    #
    # @param [URI, String] server Server URI
    # @param [Hash] options Server options
    #
    def initialize(server, options={})
      @server = URI.parse(server.to_s)
      @options = DEFAULT_SERVER_OPTIONS.merge(options)
    end

    def request_options
      {
        ssl_verify_mode: @options[:ssl_verify_mode],
        ssl_ca_file: @options[:ssl_ca_file],
      }
    end

    #
    # Version REST API
    # @return [Version] RocketChat and API Version
    # @raise [HTTPError]
    #
    def version
      response = Util.request(@server + "/api/version", request_options)
      raise HTTPError.new("Invalid http response code: #{response.code}") if not response.is_a?(Net::HTTPOK)
      Version.new(JSON.parse(response.body)['versions'])
    end

    #
    # Login REST API
    # @param [String] user Username
    # @param [String] password Password
    # @return [Session] RocketChat Session
    # @raise [LoginError]
    #
    def login(user, password)
      response = Util.request(
        @server + "/api/login",
        {
          method: :post,
          body: {
            user: user,
            password: password
          }
        }.merge(request_options)
      )
      response_json = JSON.parse(response.body)
      raise LoginError.new(response_json['message']) if response_json['status'] == 'error'
      Session.new(self, Token.new(response_json['data']))
    end
  end

  #
  # RocketChat Session
  #
  class Session
    # Server instance logged into
    attr_reader :server
    # Session token
    attr_reader :token

    #
    # @param [Server] server Server
    # @param [Token] token Session token
    #
    def initialize(server, token)
      @server = server
      @token = token.dup.freeze
    end

    #
    # Logoff REST API
    # @return [NilClass]
    # @raise [Error]
    #
    def logoff
      response = Util.request(
        @server.server + "/api/logout",
        {
          method: :post,
          headers: {
            "X-Auth-Token": @token.auth_token,
            "X-User-Id": @token.user_id,
          }
        }.merge(@server.request_options)
      )
      response_json = JSON.parse(response.body)
      raise Error.new(response_json['message']) if response_json['status'] == 'error'
      nil
    end

    #
    # An alias for logoff
    #
    def logout
      logoff
    end

    #
    # Fetch public rooms REST API
    # @return [[Room]] An array of Room
    #
    def public_rooms
      response = Util.request(
        @server.server + "/api/publicRooms",
        {
          headers: {
            "X-Auth-Token": @token.auth_token,
            "X-User-Id": @token.user_id,
          }
        }.merge(@server.request_options)
      )
      response_json = JSON.parse(response.body)
      raise Error.new(response_json['message']) if response_json['status'] == 'error'
      response_json['rooms'].map{|room| Room.new(self, room)}
    end

    #
    # Get a room instance
    # @param [String] room_name A name of room
    # @return [Room, NilClass] room or nil
    #
    def [](room_name)
      public_rooms.find{|x| x.name == room_name}
    end
  end

  #
  # RocketChat Room
  #
  class Room
    # Raw room data
    attr_reader :data

    #
    # @param [Session] session Session
    # @param [Hash] data Raw room data
    #
    def initialize(session, data)
      @session = session
      @data = Util.stringify_hashkeys(data)
      @data['ts'] = Time.parse(@data['ts'])
      @data['lm'] = Time.parse(@data['lm']) if @data['lm']
      @data.freeze
    end

    # Room ID
    def id;                @data['_id']; end
    # Room name
    def name;              @data['name']; end
    # Usernames joined into a room
    def usernames;         @data['usernames']; end
    # Created timestamp
    def created_timestamp; @data['ts']; end
    # Updated timestamp
    def updated_timestamp; @data['lm']; end
    # Topic
    def topic;             @data['topic']; end
    # Number of messages
    def msgs;              @data['msgs']; end
    # Default or not
    def default;           @data['default'] || false; end
    # Archived or not
    def archived;          @data['archived'] || false; end

    #
    # Join REST API
    # @return [NilClass]
    # @raise [Error]
    #
    def join
      response = Util.request(
        @session.server.server + "/api/rooms/#{id}/join",
        {
          body: {},
          headers: {
            "X-Auth-Token": @session.token.auth_token,
            "X-User-Id": @session.token.user_id,
          }
        }.merge(@session.server.request_options)
      )
      raise NoSuchRoomError.new if response.is_a?(Net::HTTPInternalServerError)
      response_json = JSON.parse(response.body)
      raise Error.new(response_json['message']) if response_json['status'] == 'error'
      nil
    end

    #
    # Leave REST API
    # @return [NilClass]
    # @raise [Error]
    #
    def leave
      response = Util.request(
        @session.server.server + "/api/rooms/#{id}/leave",
        {
          body: {},
          headers: {
            "X-Auth-Token": @session.token.auth_token,
            "X-User-Id": @session.token.user_id,
          }
        }.merge(@session.server.request_options)
      )
      raise NoSuchRoomError.new if response.is_a?(Net::HTTPInternalServerError)
      response_json = JSON.parse(response.body)
      raise Error.new(response_json['message']) if response_json['status'] == 'error'
      nil
    end

    #
    # Get all unread messages REST API
    # @return [[Message]] An array of messages
    # @raise
    #
    def unreads
    end

    #
    # Send a message REST API
    # @param [String] message A message
    # @return [NilClass]
    # @raise [Error]
    #
    def post(message)
      response = Util.request(
        @session.server.server + "/api/rooms/#{id}/send",
        {
          method: :post,
          body: {msg: message}.to_json,
          headers: {
            "X-Auth-Token": @session.token.auth_token,
            "X-User-Id": @session.token.user_id,
            "Content-Type": "application/json",
          }
        }.merge(@session.server.request_options)
      )
      raise NoSuchRoomError.new if response.is_a?(Net::HTTPServerError)
      response_json = JSON.parse(response.body)
      raise Error.new(response_json['message']) if response_json['status'] == 'error'
      nil
    end

    def inspect
      sprintf(%Q[#<%s:0x%p @id="%s", @name="%s", @usernames=[%s], @created_timestamp="%s", @updated_timestamp="%s", @topic=%s, @msgs=%d, @default=%s, @archived=%s>],
              self.class.name,
              self.object_id,
              id,
              name,
              usernames.map{|x| %Q["#{x}"]}.join(", "),
              created_timestamp.to_s,
              updated_timestamp.to_s,
              topic.nil? ? "nil" : %Q["#{topic}"],
              msgs,
              default == true,
              archived == true)
    end
  end

  #
  # RocketChat Version
  #
  class Version
    # Raw version data
    attr_reader :data

    #
    # @param [Hash] data Raw version data
    #
    def initialize(data)
      @data = data.dup.freeze
    end

    # API version
    def api; @data['api']; end
    # RocketChat version
    def rocketchat; @data['rocketchat']; end

    def inspect
      sprintf(%Q[#<%s:0x%p @api="%s", @rocketchat="%s">],
              self.class.name,
              self.object_id,
              api,
              rocketchat)
    end
  end

  #
  # RocketChat Token
  #
  class Token
    # Raw token data
    attr_reader :data

    #
    # @param [Hash] data Raw token data
    #
    def initialize(data)
      @data = Util.stringify_hashkeys(data).freeze
    end

    # Authentication token
    def auth_token; @data['authToken']; end
    # User ID
    def user_id;    @data['userId']; end

    def inspect
      sprintf(%Q[#<%s:0x%p @auth_token="%s", @user_id="%s">],
              self.class.name,
              self.object_id,
              auth_token,
              user_id)
    end
  end

  #
  # RocketChat Message
  #
  class Message
    # Raw message data
    attr_reader :data

    #
    # @param [Hash] data Raw message data
    #
    def initialize(data)
      @data = Util.stringify_hashkeys(data).freeze
    end

    # Message ID
    def id;        @data['id']; end
    # ?
    def rid;       @data['rid']; end
    # Message body
    def message;   @data['message']; end
    # Message timestamp
    def timestamp; @data['timestamp']; end
    # An user who sent a message
    def user;      @data['user']; end
  end

  class Error < StandardError; end
  class LoginError < Error; end
  class NoSuchRoomError < Error; end
  class HTTPError < Error; end
  class InvalidMethodError < HTTPError; end
  class StatusError < Error; end
end

