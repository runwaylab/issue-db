# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/utils/init"

class DummyClass
  include Init

  attr_accessor :client, :repo, :label, :log

  def initialize(client, repo, label, log)
    @client = client
    @repo = repo
    @label = label
    @log = log
  end
end

describe Init do
  let(:client) { double("client") }
  let(:repo) { double("repo", full_name: "user/repo") }
  let(:label) { "issue-db" }
  let(:log) { double("log", debug: nil, error: nil) }
  let(:dummy_instance) { DummyClass.new(client, repo, label, log) }

  describe "#init!" do
    context "when label is created successfully" do
      it "creates the label without errors" do
        expect(client).to receive(:add_label).with(
          "user/repo",
          "issue-db",
          "000000",
          { description: "This issue is managed by the issue-db Ruby library. Please do not remove this label." },
          disable_retry: true
        )

        dummy_instance.init!
      end
    end

    context "when label already exists" do
      it "logs a debug message" do
        allow(client).to receive(:add_label).with(
          "user/repo",
          "issue-db",
          "000000",
          { description: "This issue is managed by the issue-db Ruby library. Please do not remove this label." },
          disable_retry: true
        ).and_raise(StandardError.new("already_exists"))

        expect(log).to receive(:debug).with("label issue-db already exists")

        dummy_instance.init!
      end
    end

    context "when another error occurs" do
      it "logs an error message" do
        allow(client).to receive(:add_label).with(
          "user/repo",
          "issue-db",
          "000000",
          { description: "This issue is managed by the issue-db Ruby library. Please do not remove this label." },
          disable_retry: true
        ).and_raise(StandardError.new("some other error"))

        expect(log).to receive(:error).with("error creating label: some other error")

        dummy_instance.init!
      end

      it "does not log an error message in acceptance environment" do
        allow(client).to receive(:add_label).with(
          "user/repo",
          "issue-db",
          "000000",
          { description: "This issue is managed by the issue-db Ruby library. Please do not remove this label." },
          disable_retry: true
        ).and_raise(StandardError.new("some other error"))
        allow(ENV).to receive(:fetch).with("ENV", nil).and_return("acceptance")

        expect(log).not_to receive(:error)

        dummy_instance.init!
      end
    end
  end
end
