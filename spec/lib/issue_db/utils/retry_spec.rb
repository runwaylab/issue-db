# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/retry"

describe Retry do
  let(:log) { instance_double(Logger).as_null_object }

  describe ".setup!" do
    it "raises an ArgumentError when no logger is provided" do
      expect { described_class.setup! }.to raise_error(ArgumentError, "a logger must be provided")
    end

    it "configures Retryable with the correct default context" do
      described_class.setup!(log:)

      expect(Retryable.configuration.contexts[:default]).to include(
        on: [StandardError]
      )
    end

    it "logs the correct message when a retry occurs" do
      $stdout.sync = true
      described_class.setup!(log:)

      Retryable.with_context(:default) do |retries, _exception|
        expect(retries).to eq(0)
        raise StandardError, "test"
      rescue StandardError => error
        expect(error.message).to eq("test")
      end
    end
  end
end
