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
myip ip111 => get ip from http://www.ip111.cn
myip ip138 => get ip info from https://www.ip138.com
myip ipsb => get ip info from https://api.ip.sb/geoip
myip ipw => get ip info from http://4.ipw.cn
myip ipw6 => get ipv6 info from http://6.ipw.cn

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
    elsif args.includes? "ipw6"
      myip.ip_from_ipw(ip_version: 6)
    elsif args.includes? "ipw"
      myip.ip_from_ipw(ip_version: 4)
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
