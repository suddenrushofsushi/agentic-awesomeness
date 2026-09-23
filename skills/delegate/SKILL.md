---
name: delegate
description: Use when Craig asks to hand work to Codex or pi, for real code work or a one-off question. Triggers - "delegate", "have codex do", "give this to pi", "farm this out", "let a local model try". Claude owns the worktree, the brief, the review, and the commit; the worker only reads and edits files.
---
# delegate

Claude orchestrates. Codex or pi works only inside the folder Claude gives it. Tool: `agent` (run `agent -h`).

## 1. Pick the worker
- Craig named one: use it.
- Code change: `agent codex` (default `gpt-6-sol`). Hard or long task: add `-e high`.
- Design or architecture opinion: `-m gpt-6-astra -e high`, `gpt-6-sol` as backup. For a full design, use the blind-draft skill.
- Local, open-weight, or cheap: `agent pi` (default oMLX Qwen3.8-27B) or `agent pi -m openrouter/<model-id>`.
- GPT models go through codex. Every other non-Claude model goes through pi. Claude models: a Claude subagent (Agent tool with `model`), not `agent`.

## 2. Pick the folder
- Read-only question: the repo itself, no `--write`.
- Code change in a git repo: a new worktree that Claude creates.
  `git -C <repo> worktree add ~/github/.worktrees/<repo>/<slug> -b <branch> <base>`
  Branch: work that will ship through cpw uses `feature/<TICKET>-<slug>` (for example `feature/TECH-1234-slug`). Throwaway or bakeoff work uses `agent/<slug>`.
  If the repo documents its own worktree setup (README, Makefile, scripts), use that instead.
- **monarch-api: no worktrees yet.** Its docker compose setup does not work in a worktree. Run in the main tree, one write job at a time, and only when `git status` is clean. Delete this rule when Craig says monarch-api worktrees work.
- The worker never creates, switches, or removes worktrees or branches.

## 3. Write the brief
Write it to a file and pass it with `-`. Include: goal, relevant files and context, constraints, done-when (commands or tests that must pass), what to report. `agent` already adds the worker rules (stay in the folder, no git, report format). Do not repeat them.

## 4. Run
`agent codex --write -C <worktree> -e high - < brief.md` through Bash with `run_in_background: true`.
- Parallel jobs are fine across different worktrees.
- pi on oMLX: one job at a time.
- Follow-up: `--resume <session>`, from the `[agent]` summary line on stderr.

## 5. Review (Claude, every time)
- Read `git -C <worktree> status` and `git -C <worktree> diff`. Read every change.
- Run the done-when checks yourself. Do not trust the worker's report.
- pi has no sandbox. Also check `git -C <repo> status` in the main tree for stray edits.
- Fix small issues yourself, or `--resume` the worker with specific feedback (max 2 rounds). Then accept, rework, or drop.

## 6. Land
- Accept: Claude commits on the worktree branch.
- Code written only by Codex or pi, reviewed by Claude: `agent stamp -C <worktree> --by claude --note "<what you checked>"`.
- Claude also wrote code on the branch: run the luna-review skill instead.
- Push only on Craig's go. His go runs the cpw skill from its push step. After merge or drop: `git worktree remove <worktree>`.

## 7. Record
Write one Obsidian note per `Agents/README.md` (kind: delegate). Report to Craig in 3 lines: what changed, did it pass, what needs his decision.
