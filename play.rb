#!/usr/bin/env ruby

require 'dbus'
require 'yaml'

$DEBUG = true

data = YAML.load_file("#{__dir__}/cassette.yml")

$data = data
$client_data = $data.select { |x| x.fetch(:type) == :client }

raise unless $data[0].fetch(:type) == :client

module Interceptor
  # Expectation matching. m1 is the expected message, m2 the actual message.
  # They need to be equal "enough" to match.
  def compat?(m1, m2)
    p m1
    p m2
    # DBus replies are associated with their requests by their reply_serial
    # which is the serial of the request. This means that we need to adjust
    # our offests for each request so our replies are in sync again.
    # NB: The code only works iff the offsets are semi-consistent as
    #   excess offset divergence can cause reply syncness to get lost if
    #   a request and its reply are far apart (i.e. between the two are
    #   ther requests with different offset values).
    m1.interface == m2.interface &&
      m1.params == m2.params &&
      m1.member == m2.member
  end

  # Override standard message handling. Foreach incoming message we'll check
  # our expectations to make sure the incoming message is the one we expected,
  # if so we play all server-side messages up to the next client message.
  # Then we wait for the next client message and verify it being expected etc...
  def process(m)
    if m.sender&.start_with?('org.freedesktop.DBus') && (m.destination && m.destination == $bus.unique_name || m.destination == $service.name)
      # Random crap calls from dbus itself, supposedly because we register.
      return super(m)
    end
    expected = $data[0].fetch(:msg)
    raise "Not expected #{m.inspect}" unless compat?(expected, m)

    # Track all serials. When we reply to a request we need to reference the
    # client's serial so the client knows what we replied to. BUT!
    # The serial is not consistent across runs and also not consistent between
    # playback runs. One additional client-side message and the serial is off.
    # To compensate we establish a fixed map of the client serials and the
    # serial of the recorded expectation. Later when replying we can then map
    # the recorded reply_serial to the reply_serial we need to actually make
    # it work.
    @client_reply_translator ||= {}
    @client_reply_translator[expected.serial] = m.serial

    $data.shift
    while $data[0] && $data[0].fetch(:type) != :client
      x = $data.shift.fetch(:msg)
      next if x.sender == 'org.freedesktop.DBus' # FIXME bogus recording
      next if x.destination == 'org.freedesktop.DBus' # FIXME bogus recording

      puts "           pushing ==>>> "
      p x

      new_message = DBus::Message.new(x.message_type)
      new_message.path = x.path
      new_message.interface = x.interface
      new_message.member = x.member
      new_message.error_name = x.error_name
      new_message.destination = m.sender
      unless x.params.empty?
        params = x.params.dup
        DBus::Type::Parser.new(x.signature).parse.each do |t|
          new_message.add_param(t, params.shift)
        end
      else
        new_message.signature = x.signature
      end
      # .sender auto-set
      if x.reply_serial
        new_message.reply_serial = @client_reply_translator.fetch(x.reply_serial)
      end

      p new_message
      @message_queue.push(new_message)
    end
    exit 0 if $data.empty?
    puts "        -_- Zzzzz"
    puts "now waiting for #{$data[0]}"
  end
end

$bus = bus = DBus.session_bus
$service = bus.request_service("org.freedesktop.PackageKit")
p bus.unique_name

# Only install our traffic interceptor after we are registered. So we are
# properly working.
DBus::Connection.prepend(Interceptor)

main = DBus::Main.new
main << bus
main.run
