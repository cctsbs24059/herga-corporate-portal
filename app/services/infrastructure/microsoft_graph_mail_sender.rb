# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'openssl'

module Infrastructure
  class MicrosoftGraphMailSender
    class ConfigurationError < StandardError; end
    class AuthenticationError < StandardError; end
    class SubmissionError < StandardError; end

    TOKEN_URL_BASE = 'https://login.microsoftonline.com'.freeze
    GRAPH_URL_BASE = 'https://graph.microsoft.com'.freeze
    SENDER = 'info@hergafarmsgroup.com'.freeze

    def deliver!(to:, subject:, body:)
      validate_configuration!
      token = acquire_token!
      uri = URI("#{GRAPH_URL_BASE}/v1.0/users/#{URI.encode_www_form_component(sender)}/sendMail")
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{token}"
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate({
        message: {
          subject: subject,
          body: { contentType: 'Text', content: body },
          toRecipients: [{ emailAddress: { address: to } }]
        },
        saveToSentItems: true
      })
      response = http_request(uri, request)
      return true if response.code.to_i == 202

      raise SubmissionError, "Graph sendMail HTTP #{response.code}: #{safe_error(response.body)}"
    end

    private

    def sender
      ENV.fetch('HERGA_M365_SENDER', SENDER)
    end

    def validate_configuration!
      %w[HERGA_M365_TENANT_ID HERGA_M365_CLIENT_ID HERGA_M365_CLIENT_SECRET].each do |name|
        raise ConfigurationError, "Missing #{name}" if ENV[name].to_s.strip.empty?
      end
      raise ConfigurationError, 'HERGA_M365_SENDER must be info@hergafarmsgroup.com' unless sender.casecmp?(SENDER)
    end

    def acquire_token!
      tenant = ENV.fetch('HERGA_M365_TENANT_ID')
      raise ConfigurationError, 'Invalid tenant ID' unless tenant.match?(/\A[0-9a-fA-F-]{36}\z/)
      uri = URI("#{TOKEN_URL_BASE}/#{tenant}/oauth2/v2.0/token")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(
        'client_id' => ENV.fetch('HERGA_M365_CLIENT_ID'),
        'client_secret' => ENV.fetch('HERGA_M365_CLIENT_SECRET'),
        'scope' => 'https://graph.microsoft.com/.default',
        'grant_type' => 'client_credentials'
      )
      response = http_request(uri, request)
      raise AuthenticationError, "Token request HTTP #{response.code}" unless response.code.to_i == 200
      token = JSON.parse(response.body).fetch('access_token')
      raise AuthenticationError, 'Empty access token' if token.to_s.empty?
      token
    rescue JSON::ParserError, KeyError
      raise AuthenticationError, 'Malformed token response'
    end

    def http_request(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 25,
                      verify_mode: OpenSSL::SSL::VERIFY_PEER) do |http|
        http.request(request)
      end
    end

    def safe_error(body)
      parsed = JSON.parse(body.to_s)
      parsed.dig('error', 'code').to_s[0, 80]
    rescue JSON::ParserError, TypeError
      'Request rejected'
    end
  end
end
