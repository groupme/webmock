require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'webmock_shared'
require 'ostruct'
require 'net_http_spec_helper'
require 'net_http_shared'

include NetHTTPSpecHelper

describe "Webmock with Net:HTTP" do
  it_should_behave_like "WebMock"

  let(:port){ WebMockServer.instance.port }

  it "should still have const Get defined on replaced Net::HTTP" do
    Object.const_get("Net").const_get("HTTP").const_defined?("Get").should be_true
  end

  it "should work with block provided" do
    stub_http_request(:get, "www.example.com").to_return(:body => "abc"*100000)
    Net::HTTP.start("www.example.com") { |query| query.get("/") }.body.should == "abc"*100000
  end

  it "should handle multiple values for the same response header" do
    stub_http_request(:get, "www.example.com").to_return(:headers => { 'Set-Cookie' => ['foo=bar', 'bar=bazz'] })
    response = Net::HTTP.get_response(URI.parse("http://www.example.com/"))
    response.get_fields('Set-Cookie').should == ['bar=bazz', 'foo=bar']
  end

  it "should yield block on response" do
    stub_http_request(:get, "www.example.com").to_return(:body => "abc")
    response_body = ""
    http_request(:get, "http://www.example.com/") do |response|
      response_body = response.body
    end
    response_body.should == "abc"
  end

  it "should handle Net::HTTP::Post#body" do
    stub_http_request(:post, "www.example.com").with(:body => "my_params").to_return(:body => "abc")
    req = Net::HTTP::Post.new("/")
    req.body = "my_params"
    Net::HTTP.start("www.example.com") { |http| http.request(req)}.body.should == "abc"
  end

  it "should handle Net::HTTP::Post#body_stream" do
    stub_http_request(:post, "www.example.com").with(:body => "my_params").to_return(:body => "abc")
    req = Net::HTTP::Post.new("/")
    req.body_stream = StringIO.new("my_params")
    Net::HTTP.start("www.example.com") { |http| http.request(req)}.body.should == "abc"
  end

  it "should behave like Net::HTTP and raise error if both request body and body argument are set" do
    stub_http_request(:post, "www.example.com").with(:body => "my_params").to_return(:body => "abc")
    req = Net::HTTP::Post.new("/")
    req.body = "my_params"
    lambda {
      Net::HTTP.start("www.example.com") { |http| http.request(req, "my_params")}
    }.should raise_error("both of body argument and HTTPRequest#body set")
  end

  it "should return a Net::ReadAdapter from response.body when a stubbed request is made with a block and #read_body" do
    WebMock.stub_request(:get, 'http://example.com/').to_return(:body => "the body")
    response = Net::HTTP.new('example.com', 80).request_get('/') { |r| r.read_body { } }
    response.body.should be_a(Net::ReadAdapter)
  end

  it "should have request 1 time executed in registry after 1 real request", :net_connect => true do
    WebMock.allow_net_connect!
    http = Net::HTTP.new('localhost', port)
    http.get('/') {}
    WebMock::RequestRegistry.instance.requested_signatures.hash.size.should == 1
    WebMock::RequestRegistry.instance.requested_signatures.hash.values.first.should == 1
  end

  describe "connecting on Net::HTTP.start" do
    before(:each) do
      @http = Net::HTTP.new('www.google.com', 443)
      @http.use_ssl = true
      @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    describe "when net http is allowed" do
      it "should not connect to the server until the request", :net_connect => true do
        WebMock.allow_net_connect!
        @http.start {|conn|
          conn.peer_cert.should be_nil
        }
      end

      it "should connect to the server on start", :net_connect => true do
        WebMock.allow_net_connect!(:net_http_connect_on_start => true)
        @http.start {|conn|
          cert = OpenSSL::X509::Certificate.new conn.peer_cert
          cert.should be_a(OpenSSL::X509::Certificate)
        }
      end

    end

    describe "when net http is disabled and allowed only for some hosts" do
      it "should not connect to the server until the request", :net_connect => true do
        WebMock.disable_net_connect!(:allow => "www.google.com")
        @http.start {|conn|
          conn.peer_cert.should be_nil
        }
      end

      it "should connect to the server on start", :net_connect => true do
        WebMock.disable_net_connect!(:allow => "www.google.com", :net_http_connect_on_start => true)
        @http.start {|conn|
          cert = OpenSSL::X509::Certificate.new conn.peer_cert
          cert.should be_a(OpenSSL::X509::Certificate)
        }
      end
    end
  end

  describe "when net_http_connect_on_start is true" do
    before(:each) do
      WebMock.allow_net_connect!(:net_http_connect_on_start => true)
    end
    it_should_behave_like "Net::HTTP"
  end

  describe "when net_http_connect_on_start is false" do
    before(:each) do
      WebMock.allow_net_connect!(:net_http_connect_on_start => false)
    end
    it_should_behave_like "Net::HTTP"
  end

  describe 'after_request callback support', :net_connect => true do
    let(:expected_body_regex) { /hello world/ }

    before(:each) do
      WebMock.allow_net_connect!
      @callback_invocation_count = 0
      WebMock.after_request do |_, response|
        @callback_invocation_count += 1
        @callback_response = response
      end
    end

    after(:each) do
      WebMock.reset_callbacks
    end

    def perform_get_with_returning_block
      http_request(:get, "http://localhost:#{port}/") do |response|
        return response.body
      end
    end

    it "should support the after_request callback on an request with block and read_body" do
      response_body = ''
      http_request(:get, "http://localhost:#{port}/") do |response|
        response.read_body { |fragment| response_body << fragment }
      end
      response_body.should =~ expected_body_regex

      @callback_response.body.should == response_body
    end

    it "should support the after_request callback on a request with a returning block" do
      response_body = perform_get_with_returning_block
      response_body.should =~ expected_body_regex
      @callback_response.should be_instance_of(WebMock::Response)
      @callback_response.body.should == response_body
    end

    it "should only invoke the after_request callback once, even for a recursive post request" do
      Net::HTTP.new('localhost', port).post('/', nil)
      @callback_invocation_count.should == 1
    end
  end
end
