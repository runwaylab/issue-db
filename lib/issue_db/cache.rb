# frozen_string_literal: true

module IssueDB
  module Cache
    # A helper method to update all issues in the cache
    # :return: The updated issue cache as a list of issues
    def update_issue_cache!
      @log.debug("updating issue cache")

      # find all issues in the repo that were created by this library
      query = "repo:#{@repo.full_name} label:#{@label}"

      search_response = nil
      begin
        # issues structure: { "total_count": 0, "incomplete_results": false, "items": [<issues>] }
        search_response = @client.search_issues(query)
      rescue StandardError => e
        retry_err_msg = "error search_issues() call: #{e.message}"
        @log.error(retry_err_msg)
        raise StandardError, retry_err_msg
      end

      # Safety check to ensure search_response and items are not nil
      if search_response.nil? || search_response.items.nil?
        @log.error("search_issues returned nil response or nil items")
        raise StandardError, "search_issues returned invalid response"
      end

      @log.debug("issue cache updated - cached #{search_response.total_count} issues")
      @issues = search_response.items
      @issues_last_updated = Time.now
      return @issues
    end
  end
end
