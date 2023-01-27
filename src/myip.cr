require "crystagiri"
require "./myip/*"
require "option_parser"
require "json"

chan = Channel(Tuple(String, String)).new

def get_ip_from_ib_sb(chan)
  spawn do
    url = "https://api.ip.sb/geoip"
    doc = Crystagiri::HTML.from_url url, follow: true
    result = JSON.parse(doc.content)
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
    doc = Crystagiri::HTML.from_url "http://www.ip138.com", follow: true
    ip138_url = doc.at_css("iframe").not_nil!.node.attributes["src"].content
    url = "http:#{ip138_url}"
    doc = Crystagiri::HTML.from_url url

    chan.send({"ip138.com：", doc.at_css("body p").not_nil!.content.strip})
  rescue Socket::Error
    STDERR.puts "visit #{url} failed, please check internet connection."
  rescue ArgumentError
    STDERR.puts "#{url} return 500"
  rescue ex
    STDERR.puts ex.message
  end
end

def get_ip_from_ip111(chan)
  begin
    ip111_url = "http://www.ip111.cn"
    doc = Crystagiri::HTML.from_url ip111_url

    iframe = doc.where_tag("iframe") do |tag|
      spawn do
        url = tag.node.attributes["src"].content
        ip = Crystagiri::HTML.from_url(url).at_css("body").not_nil!.content
        title = tag.node.parent.try(&.parent).try(&.parent).not_nil!.xpath_node("div[@class='card-header']").not_nil!.content.strip

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

  title = doc.at_css(".card-header").not_nil!.content.strip
  ip = doc.at_css(".card-body p").not_nil!.content.strip

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
