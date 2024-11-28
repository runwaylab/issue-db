# frozen_string_literal: true

require "rspec"
require_relative "../../lib/issue_db"

db = IssueDB.new("runwaylab/issue-db")

options = {
  include_closed: true,
}

describe IssueDB do
  context "#list" do
    records = db.list(options)
    records.each do |record|
      it "expects the record to have a data attribute and be hashes" do
        expect(record.data).to be_a(Hash)
      end

      it "expects the record to have a body_before attribute and be a string (even an empty one is fine)" do
        expect(record.body_before).to be_a(String)
      end

      it "expects the record to have a body_after attribute and be a string (even an empty one is fine)" do
        expect(record.body_after).to be_a(String)
      end

      it "expects the source data to have a number attribute and be a number" do
        expect(record.source_data[:number]).to be_a(Integer)
      end
    end
  end

  context "#read" do
    it "successfully reads an issue and returns a record even though it is closed" do
      record = db.read("event456")
      expect(record).to be_a(Record)
      expect(record.data).to be_a(Hash)
      expect(record.data["cool"]).to eq(true)
      expect(record.body_before).to match(/# Cool Issue/)
      expect(record.body_after).to match(/Some text below the data/)
      expect(record.source_data[:number]).to eq(8)
    end
  end
end
