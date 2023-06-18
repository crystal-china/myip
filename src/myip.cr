require "lexbor"
require "./myip/*"
require "http/client"
require "json"

class Myip
  getter chan = Channel(Tuple(String, String)).new
  property? output_location = false
  property? ip111_response_500 = false

  def get_ip_from_ib_sb
    spawn do
      url = "https://api.ip.sb/geoip"
      response = HTTP::Client.get(url)
      result = JSON.parse(response.body)
      io = IO::Memory.new
      PrettyPrint.format(result, io, 79)
      io.rewind
      chan.send({"ip.sb/geoip：", io.gets_to_end})
    rescue ex : ArgumentError | Socket::Error
      STDERR.puts ex.message
    end
  end

  def get_ip_from_ip138
    spawn do
      url = "http://www.ip138.com"
      doc = from_url(url, follow: true)
      ip138_url = doc.css("iframe").first.attribute_by("src")
      url = "http:#{ip138_url}"
      doc = from_url(url)

      chan.send({"ip138.com：", doc.css("body p").first.tag_text.strip})
    rescue ex : ArgumentError | Socket::Error
      STDERR.puts ex.message
    end
  end

  def get_ip_from_ip111
    ip111_url = "http://www.ip111.cn"
    doc = from_url(ip111_url, follow: true)

    iframe = doc.nodes("iframe").map do |node|
      spawn do
        url = node.attribute_by("src").not_nil!
        ip = from_url(url).body!.tag_text.strip
        title = node.parent!.parent!.parent!.css(".card-header").first.tag_text.strip

        chan.send({"ip111.cn：#{title}：", ip})
      rescue ex : ArgumentError | Socket::Error
        STDERR.puts ex.message unless chan.closed?
        chan.close
      end
    end

    {doc, iframe.size}
  rescue ex : ArgumentError | Socket::Error
    STDERR.puts ex.message
  end

  def process
    size = 0

    if output_location?
      size = 2
    else
      if (result = get_ip_from_ip111)
        doc, iframe_size = result
        title = doc.css(".card-header").first.tag_text.strip
        ip = doc.css(".card-body p").first.tag_text.strip

        STDERR.puts "ip111.cn：#{title}：#{ip}"
        size = iframe_size
      end
    end

    size.times do
      select
      when value = chan.receive?
        if value.nil?
          if !output_location?
            STDERR.puts "Trying `myip -l` again."
            self.ip111_response_500 = true
            break
          end
        else
          title, ip = value
          STDERR.puts "#{title}#{ip}"
        end
      when timeout 5.seconds
        STDERR.puts "Timeout!"
        exit
      end
    end
  end

  private def from_url(url : String, follow : Bool = false) : Lexbor::Parser
    response = HTTP::Client.get url
    if response.status_code == 200
      Lexbor::Parser.new(response.body)
    elsif follow && response.status_code == 301
      from_url response.headers["Location"], follow: true
    else
      raise ArgumentError.new "Host #{url} returned #{response.status_code}"
    end
  rescue Socket::Error
    raise Socket::Error.new "Visit #{url} failed, please check your internet connection."
  end
end
