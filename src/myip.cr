require "crystagiri"
require "./myip/*"

chan = Channel(Tuple(String, String)).new

spawn do
  doc = Crystagiri::HTML.from_url "http://www.ip138.com", follow: true
  ip138_url = doc.at_css("iframe").not_nil!.node.attributes["src"].content
  doc = Crystagiri::HTML.from_url "http:#{ip138_url}"

  chan.send({"ip138.com：", doc.at_css("body p").not_nil!.content.strip})
rescue Socket::Error | OpenSSL::SSL::Error
  STDERR.puts "visit http://www.ip138.com failed, please check internet connection."
  exit
end

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
rescue Socket::Error | OpenSSL::SSL::Error
  STDERR.puts "visit http://getip.pub failed, please check internet connection."
  exit
end

title = doc.at_css(".card-header").not_nil!.content.strip
ip = doc.at_css(".card-body p").not_nil!.content.strip

STDERR.puts "ip111.cn：#{title}：#{ip}"

3.times do |i|
  select
  when value = chan.receive
    title, ip = value

    STDERR.puts "#{title}#{ip}"
  when timeout 5.seconds
    STDERR.puts "Timeout!"
    exit
  end
end
