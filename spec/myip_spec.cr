require "./spec_helper"
require "http/server"

class TestableMyip < Myip
  def fetch_url(url, *, follow = false, headers = HTTP::Headers.new)
    from_url(url, follow: follow, headers: headers)
  end
end

describe Myip do
  it "works" do
    false.should eq(false)
  end

  it "starts a spinner on Crystal's current execution context" do
    spinner = Term::Spinner.new(interval: 1.millisecond)

    spinner.run do
      spinner.success
    end

    spinner.done?.should be_true
  end

  it "follows redirects with the redirected host header" do
    expected_host = ""
    server = HTTP::Server.new do |context|
      case context.request.path
      when "/redirect"
        context.response.status = HTTP::Status::MOVED_PERMANENTLY
        context.response.headers["Location"] = "/final"
      when "/final"
        context.request.headers["Host"].should eq(expected_host)
        context.response.print("<html><body>redirected</body></html>")
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    expected_host = "127.0.0.1:#{address.port}"
    spawn { server.listen }

    begin
      doc, status = TestableMyip.new.fetch_url(
        "http://#{expected_host}/redirect",
        follow: true,
        headers: HTTP::Headers{"Host" => "stale.example"}
      )

      status.should eq(200)
      doc.body!.tag_text.should contain("redirected")
    ensure
      server.close
    end
  end
end
