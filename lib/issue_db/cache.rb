# frozen_string_literal: true

module Cache
  # A helper method to update all issues in the cache
  # :return: The updated issue cache as a list of issues
  def update_issue_cache!
    @log.debug("updating issue cache")

    # find all issues in the repo that were created by this library
    query = "repo:#{@repo.full_name} label:#{@label}"

    search_response = nil
    begin
      Retryable.with_context(:default) do
        wait_for_rate_limit!(:search) # specifically wait for the search rate limit as it is much lower

        begin
          # issues structure: { "total_count": 0, "incomplete_results": false, "items": [<issues>] }
          search_response = @client.search_issues(query)
        rescue StandardError => e
          # re-raise the error but if its a secondary rate limit error, just sleep for minute (oof)
          sleep(60) if e.message.include?("exceeded a secondary rate limit")
          raise e
        end
      end
    rescue StandardError => e
      retry_err_msg = "error search_issues() call: #{e.message} - ran out of retries"
      @log.error(retry_err_msg)
      raise retry_err_msg
    end

    @log.debug("issue cache updated - cached #{search_response.total_count} issues")
    @issues = search_response.items
    @issues_last_updated = Time.now
    return @issues
  end
end
