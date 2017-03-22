#!/usr/bin/env ruby

require 'dbus'
require 'yaml'

$DEBUG = true

$dump = []
def exit_handler
  puts x = YAML.dump($dump)
  File.write("#{__dir__}/recording", x)
  exit
end

at_exit { exit_handler }
Signal.trap('INT') { exit_handler }
Signal.trap('TERM') { exit_handler }

bus = DBus.system_bus
# Use newish Monitoring facilitites of dbus-daemon to do the recording.
raise 'Need rootout to record via monitoring.' unless Process.uid.to_i.zero?
p x = bus['org.freedesktop.DBus']['/org/freedesktop/DBus']
p x.introspect
p monitoring = x['org.freedesktop.DBus.Monitoring']
p monitoring.methods
p monitoring.BecomeMonitor([], 0)

module Interpecetor
  def process(msg)
    $dump << msg
  end
end
class DBus::Connection
  prepend Interpecetor
end

main = DBus::Main.new
main << bus
main.run
