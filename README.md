# issue-db

[![test](https://github.com/runwaylab/issue-db/actions/workflows/test.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/test.yml)
[![lint](https://github.com/runwaylab/issue-db/actions/workflows/lint.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/lint.yml)
[![build](https://github.com/runwaylab/issue-db/actions/workflows/build.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/build.yml)
[![acceptance](https://github.com/runwaylab/issue-db/actions/workflows/acceptance.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/acceptance.yml)
[![release](https://github.com/runwaylab/issue-db/actions/workflows/release.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/release.yml)
[![coverage](./docs/assets/coverage.svg)](./docs/assets/coverage.svg)

A Ruby Gem to use GitHub Issues as a NoSQL JSON document db.

## Quick Start ⚡

Here is an extremely basic example of using the `issue-db` gem:

```ruby
require "issue_db"

# The GitHub repository to use as the database
repo = "runwaylab/grocery-orders"

# Create a new database instance
db = IssueDB.new(repo)

# Write a new record to the database
db.create("order_number_123", { location: "London", items: [ "cookies", "espresso" ] })

# Read the newly created record from the database
record = db.read("order_number_123")

puts record.data # => {location: "London", items: ["cookies", "espresso"]}
```

Here is a more advanced example of using the `issue-db` gem:

```ruby
# Assuming you have a GitHub personal access token set as the GITHUB_TOKEN env var
require "issue_db"

# The GitHub repository to use as the database
repo = "runwaylab/grocery-orders"

# Create a new database instance
db = IssueDB.new(repo)

# Write a new record to the database where the title of the issue is the unique key
new_issue = db.create("order_number_123", { location: "London", items: [ "cookies", "espresso" ] })

# View the record data and the source data which contains the GitHub issue object
puts new_issue.data # => {location: "London", items: ["cookies", "espresso"]}
puts new_issue.source_data.state # => "open" (the GitHub issue is open so the record is active)
puts new_issue.source_data.html_url # => "https://github.com/runwaylab/grocery-orders/issues/<number>" (the URL of the GitHub issue which is the DB record)

# Update the record
updated_issue = db.update("order_number_123", { location: "London", items: [ "cookies", "espresso", "chips" ] })

# View the updated record data
puts updated_issue.data # => {location: "London", items: ["cookies", "espresso", "chips"]}

# Get the record by key
record = db.read("order_number_123")

# View the record data
puts record.data # => {location: "London", items: ["cookies", "espresso", "chips"]}

# Delete the record
deleted_record = db.delete("order_number_123")
puts deleted_record.source_data.state # => "closed" (the GitHub issue is closed as "completed" so the record is inactive)

# List all keys in the database including closed records
keys = db.list_keys({ include_closed: true })

puts keys # => ["order_number_123"]

# List all records in the database including closed records
records = db.list({ include_closed: true })

puts records.first.data # => {location: "London", items: ["cookies", "espresso", "chips"]}
puts records.first.source_data.state # => "closed" (the GitHub issue is closed as "completed" so the record is inactive)
```
