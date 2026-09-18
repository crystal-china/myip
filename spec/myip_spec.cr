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
      doc = TestableMyip.new.fetch_url(
        "http://#{expected_host}/redirect",
        follow: true,
        headers: HTTP::Headers{"Host" => "stale.example"}
      )

      doc.body!.tag_text.should contain("redirected")
    ensure
      server.close
    end
  end

  it "rejects a non-2xx response" do
    server = HTTP::Server.new do |context|
      context.response.status = HTTP::Status::BAD_GATEWAY
      context.response.print("<html><body>bad gateway</body></html>")
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }

    begin
      url = "http://127.0.0.1:#{address.port}"
      expect_raises(ArgumentError, "Host #{url} returned 502") do
        TestableMyip.new.fetch_url(url)
      end
    ensure
      server.close
    end
  end

  it "rejects a redirect without a Location header" do
    server = HTTP::Server.new do |context|
      context.response.status = HTTP::Status::MOVED_PERMANENTLY
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }

    begin
      url = "http://127.0.0.1:#{address.port}"
      expect_raises(ArgumentError, "Host #{url} returned 301 without a Location header") do
        TestableMyip.new.fetch_url(url, follow: true)
      end
    ensure
      server.close
    end
  end

  it "rejects redirects beyond the configured limit" do
    server = HTTP::Server.new do |context|
      context.response.status = HTTP::Status::FOUND
      context.response.headers["Location"] = "/loop"
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }

    begin
      url = "http://127.0.0.1:#{address.port}/loop"
      expect_raises(ArgumentError, "Too many redirects while visiting #{url}") do
        TestableMyip.new.fetch_url(url, follow: true)
      end
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

  it "extracts an IPv6 address from a Dyn CheckIP HTML response" do
    body = "<html><body>Current IP Address: 2001:db8::1</body></html>"
    TestableMyip.new.parse_dyndns(body).should eq("2001:db8::1")
  end

  it "reports an invalid Dyn CheckIP HTML response" do
    expect_raises(ArgumentError, "Unable to parse Dyn CheckIP response") do
      TestableMyip.new.parse_dyndns("<html><body>unexpected response</body></html>")
    end
  end

  it "rejects an invalid Dyn CheckIP address" do
    expect_raises(ArgumentError, "Unable to parse Dyn CheckIP response") do
      TestableMyip.new.parse_dyndns("<html><body>Current IP Address: 999.2.3.4</body></html>")
    end
  end

  it "returns 1 for an unknown command" do
    output = IO::Memory.new
    error = IO::Memory.new
    cli = File.expand_path("../src/cli.cr", __DIR__)

    status = Process.run(
      "crystal",
      ["run", cli, "--", "unknown"],
      output: output,
      error: error
    )

    status.exit_code.should eq(1)
    output.to_s.should be_empty
    error.to_s.should contain("Usage:")
  end

  it "returns 1 for an invalid option" do
    output = IO::Memory.new
    error = IO::Memory.new
    cli = File.expand_path("../src/cli.cr", __DIR__)

    status = Process.run(
      "crystal",
      ["run", cli, "--", "--bad"],
      output: output,
      error: error
    )

    status.exit_code.should eq(1)
    output.to_s.should be_empty
    error.to_s.should start_with("Invalid option: --bad")
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
