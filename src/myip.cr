require "crystagiri"
require "./myip/*"

chan = Channel(Tuple(String, String)).new

begin
  doc = Crystagiri::HTML.from_url "https://getip.pub"

  iframe = doc.where_tag("iframe") do |tag|
    spawn do
      title = tag.node.parent.try(&.parent).not_nil!.xpath_node("td").not_nil!.text
      url = tag.node.attributes["src"].content
      ip = Crystagiri::HTML.from_url(url).content.chomp

      chan.send({title, ip})
    rescue OpenSSL::SSL::Error
      STDERR.puts "visit #{url} failed"
      exit
    end
  end
rescue OpenSSL::SSL::Error
  STDERR.puts "visit http://getip.pub failed"
  exit
end

iframe.size.times do |i|
  title, ip = chan.receive

  STDERR.puts "#{title}：#{ip}"
end
