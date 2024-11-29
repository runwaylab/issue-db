# issue-db

[![test](https://github.com/runwaylab/issue-db/actions/workflows/test.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/test.yml)
[![lint](https://github.com/runwaylab/issue-db/actions/workflows/lint.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/lint.yml)
[![build](https://github.com/runwaylab/issue-db/actions/workflows/build.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/build.yml)
[![acceptance](https://github.com/runwaylab/issue-db/actions/workflows/acceptance.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/acceptance.yml)
[![release](https://github.com/runwaylab/issue-db/actions/workflows/release.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/release.yml)
[![coverage](./docs/assets/coverage.svg)](./docs/assets/coverage.svg)

A Ruby Gem to use GitHub Issues as a NoSQL JSON document db.

## Quick Start ⚡

The `issue-db` gem uses CRUD operations to read and write data to a GitHub repository using issues as the records. The title of the issue is used as the unique key for the record and the body of the issue is used to store the data in JSON format.

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

> A more detailed example can be found below.

## Installation 🚚

You may install this Gem from either [RubyGems](https://rubygems.org/gems/issue-db) or [GitHub Packages](https://github.com/runwaylab/issue-db/pkgs/rubygems/issue-db).

RubyGems:

```ruby
source "https://rubygems.org"

gem "issue-db", "X.X.X" # Replace X.X.X with the version you want to use
```

GitHub Packages:

```ruby
source "https://rubygems.pkg.github.com/runwaylab" do
  gem "issue-db", "X.X.X" # Replace X.X.X with the version you want to use
end
```

Command Line Installation:

```sh
gem install issue-db --version "X.X.X"
```

## Usage 💻

The following CRUD operations are available for the `issue-db` gem:

> Note: All methods return the `IssueDB::Record` of the object which was involved in the operation

### `db.create(key, data, options = {})`

- `key` (String) - The unique key for the record. This is the title of the GitHub issue. It must be unique within the database.
- `data` (Hash) - The data to write to the record. This can be any valid JSON data type (String, Number, Boolean, Array, Object, or nil).
- `options` (Hash) - A hash of options to configure the create operation.

Example:

```ruby
record = db.create("order_number_123", { location: "London", items: [ "cookies", "espresso" ] })

# with the `body_before` and `body_after` options to add markdown text before and after the data in the GitHub issue body
# this can be useful if you want to add additional context to the data in the issue body for humans to read
# more on this in another section of the README below
options = { body_before: "some markdown text before the data", body_after: "some markdown text after the data" }
record = db.create("order_number_123", { location: "London", items: [ "cookies", "espresso" ] }, options)
```

Notes:

- If the key already exists in the database, the `create` method will return the existing record without modifying it.

### `db.read(key, options = {})`

- `key` (String) - The unique key for the record. This is the title of the GitHub issue.
- `options` (Hash) - A hash of options to configure the read operation.

Example:

```ruby
record = db.read("order_number_123")

# with the `include_closed` option to include records that have been deleted (i.e. the GitHub issue is closed)
options = { include_closed: true }
record = db.read("order_number_123", options)
```

### `db.update(key, data, options = {})`

- `key` (String) - The unique key for the record. This is the title of the GitHub issue.
- `data` (Hash) - The data to write to the record. This can be any valid JSON data type (String, Number, Boolean, Array, Object, or nil).
- `options` (Hash) - A hash of options to configure the update operation.

Example:

```ruby
record = db.update("order_number_123", { location: "London", items: [ "cookies", "espresso", "chips" ] })

# with the `body_before` and `body_after` options to add markdown text before and after the data in the GitHub issue body
# this can be useful if you want to add additional context to the data in the issue body for humans to read
# more on this in another section of the README below
options = { body_before: "# Order 123\n\nData:", body_after: "Please do not edit the body of this issue" }
record = db.update("order_number_123", { location: "London", items: [ "cookies", "espresso", "chips" ] }, options)
```

### `db.delete(key, options = {})`

- `key` (String) - The unique key for the record. This is the title of the GitHub issue.
- `options` (Hash) - A hash of options to configure the delete operation.

Example:

```ruby
record = db.delete("order_number_123")
```

### `db.list_keys(options = {})`

- `options` (Hash) - A hash of options to configure the list operation.

Example:

```ruby
keys = db.list_keys

# with the `include_closed` option to include records that have been deleted (i.e. the GitHub issue is closed)
options = { include_closed: true }
keys = db.list_keys(options)
```

### `db.list(options = {})`

- `options` (Hash) - A hash of options to configure the list operation.

Example:

```ruby
records = db.list

# with the `include_closed` option to include records that have been deleted (i.e. the GitHub issue is closed)
options = { include_closed: true }
records = db.list(options)
```

## Advanced Example 🚀

Here is a more advanced example of using the `issue-db` gem that demonstrates many different features of the gem:

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

# Inspection of the first record in the list
puts records.first.data # => {location: "London", items: ["cookies", "espresso", "chips"]}
puts records.first.source_data.state # => "closed" (the GitHub issue is closed as "completed" so the record is inactive)

# Force a refresh of the database cache (useful if you have made changes to the database outside of the gem and don't want to wait for the cache to refresh)
db.refresh!
```
