# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/models/record"

describe Record do
  let(:valid_issue) do
    double(
      "issue",
      title: "event123",
      body: <<~BODY
        This is the body before the data.
        <!--- issue-db-start -->
        {
          "color": "blue",
          "cool": true,
          "popularity": 100,
          "tags": ["tag1", "tag2"]
        }
        <!--- issue-db-end -->
        This is the body after the data.
      BODY
    )
  end

  let(:empty_body_issue) do
    double("issue", title: "event123", body: "", number: 1)
  end

  let(:invalid_json_issue) do
    double(
      "issue",
      title: "event123",
      body: <<~BODY,
        This is the body before the data.
        <!--- issue-db-start -->
        {
          "color": "blue",
          "cool": true,
          "popularity": 100,
          "tags": ["tag1", "tag2"
        <!--- issue-db-end -->
        This is the body after the data.
      BODY
      number: 2
    )
  end

  describe "#initialize" do
    context "with valid input" do
      it "parses the issue body correctly" do
        record = Record.new(valid_issue)
        expect(record.body_before).to eq("This is the body before the data.")
        expect(record.data).to eq({
          "color" => "blue",
          "cool" => true,
          "popularity" => 100,
          "tags" => ["tag1", "tag2"]
        })
        expect(record.body_after).to eq("This is the body after the data.")
        expect(record.key).to eq("event123")
      end
    end

    context "with empty issue body" do
      it "raises an IssueParseError" do
        expect { Record.new(empty_body_issue) }.to raise_error(IssueParseError, "issue body is empty for issue number 1")
      end
    end

    context "with invalid JSON in issue body" do
      it "raises an IssueParseError" do
        expect { Record.new(invalid_json_issue) }.to raise_error(IssueParseError, /failed to parse issue body data contents for issue number: 2/)
      end
    end
  end
end
