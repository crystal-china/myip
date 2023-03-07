require "lexbor"
require "http/client"
require "./myip/*"
require "option_parser"
require "json"

chan = Channel(Tuple(String, String)).new

def from_url(url : String, follow : Bool = false) : Lexbor::Parser
  response = HTTP::Client.get url
  if response.status_code == 200
    Lexbor::Parser.new(response.body)
  elsif follow && response.status_code == 301
    from_url response.headers["Location"], follow: true
  else
    raise ArgumentError.new "Host returned #{response.status_code}"
  end
rescue Socket::Error
  raise Socket::Error.new "Host #{url} cannot be fetched"
end

def get_ip_from_ib_sb(chan)
  spawn do
    url = "https://api.ip.sb/geoip"
    response = HTTP::Client.get(url)
    result = JSON.parse(response.body)
    io = IO::Memory.new
    PrettyPrint.format(result, io, 79)
    io.rewind
    chan.send({"ip.sb/geoip：", io.gets_to_end})
  rescue Socket::Error
    STDERR.puts "visit #{url} failed, please check internet connection."
  rescue ArgumentError
    STDERR.puts "#{url} return 500"
  rescue ex
    STDERR.puts ex.message
  end
end

def get_ip_from_ip138(chan)
  spawn do
    url = "http://www.ip138.com"
    doc = from_url(url, follow: true)
    ip138_url = doc.css("iframe").first.attribute_by("src")
    url = "http:#{ip138_url}"
    doc = from_url url

    chan.send({"ip138.com：", doc.css("body p").first.tag_text.strip})
  rescue Socket::Error
    STDERR.puts "visit #{url} failed, please check internet connection."
  rescue ArgumentError
    STDERR.puts "#{url} return 500"
  rescue ex
    STDERR.puts ex.message
  end
end

def get_ip_from_ip111(chan)
  ip111_url = "http://www.ip111.cn"
  doc = from_url(ip111_url, follow: true)

  iframe = doc.nodes("iframe").map do |node|
    spawn do
      url = node.attribute_by("src").not_nil!
      ip = from_url(url).body!.tag_text.strip
      title = node.parent!.parent!.parent!.css(".card-header").first.tag_text.strip

      chan.send({"ip111.cn：#{title}：", ip})
    rescue Socket::Error
      STDERR.puts "visit #{url} failed, please check internet connection."
    rescue ArgumentError
      STDERR.puts "#{url} return 500"
    rescue ex
      STDERR.puts ex.message
    end
  end

  {doc, iframe.size}
rescue Socket::Error
  STDERR.puts "visit #{ip111_url} failed, please check internet connection."
  exit
rescue ArgumentError
  STDERR.puts "#{ip111_url} return 500"
  exit
rescue ex
  STDERR.puts ex.message
  exit
end

at_exit do
  output_location = false

  OptionParser.parse do |parser|
    parser.banner = <<-USAGE
Usage: myip <option>
USAGE

    parser.on("-l", "--location", "Use ip138.com to get more accurate ip location information.") do
      get_ip_from_ip138(chan)
      get_ip_from_ib_sb(chan)
      output_location = true
    end

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

  doc, iframe_size = get_ip_from_ip111(chan)

  title = doc.css(".card-header").first.tag_text.strip
  ip = doc.css(".card-body p").first.tag_text.strip

  STDERR.puts "ip111.cn：#{title}：#{ip}"

  size = output_location ? iframe_size + 2 : iframe_size

  size.times do
    select
    when value = chan.receive
      title, ip = value

      STDERR.puts "#{title}#{ip}"
    when timeout 5.seconds
      STDERR.puts "Timeout!"
      exit
    end
  end

  {% if flag?(:win32) %}
    puts "Pressing any key to exit."
    STDIN.read_char
  {% end %}
end
