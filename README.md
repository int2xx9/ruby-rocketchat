# Rocket.Chat REST API for Ruby

This is a gem for [Rocket.Chat](https://rocket.chat/).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rocketchat'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rocketchat


## List of supported API

Currently this gem supports below APIs only. (And also supports API version 0.1 only.)

* /api/version
* /api/login
* /api/logout
* /api/publicRooms
* /api/room/:id/join
* /api/room/:id/leave
* /api/room/:id/send


## Usage

To get Rocket.Chat version and API version:

```ruby
require 'rocketchat'

rcs = RocketChat::Server.new("http://your.server.address/")
version = rcs.version
puts "Rocket.Chat version: #{version.rocketchat}"
puts "API version: #{version.api}"
```

To find public rooms:

```ruby
require 'rocketchat'

rcs = RocketChat::Server.new("http://your.server.address/")
rc = rcs.login("username", "password")
rc.public_rooms.each do |room|
  puts "##{room.name}(#{room.id}): #{room.msgs}messages"
end
```

You can also use [] to open a specific room.

```ruby
require 'rocketchat'

rcs = RocketChat::Server.new("http://your.server.address/")
rc = rcs.login("username", "password")
puts "#general has #{rc["general"].msgs} messages"
```

To join or leave a room:

```ruby
require 'rocketchat'

rcs = RocketChat::Server.new("http://your.server.address/")
rc = rcs.login("username", "password")
rc["dev"].join
rc["dev"].leave
```

To send a message:

```ruby
require 'rocketchat'

rcs = RocketChat::Server.new("http://your.server.address/")
rc = rcs.login("username", "password")
rc["dev"].post("message")
```

To logout from a server.

```ruby
require 'rocketchat'

rcs = RocketChat::Server.new("http://your.server.address/")
rc = rcs.login("username", "password")
# ... join, leave, send a message, etc ...
rc.logout
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/int2xx9/ruby-rocketchat.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

