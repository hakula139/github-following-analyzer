#!/usr/bin/env nu

def --wrapped main [...args: string] {
  let endpoint = $args.1?
  let pagination = if $endpoint == "user" { [] } else { ["--paginate" "--slurp"] }
  let expected = ([
    "api" $endpoint
    "--hostname" "github.com"
    "--method" "GET"
    "--header" "Accept: application/vnd.github+json"
  ] | append $pagination)
  if $args != $expected {
    print --stderr "Unexpected request arguments."
    exit 1
  }

  let responses = ($env.GFA_RESPONSES | from json)
  let response = ($responses | get $endpoint)
  print --no-newline $response.stdout
  print --stderr --no-newline $response.stderr
  exit $response.exit_code
}
