# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/issue_db/database"

describe Database, :vcr do
  before(:all) do
    @client = Octokit::Client.new(access_token: FAKE_TOKEN, page_size: 100)
    @client.auto_paginate = true
  end

  let(:repo) { instance_double(Repository, full_name: REPO) }
  let(:current_time) { Time.parse("2024-01-01 00:00:00").utc }
  let(:log) { instance_double(RedactingLogger).as_null_object }
  let(:label) { "issue-db" }
  let(:cache_expiry) { 60 }

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
    Retry.setup!(log:)
  end

  subject { described_class.new(log, @client, repo, label, cache_expiry) }

  it "returns a database object successfully" do
    expect(subject.class).to eq(Database)
  end

  it "reads a single issue successfully" do
    issue = subject.read("event456")
    expect(issue.source_data.number).to eq(8)
    expect(issue.source_data.state).to eq("open")
    expect(issue.source_data.html_url).to match(/runwaylab\/issue-db\/issues\/8/)
  end

  context "rate limits" do
    it "hits rate limits while trying to read an issue" do
      expect(log).to receive(:debug).with(/checking rate limit status for type: search/)
      expect(log).to receive(:debug).with(/rate_limit remaining: 0/)
      expect(log).to receive(:info).with(/github rate_limit hit/)
      issue = subject.read("event456")
      expect(issue.source_data.number).to eq(8)
      expect(issue.source_data.state).to eq("open")
      expect(issue.source_data.html_url).to match(/runwaylab\/issue-db\/issues\/8/)
    end

    it "thinks that rate limits are hit while trying to read an issue but they are not" do
      expect(log).to receive(:debug).with(/checking rate limit status for type: core/)
      expect(log).to receive(:debug).with(/rate_limit remaining: 0/)
      expect(log).to receive(:debug).with(/rate_limit not hit - remaining: 1000/)
      issue = subject.create("event999", {cool: true})
      expect(issue.source_data.number).to eq(11)
      expect(issue.source_data.state).to eq("open")
      expect(issue.source_data.html_url).to match(/runwaylab\/issue-db\/issues\/11/)
    end
  end
end
