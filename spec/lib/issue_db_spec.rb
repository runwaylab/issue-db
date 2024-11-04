# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/issue_db"

describe IssueDB do
  let(:current_time) { Time.parse("2024-01-01 00:00:00").utc }
  let(:log) { instance_double(RedactingLogger).as_null_object }
  let(:issue_db) { described_class.new(log:) }

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
  end

  it "is a valid version string" do
    expect(issue_db.version).to match(/\A\d+\.\d+\.\d+(\.\w+)?\z/)
  end
end
