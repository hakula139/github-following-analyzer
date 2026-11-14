# AGENTS.md: github-following-analyzer

- Keep credentials, API responses, login lists, and analysis results local. Never include personal data in fixtures or public logs.
- Keep tests offline. Use the adjacent `gh.stub.nu` through devkit's `nu-test` runner.
- Fetch from GitHub.com using the current gh account, then pin both collections to that account's login. Compare stable numeric IDs and abort the entire report on request or validation failure.
- Preserve stdout for the complete report and stderr for summaries and errors. Never mutate GitHub state or persist reports automatically.
