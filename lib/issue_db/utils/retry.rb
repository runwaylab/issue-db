# frozen_string_literal: true

require "retryable"

module Retry
  # This method should be called as early as possible in the startup of your application
  # It sets up the Retryable gem with custom contexts and passes through a few options
  # Should the number of retries be reached without success, the last exception will be raised
  # :param log: the logger to use for retryable logging
  def self.setup!(log: nil)
    raise ArgumentError, "a logger must be provided" if log.nil?

    log_method = lambda do |retries, exception|
      # :nocov:
      log.debug("[retry ##{retries}] #{exception.class}: #{exception.message} - #{exception.backtrace.join("\n")}")
      # :nocov:
    end

    ######## Retryable Configuration ########
    # All defaults available here:
    # https://github.com/nfedyashev/retryable/blob/6a04027e61607de559e15e48f281f3ccaa9750e8/lib/retryable/configuration.rb#L22-L33
    Retryable.configure do |config|
      config.contexts[:default] = {
        on: [StandardError],
        sleep: ENV.fetch("ISSUE_DB_SLEEP", 3),
        tries: ENV.fetch("ISSUE_DB_RETRIES", 10),
        log_method:
      }
    end
  end
end
