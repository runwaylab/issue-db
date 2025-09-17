# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/github"

describe IssueDB::Utils::GitHub do
  let(:app_id) { 123 }
  let(:installation_id) { 456 }
  let(:app_key) { File.read("spec/fixtures/fake_private_key.pem") }
  let(:jwt_token) { "mocked_jwt_token" }
  let(:access_token) { "mocked_access_token" }
  let(:mock_client) { instance_double(Octokit::Client) }
  let(:mock_logger) { instance_double(RedactingLogger) }

  let(:default_rate_limit_response) do
    {
      resources: {
        core: { remaining: 5000, used: 0, limit: 5000, reset: (Time.now + 3600).to_i },
        search: { remaining: 30, used: 0, limit: 30, reset: (Time.now + 3600).to_i },
        graphql: { remaining: 5000, used: 0, limit: 5000, reset: (Time.now + 3600).to_i }
      }
    }
  end

  let(:rate_limit_hit_response) do
    {
      resources: {
        core: { remaining: 0, used: 5000, limit: 5000, reset: (Time.now + 10).to_i }
      }
    }
  end

  def stub_environment_vars
    allow(ENV).to receive(:fetch).and_call_original
    %w[GH_APP_ID GH_APP_INSTALLATION_ID GH_APP_KEY GH_APP_LOG_LEVEL
       GH_APP_SLEEP GH_APP_RETRIES GH_APP_EXPONENTIAL_BACKOFF GH_APP_ALGO].each do |var|
      default_value = case var
                      when "GH_APP_ID" then app_id.to_s
                      when "GH_APP_INSTALLATION_ID" then installation_id.to_s
                      when "GH_APP_KEY" then app_key
                      when "GH_APP_LOG_LEVEL" then "INFO"
                      when "GH_APP_SLEEP" then "3"
                      when "GH_APP_RETRIES" then "10"
                      when "GH_APP_EXPONENTIAL_BACKOFF" then "false"
                      when "GH_APP_ALGO" then "RS256"
                      end
      allow(ENV).to receive(:fetch).with(var, anything).and_return(default_value)
      allow(ENV).to receive(:fetch).with(var).and_return(default_value)
    end
  end

  def stub_dependencies
    # Stub logger
    [:debug, :info, :warn, :error].each { |method| allow(mock_logger).to receive(method) }
    allow(RedactingLogger).to receive(:new).and_return(mock_logger)

    # Stub Octokit client
    allow(Octokit::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:auto_paginate=).with(true)
    allow(mock_client).to receive(:per_page=).with(100)
    allow(mock_client).to receive(:create_app_installation_access_token)
      .with(installation_id).and_return(token: access_token)

    # Stub JWT and Time
    allow(JWT).to receive(:encode).and_return(jwt_token)
    allow(Time).to receive(:now).and_return(Time.at(1640995200))
  end

  before do
    stub_environment_vars
    stub_dependencies
  end

  describe "#initialize" do
    it "initializes with environment variables" do
      github = IssueDB::Utils::GitHub.new
      expect(github.instance_variable_get(:@app_id)).to eq(app_id)
      expect(github.instance_variable_get(:@installation_id)).to eq(installation_id)
      expect(github.instance_variable_get(:@app_key)).to eq(app_key.gsub('\\n', "\n"))
      expect(github.instance_variable_get(:@app_algo)).to eq("RS256")
    end

    it "initializes with provided parameters" do
      custom_logger = instance_double(RedactingLogger)
      allow(custom_logger).to receive(:debug)

      github = IssueDB::Utils::GitHub.new(log: custom_logger, app_id: 999, installation_id: 888,
                                 app_key: app_key, app_algo: "RS512")

      expect(github.instance_variable_get(:@log)).to eq(custom_logger)
      expect(github.instance_variable_get(:@app_id)).to eq(999)
      expect(github.instance_variable_get(:@installation_id)).to eq(888)
      expect(github.instance_variable_get(:@app_key)).to eq(app_key.gsub('\\n', "\n"))
      expect(github.instance_variable_get(:@app_algo)).to eq("RS512")
    end

    it "loads app key from .pem file path" do
      pem_file_path = "spec/fixtures/fake_private_key.pem"
      github = IssueDB::Utils::GitHub.new(app_id: 999, installation_id: 888, app_key: pem_file_path)
      expected_key = File.read(pem_file_path)
      expect(github.instance_variable_get(:@app_key)).to eq(expected_key)
    end

    context "error handling" do
      it "raises error when app key file doesn't exist" do
        expect {
          IssueDB::Utils::GitHub.new(app_id: 999, installation_id: 888, app_key: "nonexistent_file.pem")
        }.to raise_error("App key file not found: nonexistent_file.pem")
      end

      it "raises error when app key file is empty" do
        empty_file_path = "spec/fixtures/empty_key.pem"
        File.write(empty_file_path, "")

        begin
          expect {
            IssueDB::Utils::GitHub.new(app_id: 999, installation_id: 888, app_key: empty_file_path)
          }.to raise_error("App key file is empty: #{empty_file_path}")
        ensure
          File.delete(empty_file_path) if File.exist?(empty_file_path)
        end
      end

      it "raises error when environment variable is missing" do
        allow(ENV).to receive(:fetch).with("GH_APP_KEY") { raise "environment variable GH_APP_KEY is not set" }
        expect {
          IssueDB::Utils::GitHub.new(app_id: 999, installation_id: 888)
        }.to raise_error(/environment variable GH_APP_KEY is not set/)
      end
    end

    it "processes escape sequences in app key string" do
      key_with_escapes = "-----BEGIN RSA PRIVATE KEY-----\\nsome\\nkey\\ndata\\n-----END RSA PRIVATE KEY-----"
      github = IssueDB::Utils::GitHub.new(app_id: 999, installation_id: 888, app_key: key_with_escapes)
      expected_key = key_with_escapes.gsub('\\n', "\n")
      expect(github.instance_variable_get(:@app_key)).to eq(expected_key)
    end

    it "falls back to environment variables when parameters are not provided" do
      github = IssueDB::Utils::GitHub.new(app_id: 999, installation_id: 888)
      expect(github.instance_variable_get(:@app_key)).to eq(app_key.gsub('\\n', "\n"))
    end

    it "creates default logger when none provided" do
      github = IssueDB::Utils::GitHub.new
      expect(github.instance_variable_get(:@log)).to eq(mock_logger)
    end
  end

  describe "private methods" do
    let(:github) { IssueDB::Utils::GitHub.new }

    describe "#client" do
      it "creates a new client when client is nil" do
        expect(github.send(:client)).to eq(mock_client)
        expect(mock_client).to have_received(:create_app_installation_access_token).with(installation_id)
      end

      it "creates a new client when token is expired" do
        github.instance_variable_set(:@token_refresh_time, Time.now - IssueDB::Utils::GitHub::TOKEN_EXPIRATION_TIME - 1)
        expect(github.send(:client)).to eq(mock_client)
      end

      it "returns cached client when token is not expired" do
        github.instance_variable_set(:@client, mock_client)
        github.instance_variable_set(:@token_refresh_time, Time.now)
        expect(Octokit::Client).not_to receive(:new)
        expect(github.send(:client)).to eq(mock_client)
      end
    end

    describe "#jwt_token" do
      it "generates a JWT token with correct payload" do
        expect(JWT).to receive(:encode).with(
          hash_including(iat: kind_of(Integer), exp: kind_of(Integer), iss: app_id),
          kind_of(OpenSSL::PKey::RSA), "RS256"
        ).and_return(jwt_token)

        result = github.send(:jwt_token)
        expect(result).to eq(jwt_token)
      end

      it "raises OpenSSL error for invalid RSA private key" do
        invalid_github = IssueDB::Utils::GitHub.new(app_id: 123, app_key: "invalid-key-content")
        allow(JWT).to receive(:encode).and_call_original
        expect { invalid_github.send(:jwt_token) }.to raise_error(OpenSSL::PKey::RSAError)
      end
    end

    describe "#token_expired?" do
      it "returns true when token_refresh_time is nil" do
        github.instance_variable_set(:@token_refresh_time, nil)
        expect(github.send(:token_expired?)).to be true
      end

      it "returns true when token has expired" do
        github.instance_variable_set(:@token_refresh_time, Time.now - IssueDB::Utils::GitHub::TOKEN_EXPIRATION_TIME - 1)
        expect(github.send(:token_expired?)).to be true
      end

      it "returns false when token has not expired" do
        github.instance_variable_set(:@token_refresh_time, Time.now)
        expect(github.send(:token_expired?)).to be false
      end
    end
  end

  describe "#wait_for_rate_limit!" do
    let(:github) { IssueDB::Utils::GitHub.new }

    before do
      allow(github).to receive(:client).and_return(mock_client)
    end

    it "fetches rate limit when not cached" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
      github.wait_for_rate_limit!(:core)
      expect(mock_client).to have_received(:get).with("rate_limit")
    end

    it "exits early when rate limit is not hit" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
      expect(github).not_to receive(:sleep)
      github.wait_for_rate_limit!(:core)
    end

    it "sleeps when rate limit is hit" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(rate_limit_hit_response)
      allow(github).to receive(:sleep)

      github.wait_for_rate_limit!(:core)

      expect(github).to have_received(:sleep)
      expect(mock_logger).to have_received(:info).with(/github rate_limit hit: sleeping for:/)
    end

    it "handles rate limit that resets after refresh" do
      first_response = {
        resources: { core: { remaining: 0, used: 5000, limit: 5000, reset: (Time.now - 10).to_i } }
      }
      second_response = {
        resources: { core: { remaining: 5000, used: 0, limit: 5000, reset: (Time.now + 3600).to_i } }
      }

      allow(mock_client).to receive(:get).with("rate_limit").and_return(first_response, second_response)
      expect { github.wait_for_rate_limit!(:core) }.not_to raise_error
    end

    it "updates rate limit count for different types" do
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
      github.wait_for_rate_limit!(:search)

      rate_limit_all = github.instance_variable_get(:@rate_limit_all)
      expect(rate_limit_all[:resources][:search][:remaining]).to eq(29) # 30 - 1
    end
  end

  describe "#method_missing" do
    let(:github) { IssueDB::Utils::GitHub.new }

    before do
      allow(github).to receive(:client).and_return(mock_client)
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
    end

    it "delegates method calls to the Octokit client with appropriate rate limit types" do
      # Core rate limit
      allow(mock_client).to receive(:rate_limit).and_return("mocked_response")
      result = github.rate_limit
      expect(result).to eq("mocked_response")

      # Search rate limit
      allow(mock_client).to receive(:search_users).with("test").and_return("search_result")
      result = github.search_users("test")
      expect(result).to eq("search_result")

      # GraphQL rate limit
      allow(mock_client).to receive(:post).with("/graphql", { query: "test" }).and_return("graphql_result")
      result = github.post("/graphql", { query: "test" })
      expect(result).to eq("graphql_result")
    end

    it "handles POST with various arguments" do
      allow(mock_client).to receive(:post).with("/some/endpoint", { data: "test" }).and_return("post_result")
      result = github.post("/some/endpoint", { data: "test" })
      expect(result).to eq("post_result")

      allow(mock_client).to receive(:post).with(nil).and_return("nil_post_result")
      result = github.post(nil)
      expect(result).to eq("nil_post_result")
    end

    it "handles search_issues with secondary rate limit error" do
      secondary_rate_limit_error = StandardError.new("You have exceeded a secondary rate limit")
      allow(mock_client).to receive(:search_issues).with("test").and_raise(secondary_rate_limit_error)
      allow(github).to receive(:sleep)

      expect {
        github.search_issues("test")
      }.to raise_error(StandardError, /exceeded a secondary rate limit/)

      expect(mock_logger).to have_received(:warn).with(/GitHub secondary rate limit hit, sleeping for 60 seconds/)
      expect(github).to have_received(:sleep).with(60)
    end

    it "handles search_issues successful call" do
      allow(mock_client).to receive(:search_issues).with("test").and_return("search_issues_result")
      result = github.search_issues("test")
      expect(result).to eq("search_issues_result")
    end

    context "retry behavior" do
      it "retries failed requests" do
        allow(mock_client).to receive(:user).and_raise(StandardError.new("Network error")).once
        allow(mock_client).to receive(:user).and_return("user_data")
        result = github.user
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
        allow(github).to receive(:sleep)

        result = github.repositories
        expect(result).to eq("repos_data")
        expect(github).to have_received(:sleep).twice
      end

      it "retries with exponential backoff when enabled" do
        allow(ENV).to receive(:fetch).with("GH_APP_EXPONENTIAL_BACKOFF", "false").and_return("true")
        github_exponential = IssueDB::Utils::GitHub.new
        allow(github_exponential).to receive(:client).and_return(mock_client)
        allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)

        error_count = 0
        allow(mock_client).to receive(:organizations) do
          error_count += 1
          error_count < 3 ? raise(StandardError.new("Temporary error")) : "orgs_data"
        end
        allow(github_exponential).to receive(:sleep)

        result = github_exponential.organizations
        expect(result).to eq("orgs_data")
        expect(github_exponential).to have_received(:sleep).twice
      end

      it "gives up after max retries" do
        allow(mock_client).to receive(:organizations).and_raise(StandardError.new("Persistent error"))
        allow(github).to receive(:sleep)

        expect {
          github.organizations
        }.to raise_error(StandardError, "Persistent error")

        expect(github).to have_received(:sleep).exactly(9).times
      end

      it "bypasses retry logic when disable_retry is true for search_issues" do
        allow(mock_client).to receive(:search_issues).with("test").and_raise(StandardError.new("Network error"))
        allow(github).to receive(:sleep)

        expect {
          github.search_issues("test", disable_retry: true)
        }.to raise_error(StandardError, "Network error")

        expect(github).not_to have_received(:sleep)
      end

      it "bypasses retry logic when disable_retry is true for other methods" do
        allow(mock_client).to receive(:user).and_raise(StandardError.new("Network error"))
        allow(github).to receive(:sleep)

        expect {
          github.user(disable_retry: true)
        }.to raise_error(StandardError, "Network error")

        expect(github).not_to have_received(:sleep)
      end
    end
  end

  describe "#respond_to_missing?" do
    let(:github) { IssueDB::Utils::GitHub.new }

    before do
      allow(github).to receive(:client).and_return(mock_client)
    end

    it "returns true when Octokit client responds to method" do
      allow(mock_client).to receive(:respond_to?).with(:rate_limit, false).and_return(true)
      expect(github.respond_to?(:rate_limit)).to be true
    end

    it "returns false when Octokit client does not respond to method" do
      allow(mock_client).to receive(:respond_to?).with(:nonexistent_method, false).and_return(false)
      expect(github.respond_to?(:nonexistent_method)).to be false
    end

    it "includes private methods when specified" do
      allow(mock_client).to receive(:respond_to?).with(:private_method, true).and_return(true)
      expect(github.respond_to?(:private_method, true)).to be true
    end

    context "add_label method with disable_retry in options hash" do
      before do
        # Mock the rate limit call that happens in wait_for_rate_limit!
        allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
      end

      it "extracts disable_retry from options hash and passes clean options to Octokit" do
        options_with_disable_retry = {
          description: "Test label",
          disable_retry: true
        }

        expected_clean_options = {
          description: "Test label"
        }

        allow(mock_client).to receive(:add_label).with(
          "owner/repo",
          "test-label",
          "ff0000",
          expected_clean_options
        ).and_return("label_created")

        result = github.add_label("owner/repo", "test-label", "ff0000", options_with_disable_retry)
        expect(result).to eq("label_created")
        expect(mock_client).to have_received(:add_label).with(
          "owner/repo",
          "test-label",
          "ff0000",
          expected_clean_options
        )
      end

      it "handles disable_retry in options hash and skips retry on failure" do
        options_with_disable_retry = {
          description: "Test label",
          disable_retry: true
        }

        error = StandardError.new("API error")
        allow(mock_client).to receive(:add_label).and_raise(error)

        expect { github.add_label("owner/repo", "test-label", "ff0000", options_with_disable_retry) }.to raise_error(error)
        expect(mock_client).to have_received(:add_label).once # Should not retry
      end

      it "handles options hash without disable_retry normally" do
        options_without_disable_retry = {
          description: "Test label",
          color: "blue"
        }

        allow(mock_client).to receive(:add_label).with(
          "owner/repo",
          "test-label",
          "ff0000",
          options_without_disable_retry
        ).and_return("label_created")

        result = github.add_label("owner/repo", "test-label", "ff0000", options_without_disable_retry)
        expect(result).to eq("label_created")
      end

      it "prioritizes keyword argument disable_retry over options hash disable_retry" do
        options_with_disable_retry = {
          description: "Test label",
          disable_retry: false  # This should be overridden
        }

        expected_clean_options = {
          description: "Test label"
        }

        allow(mock_client).to receive(:add_label).with(
          "owner/repo",
          "test-label",
          "ff0000",
          expected_clean_options
        ).and_return("label_created")

        # Keyword argument should take precedence
        result = github.add_label("owner/repo", "test-label", "ff0000", options_with_disable_retry, disable_retry: true)
        expect(result).to eq("label_created")
      end

      it "works with minimal arguments (no options hash)" do
        allow(mock_client).to receive(:add_label).with(
          "owner/repo",
          "test-label",
          "ff0000"
        ).and_return("label_created")

        result = github.add_label("owner/repo", "test-label", "ff0000")
        expect(result).to eq("label_created")
      end

      it "handles non-hash fourth argument gracefully" do
        # If someone passes a non-hash as the fourth argument, it should not crash
        allow(mock_client).to receive(:add_label).with(
          "owner/repo",
          "test-label",
          "ff0000",
          "not_a_hash"
        ).and_return("label_created")

        result = github.add_label("owner/repo", "test-label", "ff0000", "not_a_hash")
        expect(result).to eq("label_created")
      end

      it "only processes disable_retry for add_label method, not other methods" do
        options_with_disable_retry = {
          description: "Test description",
          disable_retry: true
        }

        # For non-add_label methods, disable_retry should remain in the options
        allow(mock_client).to receive(:create_issue).with(
          "owner/repo",
          "Test Issue",
          "Body",
          options_with_disable_retry  # disable_retry should NOT be filtered out
        ).and_return("issue_created")

        result = github.create_issue("owner/repo", "Test Issue", "Body", options_with_disable_retry)
        expect(result).to eq("issue_created")
      end
    end
  end

  describe "integration scenarios" do
    let(:github) { IssueDB::Utils::GitHub.new }

    before do
      allow(github).to receive(:client).and_return(mock_client)
      allow(mock_client).to receive(:get).with("rate_limit").and_return(default_rate_limit_response)
    end

    it "handles complete workflow: rate limit check, API call, response" do
      allow(mock_client).to receive(:user).and_return({ login: "testuser" })

      result = github.user

      expect(result).to eq({ login: "testuser" })
      expect(mock_client).to have_received(:get).with("rate_limit")
      expect(mock_client).to have_received(:user)
    end

    it "handles authentication failure gracefully" do
      auth_error = StandardError.new("Authentication failed")
      allow(mock_client).to receive(:user).and_raise(auth_error)
      expect { github.user }.to raise_error(StandardError, "Authentication failed")
    end

    it "properly initializes retry configuration" do
      retry_sleep = github.instance_variable_get(:@retry_sleep)
      retry_tries = github.instance_variable_get(:@retry_tries)
      retry_exponential_backoff = github.instance_variable_get(:@retry_exponential_backoff)
      expect(retry_sleep).to eq(3)
      expect(retry_tries).to eq(10)
      expect(retry_exponential_backoff).to be false
    end

    it "allows enabling exponential backoff" do
      allow(ENV).to receive(:fetch).with("GH_APP_EXPONENTIAL_BACKOFF", "false").and_return("true")
      github = IssueDB::Utils::GitHub.new
      retry_exponential_backoff = github.instance_variable_get(:@retry_exponential_backoff)
      expect(retry_exponential_backoff).to be true
    end
  end
end
