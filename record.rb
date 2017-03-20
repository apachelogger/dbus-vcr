#!/usr/bin/env ruby

require 'dbus'
require 'yaml'

$DEBUG = true

def accept?(msg)
  return true if msg.sender && $actors.include?(msg.sender)
  return true if msg.destination && $actors.include?(msg.destination)
  return true if msg.interface&.start_with?('org.freedesktop.PackageKit')
  return true if msg.destination&.start_with?('org.freedesktop.PackageKit')
  return true if msg.sender&.start_with?('org.freedesktop.PackageKit')
  return true if msg.params[0]&.respond_to?(:start_with?) && msg.params[0].start_with?('org.freedesktop.PackageKit')
  false
end

def input?(msg)
  msg.destination == 'org.freedesktop.PackageKit'
end

def output?(msg)
  # PK boradcasts everything.
  msg.destination.nil?
end

def record(msg)
  type = input?(msg) ? :client : :server
  $dump << {
    type: type,
    msg: msg
  }
end

$actors = []
$dump = []
def exit_handler
  puts x = YAML.dump($dump)
  File.write("#{__dir__}/recording", x)
  exit
end

at_exit { exit_handler }
Signal.trap("INT") { exit_handler }

bus = DBus.system_bus

# Use newish Monitoring facilitites of dbus-daemon to do the recording.
p x = bus["org.freedesktop.DBus"]["/org/freedesktop/DBus"]
p x.introspect
p monitoring = x["org.freedesktop.DBus.Monitoring"]
p monitoring.methods
p monitoring.BecomeMonitor([], 0)

module Interpecetor
  def process(msg)
    # p caller
    unless accept?(msg)
      # puts "-----------------------------------------------------"
      # puts "discarding:"
      # p msg
      # puts "-----------------------------------------------------"
      return
    end
    # Register known packagekit actors so we can record their sequenced but
    # nameless replies.
    $actors << msg.sender if msg.sender && !$actors.include?(msg.sender)
    $actors << msg.destination if msg.destination && !$actors.include?(msg.destination)
    msg.instance_variables.each do |v|
      p "#{v} => #{msg.instance_variable_get(v)}"
    end
    record(msg)
  end
end
class DBus::Connection
  prepend Interpecetor
end

main = DBus::Main.new
main << bus
main.run
