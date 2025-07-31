# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/issue_db"

describe IssueDB::Client do
  let(:current_time) { Time.parse("2024-01-01 00:00:00").utc }
  let(:log) { instance_double(RedactingLogger).as_null_object }
  let(:client) { instance_double(Octokit::Client).as_null_object }
  let(:database) { instance_double(IssueDB::Database).as_null_object }
  let(:record) { instance_double(IssueDB::Record).as_null_object }

  before(:each) do
    allow(Time).to receive(:now).and_return(current_time)
    allow(Octokit::Client).to receive(:new).and_return(client)
    allow(IssueDB::Database).to receive(:new).and_return(database)
    allow(record).to receive(:data).and_return({ "cool" => true, "number" => 1 })
  end

  subject { described_class.new(REPO, log:, octokit_client: client) }

  it "allows module-level instantiation via IssueDB.new" do
    # This tests the module-level new method that delegates to Client.new
    instance = IssueDB.new(REPO, log:, octokit_client: client)
    expect(instance).to be_a(IssueDB::Client)
  end

  it "is a valid version string" do
    expect(subject.version).to match(/\A\d+\.\d+\.\d+(\.\w+)?\z/)
  end

  context "#read" do
    it "makes a read operation" do
      expect(database).to receive(:read).with("event123", {}).and_return(record)
      record = subject.read("event123")
      expect(record.data["cool"]).to eq(true)
    end
  end

  context "#create" do
    it "makes a create operation" do
      expect(database).to receive(:create).with("event123", { "cool" => true, "number" => 1 }, {}).and_return(record)
      record = subject.create("event123", { "cool" => true, "number" => 1 })
      expect(record.data["cool"]).to eq(true)
    end
  end

  context "#update" do
    it "makes an update operation" do
      expect(database).to receive(:update).with("event123", { "cool" => true, "number" => 1 }, {}).and_return(record)
      record = subject.update("event123", { "cool" => true, "number" => 1 })
      expect(record.data["cool"]).to eq(true)
    end
  end

  context "#delete" do
    it "makes a delete operation" do
      expect(database).to receive(:delete).with("event123", {}).and_return(record)
      record = subject.delete("event123")
      expect(record.data["cool"]).to eq(true)
    end
  end

  context "#list" do
    it "makes a list operation" do
      expect(database).to receive(:list).with({}).and_return([record])
      records = subject.list
      expect(records.first.data["cool"]).to eq(true)
    end
  end

  context "#list_keys" do
    it "makes a list_keys operation" do
      expect(database).to receive(:list_keys).with({}).and_return(["event123", "event456", "event789"])
      records = subject.list_keys
      expect(records.first).to eq("event123")
    end
  end

  context "#refresh!" do
    it "makes a refresh! operation" do
      expect(database).to receive(:refresh!).and_return([])
      expect(subject.refresh!).to eq([])
    end
  end
end
