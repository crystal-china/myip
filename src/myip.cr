require "lexbor"
require "./myip/*"
require "http/client"
require "json"
require "http/headers"

class Myip
  getter chan = Channel(Tuple(String, String)).new

  def get_ip_from_ib_sb
    spawn do
      url = "https://api.ip.sb/geoip"
      response = HTTP::Client.get(url)
      result = JSON.parse(response.body)
      io = IO::Memory.new
      PrettyPrint.format(result, io, width: 79)
      io.rewind
      chan.send({"----- Result from: #{url}：您访问外网地址信息：-----\n", io.gets_to_end})
    rescue ex : ArgumentError | Socket::Error
      chan.send({"----- Error from: #{url}：-----\n", ex.message.not_nil!})
    end
  end

  def get_ip_from_ip138
    spawn do
      url = "https://www.ip138.com"
      doc, code = from_url(url, follow: true)
      ip138_url = doc.css("iframe").first.attribute_by("src")
      headers = HTTP::Headers{"Origin" => "https://ip.skk.moe"}

      doc, code = from_url("https:#{ip138_url}", headers: headers)

      if code == 502
        myip = doc.css("body p span.F").first.tag_text[/IP:\s*([0-9.]+)/, 1]
        url = "https://www.ip138.com/iplookup.php?ip=#{myip}"
        doc, code = from_url(url, headers: headers)

        output = String.build do |io|
          doc.css("div.table-box>table>tbody tr").each { |x| io << x.tag_text }
        end

        chan.send({"----- Result from: #{url}：-----\n", output.squeeze('\n')})
      else
        chan.send({"----- Result from: #{url}：-----\n", doc.css("body p").first.tag_text.strip})
      end
    rescue ex : ArgumentError | Socket::Error
      chan.send({"----- Error from: #{url}：-----\n", ex.message.not_nil!})
    end
  end

  def process
    2.times do
      select
      when value = chan.receive
        title, ipinfo = value
        STDERR.puts "#{title}#{ipinfo}"
      when timeout 5.seconds
        STDERR.puts "Timeout, check your network connection!"
        exit
      end
    end
  end

  private def from_url(url : String, *, follow : Bool = false, headers = HTTP::Headers.new) : Tuple(Lexbor::Parser, Int32)
    response = HTTP::Client.get url, headers: headers
    if response.status_code == 200
      {Lexbor::Parser.new(response.body), 200}
    elsif follow && response.status_code == 301
      from_url response.headers["Location"], follow: true, headers: headers
    elsif response.status_code == 502
      {Lexbor::Parser.new(response.body), 502}
    else
      raise ArgumentError.new "Host #{url} returned #{response.status_code}"
    end
  rescue e : Socket::Error
    e.inspect_with_backtrace(STDERR)
    raise Socket::Error.new "Visit #{url} failed, please check your internet connection."
  end
end
