require "crystagiri"
require "./myip/*"

chan = Channel(String).new

begin
  doc = Crystagiri::HTML.from_url "https://getip.pub"

  iframe_urls = [] of String
  iframe = doc.where_tag("iframe") { |tag| iframe_urls << tag.node.attributes["src"].content }

  iframe_urls.each_with_index do |url, i|
    spawn do
      chan.send Crystagiri::HTML.from_url(url).content.chomp
    end
  end
rescue OpenSSL::SSL::Error
  STDERR.puts "Can't visit https://getip.pub"
  exit
end

3.times do |i|
  ip = chan.receive

  case i
  when 0
    STDERR.puts ip
  when 1
    STDERR.puts "外网 IP：#{ip}"
  when 2
    STDERR.puts "翻墙 IP：#{ip}"
  end
end
