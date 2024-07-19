require "lexbor"
require "./myip/*"
require "http/client"
require "json"
require "http/headers"
require "colorize"
require "term-spinner"

alias IPInfo = String
alias IP = String

class String
  def as_title
    self.colorize(:yellow).on_blue.bold
  end
end

class Myip
  def new_spinner(msg : String, interval = 0.5.seconds)
    Term::Spinner.new(":spinner " + msg, format: :dots, interval: interval)
  end

  getter chan = Channel(Tuple(IPInfo, IP?)).new
  property chan_send_count : Int32 = 0
  property detail_chan_send_count : Int32 = 0

  def ip_from_ib_sb
    self.chan_send_count = chan_send_count() + 1

    spawn do
      url = "https://api.ip.sb/geoip"
      spinner = new_spinner("Connecting to #{url.as_title} ...")

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
    # 注意: ip111.cn 仅支持 http, 不支持 https:
    ip111_url = "http://www.ip111.cn"
    spinner = new_spinner("Connecting to #{ip111_url.as_title}")

    doc = uninitialized Lexbor::Parser

    spinner.run do
      doc, _code = from_url(ip111_url)

      title = doc.css(".card-header").first.tag_text.strip
      ipinfo = doc.css(".card-body p").first.tag_text.strip

      STDERR.puts "#{title}：#{ipinfo}"

      spinner.success
    end

    headers = HTTP::Headers{"Referer" => "http://www.ip111.cn/"}

    urls = [] of Array(String)
    doc.nodes("iframe").each do |node|
      url = node.attribute_by("src").not_nil!
      title = node.parent!.parent!.parent!.css(".card-header").first.tag_text.strip

      urls << [url, title]
    end

    spinner = new_spinner("Connecting to #{ip111_url.as_title}：   #{urls.map(&.[0]).join(" ").as_title} ...")

    # 这里只能用 each, 没有 map, 因为 doc.nodes("iframe") 是一个 Iterator::SelectIterator 对象
    urls.each do |(url, title)|
      self.chan_send_count = chan_send_count() + 1

      spawn do
        spinner.run do
          doc, _code = from_url(url, headers: headers)
          title =
            ipinfo = doc.body!.tag_text.strip

          ip = ipinfo[/[a-z0-9:.]+/]

          chan.send({"#{title}：#{ipinfo}", ip})

          spinner.success
        rescue ex : ArgumentError | Socket::Error
          chan.send({ex.message.not_nil!, nil})
        end
      end
    end
  end

  def ip_from_ip138
    self.chan_send_count = chan_send_count + 1

    spawn do
      url = "https://www.ip138.com"
      spinner = new_spinner("Connecting to :status ...")

      spinner.update(status: url.as_title.to_s)
      ip138_url = ""

      spinner.run do
        doc, _code = from_url(url, follow: true)
        ip138_url = doc.css("iframe").first.attribute_by("src")

        spinner.success
      end

      headers = HTTP::Headers{"Origin" => "https://ip.skk.moe"}

      spinner.update(status: ip138_url.as_title.to_s)

      code = 0
      doc = uninitialized Lexbor::Parser

      spinner.run do
        doc, code = from_url("https:#{ip138_url}", headers: headers)

        spinner.success
      end

      if code == 502
        myip = doc.css("body p span.F").first.tag_text[/IP:\s*([0-9.]+)/, 1]
        url = "https://www.ip138.com/iplookup.php?ip=#{myip}"

        spinner.update(status: url.as_title.to_s)

        spinner.run do
          doc, _code = from_url(url, headers: headers)

          output = String.build do |io|
            doc.css("div.table-box>table>tbody tr").each { |x| io << x.tag_text }
          end

          chan.send({output.squeeze('\n'), nil})

          spinner.success
        end
      else
        chan.send({doc.css("body p").first.tag_text.strip, nil})
      end
    rescue ex : ArgumentError | Socket::Error
      chan.send({ex.message.not_nil!, nil})
    end
  end

  def process
    detail_chan = Channel(String).new
    details_ip_urls = [] of String
    spinner = new_spinner("Connecting to :status： ...")

    chan_send_count.times do
      select
      when value = chan.receive
        ipinfo, ip = value

        STDERR.puts ipinfo

        if !ip.nil?
          self.detail_chan_send_count = detail_chan_send_count() + 1

          spawn do
            details_ip_url = "https://www.ipshudi.com/#{ip}.htm"
            details_ip_urls << details_ip_url.as_title.to_s

            spinner.update(status: "#{details_ip_urls.join(" ")}")

            spinner.run do
              doc, _code = from_url(details_ip_url)

              output = String.build do |io|
                doc.css("div.ft>table>tbody>tr>td").each do |x|
                  io << x.tag_text
                end
              end

              detail_chan.send(output.squeeze('\n'))

              spinner.success
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
