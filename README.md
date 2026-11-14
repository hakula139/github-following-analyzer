# github-following-analyzer

[![CI](https://github.com/hakula139/github-following-analyzer/actions/workflows/ci.yml/badge.svg)](https://github.com/hakula139/github-following-analyzer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Find accounts you follow that do not follow you back on GitHub.com, with an allowlist for intentional exceptions. The command uses your current GitHub CLI account, fetches both complete lists, and compares stable user IDs so renamed accounts still match. It only reads GitHub data.

## Install

Run from this checkout with [Nix](https://nixos.org/download/) and flakes enabled, or use the executable source with [Nushell](https://www.nushell.sh/) 0.116 or later and [GitHub CLI](https://cli.github.com/) on `PATH`.

Authenticate GitHub CLI for GitHub.com:

```bash
gh auth login --hostname github.com
```

The command reuses gh credentials and explicitly targets GitHub.com, including when `GH_HOST` names another host. It does not require a new token or secret file.

## Configuration

By default, the command reads `./config.toml` relative to the current working directory. An absent default file means no exemptions. To configure exceptions, copy the example and edit the ignored local file:

```bash
cp config.example.toml config.toml
```

The only supported key is `allow_list`, an array of GitHub usernames. For example:

```toml
allow_list = ["example-user"]
```

An omitted `allow_list` means an empty list. Names match current logins without regard to case, and duplicates are ignored. Use bare usernames without surrounding spaces or an `@` prefix. Update the allowlist when an allowed account renames.

`--config PATH` selects another file. An explicitly selected missing file is an error, including `--config config.toml`. Invalid TOML, unknown keys, and invalid usernames also fail before any report is printed.

Keep secrets in an ignored `.env.local` if needed. The repository's `.envrc` loads it optionally after entering the dev shell. GitHub CLI authentication is sufficient for normal use.

## Usage

Run the Nix package from this checkout:

```bash
nix run . --
nix run . -- --json
nix run . -- --config config.toml --json
```

Or run the executable source:

```bash
./src/github-following-analyzer.nu
./src/github-following-analyzer.nu --json
./src/github-following-analyzer.nu --config config.toml --json
```

`--help` reads no config and makes no API requests. Success exits with code 0, including when there are accounts to review. Invalid config, missing `gh`, authentication failures, failed pages, rate limits, and malformed responses cause a nonzero exit with a diagnostic on stderr and empty stdout.

Reports are printed without being saved automatically. To save them locally, create the ignored `results/` directory:

```bash
mkdir -p results
nix run . -- > results/following.txt
nix run . -- --json > results/following.json
```

Keep reports private. Shell redirection may create an empty file on failure. The command never unfollows accounts or caches API responses.

## Output

Text output contains one `login URL` pair per actionable account, sorted by login without regard to case. If every non-reciprocal account is exempt or there are no such accounts, it prints `No accounts to review.` A one-line account, following, follower, allowed, and actionable result count summary goes to stderr in both modes.

`--json` emits a complete record on stdout. This example uses invented accounts:

```json
{
  "account": "example-account",
  "following_count": 3,
  "followers_count": 1,
  "allow_listed_count": 1,
  "not_following_back": [
    { "id": 101, "login": "example-user", "url": "https://github.com/example-user" }
  ]
}
```

Following and follower counts include all distinct fetched user IDs. `allow_listed_count` counts only non-reciprocal accounts excluded by the allowlist. Unused configured names and allowed accounts that already follow back do not increase it. `not_following_back` contains the remaining actionable rows, preserving each following row's `id`, `login`, and `html_url` (as `url`).

The account is identified once, and both lists are fetched using that login. Following and followers are fetched at different times, so changes while the command runs can affect this snapshot.

## Development

See [AGENTS.md](AGENTS.md) for project contracts and verification commands.

## License

Copyright (c) 2026 [Hakula](https://hakula.xyz). Licensed under the [MIT License](LICENSE).
