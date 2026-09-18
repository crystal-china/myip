require "option_parser"
require "log"
require "./myip"

Log.setup_from_env(
  default_level: :error,
  backend: Log::IOBackend.new(STDERR)
)

COMMAND_TIMEOUT = 30.seconds

ARGV << "--help" if ARGV.empty?

myip = Myip.new
command_done = Channel(Nil).new

spawn do
  select
  when command_done.receive
  when timeout COMMAND_TIMEOUT
    STDERR.puts "Timeout, check your network connection!"
    exit 1
  end
end

usage = <<-USAGE
  Usage:
  myip ip111 => get ip info from https://ip111.cn
  myip ip138 => get ip info from https://www.ip138.com
  myip ipsb => get ip info from https://api.ip.sb/geoip
  myip ifconfig.io => get IP from https://ifconfig.io/ip
  myip ifconfig.co => get IP and geolocation info from https://ifconfig.co/json
  myip ifconfig.me => get connection info from https://ifconfig.me/all.json
  myip icanhazip => get IP from https://icanhazip.com
  myip httpbin => get origin IP from https://httpbin.org/ip
  myip dyndns => get IP from http://checkip.dyndns.org
  myip ipify => get IPv4 from https://api.ipify.org
  myip ipify6 => get IPv6 from https://api6.ipify.org
  myip cf => get connection info from Cloudflare trace
  myip ident => get IP and geolocation info from ident.me
  myip aws => get IP from AWS CheckIP
  myip akamai => get IP from Akamai

  USAGE

remaining_args = [] of String

OptionParser.parse do |opt|
  opt.banner = usage
  opt.on("-h", "--help", "Show this help message and exit") do
    puts opt
    exit
  end

  opt.on("-v", "--version", "Show version") do
    puts Myip::VERSION
    exit
  end

  opt.invalid_option do |flag|
    abort "Invalid option: #{flag}\n\n#{opt}"
  end

  opt.missing_option do |flag|
    abort "Missing option for #{flag}\n\n#{opt}"
  end

  opt.unknown_args do |args|
    remaining_args = args
  end
end

unless remaining_args.size == 1
  abort "Expected exactly one command, got #{remaining_args.size}.\n\n#{usage}"
end

case remaining_args.first
when "ip111"
  myip.ip_from_ip111
when "ip138"
  myip.ip_from_ip138
when "ipsb"
  myip.ip_from_ip_sb
when "ifconfig.io"
  myip.ip_from_ifconfig_io
when "ifconfig.co"
  myip.ip_from_ifconfig_co
when "ifconfig.me"
  myip.ip_from_ifconfig_me
when "icanhazip"
  myip.ip_from_icanhazip
when "httpbin"
  myip.ip_from_httpbin
when "dyndns"
  myip.ip_from_dyndns
when "ipify6"
  myip.ip_from_ipify(ip_version: 6)
when "ipify"
  myip.ip_from_ipify(ip_version: 4)
when "cf"
  myip.ip_from_cf
when "ident"
  myip.ip_from_ident
when "aws"
  myip.ip_from_aws
when "akamai"
  myip.ip_from_akamai
else
  abort usage
end

myip.process
command_done.send(nil)

at_exit do
  {% if flag?(:win32) %}
    puts "Pressing any key to exit."
    STDIN.read_char
  {% end %}
end
