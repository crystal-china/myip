require "option_parser"
require "./myip"

ARGV << "--help" if ARGV.empty?

# ip111 = false
# ip138 = false
# ipsb = false
# ipw = false

myip = Myip.new

usage = <<-USAGE
Usage:
myip ip111 => get ip info from https://ip111.cn
myip ip138 => get ip info from https://www.ip138.com
myip ipsb => get ip info from https://api.ip.sb/geoip
myip ifconfig => get ip info from https://ifconfig.io
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
    if args.includes? "ip111"
      myip.ip_from_ip111
    elsif args.includes? "ip138"
      myip.ip_from_ip138
    elsif args.includes? "ipsb"
      myip.ip_from_ip_sb
    elsif args.includes? "ifconfig"
      myip.ip_from_ifconfig
    elsif args.includes? "ipify6"
      myip.ip_from_ipify(ip_version: 6)
    elsif args.includes? "ipify"
      myip.ip_from_ipify(ip_version: 4)
    elsif args.includes? "cf"
      myip.ip_from_cf
    elsif args.includes? "ident"
      myip.ip_from_ident
    elsif args.includes? "aws"
      myip.ip_from_aws
    elsif args.includes? "akamai"
      myip.ip_from_akamai
    else
      STDERR.puts usage
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
