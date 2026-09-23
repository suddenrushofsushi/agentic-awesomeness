#!/usr/bin/env python3
"""Claude Code PreToolUse hook (matcher: Bash). Blocks `git push` unless every commit it
ships (HEAD, or each refspec's source) has a review stamp from `agent review` (Luna) or
`agent stamp`. Pushes it cannot resolve (--all, --tags, --mirror, bad refs) are blocked.
Exit 2 = block.

Bypass, only when Craig says so: prefix the command with AGENT_REVIEW_SKIP=1.
"""
import json, os, re, shlex, subprocess, sys
from pathlib import Path

GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def pushes(command, cwd):
    """Yield (repo_dir, push_args) for each `git push` in a shell command line."""
    for segment in re.split(r"&&|\|\||[;|\n]", command):
        try:
            words = shlex.split(segment)
        except ValueError:
            words = segment.split()
        while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            words = words[1:]  # env assignments
        if not words:
            continue
        if words[0] == "cd" and len(words) > 1:
            cwd = str(Path(cwd, os.path.expanduser(words[1])))
            continue
        if Path(words[0]).name != "git":
            continue
        repo, i = cwd, 1
        while i < len(words) and words[i].startswith("-"):
            opt = words[i].split("=", 1)[0]
            if opt == "-C" and i + 1 < len(words):
                repo = str(Path(repo, os.path.expanduser(words[i + 1])))
            i += 2 if opt in GIT_OPTS_WITH_VALUE and "=" not in words[i] else 1
        if i < len(words) and words[i] == "push":
            yield repo, words[i + 1:]


PUSH_OPTS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}


def targets(repo, args):
    """Commits this push would ship. None means it cannot tell, so block."""
    positional, i = [], 0
    while i < len(args):
        word = args[i]
        if word in ("--all", "--branches", "--mirror", "--tags"):
            return None
        if word.startswith("-"):
            i += 2 if word in PUSH_OPTS_WITH_VALUE else 1
            continue
        positional.append(word)
        i += 1
    refspecs = positional[1:]  # positional[0] is the remote
    if not refspecs:
        return [git(repo, "rev-parse", "HEAD")]
    shas = []
    for spec in refspecs:
        src = spec.lstrip("+").split(":", 1)[0]
        if not src:
            continue  # ":dst" deletes a remote ref, ships no code
        sha = git(repo, "rev-parse", "--verify", "--quiet", f"{src}^{{commit}}")
        if not sha:
            return None
        shas.append(sha)
    return shas


def main():
    data = json.load(sys.stdin)
    command = (data.get("tool_input") or {}).get("command", "")
    if "AGENT_REVIEW_SKIP=1" in command:
        return 0
    for repo, args in pushes(command, data.get("cwd") or os.getcwd()):
        if "--delete" in args or "-d" in args:
            continue  # deleting a remote ref ships no code
        common = git(repo, "rev-parse", "--git-common-dir")
        if not common or not git(repo, "rev-parse", "HEAD"):
            continue  # not a repo: git push fails on its own
        shas = targets(repo, args)
        stamps = Path(repo, common).resolve() / "agent-review"
        missing = ["(could not resolve what this push ships)"] if shas is None else \
            [s[:10] for s in shas if not (stamps / s).exists()]
        if missing:
            print(f"Push blocked in {repo}: no review stamp for {', '.join(missing)}. "
                  "Run the luna-review skill (agent review) first. For Codex/pi-only code you reviewed, "
                  "use `agent stamp --by claude --note ...`. Bypass only if Craig says so: AGENT_REVIEW_SKIP=1.",
                  file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
