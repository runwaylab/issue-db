# frozen_string_literal: true

module Throttle
  def fetch_rate_limit
    @rate_limit_all = Retryable.with_context(:default) do
      @client.get("rate_limit")
    end
  end

  def update_rate_limit(type)
    @rate_limit_all[:resources][type][:remaining] -= 1
  end

  def rate_limit_details(type)
    # fetch the provided rate limit type
    # rate_limit resulting structure: {:limit=>5000, :used=>15, :remaining=>4985, :reset=>1713897293}
    rate_limit = @rate_limit_all[:resources][type]

    # calculate the time the rate limit will reset
    resets_at = Time.at(rate_limit[:reset]).utc

    return {
      rate_limit: rate_limit,
      resets_at: resets_at,
    }
  end

  # A helper method to check the client's current rate limit status before making a request
  # NOTE: This method will sleep for the remaining time until the rate limit resets if the rate limit is hit
  # :param: type [Symbol] the type of rate limit to check (core, search, graphql, etc) - default: :core
  # :return: nil (nothing) - this method will block until the rate limit is reset for the given type
  def wait_for_rate_limit!(type = :core)
    @log.debug("checking rate limit status for type: #{type}")
    # make a request to get the comprehensive rate limit status
    # note: checking the rate limit status does not count against the rate limit in any way
    fetch_rate_limit if @rate_limit_all.nil?

    details = rate_limit_details(type)
    rate_limit = details[:rate_limit]
    resets_at = details[:resets_at]

    @log.debug(
      "rate_limit remaining: #{rate_limit.remaining} - " \
      "used: #{rate_limit.used} - " \
      "resets_at: #{resets_at} - " \
      "current time: #{Time.now}"
    )

    # exit early if the rate limit is not hit (we have remaining requests)
    unless rate_limit.remaining.zero?
      update_rate_limit(type)
      return
    end

    # if we make it here, we (probably) have hit the rate limit
    # fetch the rate limit again if we are at zero or if the rate limit reset time is in the past
    fetch_rate_limit if rate_limit.remaining.zero? || rate_limit.remaining < 0 || resets_at < Time.now

    details = rate_limit_details(type)
    rate_limit = details[:rate_limit]
    resets_at = details[:resets_at]

    # exit early if the rate limit is not actually hit (we have remaining requests)
    unless rate_limit.remaining.zero?
      @log.debug("rate_limit not hit - remaining: #{rate_limit.remaining}")
      update_rate_limit(type)
      return
    end

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
