# frozen_string_literal: true

require_relative "../utils/parse"

class IssueParseError < StandardError; end

class Record
  include Parse

  attr_reader :body_before, :data, :body_after, :source_data, :key
  def initialize(data)
    @key = data.title
    @source_data = data
    parse!
  end

  protected

  def parse!
    if @source_data.body.nil? || @source_data.body.strip == ""
      raise IssueParseError, "issue body is empty for issue number #{@source_data.number}"
    end

    begin
      parsed = parse(@source_data.body)
    rescue JSON::ParserError => e
      message = "failed to parse issue body data contents for issue number: #{@source_data.number} - #{e.message}"
      raise IssueParseError, message
    end

    @body_before = parsed[:body_before]
    @data = parsed[:data]
    @body_after = parsed[:body_after]
  end
end
