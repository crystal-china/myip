require "./spec_helper"
require "http/server"

class TestableMyip < Myip
  def fetch_url(url, *, follow = false, headers = HTTP::Headers.new)
    from_url(url, follow: follow, headers: headers)
  end

  def format_body(body : String)
    format_raw_body(body)
  end

  def parse_dyndns(body : String)
    parse_dyndns_body(body)
  end

  def fetch_http(url : String, *, connect_timeout : Time::Span, read_timeout : Time::Span)
    http_get(url, connect_timeout: connect_timeout, read_timeout: read_timeout)
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

  it "pretty-prints JSON responses" do
    TestableMyip.new.format_body(%({"ip":"1.2.3.4","country":"CN"})).should eq(<<-JSON)
      {
        "ip": "1.2.3.4",
        "country": "CN"
      }
      JSON
  end

  it "keeps non-JSON responses as plain text" do
    TestableMyip.new.format_body("  1.2.3.4\n").should eq("1.2.3.4")
  end

  it "extracts the IP address from a Dyn CheckIP HTML response" do
    body = "<html><head><title>Current IP Check</title></head><body>Current IP Address: 1.2.3.4</body></html>"
    TestableMyip.new.parse_dyndns(body).should eq("1.2.3.4")
  end

  it "times out while waiting for an HTTP response" do
    server = HTTP::Server.new do |context|
      sleep 100.milliseconds
      context.response.print("late response")
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }

    begin
      expect_raises(IO::TimeoutError) do
        TestableMyip.new.fetch_http(
          "http://127.0.0.1:#{address.port}",
          connect_timeout: 1.second,
          read_timeout: 10.milliseconds
        )
      end
    ensure
      server.close
    end
  end
end
