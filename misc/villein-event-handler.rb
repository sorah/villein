#!/usr/bin/env ruby
#require 'json'
require 'socket'

sock = TCPSocket.new(ARGV[0], ARGV[1].to_i)
sock.set_encoding(Encoding::ASCII_8BIT)


ENV.each do |name, value|
  next unless name.start_with?('SERF'.freeze)

  sock.write "#{name}=#{value}\0"
end

sock.write "\0"
sock.write $stdin.read
sock.close_write

if ENV["SERF_EVENT"] == "query"
  $stdout.write sock.read
end
