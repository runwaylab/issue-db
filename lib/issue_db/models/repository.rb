# frozen_string_literal: true

module IssueDB
  class RepoFormatError < StandardError; end

  class Repository
    attr_reader :owner, :repo, :full_name
    def initialize(repo)
      @repo = repo
      validate!
    end

  protected

    def validate!
      if @repo.nil? || !@repo.include?("/")
        raise RepoFormatError, "repository #{@repo} is invalid - valid format: <owner>/<repo>"
      end

      @full_name = @repo.strip
      @owner, @repo = @full_name.split("/")
    end
  end
end
