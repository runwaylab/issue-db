# frozen_string_literal: true

require "spec_helper"
require "octokit"

RSpec.describe "GitHub API", :vcr do
  before(:all) do
    @client = Octokit::Client.new(access_token: ENV["GITHUB_TOKEN"], page_size: 100)
    @client.auto_paginate = true
    @repo = "monalisa/octo-awesome"
    @login = "monalisa"
  end

  it "fetches all open issues" do
    issues = @client.list_issues(@repo, state: "open")
    expect(issues).not_to be_empty
  end

  it "fetches the client rate limit" do
    rate_limit = @client.get("rate_limit")
    expect(rate_limit[:resources][:core][:remaining]).to be > 0
  end

  it "fetches all issues including closed issues" do
    issues = @client.list_issues(@repo, state: "all")
    expect(issues).not_to be_empty
  end

  it "marks all currently open issues as closed" do
    issues = @client.list_issues(@repo, state: "open")
    issues.each do |issue|
      @client.close_issue(@repo, issue.number)
    end
    closed_issues = @client.list_issues(@repo, state: "closed")
    expect(closed_issues).not_to be_empty
  end

  it "gets a single issue by number" do
    issue_number = 1
    issue = @client.issue(@repo, issue_number)
    expect(issue.number).to eq(issue_number)
  end

  it "creates a new issue" do
    issue = @client.create_issue(@repo, "New issue title", "New issue body")
    expect(issue.title).to eq("New issue title")
  end

  it "assigns an existing issue to a person" do
    issue_number = 1
    assignee = @login
    issue = @client.update_issue(@repo, issue_number, assignees: [assignee])
    expect(issue.assignees.map(&:login)).to include(assignee)
  end

  it "reopens an issue with a comment" do
    issue_number = 1
    @client.reopen_issue(@repo, issue_number)
    comment = @client.add_comment(@repo, issue_number, "Reopening this issue")
    expect(comment.body).to eq("Reopening this issue")
  end

  it "adds a comment to an already open issue" do
    issue_number = 1
    comment = @client.add_comment(@repo, issue_number, "Adding a comment")
    expect(comment.body).to eq("Adding a comment")
  end

  it "uses the search API to find issues" do
    query = "repo:#{@repo} author:#{@login}"
    issues = @client.search_issues(query)
    expect(issues.items).not_to be_empty
  end

  it "locks an issue" do
    issue_number = 1
    @client.lock_issue(@repo, issue_number)
    issue = @client.issue(@repo, issue_number)
    expect(issue.locked).to be true
  end

  it "unlocks an issue" do
    issue_number = 1
    @client.unlock_issue(@repo, issue_number)
    issue = @client.issue(@repo, issue_number)
    expect(issue.locked).to be false
  end

  it "lists comments on an issue" do
    issue_number = 1
    comments = @client.issue_comments(@repo, issue_number)
    expect(comments).not_to be_empty
  end

  it "edits an issue" do
    issue_number = 1
    updated_title = "Updated issue title"
    updated_body = "Updated issue body"
    issue = @client.update_issue(@repo, issue_number, title: updated_title, body: updated_body)
    expect(issue.title).to eq(updated_title)
    expect(issue.body).to eq(updated_body)
  end

  it "deletes a comment" do
    issue_number = 1
    comment = @client.add_comment(@repo, issue_number, "This comment will be deleted")
    @client.delete_comment(@repo, comment.id)
    comments = @client.issue_comments(@repo, issue_number)
    expect(comments.map(&:id)).not_to include(comment.id)
  end

  it "updates issue labels" do
    issue_number = 1
    labels = ["bug", "enhancement"]
    issue = @client.update_issue(@repo, issue_number, labels: labels)
    expect(issue.labels.map(&:name)).to include(*labels)
  end

  it "updates issue milestones" do
    issue_number = 1
    milestone_number = 1 # Replace with a valid milestone number
    issue = @client.update_issue(@repo, issue_number, milestone: milestone_number)
    expect(issue.milestone.number).to eq(milestone_number)
  end

  it "lists all labels for a repository" do
    labels = @client.labels(@repo)
    expect(labels).not_to be_empty
  end

  it "lists all milestones for a repository" do
    milestones = @client.milestones(@repo)
    expect(milestones).not_to be_empty
  end

  it "lists all issues assigned to a user" do
    issues = @client.list_issues(@repo, assignee: @login)
    expect(issues).not_to be_empty
  end

  it "lists all issues created by a user" do
    issues = @client.list_issues(@repo, creator: @login)
    expect(issues).not_to be_empty
  end

  it "lists all issues mentioning a user" do
    issues = @client.list_issues(@repo, mentioned: @login)
    expect(issues).not_to be_empty
  end
end
