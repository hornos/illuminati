#!/usr/bin/env ruby
require 'pusher'
require 'pusher-client'
require 'msgpack'
require 'xz'
require 'ascii85'

require 'gibberish'
require 'securerandom'
require 'digest/md5'

require 'gli'

require 'eat'
require 'sqlite3'

include GLI::App
program_desc 'The Ting Tings'
version 1.0

def msgpack(data,enc=:encode)
  return data.to_msgpack if enc == :encode
  MessagePack.unpack(data)
end

def xz(data,enc=:encode)
  return XZ::compress(data) if enc == :encode
  XZ::decompress(data)
end

def ascii85(data,enc=:encode)
  return Ascii85.encode(data) if enc == :encode
  Ascii85.decode(data)
end


def aes(data,enc=:encode)
  return @cipher.enc(data) if enc == :encode
  @cipher.dec(data)
end


def encode(data,redux=@config[:redux])
  redux.inject(data) do |enc,encoder|
    data = send(encoder.to_sym, data, :encode)
  end
  data
end

def decode(data,redux=@config[:redux])
  redux.reverse.inject(data) do |enc,encoder|
    data = send(encoder.to_sym, data, :decode)
  end
  data
end


# Global options
desc 'Config'
default_value "#{File.basename(__FILE__)}.yml"
arg_name 'config'
flag [:c,:config]

desc 'Secret Key'
default_value "#{File.basename(__FILE__)}.key"
arg_name 'key'
flag [:k,:key]

desc 'Use UPNP'
switch [:u,:upnp]

desc 'Ting client'
arg_name ''
command :client do |cmd|
  cmd.action do |global_options,options,args|
    cfg   = @config[:pusher]

    PusherClient.logger = Logger.new(STDOUT)
    PusherClient.logger.level = Logger::INFO
    options = {:secret => cfg[:secret]} 
    socket = PusherClient::Socket.new(cfg[:key], options)

    # Subscribe to two channels
    socket.subscribe(cfg[:channel])
    socket[cfg[:channel]].bind(cfg[:event]) do |data|
      data = decode(data)
      case data[0]
      when 'ping'
        # puts 'ping'
        # send back external ip
        chan  = cfg[:channel]
        event = cfg[:event]
        ip = eat('http://ifconfig.me/ip', :timeout => 10)
        Pusher[chan].trigger(event, encode(['pong',@config[:myid],ip.strip!]))
      when 'pong'
        @db.execute "REPLACE INTO hosts VALUES('"+data[1]+"','"+data[2]+"')"
        # puts "REPLACE INTO hosts VALUES('"+data[1]+"','"+data[2]+"')"
        puts "Registering host #{data[1]} (#{data[2]})"
      else
        puts data
      end
    end
    socket.connect
  end
end

desc 'Ping'
arg_name ''
command :ping do |cmd|
  cmd.action do |global_options,options,args|
    cfg   = @config[:pusher]
    chan  = cfg[:channel]
    event = cfg[:event]
    Pusher[chan].trigger(event, encode(['ping',args]))
  end
end

desc 'Generate shared key'
arg_name ''
command :genkey do |cmd|
  cmd.action do |global_options,options,args|
    print SecureRandom.urlsafe_base64(len=32)
  end
end

pre do |global,command,options,args|
  @config = YAML.load( ERB.new( File.read( global[:config] ) ).result )
  @config[:id] = global[:id] || command.name.to_s
  {:args=> args, :global=> global, :options=> options}.each { |k,v| @config[k] = v }
  @config[:key] = File.read( global[:key] )
  @cipher = Gibberish::AES.new(@config[:key])

  # init Pusher
  cfg = @config[:pusher]
  Pusher.app_id = cfg[:app_id]
  Pusher.key    = cfg[:key]
  Pusher.secret = cfg[:secret]
  # Pusher.encrypted =

  puts 'Ting GPUPNP Client'

  # UPNP discovery
  if global[:u]
    require 'open3'
    stdin, stdout, stderr = Open3.popen3('upnpc -l')
    for l in stdout.readlines
      case l
        when /ExternalIPAddress/
          @externalip = l.split.last
          die('UPNP failed') if @externalip.empty?
          puts "External IP: #{@externalip}"
      end
    end
  end

  # init DB
  @db = SQLite3::Database.open "#{File.basename(__FILE__)}.db"
  @db.execute "CREATE TABLE IF NOT EXISTS hosts(id TEXT PRIMARY KEY, ip TEXT)"
end

post do |global,command,options,args|
end

on_error do |exception|
  STDERR.puts exception.backtrace
  # require 'pry'
  # binding.pry
  true
end

exit run(ARGV)
