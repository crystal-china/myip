require "lexbor"
require "./myip/*"
require "http/client"
require "json"
require "http/headers"
require "colorize"

class Myip
  getter chan = Channel(Tuple(String, String, String?)).new
  property chan_send_count : Int32 = 0
  property ip111_chan_send_count : Int32 = 0

  def ip_from_ib_sb
    self.chan_send_count = chan_send_count() + 1

    spawn do
      url = "https://api.ip.sb/geoip"
      response = HTTP::Client.get(url)
      result = JSON.parse(response.body)
      io = IO::Memory.new
      PrettyPrint.format(result, io, width: 79)
      io.rewind
      chan.send({"----- Result from: #{url}：您访问外网地址信息：-----", io.gets_to_end, nil})
    rescue ex : ArgumentError | Socket::Error
      chan.send({"----- Error from: #{url}：-----", ex.message.not_nil!, nil})
    end
  end

  def ip_from_ip111
    # 注意: ip111.cn 仅支持 http, 不支持 https:
    ip111_url = "http://www.ip111.cn"

    doc, code = from_url(ip111_url)

    title = doc.css(".card-header").first.tag_text.strip
    ipinfo = doc.css(".card-body p").first.tag_text.strip

    STDERR.puts "----- Result from #{ip111_url}：-----", "#{title}：#{ipinfo}"

    headers = HTTP::Headers{"Referer" => "http://www.ip111.cn/"}

    # 这里只能用 each, 没有 map, 因为 doc.nodes("iframe") 是一个 Iterator::SelectIterator 对象
    doc.nodes("iframe").each do |node|
      self.chan_send_count = chan_send_count() + 1
      self.ip111_chan_send_count = ip111_chan_send_count() + 1

      spawn do
        url = node.attribute_by("src").not_nil!
        doc, code = from_url(url, headers: headers)
        title = node.parent!.parent!.parent!.css(".card-header").first.tag_text.strip
        ipinfo = doc.body!.tag_text.strip

        ip = ipinfo[/[a-z0-9:.]+/]

        chan.send({"----- Result from #{ip111_url}：#{url}：-----", "#{title}：#{ipinfo}", ip})
      rescue ex : ArgumentError | Socket::Error
        chan.send({"----- Error from: #{ip111_url}：#{url}：-----", ex.message.not_nil!, nil})
      end
    end
  end

  def ip_from_ip138
    self.chan_send_count = chan_send_count + 1

    spawn do
      url = "https://www.ip138.com"
      doc, _code = from_url(url, follow: true)
      ip138_url = doc.css("iframe").first.attribute_by("src")
      headers = HTTP::Headers{"Origin" => "https://ip.skk.moe"}

      doc, code = from_url("https:#{ip138_url}", headers: headers)

      if code == 502
        myip = doc.css("body p span.F").first.tag_text[/IP:\s*([0-9.]+)/, 1]
        url = "https://www.ip138.com/iplookup.php?ip=#{myip}"
        doc, _code = from_url(url, headers: headers)

        output = String.build do |io|
          doc.css("div.table-box>table>tbody tr").each { |x| io << x.tag_text }
        end

        chan.send({"----- Result from: #{url}：-----", output.squeeze('\n'), nil})
      else
        chan.send({"----- Result from: #{url}：-----", doc.css("body p").first.tag_text.strip, nil})
      end
    rescue ex : ArgumentError | Socket::Error
      chan.send({"----- Error from: #{url}：-----", ex.message.not_nil!, nil})
    end
  end

  def process
    detail_chan = Channel(Tuple(String, String)).new

    chan_send_count.times do
      select
      when value = chan.receive
        title, ipinfo, ip = value

        STDERR.puts "#{title.colorize(:yellow).on_blue.bold}\n#{ipinfo}"

        if !ip.nil?
          spawn do
            details_ip_url = "https://www.ipshudi.com/#{ip}.htm"

            doc, _code = from_url(details_ip_url)

            output = String.build do |io|
              doc.css("div.ft>table>tbody>tr>td").each { |x| io << x.tag_text }
            end

            detail_chan.send({"----- Checking #{ip} use ipshudi.com：-----", output.squeeze('\n')})
          end
        end
      when timeout 5.seconds
        STDERR.puts "Timeout, check your network connection!"
        exit
      end
    end

    ip111_chan_send_count.times do
      select
      when value = detail_chan.receive
        title, ipinfo = value

        STDERR.puts "#{title.colorize(:yellow).on_blue.bold}\n#{ipinfo}"
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
