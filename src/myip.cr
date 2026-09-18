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
  CONNECT_TIMEOUT = 5.seconds
  READ_TIMEOUT    = 8.seconds

  getter chan = Channel(Tuple(String, String?)).new
  getter error_chan = Channel(String).new
  property chan_send_count : Int32 = 0

  def ip_from_ifconfig_io
    ip_from_raw("ifconfig.io", "https://ifconfig.io/ip")
  end

  def ip_from_ifconfig_co
    ip_from_raw("ifconfig.co", "https://ifconfig.co/json")
  end

  def ip_from_ifconfig_me
    ip_from_raw("ifconfig.me", "https://ifconfig.me/all.json")
  end

  def ip_from_icanhazip
    ip_from_raw("icanhazip", "https://icanhazip.com")
  end

  def ip_from_httpbin
    ip_from_raw("httpbin.org", "https://httpbin.org/ip")
  end

  def ip_from_dyndns
    self.chan_send_count = chan_send_count() + 1
    spawn do
      url = "http://checkip.dyndns.org"
      spinner = Term::Spinner.new(":spinner Connecting to #{url.as_title} ...", format: :dots, interval: 0.2.seconds)

      spinner.run do
        response = http_get(url)
        unless response.success?
          raise ArgumentError.new "Host #{url} returned #{response.status_code}"
        end

        result = parse_dyndns_body(response.body)
        spinner.success
        chan.send({"Dyn CheckIP", result})
      rescue ex : ArgumentError | IO::Error | OpenSSL::SSL::Error | Lexbor::Error
        error_chan.send("Dyn CheckIP failed: #{ex.message}")
      end
    end
  end

  def ip_from_ipify(ip_version : Int32 = 4)
    url = case ip_version
          when 4
            "https://api.ipify.org"
          when 6
            "https://api6.ipify.org"
          else
            raise ArgumentError.new "Unsupported IP version: #{ip_version}"
          end

    ip_from_raw("ipify IPv#{ip_version}", url)
  end

  def ip_from_cf
    ip_from_raw("Cloudflare trace", "https://cloudflare.com/cdn-cgi/trace")
  end

  def ip_from_ident
    ip_from_raw("ident.me", "https://ident.me/json")
  end

  def ip_from_aws
    ip_from_raw("AWS CheckIP", "https://checkip.amazonaws.com/")
  end

  def ip_from_akamai
    ip_from_raw("Akamai", "https://whatismyip.akamai.com/")
  end

  def ip_from_ip_sb
    ip_from_raw("ip.sb", "https://api.ip.sb/geoip")
  end

  def ip_from_ip111
    spinner = Term::Spinner::Multi.new(":spinner", format: :dots, interval: 0.2.seconds)
    ip111_url = "https://ip111.cn"
    homepage_spinner = spinner.register("Connecting to #{ip111_url.as_title} ...")

    homepage_doc = nil.as(Lexbor::Parser?)
    homepage_spinner.run do
      doc = from_url(ip111_url, follow: true, headers: HTTP::Headers{
        "User-Agent" => "curl/7.88.1",
        "Accept"     => "*/*",
      })
      homepage_doc = doc

      homepage_spinner.success
    end

    raise ArgumentError.new "ip111: homepage response was not parsed" unless homepage_doc
    doc = homepage_doc.as(Lexbor::Parser)

    title_node = doc.css(".card-header").first? ||
                 raise ArgumentError.new "ip111: .card-header not found"

    ipinfo_node = doc.css(".card-body p").first? ||
                  raise ArgumentError.new "ip111: .card-body p not found"

    title = title_node.tag_text.strip
    ipinfo = ipinfo_node.tag_text.strip

    self.chan_send_count = chan_send_count() + 1
    spawn { chan.send({title, ipinfo}) }

    # 这里只能用 each, 没有 map, 因为 doc.nodes("iframe") 是一个 Iterator::SelectIterator 对象
    doc.nodes("iframe").each do |node|
      self.chan_send_count = chan_send_count() + 1
      url = node.attribute_by("src") || raise ArgumentError.new "ip111: iframe src not found"
      raise ArgumentError.new "ip111: iframe src is empty" if url.empty?

      spawn do
        iframe_spinner = spinner.register("Connecting to #{url.as_title} ...")
        headers = HTTP::Headers{
          "Referer" => "https://ip111.cn/",
        }

        iframe_spinner.run do
          doc = from_url(url, headers: headers)
          body_node = doc.body || raise ArgumentError.new "ip111 iframe: body not found"

          ipinfo = body_node.tag_text.strip

          # 这里的 parse title 涉及一些 IO 等待情况（非一蹴而就）
          # 如果在 spawn 外面解析 title, 然后传递 title 到 spawn 代码块里面，
          # 此时会涉及 "共享变量" 的经典问题，即： spawn 内部共享外面的变量
          # 可能会出现，spawn 内部看到的外部的 url 是两个相同的 url.
          parent = node.parent || raise ArgumentError.new "ip111: iframe parent not found"

          grandparent = parent.parent || raise ArgumentError.new "ip111: iframe grandparent not found"

          container = grandparent.parent || raise ArgumentError.new "ip111: iframe container not found"

          title_node = container.css(".card-header").first? ||
                       raise ArgumentError.new "ip111: iframe .card-header not found"

          title = title_node.tag_text.strip
          iframe_spinner.success
          chan.send({title, ipinfo})
        end
      rescue ex : ArgumentError | IO::Error | OpenSSL::SSL::Error | URI::Error | Lexbor::Error
        error_chan.send("ip111 failed: #{ex.message}")
      end
    end
  end

  def ip_from_ip138
    self.chan_send_count = chan_send_count() + 1
    spinner = Term::Spinner::Multi.new(":spinner", format: :dots, interval: 0.2.seconds)
    spawn do
      # IP138 首页，用于查找实际显示 IP 信息的 iframe。
      url = "https://www.ip138.com"
      sp = spinner.register("Connecting to #{url.as_title} ...")

      # 首页 iframe 的 src，当前通常是 //数字.ip138.com/ 形式。
      iframe_src = nil.as(String?)
      sp.run do
        doc = from_url(url, follow: true)
        iframe = doc.css("iframe").first? || raise ArgumentError.new "ip138: iframe not found"

        src = iframe.attribute_by("src") || raise ArgumentError.new "ip138: iframe src not found"
        raise ArgumentError.new "ip138: iframe src is empty" if src.empty?
        iframe_src = src

        sp.success
      end

      raise ArgumentError.new "ip138: iframe src was not parsed" unless iframe_src
      ip138_url = iframe_src.as(String)

      # 转成完整 URL，同时兼容协议相对、绝对以及普通相对地址。
      #
      # URI.parse("https://www.ip138.com")
      #   .resolve("//2026.ip138.com/")
      #   .to_s
      #
      # 结果是：https://2026.ip138.com/
      ip138_url = URI.parse(url).resolve(ip138_url).to_s

      ip138_host = URI.parse(ip138_url).host ||
                   raise ArgumentError.new "ip138: iframe URL has no host: #{ip138_url}"

      headers = HTTP::Headers{
        "Accept"         => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Host"           => ip138_host,
        "Referer"        => url,
        "Sec-Fetch-Dest" => "iframe",
        "Sec-Fetch-Mode" => "navigate",
        "Sec-Fetch-Site" => "same-site",
        "User-Agent"     => "Mozilla/5.0 (X11; Linux x86_64; rv:145.0) Gecko/20100101 Firefox/145.0",
      }

      sp1 = spinner.register("Connecting to #{ip138_url.as_title} ...")

      iframe_doc = nil.as(Lexbor::Parser?)
      sp1.run do
        doc = from_url(ip138_url, headers: headers)
        iframe_doc = doc

        sp1.success
      end

      raise ArgumentError.new "ip138: iframe response was not parsed" unless iframe_doc
      doc = iframe_doc.as(Lexbor::Parser)
      body_node = doc.body || raise ArgumentError.new "ip138: iframe body not found"

      body = body_node.tag_text.strip
      first_line = body.lines.first? || raise ArgumentError.new "ip138: iframe body is empty"

      chan.send({"ip138.com", first_line.strip})
    rescue ex : ArgumentError | IO::Error | OpenSSL::SSL::Error | URI::Error | Lexbor::Error
      error_chan.send("ip138 failed: #{ex.message}")
    end
  end

  def process
    results = [] of Tuple(String, String?)
    errors = [] of String
    failed = false

    chan_send_count.times do
      select
      when value = chan.receive
        results << value
      when message = error_chan.receive
        errors << message
        failed = true
      when timeout 30.seconds
        STDERR.puts "Timeout, check your network connection!"
        exit 1
      end
    end

    results.each do |label, value|
      value ? STDOUT.puts("#{label}: #{value}") : STDOUT.puts(label)
    end
    errors.each { |message| STDERR.puts message }

    exit 1 if failed
  end

  private def ip_from_raw(name : String, url : String)
    self.chan_send_count = chan_send_count() + 1
    spawn do
      spinner = Term::Spinner.new(":spinner Connecting to #{url.as_title} ...", format: :dots, interval: 0.2.seconds)

      spinner.run do
        response = http_get(url)
        unless response.success?
          raise ArgumentError.new "Host #{url} returned #{response.status_code}"
        end

        result = format_raw_body(response.body)
        spinner.success
        chan.send({name, result})
      rescue ex : ArgumentError | IO::Error | OpenSSL::SSL::Error
        error_chan.send("#{name} failed: #{ex.message}")
      end
    end
  end

  private def format_raw_body(body : String) : String
    stripped_body = body.strip
    begin
      JSON.parse(stripped_body).to_pretty_json
    rescue JSON::ParseException
      stripped_body
    end
  end

  private def parse_dyndns_body(body : String) : String
    body_node = Lexbor::Parser.new(body).body ||
                raise ArgumentError.new "Dyn CheckIP response has no body"

    text = body_node.tag_text.strip
    match = text.match(/Current IP Address:\s*([0-9a-fA-F:.]+)/)
    raise ArgumentError.new "Unable to parse Dyn CheckIP response" unless match

    match[1]
  end

  private def http_get(url : String, headers = HTTP::Headers.new, *, connect_timeout = CONNECT_TIMEOUT, read_timeout = READ_TIMEOUT) : HTTP::Client::Response
    uri = URI.parse(url)
    HTTP::Client.new(uri) do |client|
      client.connect_timeout = connect_timeout
      client.read_timeout = read_timeout
      client.get(uri.request_target, headers: headers)
    end
  end

  private def from_url(url : String, *, follow : Bool = false, headers = HTTP::Headers.new, redirects_left : Int32 = 5) : Lexbor::Parser
    response = http_get(url, headers)
    if response.status_code == 200
      Lexbor::Parser.new(response.body)
    elsif follow && response.status_code.in?(301, 302, 303, 307, 308)
      raise ArgumentError.new "Too many redirects while visiting #{url}" if redirects_left <= 0

      location = response.headers["Location"]?
      raise ArgumentError.new "Host #{url} returned #{response.status_code} without a Location header" unless location

      redirect_url = URI.parse(url).resolve(location).to_s
      redirect_headers = headers.dup
      redirect_headers.delete("Host")

      from_url redirect_url,
        follow: true,
        headers: redirect_headers,
        redirects_left: redirects_left - 1
    else
      raise ArgumentError.new "Host #{url} returned #{response.status_code}"
    end
  rescue e : Socket::Error
    # e.inspect_with_backtrace(STDERR)
    raise Socket::Error.new "Visit #{url} failed: #{e.message}"
  end
end
