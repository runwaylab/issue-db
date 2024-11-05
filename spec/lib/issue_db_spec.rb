# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/issue_db"

describe IssueDB do
  let(:current_time) { Time.parse("2024-01-01 00:00:00").utc }
  let(:log) { instance_double(RedactingLogger).as_null_object }
  let(:client) { instance_double(Octokit::Client).as_null_object }

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
    allow(Octokit::Client).to receive(:new).and_return(client)
  end

  subject { described_class.new(REPO, log:, octokit_client: client) }

  it "is a valid version string" do
    expect(subject.version).to match(/\A\d+\.\d+\.\d+(\.\w+)?\z/)
  end
end
