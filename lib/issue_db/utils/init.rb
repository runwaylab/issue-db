# frozen_string_literal: true

module IssueDB
  module Init
  # A helper method for initializing the IssueDB library when .new is called
  # Everything in this method should be idempotent and safe to call multiple times
    def init!
      begin
        @client.add_label(
          @repo.full_name,
          @label,
          "000000",
          { description: "This issue is managed by the issue-db Ruby library. Please do not remove this label." },
          disable_retry: true
        )
      rescue StandardError => e
        if e.message.include?("already_exists")
          @log.debug("label #{@label} already exists")
        else
          @log.error("error creating label: #{e.message}") unless ENV.fetch("ENV", nil) == "acceptance"
        end
      end
    end
  end
end
