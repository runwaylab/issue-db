# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/github_app"

describe GitHubApp do
  let(:app_id) { 123 }
  let(:installation_id) { 456 }
  let(:app_key) { File.read("spec/fixtures/fake_private_key.pem") }
  let(:jwt_token) { "mocked_jwt_token" }
  let(:access_token) { "mocked_access_token" }
  let(:mock_client) { instance_double(Octokit::Client) }
  let(:mock_logger) { instance_double(RedactingLogger) }

  # Default rate limit response structure
  let(:default_rate_limit_response) do
    {
      resources: {
        core: { remaining: 5000, used: 0, limit: 5000, reset: (Time.now + 3600).to_i },
        search: { remaining: 30, used: 0, limit: 30, reset: (Time.now + 3600).to_i },
        graphql: { remaining: 5000, used: 0, limit: 5000, reset: (Time.now + 3600).to_i }
      }
    }
  end

  before do
    # Stub environment variables
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("GH_APP_ID").and_return(app_id.to_s)
    allow(ENV).to receive(:fetch).with("GH_APP_INSTALLATION_ID").and_return(installation_id.to_s)
    allow(ENV).to receive(:fetch).with("GH_APP_KEY").and_return(app_key)
    allow(ENV).to receive(:fetch).with("GH_APP_LOG_LEVEL", "INFO").and_return("INFO")
    allow(ENV).to receive(:fetch).with("GH_APP_SLEEP", 3).and_return("3")
    allow(ENV).to receive(:fetch).with("GH_APP_RETRIES", 10).and_return("10")
    allow(ENV).to receive(:fetch).with("GH_APP_EXPONENTIAL_BACKOFF", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("GH_APP_ALGO", "RS256").and_return("RS256")

    # Stub logger methods to avoid output during tests
    allow(mock_logger).to receive(:debug)
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:warn)
    allow(mock_logger).to receive(:error)

    # Stub RedactingLogger creation
    allow(RedactingLogger).to receive(:new).and_return(mock_logger)

    # Stub Octokit client creation and configuration
    allow(Octokit::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:auto_paginate=).with(true)
    allow(mock_client).to receive(:per_page=).with(100)
    allow(mock_client).to receive(:create_app_installation_access_token)
      .with(installation_id)
      .and_return(token: access_token)

    # Stub JWT and Time for consistent testing
    allow(JWT).to receive(:encode).and_return(jwt_token)
    allow(Time).to receive(:now).and_return(Time.at(1640995200)) # Fixed timestamp for consistency
  end

  describe "#initialize" do
    it "initializes with environment variables" do
      github_app = GitHubApp.new

      expect(github_app.instance_variable_get(:@app_id)).to eq(app_id)
      expect(github_app.instance_variable_get(:@installation_id)).to eq(installation_id)
      expect(github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub('\\n', "\n"))
      expect(github_app.instance_variable_get(:@app_algo)).to eq("RS256")
    end

    it "initializes with provided parameters" do
      custom_logger = instance_double(RedactingLogger)
      allow(custom_logger).to receive(:debug)

      github_app = GitHubApp.new(
        log: custom_logger,
        app_id: 999,
        installation_id: 888,
        app_key: app_key,
        app_algo: "RS512"
      )

      expect(github_app.instance_variable_get(:@log)).to eq(custom_logger)
      expect(github_app.instance_variable_get(:@app_id)).to eq(999)
      expect(github_app.instance_variable_get(:@installation_id)).to eq(888)
      expect(github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub('\\n', "\n"))
      expect(github_app.instance_variable_get(:@app_algo)).to eq("RS512")
    end

    it "loads app key from .pem file path" do
      pem_file_path = "spec/fixtures/fake_private_key.pem"
      github_app = GitHubApp.new(
        app_id: 999,
        installation_id: 888,
        app_key: pem_file_path
      )

      expected_key = File.read(pem_file_path)
      expect(github_app.instance_variable_get(:@app_key)).to eq(expected_key)
    end

    it "raises error when app key file doesn't exist" do
      expect {
        GitHubApp.new(
          app_id: 999,
          installation_id: 888,
          app_key: "nonexistent_file.pem"
        )
      }.to raise_error("App key file not found: nonexistent_file.pem")
    end

    it "raises error when app key file is empty" do
      empty_file_path = "spec/fixtures/empty_key.pem"
      File.write(empty_file_path, "")

      begin
        expect {
          GitHubApp.new(
            app_id: 999,
            installation_id: 888,
            app_key: empty_file_path
          )
        }.to raise_error("App key file is empty: #{empty_file_path}")
      ensure
        File.delete(empty_file_path) if File.exist?(empty_file_path)
      end
    end

    it "processes escape sequences in app key string" do
      key_with_escapes = "-----BEGIN RSA PRIVATE KEY-----\\nsome\\nkey\\ndata\\n-----END RSA PRIVATE KEY-----"
      github_app = GitHubApp.new(
        app_id: 999,
        installation_id: 888,
        app_key: key_with_escapes
      )

      expected_key = key_with_escapes.gsub('\\n', "\n")
      expect(github_app.instance_variable_get(:@app_key)).to eq(expected_key)
    end

    it "falls back to environment variables when parameters are not provided" do
      github_app = GitHubApp.new(app_id: 999, installation_id: 888)
      expect(github_app.instance_variable_get(:@app_key)).to eq(app_key.gsub('\\n', "\n"))
    end

    it "raises error when environment variable is missing and no parameter provided" do
      allow(ENV).to receive(:fetch).with("GH_APP_KEY") { raise "environment variable GH_APP_KEY is not set" }

      expect {
        GitHubApp.new(app_id: 999, installation_id: 888)
      }.to raise_error(/environment variable GH_APP_KEY is not set/)
    end

    it "creates default logger when none provided" do
      github_app = GitHubApp.new
      expect(github_app.instance_variable_get(:@log)).to eq(mock_logger)
    end
  end

  describe "#client (private method)" do
    let(:github_app) { GitHubApp.new }

    it "creates a new client when client is nil" do
      expect(github_app.send(:client)).to eq(mock_client)
      expect(mock_client).to have_received(:create_app_installation_access_token).with(installation_id)
    end

    it "creates a new client when token is expired" do
      # Set token refresh time to past expiration
      github_app.instance_variable_set(:@token_refresh_time, Time.now - GitHubApp::TOKEN_EXPIRATION_TIME - 1)

      expect(github_app.send(:client)).to eq(mock_client)
    end

    it "returns cached client when token is not expired" do
      # Set up cached client and recent refresh time
      github_app.instance_variable_set(:@client, mock_client)
      github_app.instance_variable_set(:@token_refresh_time, Time.now)

      # Should not create new client
      expect(Octokit::Client).not_to receive(:new)
      expect(github_app.send(:client)).to eq(mock_client)
    end
  end

  describe "#jwt_token (private method)" do
    let(:github_app) { GitHubApp.new }

    it "generates a JWT token with correct payload" do
      # Allow JWT.encode to be called and return our mock token
      expect(JWT).to receive(:encode).with(
        hash_including(
          iat: kind_of(Integer),
          exp: kind_of(Integer),
          iss: app_id
        ),
        kind_of(OpenSSL::PKey::RSA),
        "RS256"
      ).and_return(jwt_token)

      result = github_app.send(:jwt_token)
      expect(result).to eq(jwt_token)
    end

    it "raises OpenSSL error for invalid RSA private key" do
      invalid_github_app = GitHubApp.new(app_id: 123, app_key: "invalid-key-content")

      # Reset the JWT mock to allow the real method to run
      allow(JWT).to receive(:encode).and_call_original

      expect { invalid_github_app.send(:jwt_token) }.to raise_error(OpenSSL::PKey::RSAError)
    end
  end

  describe "#token_expired? (private method)" do
    let(:github_app) { GitHubApp.new }

    it "returns true when token_refresh_time is nil" do
      github_app.instance_variable_set(:@token_refresh_time, nil)
      expect(github_app.send(:token_expired?)).to be true
    end

    it "returns true when token has expired" do
      github_app.instance_variable_set(:@token_refresh_time, Time.now - GitHubApp::TOKEN_EXPIRATION_TIME - 1)
      expect(github_app.send(:token_expired?)).to be true
    end

    it "returns false when token has not expired" do
      github_app.instance_variable_set(:@token_refresh_time, Time.now)
      expect(github_app.send(:token_expired?)).to be false
    end
  end

  describe "#wait_for_rate_limit!" do
    let(:github_app) { GitHubApp.new }

    before do
      # Mock the client to avoid actual API calls
      allow(github_app).to receive(:client).and_return(mock_client)
    end

    it "fetches rate limit when not cached" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)

      github_app.wait_for_rate_limit!(:core)

      expect(mock_client).to have_received(:get).with("rate_limit")
    end

    it "exits early when rate limit is not hit" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)

      expect(github_app).not_to receive(:sleep)
      github_app.wait_for_rate_limit!(:core)
    end

    it "sleeps when rate limit is hit" do
      rate_limit_hit_response = {
        resources: {
          core: { remaining: 0, used: 5000, limit: 5000, reset: (Time.now + 10).to_i }
        }
      }

      allow(mock_client).to receive(:get).with("rate_limit").and_return(rate_limit_hit_response)
      allow(github_app).to receive(:sleep)

      github_app.wait_for_rate_limit!(:core)

      expect(github_app).to have_received(:sleep)
      expect(mock_logger).to have_received(:info).with(/github rate_limit hit: sleeping for:/)
    end

    it "handles rate limit that resets after refresh" do
      first_response = {
        resources: {
          core: { remaining: 0, used: 5000, limit: 5000, reset: (Time.now - 10).to_i }
        }
      }

      second_response = {
        resources: {
          core: { remaining: 5000, used: 0, limit: 5000, reset: (Time.now + 3600).to_i }
        }
      }

      allow(mock_client).to receive(:get).with("rate_limit").and_return(first_response, second_response)

      expect { github_app.wait_for_rate_limit!(:core) }.not_to raise_error
    end

    it "updates rate limit count for different types" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)

      github_app.wait_for_rate_limit!(:search)

      # Check that the rate limit was updated
      rate_limit_all = github_app.instance_variable_get(:@rate_limit_all)
      expect(rate_limit_all[:resources][:search][:remaining]).to eq(29) # 30 - 1
    end
  end

  describe "#method_missing" do
    let(:github_app) { GitHubApp.new }

    before do
      allow(github_app).to receive(:client).and_return(mock_client)
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
    end

    it "delegates method calls to the Octokit client with core rate limit" do
      allow(mock_client).to receive(:rate_limit).and_return("mocked_response")

      result = github_app.rate_limit

      expect(result).to eq("mocked_response")
      expect(mock_client).to have_received(:rate_limit)
    end

    it "handles search_ methods with search rate limit type" do
      allow(mock_client).to receive(:search_users).with("test").and_return("search_result")

      result = github_app.search_users("test")

      expect(result).to eq("search_result")
      expect(mock_client).to have_received(:search_users).with("test")
    end

    it "handles POST to /graphql with graphql rate limit type" do
      allow(mock_client).to receive(:post).with("/graphql", { query: "test" }).and_return("graphql_result")

      result = github_app.post("/graphql", { query: "test" })

      expect(result).to eq("graphql_result")
    end

    it "handles regular POST calls with core rate limit type" do
      allow(mock_client).to receive(:post).with("/some/endpoint", { data: "test" }).and_return("post_result")

      result = github_app.post("/some/endpoint", { data: "test" })

      expect(result).to eq("post_result")
    end

    it "handles POST with nil first argument" do
      allow(mock_client).to receive(:post).with(nil).and_return("nil_post_result")

      result = github_app.post(nil)

      expect(result).to eq("nil_post_result")
    end

    it "handles search_issues with secondary rate limit error" do
      secondary_rate_limit_error = StandardError.new("You have exceeded a secondary rate limit")
      allow(mock_client).to receive(:search_issues).with("test").and_raise(secondary_rate_limit_error)
      allow(github_app).to receive(:sleep).with(60)
      # Mock the retry mechanism's sleep as well to prevent actual retries during test
      allow(github_app).to receive(:sleep).with(anything)

      expect {
        github_app.search_issues("test")
      }.to raise_error(StandardError, /exceeded a secondary rate limit/)

      expect(mock_logger).to have_received(:warn).with(/GitHub secondary rate limit hit, sleeping for 60 seconds/)
      expect(github_app).to have_received(:sleep).with(60)
    end

    it "handles search_issues successful call" do
      allow(mock_client).to receive(:search_issues).with("test").and_return("search_issues_result")

      result = github_app.search_issues("test")

      expect(result).to eq("search_issues_result")
    end

    it "retries failed requests" do
      # First call fails, second succeeds
      allow(mock_client).to receive(:user).and_raise(StandardError.new("Network error")).once
      allow(mock_client).to receive(:user).and_return("user_data")

      result = github_app.user

      expect(result).to eq("user_data")
    end

    it "retries with fixed rate (default behavior)" do
      error_count = 0
      allow(mock_client).to receive(:repositories) do
        error_count += 1
        if error_count < 3
          raise StandardError.new("Temporary error")
        else
          "repos_data"
        end
      end
      allow(github_app).to receive(:sleep) # Mock sleep to speed up test

      result = github_app.repositories

      expect(result).to eq("repos_data")
      expect(github_app).to have_received(:sleep).twice # Should have slept 2 times before success
    end

    it "retries with exponential backoff when enabled" do
      allow(ENV).to receive(:fetch).with("GH_APP_EXPONENTIAL_BACKOFF", "false").and_return("true")

      # Create new instance with exponential backoff enabled
      github_app_exponential = GitHubApp.new
      allow(github_app_exponential).to receive(:client).and_return(mock_client)
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)

      error_count = 0
      allow(mock_client).to receive(:organizations) do
        error_count += 1
        if error_count < 3
          raise StandardError.new("Temporary error")
        else
          "orgs_data"
        end
      end
      allow(github_app_exponential).to receive(:sleep) # Mock sleep to speed up test

      result = github_app_exponential.organizations

      expect(result).to eq("orgs_data")
      expect(github_app_exponential).to have_received(:sleep).twice # Should have slept 2 times with exponential backoff
    end

    it "gives up after max retries" do
      allow(mock_client).to receive(:organizations).and_raise(StandardError.new("Persistent error"))
      allow(github_app).to receive(:sleep) # Mock sleep to speed up test

      expect {
        github_app.organizations
      }.to raise_error(StandardError, "Persistent error")

      # Should have slept 9 times (10 attempts total - 1)
      expect(github_app).to have_received(:sleep).exactly(9).times
    end
  end

  describe "#respond_to_missing?" do
    let(:github_app) { GitHubApp.new }

    before do
      allow(github_app).to receive(:client).and_return(mock_client)
    end

    it "returns true when Octokit client responds to method" do
      allow(mock_client).to receive(:respond_to?).with(:rate_limit, false).and_return(true)

      expect(github_app.respond_to?(:rate_limit)).to be true
    end

    it "returns false when Octokit client does not respond to method" do
      allow(mock_client).to receive(:respond_to?).with(:nonexistent_method, false).and_return(false)

      expect(github_app.respond_to?(:nonexistent_method)).to be false
    end

    it "includes private methods when specified" do
      allow(mock_client).to receive(:respond_to?).with(:private_method, true).and_return(true)

      expect(github_app.respond_to?(:private_method, true)).to be true
    end
  end

  describe "integration scenarios" do
    let(:github_app) { GitHubApp.new }

    before do
      allow(github_app).to receive(:client).and_return(mock_client)
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
    end

    it "handles complete workflow: rate limit check, API call, response" do
      allow(mock_client).to receive(:user).and_return({ login: "testuser" })

      result = github_app.user

      expect(result).to eq({ login: "testuser" })
      expect(mock_client).to have_received(:get).with("rate_limit")
      expect(mock_client).to have_received(:user)
    end

    it "handles authentication failure gracefully" do
      auth_error = StandardError.new("Authentication failed")
      allow(mock_client).to receive(:user).and_raise(auth_error)

      expect { github_app.user }.to raise_error(StandardError, "Authentication failed")
    end

    it "properly initializes retry configuration" do
      # Check that retry configuration is set up
      retry_sleep = github_app.instance_variable_get(:@retry_sleep)
      retry_tries = github_app.instance_variable_get(:@retry_tries)
      retry_exponential_backoff = github_app.instance_variable_get(:@retry_exponential_backoff)
      expect(retry_sleep).to eq(3)
      expect(retry_tries).to eq(10)
      expect(retry_exponential_backoff).to be false
    end

    it "allows enabling exponential backoff" do
      allow(ENV).to receive(:fetch).with("GH_APP_EXPONENTIAL_BACKOFF", "false").and_return("true")

      github_app = GitHubApp.new
      retry_exponential_backoff = github_app.instance_variable_get(:@retry_exponential_backoff)
      expect(retry_exponential_backoff).to be true
    end
  end
end
