# actions

Shared GitHub Actions reusable workflows and composite actions for lokkju's repositories.
Call them pinned by full commit SHA, never by branch or tag.

## no-ai-attribution

A required pull request check that fails when a commit message in the PR, or the PR's
title or body, carries attribution to an AI tool: co-author trailers naming a tool or
vendor, vendor noreply and bot addresses, `Generated-by`/`Assisted-by` style trailers, a
coding harness's session trailer, links to AI session and chat-share pages, and the
"Generated with <tool>" boilerplate, robot-emoji line included. The person who pushes a
change is its author and is accountable for it, whatever tools they used; a vendor's name
in a trailer records nothing a reviewer needs.

It matches trailer lines, known boilerplate and session links, never a bare tool name, so
a PR that discusses a tool or sets `OPENAI_API_KEY` passes.

### Calling it

Add `.github/workflows/no-ai-attribution.yml` to the repo:

```yaml
name: no-ai-attribution
on:
  pull_request:
    types: [opened, edited, synchronize, reopened]

permissions:
  contents: read
  pull-requests: read

jobs:
  no-ai-attribution:
    uses: lokkju/actions/.github/workflows/no-ai-attribution.yml@<full commit sha>
    # with:
    #   runs-on: homelab   # default ubuntu-latest
```

`edited` and `synchronize` re-run it when the body is edited or the branch is pushed, so
fixing the text or force-pushing clears a failure. It runs on `pull_request`, not
`pull_request_target`; it needs no secrets and only read access.

### The required check's name

A job that calls a reusable workflow reports as `<caller job> / <called job>`. The called
job is `scan`, so with the caller job id `no-ai-attribution` and no `name:` the check is

```
no-ai-attribution / scan
```

and that is the exact context a ruleset or branch protection must require. Rename the
caller job, or give it a `name:`, and the check reports under a different context while
the PR waits forever on the required one. lokkju/infra's Pulumi rulesets require this
context from the GitHub Actions App (integration id 15368), with no bypass actors.

### What it reads

- Every commit in `base..head` of the PR (`git rev-list`, so a full clone: the workflow
  checks out with `fetch-depth: 0`).
- The PR title and body from the API when `gh` is on the runner, otherwise from the event
  payload.
- The scanner (`bin/no-ai-attribution`) and patterns (`patterns/ai-attribution.txt`)
  checked out from this repo at the commit the caller pinned (`job.workflow_sha`), not
  from the PR, so a PR can't edit the check it is checked by.

Commit messages are untrusted text, so the report is printed with workflow commands
stopped; each hit then becomes an escaped error annotation.

### Fixing a failure

The log lists each offending line with its commit SHA (or "PR title" / "PR body") and line
number.

- Commit messages: drop the lines. `git commit --amend` for the last commit, or
  `git rebase -i <base>` and mark the commits `reword`; then `git push --force-with-lease`.
- PR title or body: edit the PR. Saving re-runs the check.

### Patterns

`patterns/ai-attribution.txt` holds one POSIX extended regular expression per line,
matched case-insensitively against each line on its own with GNU grep (`\b` is GNU's).
Comments start with `#`. Add a pattern with at least one case in `tests/positive.txt`,
and add the prose it must not catch to `tests/negative.txt`; `tests/run.sh` fails when a
pattern has no positive case.

### Local use

The same scanner works as a `commit-msg` hook, so attribution is caught before the push:

```sh
#!/bin/sh
exec /path/to/actions/bin/no-ai-attribution commit-msg "$1"
```

Other modes: `no-ai-attribution commits <base> <head>` and
`no-ai-attribution text <label> [file]` (stdin without a file). Exit status is 0 when
clean, 1 when attribution is found, 2 on a usage or setup error.
`NO_AI_ATTRIBUTION_PATTERNS` points it at another pattern file.

### Tests

```sh
tests/run.sh
```

Needs bash, GNU grep and git. `ci.yml` runs it on every PR and push to `main`, and runs
this repo's own `no-ai-attribution / scan` check against the PR's commit, so a pattern
change is checked by the patterns it proposes.

## License

[PolyForm Shield 1.0.0](LICENSE).

Required Notice: Copyright 2026 Loki Coyote
