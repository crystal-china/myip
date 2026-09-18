require "option_parser"
require "log"
require "./myip"

Log.setup_from_env(
  default_level: :error,
  backend: Log::IOBackend.new(STDERR)
)

ARGV << "--help" if ARGV.empty?

myip = Myip.new

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

OptionParser.parse do |parser|
  parser.banner = usage
  parser.on("-h", "--help", "Show this help message and exit") do
    puts parser
    exit
  end

  parser.on("-v", "--version", "Show version") do
    puts Myip::VERSION
    exit
  end

  parser.invalid_option do |flag|
    STDERR.puts "Invalid option: #{flag}.\n\n"
    STDERR.puts parser
    exit 1
  end

  parser.missing_option do |flag|
    STDERR.puts "Missing option for #{flag}\n\n"
    STDERR.puts parser
    exit 1
  end

  parser.unknown_args do |args|
    case args.first?
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
      STDERR.puts usage
      exit 1
    end
  end
end

myip.process

at_exit do
  {% if flag?(:win32) %}
    puts "Pressing any key to exit."
    STDIN.read_char
  {% end %}
end
