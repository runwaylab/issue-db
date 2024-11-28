# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/issue_db/cache"

class DummyClass
  include Cache

  attr_accessor :client, :repo, :label, :log, :issues, :issues_last_updated

  def initialize(client, repo, label, log)
    @client = client
    @repo = repo
    @label = label
    @log = log
    @issues = []
    @issues_last_updated = nil
  end

  def wait_for_rate_limit!(type)
    # Simulate waiting for rate limit
  end
end

describe Cache do
  let(:client) { double("client") }
  let(:repo) { double("repo", full_name: "user/repo") }
  let(:label) { "issue-db" }
  let(:log) { double("log", debug: nil, error: nil) }
  let(:dummy_instance) { DummyClass.new(client, repo, label, log) }
  let(:current_time) { Time.parse("2024-01-01 00:00:00").utc }

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
    Retry.setup!(log:)
  end

  describe "#update_issue_cache!" do
    context "when cache is updated successfully" do
      it "updates the issue cache and logs the update" do
        search_response = double("search_response", total_count: 2, items: ["issue1", "issue2"])
        allow(client).to receive(:search_issues).and_return(search_response)

        expect(log).to receive(:debug).with("updating issue cache")
        expect(log).to receive(:debug).with("issue cache updated - cached 2 issues")

        result = dummy_instance.update_issue_cache!
        expect(result).to eq(["issue1", "issue2"])
        expect(dummy_instance.issues).to eq(["issue1", "issue2"])
        expect(dummy_instance.issues_last_updated).not_to be_nil
      end
    end

    context "when a secondary rate limit error occurs" do
      it "sleeps and retries" do
        allow(client).to receive(:search_issues).and_raise(StandardError.new("exceeded a secondary rate limit"))
        allow(dummy_instance).to receive(:sleep).with(60)

        expect(log).to receive(:debug).with("updating issue cache")
        expect(dummy_instance).to receive(:sleep).with(60)

        expect { dummy_instance.update_issue_cache! }.to raise_error(StandardError, /exceeded a secondary rate limit/)
      end
    end

    context "when another error occurs" do
      it "logs an error message and raises the error" do
        allow(client).to receive(:search_issues).and_raise(StandardError.new("some other error"))

        expect(log).to receive(:debug).with("updating issue cache")
        expect(log).to receive(:error).with("error search_issues() call: some other error - ran out of retries")

        expect { dummy_instance.update_issue_cache! }.to raise_error("error search_issues() call: some other error - ran out of retries")
      end
    end
  end
end
