# GitHub Following Analyzer

Find accounts you follow that do not follow you back on GitHub.com. The tool uses your current [GitHub CLI](https://cli.github.com/) account, fetches both complete lists, and compares stable user IDs so renamed accounts still match. It only reads GitHub data.

## Usage

Authenticate GitHub CLI for GitHub.com:

```sh
gh auth login --hostname github.com
```

With [Nix](https://nixos.org/download/), run from this checkout:

```sh
nix run . --
nix run . -- --json
```

Or, with Nushell 0.116 or later and `gh` on `PATH`, run the source:

```sh
./src/github-following-analyzer.nu
./src/github-following-analyzer.nu --json
```

All requests explicitly target GitHub.com, including when `GH_HOST` names another host. The account is identified once, and both lists are fetched using that login. Authentication and pagination are handled by `gh`.

Text output contains one `login URL` pair per line, sorted by login without regard to case. If there are no matches, it prints `Everyone you follow follows you back.` A concise account, following, follower, and result count summary goes to stderr in both modes.

`--json` emits a complete record on stdout. This example uses invented accounts:

```json
{
  "account": "example-account",
  "following_count": 2,
  "followers_count": 1,
  "not_following_back": [
    { "id": 101, "login": "example-user", "url": "https://github.com/example-user" }
  ]
}
```

Counts represent distinct fetched user IDs. Each result preserves the following list's `id`, `login`, and `html_url` (as `url`). Following and followers are fetched at different times, so changes while the tool runs can affect this snapshot.

Reports are printed without being saved automatically. To save them locally, create the ignored `results/` directory:

```sh
mkdir -p results
nix run . -- > results/following.txt
nix run . -- --json > results/following.json
```

Keep reports private. There are no filters or automatic unfollow actions, and the tool stores no credentials or API cache.

Success exits with code 0, including when matches exist. Missing `gh`, authentication failures, failed pages, rate limits, and malformed responses cause a nonzero exit with a diagnostic on stderr and empty stdout. Fix the reported problem before retrying. Shell redirection may still create an empty file on failure.

## Development

The Nix dev shell supplies Nushell, GitHub CLI, the offline test runner, and shared hooks:

```sh
nix develop -c nu-test src/github-following-analyzer.test.nu
nix develop -c run-hooks
nix flake check
```

Tests use an adjacent `gh` stub and invented data, with no live API calls. The flake checks both the package and tests. Community templates and security reporting inherit from [hakula139/.github](https://github.com/hakula139/.github).

## License

[MIT](LICENSE).
