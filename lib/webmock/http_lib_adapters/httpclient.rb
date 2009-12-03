if defined?(HTTPClient)

  class HTTPClient

    def do_get_block_with_webmock(req, proxy, conn, &block)
      uri = Addressable::URI.heuristic_parse(req.header.request_uri.to_s)
      uri.query_values = req.header.request_query if req.header.request_query
      uri = uri.omit(:userinfo)

      auth = www_auth.basic_auth
      auth.challenge(req.header.request_uri, nil)

      headers = Hash[req.header.all]

      if auth_cred = auth.get(req)
        if auth.scheme == 'Basic'
          userinfo = WebMock::Util::Headers.decode_userinfo_from_header(auth_cred)
          userinfo = WebMock::Util::URI.encode_unsafe_chars_in_userinfo(userinfo)
          headers.reject! {|k,v| k =~ /[Aa]uthorization/ && v =~ /^Basic / } #we added it to url userinfo          
        else
          userinfo = ""
        end

        uri.userinfo = userinfo
      end

      request_signature = WebMock::RequestSignature.new(
        req.header.request_method.downcase.to_sym,
        uri.to_s,
        :body => req.body.content,
        :headers => Hash[req.header.all]
      )

      WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)

      if WebMock.registered_request?(request_signature)
        webmock_response = WebMock.response_for_request(request_signature)
        response = build_httpclient_response(webmock_response, &block)
        conn.push(response)
      elsif WebMock.net_connect_allowed?
        do_get_block_without_webmock(req, proxy, conn, &block)
      else
        message = "Real HTTP connections are disabled. Unregistered request: #{request_signature}"
        raise WebMock::NetConnectNotAllowedError, message
      end
    end
    alias_method :do_get_block_without_webmock, :do_get_block
    alias_method :do_get_block, :do_get_block_with_webmock


    def build_httpclient_response(webmock_response, &block)
      response = HTTP::Message.new_response("")
      response.header.init_response(webmock_response.status)
      response.body =  HTTP::Message::Body.new
      response.body.init_response(webmock_response.body)

      webmock_response.headers.to_a.each { |name, value| response.header.set(name, value) }

      webmock_response.raise_error_if_any

      yield response if block_given?

      response
    end
  end

end
