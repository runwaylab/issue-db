# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/parse"

describe Parse do
  include Parse

  let(:valid_body) do
    <<~BODY
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
  end

  let(:body_with_code_blocks) do
    <<~BODY
    This is the body before the data.
    <!--- issue-db-start -->
    ```
    {
      "color": "blue",
      "cool": true,
      "popularity": 100,
      "tags": ["tag1", "tag2"]
    }
    ```
    <!--- issue-db-end -->
    This is the body after the data.
    BODY
  end

  let(:body_missing_guards) do
    <<-BODY
    This is the body before the data with missing guards.
    {
      "color": "blue",
      "cool": true,
      "popularity": 100,
      "tags": ["tag1", "tag2"]
    }
    This is the body after the data with missing guards.
    BODY
  end

  describe "#parse" do
    context "with valid input" do
      it "parses the issue body correctly" do
        result = parse(valid_body)
        expect(result[:body_before]).to eq("This is the body before the data.")
        expect(result[:data]).to eq({
          "color" => "blue",
          "cool" => true,
          "popularity" => 100,
          "tags" => ["tag1", "tag2"]
        })
        expect(result[:body_after]).to eq("This is the body after the data.")
      end
    end

    context "with code blocks in data" do
      it "parses the issue body correctly and removes code blocks" do
        result = parse(body_with_code_blocks)
        expect(result[:body_before]).to eq("This is the body before the data.")
        expect(result[:data]).to eq({
          "color" => "blue",
          "cool" => true,
          "popularity" => 100,
          "tags" => ["tag1", "tag2"]
        })
        expect(result[:body_after]).to eq("This is the body after the data.")
      end
    end

    context "with missing guards" do
      it "raises a ParseError" do
        expect { parse(body_missing_guards) }.to raise_error(ParseError, "issue body is missing a guard start or guard end")
      end
    end

    context "with custom guards" do
      let(:custom_body) do
        <<~BODY
        This is the body before the data.
        <!--- custom-start -->
        {
          "color": "blue",
          "cool": true,
          "popularity": 100,
          "tags": ["tag1", "tag2"]
        }
        <!--- custom-end -->
        This is the body after the data.
        BODY
      end

      it "parses the issue body correctly with custom guards" do
        result = parse(custom_body, guard_start: "<!--- custom-start -->", guard_end: "<!--- custom-end -->")
        expect(result[:body_before]).to eq("This is the body before the data.")
        expect(result[:data]).to eq({
          "color" => "blue",
          "cool" => true,
          "popularity" => 100,
          "tags" => ["tag1", "tag2"]
        })
        expect(result[:body_after]).to eq("This is the body after the data.")
      end
    end
  end
end
