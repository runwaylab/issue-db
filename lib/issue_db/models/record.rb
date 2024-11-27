# frozen_string_literal: true

require_relative "../utils/parse"

class IssueParseError < StandardError; end

class Record
  include Parse

  attr_reader :body_before, :data, :body_after, :source_data
  def initialize(data)
    @source_data = data
    parse!
  end

  protected

  def parse!
    if @source_data.body.nil? || @source_data.body.strip == ""
      raise IssueParseError, "issue body is empty for issue number #{@source_data.number}"
    end

    parsed = parse(@source_data.body)

    @body_before = parsed[:body_before]
    @data = parsed[:data]
    @body_after = parsed[:body_after]
  end
end
