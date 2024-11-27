# frozen_string_literal: true

class ParseError < StandardError; end

module Parse
  # Parses the issue body
  # This method returns a hash that contains the following fields:
  # - body_before: the body of the issue before the data
  # - data: the parsed data as a hash
  # - body_after: the body of the issue after the data
  def parse(body, guard_start: "<!--- issue-db-start -->", guard_end: "<!--- issue-db-end -->")
    body_array = body.split("\n")
    start_index = body_array.index(guard_start)
    end_index = body_array.index(guard_end)

    if start_index.nil? || end_index.nil?
      raise ParseError, "issue body is missing a guard start or guard end"
    end

    # remove the first and last line if they contain triple backticks (codeblock)
    data = body_array[start_index + 1...end_index]
    data.shift if data.first.include?("```")
    data.pop if data.last.include?("```")

    # rejoins the data into a string
    data = data.join("\n")
    # parse the data
    data = JSON.parse(data)

    return {
      body_before: body_array[0...start_index].join("\n"),
      data: data,
      body_after: body_array[end_index + 1..-1].join("\n"),
    }
  end
end
