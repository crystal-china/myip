require "option_parser"
require "./myip"

OptionParser.parse do |parser|
  parser.banner = <<-USAGE
Usage: myip <option>
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
end

myip = Myip.new
myip.get_ip_from_ip138
myip.get_ip_from_ib_sb
myip.get_ip_from_ip111
myip.process

at_exit do
  {% if flag?(:win32) %}
    puts "Pressing any key to exit."
    STDIN.read_char
  {% end %}
end
