# frozen_string_literal: true

require "redacting_logger"
require_relative "version"

class IssueDB
  include Version

  attr_reader :log
  attr_reader :version

  def initialize(log: nil)
    @log = log || RedactingLogger.new($stdout, level: ENV.fetch("LOG_LEVEL", "INFO").upcase)
    @version = VERSION
  end
end
