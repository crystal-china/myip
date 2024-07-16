require "option_parser"
require "./myip"
require "term-spinner"

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

msg = ":spinner " + "Connecting ... ".colorize(:yellow).on_blue.bold.to_s
spinner = Term::Spinner.new(msg, format: :dots)

spinner.auto_spin

myip = Myip.new
myip.ip_from_ip138
myip.ip_from_ib_sb
myip.ip_from_ip111
myip.process

spinner.stop("Done")

at_exit do
  {% if flag?(:win32) %}
    puts "Pressing any key to exit."
    STDIN.read_char
  {% end %}
end
