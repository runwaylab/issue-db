# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/generate"

RSpec.describe Generate do
  include Generate

  let(:data) do
    {
      "color" => "blue",
      "cool" => true,
      "popularity" => 100,
      "tags" => ["tag1", "tag2"]
    }
  end

  describe "#generate" do
    context "with default guards and no body_before or body_after" do
      it "generates the issue body correctly" do
        result = generate(data)
        expected_body = <<~BODY
          <!--- issue-db-start -->
          ```json
          {
            "color": "blue",
            "cool": true,
            "popularity": 100,
            "tags": [
              "tag1",
              "tag2"
            ]
          }
          ```
          <!--- issue-db-end -->
        BODY
        expect(result).to eq(expected_body)
      end
    end

    context "with body_before and body_after" do
      it "generates the issue body correctly with body_before and body_after" do
        result = generate(
          data,
          body_before: "# Cool Neat 🌍\n\n## Details\nThis is the body before the data:\n",
          body_after: "\nThis is the body after the data."
        )
        expected_body = <<~BODY
          # Cool Neat 🌍

          ## Details
          This is the body before the data:

          <!--- issue-db-start -->
          ```json
          {
            "color": "blue",
            "cool": true,
            "popularity": 100,
            "tags": [
              "tag1",
              "tag2"
            ]
          }
          ```
          <!--- issue-db-end -->

          This is the body after the data.
        BODY
        expect(result).to eq(expected_body.strip)
      end
    end

    context "with custom guards" do
      it "generates the issue body correctly with custom guards" do
        result = generate(data, guard_start: "<!--- custom-start -->", guard_end: "<!--- custom-end -->")
        expected_body = <<~BODY
          <!--- custom-start -->
          ```json
          {
            "color": "blue",
            "cool": true,
            "popularity": 100,
            "tags": [
              "tag1",
              "tag2"
            ]
          }
          ```
          <!--- custom-end -->
        BODY
        expect(result).to eq(expected_body)
      end
    end

    context "with all options" do
      it "generates the issue body correctly with all options" do
        result = generate(
          data,
          body_before: "This is the body before the data.",
          body_after: "This is the body after the data.",
          guard_start: "<!--- custom-start -->",
          guard_end: "<!--- custom-end -->"
        )
        expected_body = <<~BODY
          This is the body before the data.
          <!--- custom-start -->
          ```json
          {
            "color": "blue",
            "cool": true,
            "popularity": 100,
            "tags": [
              "tag1",
              "tag2"
            ]
          }
          ```
          <!--- custom-end -->
          This is the body after the data.
        BODY
        expect(result).to eq(expected_body.strip)
      end
    end
  end
end
