---
name: luna-review
description: Use before any git push of code that Claude wrote (Fable, Opus, Sonnet, or a Claude subagent), and whenever the push gate blocks a push. Runs a Codex gpt-6-luna high-effort review of the branch, fixes or disputes each finding, loops up to 3 rounds, then waits for Craig's go. Triggers - "luna review", "review before push", "Push blocked" from the gate.
---
# luna-review

The push gate (`hooks/push-gate.py` in agentic-awesomeness) blocks Claude's `git push` until the tip of each pushed ref has a review stamp. A stamp covers the whole reviewed diff from the base to that commit. `agent review` writes the stamp only when Luna finishes a review of that exact HEAD with no [P0] or [P1] finding.

## Who reviews what
- Code written by Claude: Luna, through this skill.
- Code written only by Codex or pi: Claude reviews it (delegate skill), then `agent stamp --by claude`.
- Mixed branch: this skill.
- Fix commits after the first push (the cpw loop): the PR reviewer (CodeRabbit) already re-reviews every push. A targeted fix for a failing check or a verified finding gets `agent stamp --by claude --note "cpw fix: <finding>"`. Use a Luna delta review (`agent review --base origin/<branch>`) only when the fix adds logic beyond the finding or changes a test's assertions.

## Steps
1. **Commit first.** All work is committed locally and the working tree is clean. Review against the branch the PR will target: `--base origin/<pr-base>` (cpw's base map, if you use cpw). Without `--base`, the base is `origin/<default branch>`.
2. **Review.** `agent review -C <repo>`. Run it in the background when the diff is large. The output is Luna's findings, tagged [P0] to [P3]. Every review also applies the ponytail-review lens: over-engineering comes back as [P3].
3. **Triage each finding.**
   - Agree: fix it in a new commit.
   - Disagree: write a one-line reason. Claude decides P2 and P3. Claude never rejects a P0 or P1 alone: hold it for Craig.
4. **Loop.** If you changed code, run `agent review` again, because the stamp is tied to HEAD. Max 3 rounds. Stop early when a round has no finding you accept.
   - A round with an open P0 or P1 leaves HEAD unstamped. If Craig overrules it, stamp with his decision: `agent stamp -C <repo> --by craig --note "Craig overruled [P1] <finding>: <his reason>"`. Only after he says so in chat.
5. **Report to Craig.** Fixed (one line each), disputed (finding and reason), P0/P1 held for his call, still open. Then wait.
6. **Push on Craig's go only.** The gate passes when the final HEAD has a stamp. Craig's "go" runs the cpw skill from its push step: push, PR, CI watch, CodeRabbit loop. If Craig said "cpw" up front, that was the go: push as soon as HEAD is stamped.

Bypass: `AGENT_REVIEW_SKIP=1 git push`, only when Craig says to skip review.
