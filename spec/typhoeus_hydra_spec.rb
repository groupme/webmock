require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'webmock_shared'

unless RUBY_PLATFORM =~ /java/
  require 'typhoeus_hydra_spec_helper'

  describe "Webmock with Typhoeus::Hydra" do
    include TyphoeusHydraSpecHelper

    it_should_behave_like "WebMock"

    describe "Typhoeus::Hydra features" do
      before(:each) do
        WebMock.disable_net_connect!
        WebMock.reset!
      end

      describe "callbacks" do
        before(:each) do
          @hydra = Typhoeus::Hydra.new
          @request = Typhoeus::Request.new("http://example.com")
        end

        it "should call on_complete with 2xx response" do
          body = "on_success fired"
          stub_request(:any, "example.com").to_return(:body => body)

          test = nil
          @hydra.on_complete do |c|
            test = c.body
          end
          @hydra.queue @request
          @hydra.run
          test.should == body
        end

        it "should call on_complete with 5xx response" do
          response_code = 599
          stub_request(:any, "example.com").to_return(:status => [response_code, "Server On Fire"])

          test = nil
          @hydra.on_complete do |c|
            test = c.code
          end
          @hydra.queue @request
          @hydra.run
          test.should == response_code
        end

      end
    end
  end
end
