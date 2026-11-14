#!/usr/bin/env nu

# ==================================================================================================
# GitHub Following Analyzer
# ==================================================================================================
# Read-only following-minus-followers report for the current GitHub.com account.
# ==================================================================================================

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
    error make {msg: $"GitHub.com GET ($endpoint) failed. Check `gh auth login --hostname github.com` and the gh diagnostic:\n($response.stderr | str trim)"}
  }

  try {
    $response.stdout | from json
  } catch {
    error make {msg: $"GitHub.com GET ($endpoint) returned invalid JSON."}
  }
}

def valid-login [value: any]: nothing -> bool {
  if ($value | describe) != "string" {
    false
  } else {
    $value =~ '^[A-Za-z0-9][A-Za-z0-9-]*$'
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
      error make {msg: $"GitHub.com GET ($endpoint) returned an invalid users page."}
    }
    for user in $page {
      if not ($user | describe | str starts-with "record") {
        error make {msg: $"GitHub.com GET ($endpoint) returned an invalid user record."}
      }
      if ($user.id? | describe) != "int" {
        error make {msg: $"GitHub.com GET ($endpoint) returned an invalid user ID."}
      }
      if $user.id <= 0 or not (valid-login $user.login?) {
        error make {msg: $"GitHub.com GET ($endpoint) returned an invalid user ID or login."}
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

def report []: nothing -> record {
  if (which gh | is-empty) {
    error make {msg: "GitHub CLI (gh) is required. Install gh, then run `gh auth login --hostname github.com`."}
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

  {
    account: $login
    following_count: ($following | length)
    followers_count: ($followers | length)
    not_following_back: $unmatched
  }
}

# List accounts you follow that do not follow you back on GitHub.com. Uses gh credentials.
def main [
  --json # Emit a complete JSON record on stdout.
] {
  let result = try {
    report
  } catch {|err|
    print --stderr $err.msg
    exit 1
  }

  print --stderr $"Account: ($result.account). Following: ($result.following_count). Followers: ($result.followers_count). Not following back: ($result.not_following_back | length)."
  if $json {
    print ($result | to json)
  } else if ($result.not_following_back | is-empty) {
    print "Everyone you follow follows you back."
  } else {
    for user in $result.not_following_back {
      print $"($user.login) ($user.url)"
    }
  }
}
