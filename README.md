# issue-db

[![test](https://github.com/runwaylab/issue-db/actions/workflows/test.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/test.yml)
[![lint](https://github.com/runwaylab/issue-db/actions/workflows/lint.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/lint.yml)
[![build](https://github.com/runwaylab/issue-db/actions/workflows/build.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/build.yml)
[![acceptance](https://github.com/runwaylab/issue-db/actions/workflows/acceptance.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/acceptance.yml)
[![release](https://github.com/runwaylab/issue-db/actions/workflows/release.yml/badge.svg)](https://github.com/runwaylab/issue-db/actions/workflows/release.yml)
[![coverage](./docs/assets/coverage.svg)](./docs/assets/coverage.svg)

A Ruby Gem to use GitHub Issues as a NoSQL JSON document db.

![issue-db](./docs/assets/issue-db.png)

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

This section goes into details on the following CRUD operations are available for the `issue-db` gem.

Note: All methods return the `IssueDB::Record` of the object which was involved in the operation

> [!IMPORTANT]  
> The key for the record is the title of the GitHub issue. This means that the key **must be unique** within the database. If you try to do any sort of duplicate operation on a key that already exists (like creating it again), the `issue-db` gem will return the existing record without modifying it. Here is an example log message where someone calls `db.create("order_number_123", { location: "London", items: [ "cookies", "espresso" ] })` but the key already exists: `skipping issue creation and returning existing issue - an issue already exists with the key: order_number_123`. Additionally, if there are duplicates (same issue titles), then the latest issue will be returned (ex: issue 15 will be returned instead of issue 14). Basically, if you use fully unique keys, you won't ever run into this issue so please make sure to use unique keys for your records!

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

### `db.refresh!`

Force a refresh of the database cache. This will make a request to the GitHub API to get the latest data from the GitHub issues in the repository.

This can be useful if you have made changes to the database outside of the gem and don't want to wait for the cache to refresh. By default, the cache refreshes every 60 seconds. Modified records (such as an `update` operation) will be refreshed automatically into the cache so that subsequent reads will return the updated data. The only time you really need to worry about refreshing the cache is if you have made changes to the database outside of the gem or if there is another service using this gem that is also making changes to the database.

Example:

```ruby
db.refresh!
```

## Options 🛠

This section will go into detail around how you can configure the `issue-db` gem to behave:

### Environment Variables 🌍

| Name | Description | Default Value |
|------|-------------|---------------|
| `LOG_LEVEL` | The log level to use for the `issue-db` gem. Can be one of `DEBUG`, `INFO`, `WARN`, `ERROR`, or `FATAL` | `INFO` |
| `ISSUE_DB_LABEL` | The label to use for the issues that are used as records in the database. This value is required and it is what this gem uses to scan a repo for the records it is aware of. | `issue-db` |
| `ISSUE_DB_CACHE_EXPIRY` | The number of seconds to cache the database in memory. The database is cached in memory to avoid making a request to the GitHub API for every operation. The default value is 60 seconds. | `60` |
| `GH_APP_SLEEP` | The number of seconds to sleep between requests to the GitHub API in the event of an error | `3` |
| `GH_APP_RETRIES` | The number of retries to make when there is an error making a request to the GitHub API | `10` |
| `GH_APP_EXPONENTIAL_BACKOFF` | Whether to use exponential backoff for retries. When `true`, sleep time doubles with each retry. When `false`, uses fixed sleep time. | `false` |
| `GH_APP_ALGO` | The algo to use for your GitHub App if providing a private key | `RS256` |
| `ISSUE_DB_GITHUB_TOKEN` | The GitHub personal access token to use for authenticating with the GitHub API. You can also use a GitHub app or pass in your own authenticated Octokit.rb instance | `nil` |

## Authentication 🔒

The `issue-db` gem uses the [`Octokit.rb`](https://github.com/octokit/octokit.rb) library under the hood for interactions with the GitHub API. You have four options for authentication when using the `issue-db` gem:

> Note: The order displayed below is also the order of priority that this Gem uses to authenticate.

1. Pass in your own authenticated `Octokit.rb` instance to the `IssueDB.new` method
2. Pass GitHub App authentication parameters directly to the `IssueDB.new` method
3. Use a GitHub App by setting the `ISSUE_DB_GITHUB_APP_ID`, `ISSUE_DB_GITHUB_APP_INSTALLATION_ID`, and `ISSUE_DB_GITHUB_APP_KEY` environment variables
4. Use a GitHub personal access token by setting the `ISSUE_DB_GITHUB_TOKEN` environment variable

> Using a GitHub App is the suggested method

Here are examples of each of these options:

### Using a GitHub Personal Access Token

```ruby
# Assuming you have a GitHub personal access token set as the ISSUE_DB_GITHUB_TOKEN env var
require "issue_db"

db = IssueDB.new("<org>/<repo>") # THAT'S IT! 🎉
```

### Using GitHub App Parameters Directly

You can now pass GitHub App authentication parameters directly to the `IssueDB.new` method. This is especially useful when you want to manage authentication credentials in your application code or when you have multiple GitHub Apps for different purposes:

```ruby
require "issue_db"

# Pass GitHub App credentials directly to IssueDB.new
db = IssueDB.new(
  "<org>/<repo>",
  app_id: 12345,                    # Your GitHub App ID
  installation_id: 56789,          # Your GitHub App Installation ID
  app_key: "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",  # Your GitHub App private key
  app_algo: "RS256"                 # Optional: defaults to RS256
)
```

**Parameters:**

- `app_id` (Integer) - Your GitHub App ID (found on the App's settings page)
- `installation_id` (Integer) - Your GitHub App Installation ID (found in the installation URL: `https://github.com/organizations/<org>/settings/installations/<installation_id>`)
- `app_key` (String) - Your GitHub App private key (can be the key content as a string or a file path ending in `.pem`)
- `app_algo` (String, optional) - The algorithm to use for JWT signing (defaults to "RS256")

### Using a GitHub App with Environment Variables

This is the single best way to use the `issue-db` gem because GitHub Apps have increased rate limits, fine-grained permissions, and are more secure than using a personal access token. All you have to do is provide three environment variables and the `issue-db` gem will take care of the rest:

- `ISSUE_DB_GITHUB_APP_ID`
- `ISSUE_DB_GITHUB_APP_INSTALLATION_ID`
- `ISSUE_DB_GITHUB_APP_KEY`

Here is an example of how you can use a GitHub app with the `issue-db` gem:

```ruby
# Assuming you have the following three environment variables set:

# 1: ISSUE_DB_GITHUB_APP_ID
# app ids are found on the App's settings page

# 2: ISSUE_DB_GITHUB_APP_INSTALLATION_ID
# installation ids look like this:
# https://github.com/organizations/<org>/settings/installations/<8_digit_id>

# 3. ISSUE_DB_GITHUB_APP_KEY
# app keys are found on the App's settings page and can be downloaded
# format: "-----BEGIN...key\n...END-----\n" (this will be one super long string and that's okay)
# make sure this key in your env is a single line string with newlines as "\n"

# With all three of these environment variables set, you can proceed with ease!
db = IssueDB.new("<org>/<repo>") # THAT'S IT! 🎉
```

### Using Your Own Authenticated `Octokit.rb` Instance

```ruby
require "octokit"

# Create your own authenticated Octokit.rb instance
# You should probably set the page_size to 100 and auto_paginate to true
octokit = Octokit::Client.new(access_token: "<TOKEN>", page_size: 100)
octokit.auto_paginate = true

db = IssueDB.new("<org>/<repo>", octokit_client: octokit)
```

## Advanced Example 🚀

Here is a more advanced example of using the `issue-db` gem that demonstrates many different features of the gem:

```ruby
# Assuming you have a GitHub personal access token set as the ISSUE_DB_GITHUB_TOKEN env var
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

## Embedding Markdown in the Issue Body 📝

With this library, you can write markdown text into the issue body **in addition** to the JSON data. Pretty cool right?

This can be especially useful if you want to add additional context to the data in the issue body for humans to read. For example, you want to open an issue to track the status of an employee who has a laptop that is running an out of date operating system. You might want to do a `db.write()` operation with machine readable data but _also_ include a note for the employee to read. Here is an example of how you can do that:

```ruby
body_before_text = <<~BODY
# Out of Date Operating System 🚨

<!--- HUMANS: DO NOT EDIT THIS ISSUE BODY ;) -->

It looks like your laptop is running an out of date operating system. This is a security risk.

Please update your OS as soon as possible.

## Details
BODY

body_after_text = <<~BODY
> Thank you for your attention to this matter.
BODY

options = { body_before: body_before_text, body_after: body_after_text }
data = { operating_system: "macOS 1.2.3", last_updated_at: "2024-09-30", user: "Celeste", location: "California", out_of_date: true, employee_id: 123 }
record = db.create("Out of Date OS - EmployeeID: 123", data, options) # this assumes that employee IDs are unique in this example
```

Running that code snippet will result in a database record (GitHub issue) being created that has the following markdown body:

````markdown
# Out of Date Operating System 🚨

<!--- HUMANS: DO NOT EDIT THIS ISSUE BODY ;) -->

It looks like your laptop is running an out of date operating system. This is a security risk.

Please update your OS as soon as possible.

## Details

<!--- issue-db-start -->
```json
{
  "operating_system": "macOS 1.2.3",
  "last_updated_at": "2024-09-30",
  "user": "Celeste",
  "location": "California",
  "out_of_date": true
}
```
<!--- issue-db-end -->

> Thank you for your attention to this matter.
````

Here is a screenshot of exactly how this issue would render in GitHub:

![example1](./docs/assets/example1.png)

And here is a link to the actual issue in GitHub: [issue link](https://github.com/runwaylab/issue-db/issues/19)

Now the best part about this, is that we can still use the `db.read()` method flawlessly and get the data back in a machine readable format, and we can even get back the markdown text as well! Here is an example of how you can do that:

```ruby
record = db.read("Out of Date OS - EmployeeID: 123")

puts record.data # => {"operating_system"=>"macOS 1.2.3", "last_updated_at"=>"2024-09-30", "user"=>"Celeste", "location"=>"California", "out_of_date"=>true, "employee_id"=>123}
puts record.body_before # the markdown text before the data in the issue body (as seen above, not going to repeat it here - its long)
puts record.body_after # ditto ^
# puts record.source_data.body # useful for getting the raw markdown text of the issue body as is
```

Here is a screenshot of the output of the script above:

![example2](./docs/assets/example2.png)

## Record Attributes 📦

Database "items" are called Records in this library. Records are represented by a `IssueDB::Record` object. Records are actually just GitHub issues under the hood!

Records have the following attributes:

- `key` (String) - The unique key for the record. This is the title of the GitHub issue.
- `data` (Hash) - The data for the record. This can be any valid JSON data type (String, Number, Boolean, Array, Object, or nil).
- `source_data` (Octokit::Issue) - The GitHub issue object that is the source of the record. This value is returned by Octokit and is a Sawyer::Resource object.
- `body_before` (String) - The markdown text before the data in the issue body.
- `body_after` (String) - The markdown text after the data in the issue body.

Example:

```ruby
record = db.read("order_number_123")

puts record.key # => "order_number_123"
puts record.data # => { "location"=>"London", "items"=>[ "cookies", "espresso", "chips" ] }
puts record.data["location"] # => "London"
puts record.source_data.state # => "open" (the GitHub issue is open so the record is active)
puts record.body_before # => "some markdown text before the data"
puts record.body_after # => "some markdown text after the data"
```
