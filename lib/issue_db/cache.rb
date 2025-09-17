# frozen_string_literal: true

module IssueDB
  module Cache
    # A helper method to update all issues in the cache
    # :return: The updated issue cache as a list of issues
    def update_issue_cache!
      @log.debug("updating issue cache")

      issues_response = nil
      begin
        # This fetches all issues with the specified label from the repository. This label identifies all issues...
        # ... that are managed via this library.
        # The client.auto_paginate setting will handle pagination automatically
        issues_response = @client.issues(@repo.full_name, labels: @label, state: "all")
      rescue StandardError => e
        retry_err_msg = "error issues() call: #{e.message}"
        @log.error(retry_err_msg)
        raise StandardError, retry_err_msg
      end

      # Safety check to ensure issues_response is not nil
      if issues_response.nil?
        @log.error("issues API returned nil response")
        raise StandardError, "issues API returned invalid response"
      end

      # Convert to array if it's a single issue (shouldn't happen with auto_paginate, but safety first)
      issues_response = [issues_response] unless issues_response.is_a?(Array)

      @log.debug("issue cache updated - cached #{issues_response.length} issues")
      @issues = issues_response
      @issues_last_updated = Time.now
      return @issues
    end
  end
end
