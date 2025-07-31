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

    it "creates a new record with additional labels" do
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

      # Mock the create_issue call with labels verification
      new_issue = double("issue", number: 999, state: "open", title: "new_event_with_labels", body: issue_body)
      expect(@client).to receive(:create_issue).with(
        anything, anything, anything,
        hash_including(labels: ["issue-db", "priority:high", "bug"])
      ).and_return(new_issue)

      expect(log).to receive(:debug).with(/issue created: new_event_with_labels/)

      issue = subject.create("new_event_with_labels", { test: "data" }, { labels: ["priority:high", "bug"] })
      expect(issue).to be_a(IssueDB::Record)
    end

    it "creates a new record and filters out duplicate library label from user labels" do
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

      # Mock the create_issue call - should only have one instance of "issue-db" label
      new_issue = double("issue", number: 999, state: "open", title: "new_event_no_duplicates", body: issue_body)
      expect(@client).to receive(:create_issue).with(
        anything, anything, anything,
        hash_including(labels: ["issue-db", "priority:low"])
      ).and_return(new_issue)

      expect(log).to receive(:debug).with(/issue created: new_event_no_duplicates/)

      # User tries to include the library label, but it should be filtered out
      issue = subject.create("new_event_no_duplicates", { test: "data" }, { labels: ["issue-db", "priority:low"] })
      expect(issue).to be_a(IssueDB::Record)
    end
  end

  context "update" do
    it "updates an issue successfully" do
      issue = subject.update("event999", { cool: false })
      expect(issue.source_data.number).to eq(12)
      expect(issue.source_data.state).to eq("open")
    end

    it "updates an issue with additional labels" do
      # Mock finding the issue
      existing_issue = double("issue", number: 123, title: "test_event", state: "open")
      allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

      # Create a properly formatted updated issue body with guards
      updated_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "updated data"
        }
        ```
        <!--- issue-db-end -->
      BODY

      # Mock the update_issue call with labels verification
      updated_issue = double("issue", number: 123, state: "open", title: "test_event", body: updated_body)
      expect(@client).to receive(:update_issue).with(
        anything, 123, anything, anything,
        hash_including(labels: ["issue-db", "enhancement", "documentation"])
      ).and_return(updated_issue)

      # Mock cache methods - create a proper array for @issues
      issues_array = [existing_issue]
      allow(subject).to receive(:issues).and_return(issues_array)
      subject.instance_variable_set(:@issues, issues_array)

      expect(log).to receive(:debug).with(/issue updated: test_event/)

      issue = subject.update("test_event", { test: "updated data" }, { labels: ["enhancement", "documentation"] })
      expect(issue).to be_a(IssueDB::Record)
    end

    it "updates an issue without modifying labels when none are specified" do
      # Mock finding the issue
      existing_issue = double("issue", number: 456, title: "test_preserve_labels", state: "open")
      allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

      # Create a properly formatted updated issue body with guards
      updated_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "updated data without labels"
        }
        ```
        <!--- issue-db-end -->
      BODY

      # Mock the update_issue call WITHOUT labels - should preserve existing labels
      updated_issue = double("issue", number: 456, state: "open", title: "test_preserve_labels", body: updated_body)
      expect(@client).to receive(:update_issue).with(
        anything, 456, anything, anything,
        {}  # Empty hash - no labels parameter should be sent
      ).and_return(updated_issue)

      # Mock cache methods - create a proper array for @issues
      issues_array = [existing_issue]
      allow(subject).to receive(:issues).and_return(issues_array)
      subject.instance_variable_set(:@issues, issues_array)

      expect(log).to receive(:debug).with(/issue updated: test_preserve_labels/)

      # No labels specified - should preserve existing labels
      issue = subject.update("test_preserve_labels", { test: "updated data without labels" })
      expect(issue).to be_a(IssueDB::Record)
    end

    it "updates an issue and filters out duplicate library label from user labels" do
      # Mock finding the issue
      existing_issue = double("issue", number: 123, title: "test_event_no_duplicates", state: "open")
      allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

      # Create a properly formatted updated issue body with guards
      updated_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "updated data"
        }
        ```
        <!--- issue-db-end -->
      BODY

      # Mock the update_issue call - should only have one instance of "issue-db" label
      updated_issue = double("issue", number: 123, state: "open", title: "test_event_no_duplicates", body: updated_body)
      expect(@client).to receive(:update_issue).with(
        anything, 123, anything, anything,
        hash_including(labels: ["issue-db", "priority:medium"])
      ).and_return(updated_issue)

      # Mock cache methods - create a proper array for @issues
      issues_array = [existing_issue]
      allow(subject).to receive(:issues).and_return(issues_array)
      subject.instance_variable_set(:@issues, issues_array)

      expect(log).to receive(:debug).with(/issue updated: test_event_no_duplicates/)

      # User tries to include the library label, but it should be filtered out
      issue = subject.update("test_event_no_duplicates", { test: "updated data" }, { labels: ["issue-db", "priority:medium"] })
      expect(issue).to be_a(IssueDB::Record)
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

    it "deletes an issue with additional labels before closing" do
      # Mock finding the issue
      existing_issue = double("issue", number: 456, title: "test_delete_with_labels", state: "open")
      allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

      # Mock the update_issue call with labels (before closing)
      expect(@client).to receive(:update_issue).with(
        anything, 456,
        hash_including(labels: ["issue-db", "archived", "resolved"])
      )

      # Create a properly formatted closed issue body with guards
      closed_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "data"
        }
        ```
        <!--- issue-db-end -->
      BODY

      # Mock the close_issue call
      closed_issue = double("issue", number: 456, state: "closed", title: "test_delete_with_labels", body: closed_body)
      expect(@client).to receive(:close_issue).and_return(closed_issue)

      # Mock cache methods - create a proper array for @issues
      issues_array = [existing_issue]
      allow(subject).to receive(:issues).and_return(issues_array)
      subject.instance_variable_set(:@issues, issues_array)

      expect(log).to receive(:debug).with(/issue deleted: test_delete_with_labels/)

      issue = subject.delete("test_delete_with_labels", { labels: ["archived", "resolved"] })
      expect(issue).to be_a(IssueDB::Record)
    end

    it "deletes an issue and filters out duplicate library label from user labels" do
      # Mock finding the issue
      existing_issue = double("issue", number: 456, title: "test_delete_no_duplicates", state: "open")
      allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

      # Mock the update_issue call - should only have one instance of "issue-db" label
      expect(@client).to receive(:update_issue).with(
        anything, 456,
        hash_including(labels: ["issue-db", "finished"])
      )

      # Create a properly formatted closed issue body with guards
      closed_body = <<~BODY
        <!--- issue-db-start -->
        ```json
        {
          "test": "data"
        }
        ```
        <!--- issue-db-end -->
      BODY

      # Mock the close_issue call
      closed_issue = double("issue", number: 456, state: "closed", title: "test_delete_no_duplicates", body: closed_body)
      expect(@client).to receive(:close_issue).and_return(closed_issue)

      # Mock cache methods - create a proper array for @issues
      issues_array = [existing_issue]
      allow(subject).to receive(:issues).and_return(issues_array)
      subject.instance_variable_set(:@issues, issues_array)

      expect(log).to receive(:debug).with(/issue deleted: test_delete_no_duplicates/)

      # User tries to include the library label, but it should be filtered out
      issue = subject.delete("test_delete_no_duplicates", { labels: ["issue-db", "finished"] })
      expect(issue).to be_a(IssueDB::Record)
    end
  end

  context "assignees" do
    context "create with assignees" do
      it "creates a new record with assignees" do
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

        # Mock the create_issue call with assignees verification
        new_issue = double("issue", number: 999, state: "open", title: "new_event_with_assignees", body: issue_body)
        expect(@client).to receive(:create_issue).with(
          anything, anything, anything,
          hash_including(assignees: ["user1", "user2"], labels: ["issue-db"])
        ).and_return(new_issue)

        expect(log).to receive(:debug).with(/issue created: new_event_with_assignees/)

        issue = subject.create("new_event_with_assignees", { test: "data" }, { assignees: ["user1", "user2"] })
        expect(issue).to be_a(IssueDB::Record)
      end

      it "creates a new record with both labels and assignees" do
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

        # Mock the create_issue call with both labels and assignees verification
        new_issue = double("issue", number: 999, state: "open", title: "new_event_with_both", body: issue_body)
        expect(@client).to receive(:create_issue).with(
          anything, anything, anything,
          hash_including(
            labels: ["issue-db", "priority:high", "bug"],
            assignees: ["user1", "user2"]
          )
        ).and_return(new_issue)

        expect(log).to receive(:debug).with(/issue created: new_event_with_both/)

        issue = subject.create("new_event_with_both", { test: "data" }, {
          labels: ["priority:high", "bug"],
          assignees: ["user1", "user2"]
        })
        expect(issue).to be_a(IssueDB::Record)
      end
    end

    context "update with assignees" do
      it "updates an issue with assignees" do
        # Mock finding the issue
        existing_issue = double("issue", number: 123, title: "test_event", state: "open")
        allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

        # Create a properly formatted updated issue body with guards
        updated_body = <<~BODY
          <!--- issue-db-start -->
          ```json
          {
            "test": "updated data"
          }
          ```
          <!--- issue-db-end -->
        BODY

        # Mock the update_issue call with assignees verification
        updated_issue = double("issue", number: 123, state: "open", title: "test_event", body: updated_body)
        expect(@client).to receive(:update_issue).with(
          anything, 123, anything, anything,
          hash_including(assignees: ["user3", "user4"])
        ).and_return(updated_issue)

        # Mock cache methods - create a proper array for @issues
        issues_array = [existing_issue]
        allow(subject).to receive(:issues).and_return(issues_array)
        subject.instance_variable_set(:@issues, issues_array)

        expect(log).to receive(:debug).with(/issue updated: test_event/)

        issue = subject.update("test_event", { test: "updated data" }, { assignees: ["user3", "user4"] })
        expect(issue).to be_a(IssueDB::Record)
      end

      it "updates an issue without modifying assignees when none are specified" do
        # Mock finding the issue
        existing_issue = double("issue", number: 456, title: "test_preserve_assignees", state: "open")
        allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

        # Create a properly formatted updated issue body with guards
        updated_body = <<~BODY
          <!--- issue-db-start -->
          ```json
          {
            "test": "updated data without assignees"
          }
          ```
          <!--- issue-db-end -->
        BODY

        # Mock the update_issue call WITHOUT assignees - should preserve existing assignees
        updated_issue = double("issue", number: 456, state: "open", title: "test_preserve_assignees", body: updated_body)
        expect(@client).to receive(:update_issue).with(
          anything, 456, anything, anything,
          {}  # Empty hash - no assignees parameter should be sent
        ).and_return(updated_issue)

        # Mock cache methods - create a proper array for @issues
        issues_array = [existing_issue]
        allow(subject).to receive(:issues).and_return(issues_array)
        subject.instance_variable_set(:@issues, issues_array)

        expect(log).to receive(:debug).with(/issue updated: test_preserve_assignees/)

        # No assignees specified - should preserve existing assignees
        issue = subject.update("test_preserve_assignees", { test: "updated data without assignees" })
        expect(issue).to be_a(IssueDB::Record)
      end

      it "updates an issue with both labels and assignees" do
        # Mock finding the issue
        existing_issue = double("issue", number: 123, title: "test_event", state: "open")
        allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

        # Create a properly formatted updated issue body with guards
        updated_body = <<~BODY
          <!--- issue-db-start -->
          ```json
          {
            "test": "updated data"
          }
          ```
          <!--- issue-db-end -->
        BODY

        # Mock the update_issue call with both labels and assignees verification
        updated_issue = double("issue", number: 123, state: "open", title: "test_event", body: updated_body)
        expect(@client).to receive(:update_issue).with(
          anything, 123, anything, anything,
          hash_including(
            labels: ["issue-db", "enhancement", "documentation"],
            assignees: ["user5", "user6"]
          )
        ).and_return(updated_issue)

        # Mock cache methods - create a proper array for @issues
        issues_array = [existing_issue]
        allow(subject).to receive(:issues).and_return(issues_array)
        subject.instance_variable_set(:@issues, issues_array)

        expect(log).to receive(:debug).with(/issue updated: test_event/)

        issue = subject.update("test_event", { test: "updated data" }, {
          labels: ["enhancement", "documentation"],
          assignees: ["user5", "user6"]
        })
        expect(issue).to be_a(IssueDB::Record)
      end
    end

    context "delete with assignees" do
      it "deletes an issue with assignees before closing" do
        # Mock finding the issue
        existing_issue = double("issue", number: 456, title: "test_delete_with_assignees", state: "open")
        allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

        # Mock the update_issue call with assignees (before closing)
        expect(@client).to receive(:update_issue).with(
          anything, 456,
          hash_including(assignees: ["maintainer1", "maintainer2"])
        )

        # Create a properly formatted closed issue body with guards
        closed_body = <<~BODY
          <!--- issue-db-start -->
          ```json
          {
            "test": "data"
          }
          ```
          <!--- issue-db-end -->
        BODY

        # Mock the close_issue call
        closed_issue = double("issue", number: 456, state: "closed", title: "test_delete_with_assignees", body: closed_body)
        expect(@client).to receive(:close_issue).and_return(closed_issue)

        # Mock cache methods - create a proper array for @issues
        issues_array = [existing_issue]
        allow(subject).to receive(:issues).and_return(issues_array)
        subject.instance_variable_set(:@issues, issues_array)

        expect(log).to receive(:debug).with(/issue deleted: test_delete_with_assignees/)

        issue = subject.delete("test_delete_with_assignees", { assignees: ["maintainer1", "maintainer2"] })
        expect(issue).to be_a(IssueDB::Record)
      end

      it "deletes an issue with both labels and assignees before closing" do
        # Mock finding the issue
        existing_issue = double("issue", number: 456, title: "test_delete_with_both", state: "open")
        allow(subject).to receive(:find_issue_by_key).and_return(existing_issue)

        # Mock the update_issue call with both labels and assignees (before closing)
        expect(@client).to receive(:update_issue).with(
          anything, 456,
          hash_including(
            labels: ["issue-db", "archived", "resolved"],
            assignees: ["maintainer1", "maintainer2"]
          )
        )

        # Create a properly formatted closed issue body with guards
        closed_body = <<~BODY
          <!--- issue-db-start -->
          ```json
          {
            "test": "data"
          }
          ```
          <!--- issue-db-end -->
        BODY

        # Mock the close_issue call
        closed_issue = double("issue", number: 456, state: "closed", title: "test_delete_with_both", body: closed_body)
        expect(@client).to receive(:close_issue).and_return(closed_issue)

        # Mock cache methods - create a proper array for @issues
        issues_array = [existing_issue]
        allow(subject).to receive(:issues).and_return(issues_array)
        subject.instance_variable_set(:@issues, issues_array)

        expect(log).to receive(:debug).with(/issue deleted: test_delete_with_both/)

        issue = subject.delete("test_delete_with_both", {
          labels: ["archived", "resolved"],
          assignees: ["maintainer1", "maintainer2"]
        })
        expect(issue).to be_a(IssueDB::Record)
      end
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
