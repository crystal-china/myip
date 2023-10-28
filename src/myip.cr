require "lexbor"
require "./myip/*"
require "http/client"
require "json"

class Myip
  getter chan = Channel(Tuple(String, String)).new

  def get_ip_from_ib_sb
    spawn do
      url = "https://api.ip.sb/geoip"
      response = HTTP::Client.get(url)
      result = JSON.parse(response.body)
      io = IO::Memory.new
      PrettyPrint.format(result, io, 79)
      io.rewind
      chan.send({"ip.sb/geoip：您访问外网地址信息：\n", io.gets_to_end})
    rescue ex : ArgumentError | Socket::Error
      chan.send({"ip.sb/geoip：", ex.message.not_nil!})
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
      chan.send({"ip138.com：", ex.message.not_nil!})
    end
  end

  def process
    2.times do
      select
      when value = chan.receive
        title, ip = value
        STDERR.puts "#{title}#{ip}"
      when timeout 5.seconds
        STDERR.puts "Timeout, check your network connection!"
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
