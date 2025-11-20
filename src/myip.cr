require "lexbor"
require "./myip/*"
require "http/client"
require "json"
require "http/headers"
require "colorize"
require "term-spinner"

class String
  def as_title
    self.colorize(:yellow).on_blue.bold
  end
end

class Myip
  getter chan = Channel(Tuple(String, String?)).new
  property chan_send_count : Int32 = 0
  property detail_chan_send_count : Int32 = 0

  def ip_from_ifconfig(ip_version : Int32 = 4)
    self.chan_send_count = chan_send_count() + 1

    spawn do
      url = "https://ifconfig.io"
      spinner = Term::Spinner.new(":spinner Connecting to #{url.as_title} ...", format: :dots, interval: 0.2.seconds)

      spinner.run do
        headers = HTTP::Headers{
          "User-Agent" => "curl/7.88.1",
          "Accept"     => "*/*",
          # Host 是必须的，Google Gemini 3 帮我找到的问题，
          # 只有加了这个，才能返回正确的 IP
          "Host" => "ifconfig.io",
        }

        response = HTTP::Client.get(url, headers: headers)
        body = response.body
        chan.send({body, nil})

        spinner.success
      rescue ex : ArgumentError | Socket::Error
        chan.send({ex.message.not_nil!, nil})
      end
    end
  end

  def ip_from_ipw(ip_version : Int32 = 4)
    self.chan_send_count = chan_send_count() + 1

    spawn do
      url = "http://#{ip_version}.ipw.cn"
      spinner = Term::Spinner.new(":spinner Connecting to #{url.as_title} ...", format: :dots, interval: 0.2.seconds)

      spinner.run do
        response = HTTP::Client.get(url)
        body = response.body
        chan.send({body, nil})

        spinner.success
      rescue ex : ArgumentError | Socket::Error
        chan.send({ex.message.not_nil!, nil})
      end
    end
  end

  def ip_from_ip_sb
    self.chan_send_count = chan_send_count() + 1

    spawn do
      url = "https://api.ip.sb/geoip"
      spinner = Term::Spinner.new(":spinner Connecting to #{url.as_title} ...", format: :dots, interval: 0.2.seconds)

      spinner.run do
        response = HTTP::Client.get(url)
        body = response.body
        result = JSON.parse(body)
        io = IO::Memory.new
        PrettyPrint.format(result, io, width: 79)
        io.rewind
        chan.send({io.gets_to_end, nil})

        spinner.success
      rescue JSON::ParseException
        chan.send({body.not_nil!, nil})
      rescue ex : ArgumentError | Socket::Error
        chan.send({ex.message.not_nil!, nil})
      end
    end
  end

  def ip_from_ip111
    spinner = Term::Spinner::Multi.new(":spinner", format: :dots, interval: 0.2.seconds)

    # 注意: ip111.cn 仅支持 http, 不支持 https:
    ip111_url = "http://www.ip111.cn"
    sp1 = spinner.register ":spinner Connecting to #{ip111_url.as_title} ..."

    doc = uninitialized Lexbor::Parser

    sp1.run do
      doc, _code = from_url(ip111_url)

      title = doc.css(".card-header").first.tag_text.strip
      ipinfo = doc.css(".card-body p").first.tag_text.strip

      STDERR.puts "#{title}：#{ipinfo}"

      sp1.success
    end

    headers = HTTP::Headers{"Referer" => "http://www.ip111.cn/"}

    # 这里只能用 each, 没有 map, 因为 doc.nodes("iframe") 是一个 Iterator::SelectIterator 对象
    doc.nodes("iframe").each do |node|
      self.chan_send_count = chan_send_count() + 1
      url = node.attribute_by("src").not_nil!
      title = node.parent!.parent!.parent!.css(".card-header").first.tag_text.strip

      sp = spinner.register("Connecting to #{url.as_title} ...")

      spawn do
        sp.run do
          doc, _code = from_url(url, headers: headers)
          ipinfo = doc.body!.tag_text.strip

          ip = ipinfo[/[a-z0-9:.]+/]

          chan.send({"#{title}：#{ipinfo}", ip})

          sp.success
        rescue ex : ArgumentError | Socket::Error
          chan.send({ex.message.not_nil!, nil})
        end
      end
    end
  end

  def ip_from_ip138
    spinner = Term::Spinner::Multi.new(":spinner", format: :dots, interval: 0.2.seconds)
    self.chan_send_count = chan_send_count + 1

    spawn do
      url = "https://www.ip138.com"
      sp = spinner.register("Connecting to #{url.as_title} ...")

      ip138_url = ""

      sp.run do
        doc, _code = from_url(url, follow: true)
        ip138_url = doc.css("iframe").first.attribute_by("src").not_nil!

        sp.success
      end

      headers = HTTP::Headers{"Origin" => "https://ip.skk.moe"}

      sp1 = spinner.register("Connecting to #{ip138_url.as_title} ...")

      code = 0
      doc = uninitialized Lexbor::Parser

      sp1.run do
        doc, code = from_url("https:#{ip138_url}", headers: headers)

        sp1.success
      end

      if code == 502
        myip = doc.css("body p span.F").first.tag_text[/IP:\s*([0-9.]+)/, 1]
        url = "https://www.ip138.com/iplookup.php?ip=#{myip}"

        sp2 = spinner.register("Connecting to #{url.as_title} ...")

        sp2.run do
          doc, _code = from_url(url, headers: headers)

          output = String.build do |io|
            doc.css("div.table-box>table>tbody tr").each { |x| io << x.tag_text }
          end

          chan.send({output.squeeze('\n'), nil})

          sp2.success
        end
      else
        chan.send({doc.css("body p").first.tag_text.strip, nil})
      end
    rescue ex : ArgumentError | Socket::Error
      chan.send({ex.message.not_nil!, nil})
    end
  end

  def process
    spinner = Term::Spinner::Multi.new(":spinner", format: :dots, interval: 0.2.seconds)
    detail_chan = Channel(String).new

    chan_send_count.times do
      select
      when value = chan.receive
        ipinfo, ip = value

        STDERR.puts "\n#{ipinfo}"

        if !ip.nil?
          self.detail_chan_send_count = detail_chan_send_count() + 1
          details_ip_url = "https://www.ipshudi.com/#{ip}.htm"
          sp = spinner.register("Connecting to #{details_ip_url.as_title} ...")

          spawn do
            sp.run do
              doc, _code = from_url(details_ip_url)

              output = String.build do |io|
                doc.css("div.ft>table>tbody>tr>td").each do |x|
                  io << x.tag_text
                end
              end

              detail_chan.send(output.squeeze('\n'))

              sp.success
            end
          end
        end
      when timeout 5.seconds
        STDERR.puts "Timeout, check your network connection!"
        exit
      end
    end

    detail_chan_send_count.times do
      select
      when ipinfo = detail_chan.receive
        STDERR.puts ipinfo
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
