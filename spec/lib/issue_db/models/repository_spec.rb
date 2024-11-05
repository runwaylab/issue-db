# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/issue_db/models/repository"

describe Repository do
  it "returns a valid repository" do
    repo = Repository.new(REPO)
    expect(repo.full_name).to eq(REPO)
    expect(repo.repo).to eq(REPO.split("/").last)
    expect(repo.owner).to eq(REPO.split("/").first)
  end

  it "raises an error if an invalid repo name is provided" do
    invalid_repo_name = "some#invalid?$repo!-|name+"
    expect do
      Repository.new(invalid_repo_name)
    end.to raise_error(
      RepoFormatError,
      "repository #{invalid_repo_name} is invalid - valid format: <owner>/<repo>"
    )
  end
end
