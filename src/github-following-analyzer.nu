#!/usr/bin/env nu

# ==================================================================================================
# GitHub Following Analyzer
# ==================================================================================================
# Read-only following-minus-followers report for the current GitHub.com account.
# ==================================================================================================

use std-rfc/str

# --------------------------------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------------------------------

def valid-login [value: any]: nothing -> bool {
  if ($value | describe) != "string" {
    false
  } else {
    ($value | str length) <= 39 and $value =~ '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'
  }
}

def load-allow-list [file?: path]: nothing -> list<string> {
  let selected = ($file | default "config.toml")
  if not ($selected | path exists --no-symlink) {
    if $file == null {
      return []
    }
    error make {msg: $"Config ($selected) does not exist."}
  }

  let config = try {
    open --raw $selected | into string | from toml
  } catch {
    error make {msg: $"Cannot read TOML config ($selected)."}
  }
  if not ($config | describe | str starts-with "record") {
    error make {msg: $"Config ($selected) must contain a TOML root record."}
  }
  let unknown = ($config | columns | where {|key| $key != "allow_list" })
  if ($unknown | is-not-empty) {
    error make {
      msg: $"Config ($selected): unknown keys ($unknown | str join ', '). Expected allow_list."
    }
  }
  let allowed = ($config.allow_list? | default [])
  if not (($allowed | describe) =~ '^(list|table)') {
    error make {msg: $"Config ($selected): allow_list must be a list of GitHub usernames."}
  }
  if ($allowed | any {|login| not (valid-login $login) }) {
    error make {
      msg: $"Config ($selected): allow_list entries must be valid GitHub usernames without spaces or @."
    }
  }
  $allowed | str lowercase | uniq
}

# --------------------------------------------------------------------------------------------------
# Requests and validation
# --------------------------------------------------------------------------------------------------

def request [endpoint: string, --pages] {
  let pagination = if $pages { ["--paginate" "--slurp"] } else { [] }
  let response = (
    ^gh api $endpoint
      --hostname "github.com"
      --method "GET"
      --header "Accept: application/vnd.github+json"
      ...$pagination
    | complete
  )
  if $response.exit_code != 0 {
    let intro = (
      $"
      GitHub.com GET ($endpoint) failed.
      Check `gh auth login --hostname github.com` and the gh diagnostic:
      "
      | str dedent
    )
    error make {
      msg: ([$intro ($response.stderr | str trim)] | str join "\n")
    }
  }

  try {
    $response.stdout | from json
  } catch {
    error make {msg: $"GitHub.com GET ($endpoint) returned invalid JSON."}
  }
}

def account-login [account: any]: nothing -> string {
  if not ($account | describe | str starts-with "record") {
    error make {msg: "GitHub.com GET user returned an invalid account record."}
  }
  let login = $account.login?
  if not (valid-login $login) {
    error make {msg: "GitHub.com GET user returned an invalid account login."}
  }
  $login
}

def users [endpoint: string]: nothing -> list {
  let pages = (request $endpoint --pages)
  if not (($pages | describe) =~ '^(list|table)') or ($pages | is-empty) {
    error make {msg: $"GitHub.com GET ($endpoint) returned an invalid page list."}
  }

  mut rows = []
  for page in $pages {
    if not (($page | describe) =~ '^(list|table)') {
      error make {
        msg: $"GitHub.com GET ($endpoint) returned an invalid users page."
      }
    }
    for user in $page {
      if not ($user | describe | str starts-with "record") {
        error make {
          msg: $"GitHub.com GET ($endpoint) returned an invalid user record."
        }
      }
      if ($user.id? | describe) != "int" {
        error make {msg: $"GitHub.com GET ($endpoint) returned an invalid user ID."}
      }
      if $user.id <= 0 or not (valid-login $user.login?) {
        error make {
          msg: $"GitHub.com GET ($endpoint) returned an invalid user ID or login."
        }
      }
      if ($user.html_url? | describe) != "string" {
        error make {msg: $"GitHub.com GET ($endpoint) returned an invalid user URL."}
      }
      if $user.html_url !~ '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]*$' {
        error make {msg: $"GitHub.com GET ($endpoint) returned an invalid user URL."}
      }
      $rows = ($rows | append {
        id: $user.id
        login: $user.login
        url: $user.html_url
      })
    }
  }
  $rows | uniq-by id
}

# --------------------------------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------------------------------

def report [allowed: list<string>]: nothing -> record {
  if (which gh | is-empty) {
    error make {
      msg: (
        "
        GitHub CLI (gh) is required.
        Install gh, then run `gh auth login --hostname github.com`.
        "
        | str dedent
      )
    }
  }
  let login = (account-login (request "user"))
  let following = (users $"users/($login)/following?per_page=100")
  let followers = (users $"users/($login)/followers?per_page=100")
  let follower_ids = ($followers | get -o id)
  let unmatched = (
    $following
    | where {|user| $user.id not-in $follower_ids }
    | sort-by login --ignore-case
  )
  let actionable = (
    $unmatched
    | where {|user| ($user.login | str lowercase) not-in $allowed }
  )

  {
    account: $login
    following_count: ($following | length)
    followers_count: ($followers | length)
    allow_listed_count: (($unmatched | length) - ($actionable | length))
    not_following_back: $actionable
  }
}

# List accounts you follow that do not follow you back on GitHub.com. Uses gh credentials.
def main [
  --config: path # TOML config, default ./config.toml. An absent default file is optional.
  --json # Emit a complete JSON record on stdout.
] {
  let result = try {
    let allowed = (load-allow-list $config)
    report $allowed
  } catch {|err|
    print --stderr $err.msg
    exit 1
  }

  let summary = [
    $"Account: ($result.account)."
    $"Following: ($result.following_count)."
    $"Followers: ($result.followers_count)."
    $"Allowed: ($result.allow_listed_count)."
    $"Not following back: ($result.not_following_back | length)."
  ]
  print --stderr ($summary | str join " ")
  if $json {
    print ($result | to json)
  } else if ($result.not_following_back | is-empty) {
    print "No accounts to review."
  } else {
    for user in $result.not_following_back {
      print $"($user.login) ($user.url)"
    }
  }
}
