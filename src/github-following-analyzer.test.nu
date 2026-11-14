#!/usr/bin/env nu

# ==================================================================================================
# GitHub Following Analyzer: Tests
# ==================================================================================================

use std/assert

const SCRIPT = path self "github-following-analyzer.nu"

def user [id: int, login: string]: nothing -> record {
  {
    id: $id
    login: $login
    html_url: $"https://github.com/($login)"
  }
}

def response [body: any]: nothing -> record {
  {
    stdout: ($body | to json)
    stderr: ""
    exit_code: 0
  }
}

def responses [following: any, followers: any]: nothing -> record {
  {
    user: (response {login: "example-account"})
    "users/example-account/following?per_page=100": (response $following)
    "users/example-account/followers?per_page=100": (response $followers)
  }
}

def analyze [data: record, --text, --config: path, --cwd: path]: nothing -> record {
  let output = if $text { [] } else { ["--json"] }
  let selection = if $config == null { [] } else { ["--config" $config] }
  let flags = ($output | append $selection)
  let directory = ($cwd | default { mktemp --directory })
  with-env {
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
    GH_HOST: "example.invalid"
    GFA_RESPONSES: ($data | to json)
  } {
    cd $directory
    ^$nu.current-exe --no-config-file $SCRIPT ...$flags | complete
  }
}

def "test optional config and explicit paths use the working directory" [] {
  let cases = [
    {
      name: "absent default"
      file: null
      config: null
      body: ""
    }
    {
      name: "empty default with missing allow_list"
      file: "config.toml"
      config: null
      body: ""
    }
    {
      name: "default empty allow_list"
      file: "config.toml"
      config: null
      body: "allow_list = []"
    }
    {
      name: "explicit relative path"
      file: "selected.toml"
      config: "selected.toml"
      body: "allow_list = []"
    }
  ]

  for case in $cases {
    let cwd = (mktemp --directory)
    if $case.file != null {
      $case.body | save ($cwd | path join $case.file)
    }

    let actual = (analyze (responses [[]] [[]]) --cwd $cwd --config $case.config)
    assert equal $actual.exit_code 0 $"($case.name): ($actual.stderr)"

    assert equal ($actual.stdout | from json) {
      account: "example-account"
      following_count: 0
      followers_count: 0
      allow_listed_count: 0
      not_following_back: []
    } $case.name
  }
}

def "test invalid config fails before requests without private values" [] {
  let cases = [
    {
      name: "explicit missing default path"
      file: "config.toml"
      body: null
      message: "does not exist"
    }
    {
      name: "explicit missing alternative path"
      file: "absent.toml"
      body: null
      message: "does not exist"
    }
    {
      name: "malformed TOML"
      file: "invalid.toml"
      body: 'allow_list = ["private-config-sentinel"'
      message: "Cannot read TOML config"
    }
    {
      name: "unknown key"
      file: "invalid.toml"
      body: 'cache = "private-config-sentinel"'
      message: "unknown keys cache"
    }
    {
      name: "root scalar"
      file: "invalid.toml"
      body: '"private-config-sentinel"'
      message: "Cannot read TOML config"
    }
    {
      name: "string allow_list"
      file: "invalid.toml"
      body: 'allow_list = "private-config-sentinel"'
      message: "allow_list must be a list"
    }
    {
      name: "record allow_list"
      file: "invalid.toml"
      body: 'allow_list = {name = "private-config-sentinel"}'
      message: "allow_list must be a list"
    }
    ...([
      4
      ""
      " alpha"
      "alpha "
      "@alpha"
      "alpha--beta"
      "alpha-"
      ("a" | fill --character "a" --width 40)
      {name: "private-config-sentinel"}
    ] | each {|value|
      {
        name: $"invalid username entry ($value | describe) ($value | to nuon)"
        file: "invalid.toml"
        body: ({allow_list: [$value]} | to toml)
        message: "allow_list entries must be valid GitHub usernames"
      }
    })
  ]

  for case in $cases {
    let cwd = (mktemp --directory)
    if $case.body != null {
      $case.body | save ($cwd | path join $case.file)
    }

    for text in [false true] {
      let mode = if $text { "text" } else { "JSON" }
      let label = $"($case.name), config ($case.file), ($mode) mode"

      let actual = (analyze {} --cwd $cwd --config $case.file --text=$text)

      assert ($actual.exit_code != 0) $label
      assert equal $actual.stdout "" $label
      assert ($actual.stderr | str contains $case.file) $label
      assert ($actual.stderr | str contains $case.message) $label
      assert (not ($actual.stderr | str contains "private-config-sentinel")) $label
      assert (not ($actual.stderr | str contains "GitHub.com GET")) $label
    }
  }
}

def "test help bypasses config and gh" [] {
  let actual = (with-env {PATH: []} {
    cd $env.TMPDIR
    ^$nu.current-exe --no-config-file $SCRIPT --config "absent.toml" --help | complete
  })

  assert equal $actual.exit_code 0 $actual.stderr
  assert ($actual.stdout | str contains "--config")
  assert equal $actual.stderr ""
}

def "test exemptions match current logins and count only nonreciprocal accounts" [] {
  let alpha = {
    id: 1
    login: "Alpha"
    url: "https://github.com/Alpha"
  }
  let zulu = {
    id: 2
    login: "Zulu"
    url: "https://github.com/Zulu"
  }
  let data = (responses [
    [(user 2 "Zulu") (user 3 "old-name")]
    [(user 1 "Alpha") (user 2 "Zulu")]
  ] [[(user 3 "new-name") (user 8 "Alpha")]])
  let cases = [
    {
      name: "case insensitive duplicates and reciprocal names"
      allowed: ["ALPHA" "alpha" "old-name" "unused"]
      count: 1
      expected: [$zulu]
      text: "Zulu https://github.com/Zulu\n"
    }
    {
      name: "all nonreciprocal accounts exempt"
      allowed: ["alpha" "ZULU"]
      count: 2
      expected: []
      text: "No accounts to review.\n"
    }
    {
      name: "reciprocal and unused names do not count"
      allowed: ["old-name" "unused"]
      count: 0
      expected: [$alpha $zulu]
      text: "Alpha https://github.com/Alpha\nZulu https://github.com/Zulu\n"
    }
  ]

  for case in $cases {
    let cwd = (mktemp --directory)
    {allow_list: $case.allowed} | to toml | save ($cwd | path join "config.toml")

    let json = (analyze $data --cwd $cwd)
    let text = (analyze $data --cwd $cwd --text)
    assert equal [$json.exit_code $text.exit_code] [0 0] $case.name

    assert equal ($json.stdout | from json) {
      account: "example-account"
      following_count: 3
      followers_count: 2
      allow_listed_count: $case.count
      not_following_back: $case.expected
    } $case.name
    assert equal $text.stdout $case.text $case.name
    let summary = $"Account: example-account. Following: 3. Followers: 2. Allowed: ($case.count). Not following back: ($case.expected | length).\n"
    assert equal $json.stderr $summary $"($case.name): JSON summary"
    assert equal $text.stderr $summary $"($case.name): text summary"
  }
}

def "test full pages match stable ids deduplicate and sort logins" [] {
  let following = [
    [(user 1 "Zulu") (user 2 "old-name")]
    [(user 3 "alpha") (user 1 "Zulu") (user 4 "Beta")]
  ]
  let followers = [
    [(user 8 "other")]
    [(user 2 "new-name") (user 8 "other")]
  ]

  let actual = (analyze (responses $following $followers))
  assert equal $actual.exit_code 0 $actual.stderr

  assert equal ($actual.stdout | from json) {
    account: "example-account"
    following_count: 4
    followers_count: 2
    allow_listed_count: 0
    not_following_back: [
      {
        id: 3
        login: "alpha"
        url: "https://github.com/alpha"
      }
      {
        id: 4
        login: "Beta"
        url: "https://github.com/Beta"
      }
      {
        id: 1
        login: "Zulu"
        url: "https://github.com/Zulu"
      }
    ]
  }
  assert equal $actual.stderr "Account: example-account. Following: 4. Followers: 2. Allowed: 0. Not following back: 3.\n"
}

def "test text and json keep stdout separate from summary" [] {
  let data = (responses [[(user 1 "Zulu") (user 2 "alpha")]] [[]])

  let text = (analyze $data --text)
  let json = (analyze $data)
  assert equal [$text.exit_code $json.exit_code] [0 0]

  assert equal $text.stdout "alpha https://github.com/alpha\nZulu https://github.com/Zulu\n"
  assert equal ($json.stdout | from json | get not_following_back) [
    {
      id: 2
      login: "alpha"
      url: "https://github.com/alpha"
    }
    {
      id: 1
      login: "Zulu"
      url: "https://github.com/Zulu"
    }
  ]
  assert equal $text.stderr "Account: example-account. Following: 2. Followers: 0. Allowed: 0. Not following back: 2.\n"
  assert equal $json.stderr $text.stderr
}

def "test empty collections and mutual following succeed" [] {
  let cases = [
    {
      name: "both collections empty"
      following: [[]]
      followers: [[]]
      following_count: 0
      followers_count: 0
    }
    {
      name: "no following with one follower"
      following: [[]]
      followers: [[(user 2 "alpha")]]
      following_count: 0
      followers_count: 1
    }
    {
      name: "mutual following after a rename"
      following: [[(user 1 "old-name")]]
      followers: [[(user 1 "new-name")]]
      following_count: 1
      followers_count: 1
    }
  ]

  for case in $cases {
    let data = (responses $case.following $case.followers)

    let json = (analyze $data)
    let text = (analyze $data --text)
    assert equal [$json.exit_code $text.exit_code] [0 0] $"($case.name): JSON and text exit codes"

    assert equal ($json.stdout | from json) {
      account: "example-account"
      following_count: $case.following_count
      followers_count: $case.followers_count
      allow_listed_count: 0
      not_following_back: []
    } $"($case.name): JSON report"
    assert equal $text.stdout "No accounts to review.\n" $"($case.name): text report"
    assert equal $text.stderr $json.stderr $"($case.name): text and JSON summaries"
  }
}

def "test gh failures reject misleading stdout and partial pages" [] {
  let partial = (([[(user 1 "alpha")]] | to json) + "\n" + ({message: "Forbidden"} | to json))
  let cases = [
    {
      endpoint: "user"
      stdout: ({login: "example-account"} | to json)
      diagnostic: "gh: authentication required"
    }
    {
      endpoint: "users/example-account/following?per_page=100"
      stdout: $partial
      diagnostic: "gh: page 2 failed (HTTP 403)\nretry after the rate limit resets"
    }
    {
      endpoint: "users/example-account/followers?per_page=100"
      stdout: $partial
      diagnostic: "gh: page 2 failed (HTTP 403)"
    }
  ]

  for case in $cases {
    let data = (responses [[(user 1 "alpha")]] [[]] | update $case.endpoint {
      stdout: $case.stdout
      stderr: $case.diagnostic
      exit_code: 1
    })

    for text in [false true] {
      let mode = if $text { "text" } else { "JSON" }
      let label = $"GET ($case.endpoint), ($mode) mode"
      let expected = [
        $"GitHub.com GET ($case.endpoint) failed."
        "Check `gh auth login --hostname github.com` and the gh diagnostic:"
        ($case.diagnostic | str trim)
        ""
      ]

      let actual = (analyze $data --text=$text)

      assert ($actual.exit_code != 0) $label
      assert equal $actual.stdout "" $label
      assert equal $actual.stderr ($expected | str join "\n") $label
    }
  }
}

def "test malformed external fields and page shapes abort without payloads" [] {
  let invalid_users = [
    {
      name: "non-record user"
      body: [["private-payload-sentinel"]]
    }
    {
      name: "string user ID"
      body: [[(user 1 "alpha" | update id "1")]]
    }
    {
      name: "nonpositive user ID"
      body: [[(user 1 "alpha" | update id 0)]]
    }
    {
      name: "missing user login"
      body: [[(user 1 "alpha" | reject login)]]
    }
    {
      name: "newline in user login"
      body: [[(user 1 "alpha" | update login "alpha\nprivate-payload-sentinel")]]
    }
    {
      name: "missing user URL"
      body: [[(user 1 "alpha" | reject html_url)]]
    }
    {
      name: "numeric user URL"
      body: [[(user 1 "alpha" | update html_url 4)]]
    }
    {
      name: "user URL outside GitHub.com"
      body: [[(user 1 "alpha" | update html_url "https://example.com/private-payload-sentinel")]]
    }
    {
      name: "lookalike GitHub.com domain"
      body: [[(user 1 "alpha" | update html_url "https://githubXcom/alpha")]]
    }
    {
      name: "record in place of users page"
      body: [{message: "private-payload-sentinel"}]
    }
    {
      name: "record in place of page list"
      body: {message: "private-payload-sentinel"}
    }
    {
      name: "missing pages"
      body: []
    }
    {
      name: "null page list"
      body: null
    }
  ]
  let invalid_accounts = [
    {
      name: "null account"
      body: null
    }
    {
      name: "list in place of account"
      body: []
    }
    {
      name: "string in place of account"
      body: "private-payload-sentinel"
    }
    {
      name: "missing account login"
      body: {}
    }
    {
      name: "numeric account login"
      body: {login: 4}
    }
    {
      name: "empty account login"
      body: {login: ""}
    }
    {
      name: "unsafe account login"
      body: {login: "a/b"}
    }
  ]
  let cases = [
    ...($invalid_accounts | each {|case|
      {
        name: $case.name
        endpoint: "user"
        response: (response $case.body)
      }
    })
    ...($invalid_users | each {|case|
      {
        name: $case.name
        endpoint: "users/example-account/following?per_page=100"
        response: (response $case.body)
      }
    })
    ...($invalid_users | each {|case|
      {
        name: $case.name
        endpoint: "users/example-account/followers?per_page=100"
        response: (response $case.body)
      }
    })
    {
      name: "truncated JSON"
      endpoint: "user"
      response: {
        stdout: '{"private-payload-sentinel":'
        stderr: ""
        exit_code: 0
      }
    }
  ]

  for case in $cases {
    let data = (responses [[]] [[]] | update $case.endpoint $case.response)

    for text in [false true] {
      let mode = if $text { "text" } else { "JSON" }
      let label = $"($case.name): GET ($case.endpoint), ($mode) mode"

      let actual = (analyze $data --text=$text)

      assert ($actual.exit_code != 0) $label
      assert equal $actual.stdout "" $label
      assert ($actual.stderr | str contains "invalid") $label
      assert (not ($actual.stderr | str contains "private-payload-sentinel")) $label
    }
  }
}

def "test missing gh gives an actionable error" [] {
  let actual = (with-env {PATH: []} {
    cd $env.TMPDIR
    ^$nu.current-exe --no-config-file $SCRIPT | complete
  })

  assert ($actual.exit_code != 0)
  assert equal $actual.stdout ""
  assert equal $actual.stderr (
    [
      "GitHub CLI (gh) is required."
      "Install gh, then run `gh auth login --hostname github.com`."
      ""
    ]
    | str join "\n"
  )
}
