# frozen_string_literal: true

module Init
  def init!
    begin
      @client.add_label(
        @repo.full_name,
        @label,
        "000000",
        { description: "This issue is managed by the issue-db Ruby library. Please do not remove this label." }
      )
    rescue StandardError => e
      if e.message.include?("code: already_exists")
        @log.debug("label #{@label} already exists")
      else
        @log.error("error creating label: #{e.message}") unless ENV.fetch("ENV", nil) == "acceptance"
      end
    end
  end
end
