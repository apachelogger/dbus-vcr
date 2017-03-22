#!/usr/bin/env ruby

require 'dbus'
require 'yaml'

class Actor
  def initialize(name, uid)
    @name = name
    @uid = uid
    @ignored_serials = []
  end

  def actor_in?(msg)
    msg.sender == @name || msg.sender == @uid || msg.sender.nil? ||
    msg.destination == @name || msg.destination == @uid || msg.destination.nil?
  end

  def destination?(msg)
    msg.destination == @name || msg.destination == @uid
  end

  def sender?(msg)
    msg.sender == @name || msg.sender == @uid
  end

  def ignore(msg)
    return unless sender?(msg)
    @ignored_serials << msg.serial
  end

  def ignored_request?(msg)
    return unless destination?(msg)
    @ignored_serials.include?(msg.reply_serial)
  end
end

class Filter
  def initialize(client, server)
    @client = client
    @server = server
  end

  def filter?(msg)
    # Never record protocol messages. These are used to introspect the service
    # on a dbus level such as GetNameOwner which resolves the serivce name to
    # the unique name (:1.1234 for example).
    return true if (msg.interface&.include?('org.freedesktop.DBus') || msg.destination&.include?('org.freedesktop.DBus')) && (msg.member == 'GetNameOwner' || msg.member == 'NameOwnerChanged' || msg.member == 'RequestName' || msg.member == 'NameAcquired' || msg.member == 'GetConnectionUnixUser')
    return true if @client.ignored_request?(msg) || @server.ignored_request?(msg)
    false
  end

  def filter
    output = []
    msgs = YAML.load_file('recording')
    msgs.each do |msg|
      # Skip msg.
      next unless @client.actor_in?(msg) && @server.actor_in?(msg)
      if filter?(msg)
        @client.ignore(msg)
        next
      end

      # Record
      type = @server.destination?(msg) ? :client : :server
      # First must be client request!
      next if output.size.zero? && type == :server
      output << {
        type: type,
        msg: msg
      }
    end
    File.write('casette.yml', YAML.dump(output))
  end
end

client = Actor.new(ARGV.fetch(0), ARGV.fetch(1))
server = Actor.new(ARGV.fetch(2), ARGV.fetch(3))
Filter.new(client, server).filter
