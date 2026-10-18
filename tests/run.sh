#!/usr/bin/env bash
# Tests for bin/no-ai-attribution and patterns/ai-attribution.txt. Needs bash, GNU grep
# and git. Prints one line per failure and exits non-zero if any test failed.
set -uo pipefail
export LC_ALL=C

tests_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
root=$(dirname "$tests_dir")
scanner=$root/bin/no-ai-attribution
patterns=$root/patterns/ai-attribution.txt
failures=0
passes=0

fail() { echo "FAIL: $*"; failures=$((failures + 1)); }
pass() { passes=$((passes + 1)); }

cases() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# Run the scanner outside GitHub Actions unless a test asks for it.
run() { env -u GITHUB_ACTIONS "$scanner" "$@"; }

# 1. Every positive line is flagged on its own.
while IFS= read -r line; do
  printf '%s\n' "$line" | run text case >/dev/null 2>&1
  if [ $? -eq 1 ]; then pass; else fail "positive not flagged: $line"; fi
done < <(cases "$tests_dir/positive.txt")

# 2. No negative line is flagged.
while IFS= read -r line; do
  out=$(printf '%s\n' "$line" | run text case 2>&1)
  if [ $? -eq 0 ]; then pass; else fail "negative flagged: $line"$'\n'"$out"; fi
done < <(cases "$tests_dir/negative.txt")

# 3. Every pattern has at least one positive case.
while IFS= read -r pattern; do
  if cases "$tests_dir/positive.txt" | grep -qiE -e "$pattern"; then pass; else fail "pattern has no positive case: $pattern"; fi
done < <(cases "$patterns")

# 4. CRLF text (PR bodies arrive with \r\n) is flagged, and the report has no \r.
out=$(printf 'Summary\r\n\r\nGenerated with Claude Code\r\n' | run text "PR body")
if [ $? -eq 1 ] && grep -q 'PR body, line 3: Generated with Claude Code$' <<<"$out"; then pass; else fail "CRLF body: $out"; fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo
git init -q -b main "$repo"
gitc() { git -C "$repo" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }
commit() { gitc commit -q --allow-empty --no-verify -F "$1"; git -C "$repo" rev-parse HEAD; }

printf 'base\n' >"$work/m0"
base=$(commit "$work/m0")
printf 'feat: clean change\n\nMentions OPENAI_API_KEY in prose.\n' >"$work/m1"
clean=$(commit "$work/m1")
{ printf 'fix: tainted change\n\nBody text.\n\n'; cases "$tests_dir/positive.txt" | head -n 1; } >"$work/m2"
tainted=$(commit "$work/m2")

# 5. A range with an attribution trailer fails, names the tainted commit and line, not
#    the clean one, and tells the author how to fix a commit.
out=$(cd "$repo" && run commits "$base" "$tainted")
rc=$?
if [ $rc -eq 1 ] && grep -q "commit ${tainted:0:12}, line 5:" <<<"$out" && ! grep -q "${clean:0:12}," <<<"$out" \
  && grep -q 'rebase -i' <<<"$out" && ! grep -q 'PR title' <<<"$out"; then
  pass
else
  fail "tainted range (rc=$rc): $out"
fi

# 6. A clean range passes.
out=$(cd "$repo" && run commits "$base" "$clean")
if [ $? -eq 0 ] && grep -q 'Scanned 1 commit' <<<"$out"; then pass; else fail "clean range: $out"; fi

# 7. A commit missing from the clone is a setup error, not a pass.
(cd "$repo" && run commits 0000000000000000000000000000000000000000 "$clean") >/dev/null 2>&1
if [ $? -eq 2 ]; then pass; else fail "missing base did not exit 2"; fi

# 8. commit-msg mode ignores comment lines and the verbose diff, and flags real lines.
{
  printf 'feat: x\n\n'
  printf '# Generated with Claude Code\n'
  printf '# ------------------------ >8 ------------------------\n'
  printf '+Generated with Claude Code\n'
} >"$work/msg-clean"
if run commit-msg "$work/msg-clean" >/dev/null; then pass; else fail "commit-msg flagged comments or diff"; fi
printf 'feat: x\n\nGenerated with Claude Code\n' >"$work/msg-bad"
run commit-msg "$work/msg-bad" >/dev/null
if [ $? -eq 1 ]; then pass; else fail "commit-msg missed an attribution line"; fi

# 9. Under GitHub Actions, untrusted text is printed with workflow commands stopped and
#    each hit becomes an escaped error annotation after they resume.
out=$(printf '::warning::injected\nGenerated with Claude Code\n' | GITHUB_ACTIONS=true "$scanner" text "PR body")
token=$(sed -n 's/^::stop-commands::\(.*\)$/\1/p' <<<"$out")
before=$(sed -n "1,/^::stop-commands::/p" <<<"$out")
after=$(sed -n "/^::$token::\$/,\$p" <<<"$out")
if [ -n "$token" ] && ! grep -q injected <<<"$before" && ! grep -q '^::warning' <<<"$after" \
  && grep -q '^::error title=AI attribution::PR body, line 2: Generated with Claude Code$' <<<"$after" \
  && grep -q 'edit the PR' <<<"$out"; then
  pass
else
  fail "GitHub Actions output: $out"
fi

# 10. An empty pattern file is a setup error.
: >"$work/empty.txt"
printf 'x\n' | NO_AI_ATTRIBUTION_PATTERNS=$work/empty.txt run text case >/dev/null 2>&1
if [ $? -eq 2 ]; then pass; else fail "empty pattern file did not exit 2"; fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
