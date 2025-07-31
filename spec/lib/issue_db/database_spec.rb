# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/issue_db/database"

describe IssueDB::Database, :vcr do
  before(:all) do
    @client = Octokit::Client.new(access_token: FAKE_TOKEN, page_size: 100)
    @client.auto_paginate = true
  end

  let(:repo) { instance_double(IssueDB::Repository, full_name: REPO) }
  let(:current_time) { Time.parse("2024-01-01 00:00:00").utc }
  let(:log) { instance_double(RedactingLogger).as_null_object }
  let(:label) { "issue-db" }
  let(:cache_expiry) { 60 }

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
  end

  subject { described_class.new(log, @client, repo, label, cache_expiry) }

  it "returns a database object successfully" do
    expect(subject.class).to eq(IssueDB::Database)
  end

  context "read" do
    it "reads a single issue successfully" do
      issue = subject.read("event456")
      expect(issue.source_data.number).to eq(8)
      expect(issue.source_data.state).to eq("open")
    end

    it "throws an error if the record cannot be found" do
      expect { subject.read("event888") }.to raise_error(IssueDB::RecordNotFound, /no record found for key: event888/)
    end

    it "finds that the issue cache is expired so it refreshes the cache on a read" do
      # force a cache refresh
      subject.refresh!

      expect(Time).to receive(:now).and_return(current_time + 65)
      expect(log).to receive(:debug).with(/issue cache expired - last updated/)
      issue = subject.read("event456")
      expect(issue.source_data.number).to eq(8)
    end
  end

  context "create" do
    it "fails due to bad credentials" do
      expect { subject.create("event456", { cool: true }) }.to raise_error(StandardError, /401 - Bad credentials/)
    end

    it "attempts to create a new record and finds that one already exists for the given key" do
      expect(log).to receive(:warn).with(/skipping issue creation/)
      issue = subject.create("event456", { cool: true })
      expect(issue.source_data.number).to eq(8)
      expect(issue.source_data.state).to eq("open")
    end

    it "creates a new record when no existing issues are found" do
      # Mock the client to return empty array for existing issues
      search_result = double("search_result", items: [], total_count: 0)
      allow(@client).to receive(:search_issues).and_return(search_result)

      # Create a properly formatted issue body with guards
      issue_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "data"
        }
        ```
        <!--- issue-db-end -->
      BODY

      # Mock the create_issue call
      new_issue = double("issue", number: 999, state: "open", title: "new_event_key", body: issue_body)
      allow(@client).to receive(:create_issue).and_return(new_issue)

      expect(log).to receive(:debug).with(/issue created: new_event_key/)

      issue = subject.create("new_event_key", { test: "data" })
      expect(issue).to be_a(IssueDB::Record)
    end
  end

  context "update" do
    it "updates an issue successfully" do
      issue = subject.update("event999", { cool: false })
      expect(issue.source_data.number).to eq(12)
      expect(issue.source_data.state).to eq("open")
    end
  end

  context "delete" do
    it "deletes an issue successfully (closes)" do
      # Delete the issue and verify it's closed
      issue = subject.delete("event999")
      expect(issue.source_data.number).to eq(11)
      expect(issue.source_data.state).to eq("closed")

      # Verify the deleted record doesn't appear in normal lists (open only)
      open_keys = subject.list_keys
      expect(open_keys).not_to include("event999")

      open_records = subject.list
      expect(open_records.map(&:key)).not_to include("event999")

      # But it should appear when including closed records
      all_keys = subject.list_keys({ include_closed: true })
      expect(all_keys).to include("event999")

      all_records = subject.list({ include_closed: true })
      expect(all_records.map(&:key)).to include("event999")

      # Verify the closed record has the correct state
      closed_record = all_records.find { |r| r.key == "event999" }
      expect(closed_record.source_data.state).to eq("closed")
    end
  end

  context "list_keys" do
    it "lists all keys successfully" do
      keys = subject.list_keys
      expect(keys).to eq(%w[event456 event234 event123])
    end
  end

  context "list" do
    it "lists all records successfully" do
      records = subject.list
      expect(records.first.data).to eq({ "age" => 333, "apple" => "red", "cool" => true, "user" => "mona" })
      expect(records.first.source_data.number).to eq(8)
      expect(records.last.source_data.number).to eq(6)
      expect(records.size).to eq(3)
    end
  end

  context "refresh!" do
    it "refreshes the cache successfully" do
      results = subject.refresh!
      expect(results.length).to eq(5)
      expect(results.first.number).to eq(11)
    end
  end

  context "edge cases" do
    it "handles cache inconsistency gracefully in update" do
      # First initialize the cache properly with mocked data
      search_result = double("search_result", total_count: 1, items: [{ title: "existing_issue", state: "open", number: 1 }])
      allow(@client).to receive(:search_issues).and_return(search_result)

      # Initialize cache
      subject.send(:update_issue_cache!)

      # Now simulate an issue that exists in find_issue_by_key but not in the cache array
      fake_issue = double("fake_issue", title: "fake_issue", state: "open", number: 999)
      allow(subject).to receive(:find_issue_by_key).with("fake_issue", {}).and_return(fake_issue)

      # Mock the update call
      issue_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "data"
        }
        ```
        <!--- issue-db-end -->
      BODY
      updated_issue = double("updated_issue", number: 999, state: "open", title: "fake_issue", body: issue_body)
      allow(@client).to receive(:update_issue).and_return(updated_issue)

      # Mock update_issue_cache! to prevent actual API calls
      expect(subject).to receive(:update_issue_cache!)
      expect(log).to receive(:warn).with(/issue not found in cache during update/)

      result = subject.update("fake_issue", { test: "data" })
      expect(result).to be_a(IssueDB::Record)
    end

    it "handles cache inconsistency gracefully in delete" do
      # First initialize the cache properly with mocked data
      search_result = double("search_result", total_count: 1, items: [{ title: "existing_issue", state: "open", number: 1 }])
      allow(@client).to receive(:search_issues).and_return(search_result)

      # Initialize cache
      subject.send(:update_issue_cache!)

      # Now simulate an issue that exists in find_issue_by_key but not in the cache array
      fake_issue = double("fake_issue", title: "fake_issue", state: "open", number: 999)
      allow(subject).to receive(:find_issue_by_key).with("fake_issue", {}).and_return(fake_issue)

      # Mock the delete call
      issue_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "data"
        }
        ```
        <!--- issue-db-end -->
      BODY
      deleted_issue = double("deleted_issue", number: 999, state: "closed", title: "fake_issue", body: issue_body)
      allow(@client).to receive(:close_issue).and_return(deleted_issue)

      # Mock update_issue_cache! to prevent actual API calls
      expect(subject).to receive(:update_issue_cache!)
      expect(log).to receive(:warn).with(/issue not found in cache during delete/)

      result = subject.delete("fake_issue")
      expect(result).to be_a(IssueDB::Record)
    end
  end
end
