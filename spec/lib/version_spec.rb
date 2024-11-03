# frozen_string_literal: true

require "spec_helper"

describe IssueDB do
  it "is a valid version string" do
    expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+(\.\w+)?\z/)
  end
end
