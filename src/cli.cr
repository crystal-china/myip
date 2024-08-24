require "option_parser"
require "./myip"

ARGV << "--help" if ARGV.empty?

ip111 = false
ip138 = false
ipsb = false

OptionParser.parse do |parser|
  parser.banner = <<-USAGE
Usage:
myip ip111 => get ip from http://www.ip111.cn
myip ip138 => get ip info from https://www.ip138.com
myip ipsb => get ip info from https://api.ip.sb/geoip

USAGE

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
      ip111 = true
    elsif args.includes? "ip138"
      ip138 = true
    elsif args.includes? "ipsb"
      ipsb = true
    end
  end
end

myip = Myip.new
myip.ip_from_ip138 if ip138
myip.ip_from_ip_sb if ipsb
myip.ip_from_ip111 if ip111
myip.process

at_exit do
  {% if flag?(:win32) %}
    puts "Pressing any key to exit."
    STDIN.read_char
  {% end %}
end
