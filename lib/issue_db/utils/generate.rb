# frozen_string_literal: true

module IssueDB
  class GenerateError < StandardError; end

  module Generate
  # Generates the issue body with embedded data
  # :param data [Hash] the data to embed in the issue body
  # :param body_before [String] the body of the issue before the data (optional)
  # :param body_after [String] the body of the issue after the data (optional)
  # :param guard_start [String] the guard start string which is used to identify the start of the data
  # :param guard_end [String] the guard end string which is used to identify the end of the data
  # :return [String] the issue body with the embedded data
    def generate(
      data,
      body_before: nil,
      body_after: nil,
      guard_start: "<!--- issue-db-start -->",
      guard_end: "<!--- issue-db-end -->"
      )

      # json formatting options
      opts = {
        indent: "  ",
        space: " ",
        object_nl: "\n",
        array_nl: "\n",
        allow_nan: true,
        max_nesting: false
      }

      json_data = JSON.pretty_generate(data, opts)

      # construct the body
      body = ""
      body += "#{body_before}\n" unless body_before.nil? # the first part of the body
      body += "#{guard_start}\n" # the start of the data
      body += "```json\n" # the start of the json codeblock
      body += "#{json_data}\n" # the data
      body += "```\n" # the end of the json codeblock
      body += "#{guard_end}\n" # the end of the data
      body += body_after unless body_after.nil? # the last part of the body

      return body
    end
  end
end
