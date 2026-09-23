---
name: bakeoff
description: Use when Craig wants to compare models on the same task. Triggers - "bakeoff", "model test", "try this on N models", "which model does X best", "compare qwen / deepseek / gpt / claude on ...". Same prompt to every model, results side by side in one Obsidian note.
---
# bakeoff

## 1. Task
Write one prompt to a file. Every model gets exactly this prompt. Never tailor it per model. Add a done-when so answers can be judged.

## 2. Models
Craig's list. If he gives none, use:
- `agent codex` (gpt-6-sol)
- `agent pi` (oMLX Qwen3.8-27B)
- `agent pi -m openrouter/deepseek/deepseek-v4-pro`
- one Claude subagent (Agent tool, `model: sonnet`)

Model ids: `agent pi -m openrouter/<id>` for OpenRouter, `agent codex -m <id>` for GPT. List pi models with `pi --list-models`.

## 3. Folders
- Read-only task: all models run in the same repo, no `--write`.
- Code task: one worktree per model, created by Claude (delegate skill, step 2).
- monarch-api code tasks wait until its worktrees work. Read-only monarch-api bakeoffs are fine.

## 4. Run
All models in parallel, in the background. Only one pi-on-oMLX job at a time. The Claude subagent gets the same prompt file.

## 5. Score
- Per model: seconds, tokens, and cost from the `[agent]` summary line or the run's `meta.json`.
- Quality: Claude judges each answer against the done-when. For code, run the checks in each worktree.
- Optional blind score: `evaluate` (Jev) with only the task and the answer in state, never the model name.

## 6. Record
One Obsidian note per `Agents/README.md` (kind: bakeoff). It holds a table (model, time, cost, pass, notes), each answer or diff summary under its own heading, and Claude's verdict. Report to Craig: the table and a one-line verdict. Remove bakeoff worktrees when Craig is done with them.
