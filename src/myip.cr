require "crystagiri"
require "./myip/*"
require "option_parser"

chan = Channel(Tuple(String, String)).new
terminate = Channel(Nil).new
done = Channel(Nil).new

def get_ip_from_ip138(chan)
  spawn do
    doc = Crystagiri::HTML.from_url "http://www.ip138.com", follow: true
    ip138_url = doc.at_css("iframe").not_nil!.node.attributes["src"].content
    doc = Crystagiri::HTML.from_url "http:#{ip138_url}"

    chan.send({"ip138.com：", doc.at_css("body p").not_nil!.content.strip})
  rescue Socket::Error | OpenSSL::SSL::Error
    STDERR.puts "visit http://www.ip138.com failed, please check internet connection."
    exit
  end
end

def get_ip_from_ip111(chan)
  begin
    doc = Crystagiri::HTML.from_url "http://www.ip111.cn"

    iframe = doc.where_tag("iframe") do |tag|
      spawn do
        url = tag.node.attributes["src"].content
        ip = Crystagiri::HTML.from_url(url).at_css("body").not_nil!.content
        title = tag.node.parent.try(&.parent).try(&.parent).not_nil!.xpath_node("div[@class='card-header']").not_nil!.content.strip

        chan.send({"ip111.cn：#{title}：", ip})
      rescue OpenSSL::SSL::Error
        STDERR.puts "visit #{url} failed"
        exit
      end
    end

    {doc, iframe.size}
  rescue Socket::Error | OpenSSL::SSL::Error
    STDERR.puts "visit http://getip.pub failed, please check internet connection."
    exit
  end
end

def output(chan, size)
end

at_exit do
  output_i138 = false

  OptionParser.parse do |parser|
    parser.banner = <<-USAGE
Usage: myip <option>
USAGE

    parser.on("-l", "--location", "Use ip138.com to get more accurate ip location information.") do
      get_ip_from_ip138(chan)
      output_i138 = true
    end

    parser.on("-h", "--help", "Show this help message and exit") do
      puts parser
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

  size = output_i138 ? iframe_size + 1 : iframe_size

  spawn do
    loop do
      select
      when value = chan.receive
        title, ip = value

        STDERR.puts "#{title}#{ip}"
      when terminate.receive?
        break
      when timeout 5.seconds
        STDERR.puts "Timeout!"
        exit
      end
    end
    done.close
  end

  terminate.close
  done.receive?

  # size.times do |i|
  #   select
  #   when value = chan.receive
  #     title, ip = value

  #     STDERR.puts "#{title}#{ip}"
  #   when timeout 5.seconds
  #     STDERR.puts "Timeout!"
  #     exit
  #   end
  # end
end
