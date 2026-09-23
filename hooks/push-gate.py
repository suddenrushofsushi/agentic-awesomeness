#!/usr/bin/env python3
"""Claude Code PreToolUse hook (matcher: Bash). Blocks `git push` unless the tip of each
pushed ref (HEAD, or each refspec's source) has a review stamp from `agent review` (Luna)
or `agent stamp`. A stamp covers the whole reviewed diff from the base to that commit, so
commits below a stamped tip need no stamp of their own. Pushes it cannot resolve
(--all, --tags, --mirror, bad refs) are blocked. Exit 2 = block.

Bypass, only when Craig says so: AGENT_REVIEW_SKIP=1 as a prefix on the git push itself.
"""
import json, os, re, shlex, subprocess, sys
from pathlib import Path

GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def git(cwd, *args):
    p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


SEPARATORS = set("&|;()")
WRAPPERS = {"env", "command", "builtin", "exec", "nice", "nohup", "sudo", "time", "timeout", "xargs", "caffeinate"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def segments(command):
    """Split a shell line into simple commands, respecting quotes."""
    lex = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    words = []
    try:
        for tok in lex:
            if set(tok) <= SEPARATORS:
                if words:
                    yield words
                words = []
            else:
                words.append(tok)
    except ValueError:  # unbalanced quotes: rough split, so a push still gets seen
        yield from (seg.split() for seg in re.split(r"[&|;()\n]", command) if seg.strip())
        return
    if words:
        yield words


def pushes(command, cwd, env=frozenset(), depth=0):
    """Yield (repo_dir, push_args, env_assignments) for each `git push` in a shell command line.
    Unwraps env/timeout/xargs-style prefixes, `sh -c '...'`, and `eval`."""
    # ponytail: backtick substitution and exotic wrapper options (sudo -u USER) are not unwrapped
    for words in segments(command):
        seg_env = set(env)
        while True:
            while words and ASSIGNMENT.match(words[0]):
                seg_env.add(words.pop(0))
            if words and Path(words[0]).name in WRAPPERS:
                words.pop(0)
                while words and (words[0].startswith("-") or words[0][:1].isdigit()):
                    words.pop(0)  # wrapper options and timeout durations
                continue
            break
        if not words:
            continue
        name = Path(words[0]).name
        if name in SHELLS or name == "eval":
            if name == "eval":
                inner = " ".join(words[1:])
            else:
                inner = next((words[i + 1] for i, w in enumerate(words[:-1])
                              if re.match(r"^-[a-z]*c[a-z]*$", w)), None)
            if inner and depth < 3:
                yield from pushes(inner, cwd, frozenset(seg_env), depth + 1)
            continue
        if name == "cd" and len(words) > 1:
            cwd = str(Path(cwd, os.path.expanduser(words[1])))
            continue
        if name != "git":
            continue
        repo, i = cwd, 1
        while i < len(words) and words[i].startswith("-"):
            opt = words[i].split("=", 1)[0]
            if opt == "-C" and i + 1 < len(words):
                repo = str(Path(repo, os.path.expanduser(words[i + 1])))
            i += 2 if opt in GIT_OPTS_WITH_VALUE and "=" not in words[i] else 1
        if i < len(words) and words[i] == "push":
            yield repo, words[i + 1:], seg_env


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


def main(raw):
    data = json.loads(raw)
    command = (data.get("tool_input") or {}).get("command", "")
    for repo, args, env in pushes(command, data.get("cwd") or os.getcwd()):
        if "AGENT_REVIEW_SKIP=1" in env or "--delete" in args or "-d" in args:
            continue  # deleting a remote ref ships no code
        common = git(repo, "rev-parse", "--git-common-dir")
        shas = targets(repo, args) if common and git(repo, "rev-parse", "HEAD") else None  # unknown repo: fail closed
        missing = ["(could not resolve what this push ships)"] if shas is None else \
            [s[:10] for s in shas if not (Path(repo, common).resolve() / "agent-review" / s).exists()]
        if missing:
            print(f"Push blocked in {repo}: no review stamp for {', '.join(missing)}. "
                  "Run the luna-review skill (agent review) first. For Codex/pi-only code you reviewed, or a targeted "
                  "fix after the first push, use `agent stamp --by claude --note ...`. Bypass only if Craig says so: AGENT_REVIEW_SKIP=1.",
                  file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    raw = sys.stdin.read()
    try:
        sys.exit(main(raw))
    except Exception as e:  # Claude Code treats exit 1 as "allow", so a crash near a push must block
        if "push" not in raw:
            sys.exit(0)
        print(f"Push gate error ({type(e).__name__}: {e}); blocking to be safe.", file=sys.stderr)
        sys.exit(2)
