# frozen_string_literal: true

module Throttle
  # A helper method to check the client's current rate limit status before making a request
  # NOTE: This method will sleep for the remaining time until the rate limit resets if the rate limit is hit
  # :param: type [Symbol] the type of rate limit to check (core, search, graphql, etc) - default: :core
  # :return: nil (nothing) - this method will block until the rate limit is reset for the given type
  def wait_for_rate_limit!(type = :core)
    @log.debug("checking rate limit status for type: #{type}")
    # make a request to get the comprehensive rate limit status
    # note: checking the rate limit status does not count against the rate limit in any way
    rate_limit_all = Retryable.with_context(:default) do
      @client.get("rate_limit")
    end

    # fetch the provided rate limit type
    # rate_limit resulting structure: {:limit=>5000, :used=>15, :remaining=>4985, :reset=>1713897293}
    rate_limit = rate_limit_all[:resources][type]

    # calculate the time the rate limit will reset
    resets_at = Time.at(rate_limit[:reset]).utc

    @log.debug(
      "rate_limit remaining: #{rate_limit.remaining} - " \
      "used: #{rate_limit.used} - " \
      "resets_at: #{resets_at} - " \
      "current time: #{Time.now}"
    )

    # exit early if the rate limit is not hit (we have remaining requests)
    return unless rate_limit.remaining.zero?

    # if we make it here, we have hit the rate limit

    # calculate the sleep duration - ex: reset time - current time
    sleep_duration = resets_at - Time.now
    @log.debug("sleep_duration: #{sleep_duration}")
    sleep_duration = [sleep_duration, 0].max # ensure sleep duration is not negative
    sleep_duration_and_a_little_more = sleep_duration.ceil + 2 # sleep a little more than the rate limit reset time

    # log the sleep duration and begin the blocking sleep call
    @log.info("github rate_limit hit: sleeping for: #{sleep_duration_and_a_little_more} seconds")
    sleep(sleep_duration_and_a_little_more)

    @log.info("github rate_limit sleep complete - Time.now: #{Time.now}")
  end
end
