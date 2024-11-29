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

  context "read" do
    it "reads a single issue successfully" do
      issue = subject.read("event456")
      expect(issue.source_data.number).to eq(8)
      expect(issue.source_data.state).to eq("open")
    end

    it "throws an error if the record cannot be found" do
      expect { subject.read("event888") }.to raise_error(RecordNotFound, /no record found for key: event888/)
    end

    it "finds that the issue cache is expired so it refreshes the cache on a read" do
      # force a cache refresh
      subject.refresh!

      expect(Time).to receive(:now).and_return(current_time + 65)
      expect(log).to receive(:debug).with(/issue cache expired - last updated/)
      issue = subject.read("event456")
      expect(issue.source_data.number).to eq(8)
    end
  end

  context "create" do
    it "fails due to bad credentials" do
      expect { subject.create("event456", {cool: true}) }.to raise_error(StandardError, /401 - Bad credentials/)
    end

    it "attempts to create a new record and finds that one already exists for the given key" do
      expect(log).to receive(:warn).with(/skipping issue creation/)
      issue = subject.create("event456", {cool: true})
      expect(issue.source_data.number).to eq(8)
      expect(issue.source_data.state).to eq("open")
    end
  end

  context "update" do
    it "updates an issue successfully" do
      issue = subject.update("event999", {cool: false})
      expect(issue.source_data.number).to eq(12)
      expect(issue.source_data.state).to eq("open")
    end
  end

  context "delete" do
    it "deletes an issue successfully (closes)" do
      issue = subject.delete("event999")
      expect(issue.source_data.number).to eq(11)
      expect(issue.source_data.state).to eq("closed")
    end
  end

  context "list_keys" do
    it "lists all keys successfully" do
      keys = subject.list_keys
      expect(keys).to eq(%w[event456 event234 event123])
    end
  end

  context "list" do
    it "lists all records successfully" do
      records = subject.list
      expect(records.first.data).to eq({"age"=>333, "apple"=>"red", "cool"=>true, "user"=>"mona"})
      expect(records.first.source_data.number).to eq(8)
      expect(records.last.source_data.number).to eq(6)
      expect(records.size).to eq(3)
    end
  end

  context "refresh!" do
    it "refreshes the cache successfully" do
      results = subject.refresh!
      expect(results.length).to eq(5)
      expect(results.first.number).to eq(11)
    end
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
    end
  end
end
