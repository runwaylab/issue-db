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

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
    Retry.setup!(log:)
  end

  subject { described_class.new(log, @client, repo) }

  it "returns a database object successfully" do
    expect(subject.class).to eq(Database)
  end

  it "reads a single issue successfully" do
    issue = subject.read(1)
    expect(issue.number).to eq(1)
    expect(issue.state).to eq("closed")
    expect(issue.html_url).to match(/monalisa\/octo-awesome\/issues\/1/)
  end
end
