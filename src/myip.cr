require "crystagiri"

doc = Crystagiri::HTML.from_url "https://getip.pub"

iframe_urls = [] of String
iframe = doc.where_tag("iframe") { |tag| iframe_urls << tag.node.attributes["src"].content }

iframe_urls.each_with_index do |url, i|
  ip = Crystagiri::HTML.from_url(url).content

  case i
  when 0
    puts ip
  when 1
    puts "外网: #{ip}"
  when 2
    puts "翻墙: #{ip}"
  end
end
