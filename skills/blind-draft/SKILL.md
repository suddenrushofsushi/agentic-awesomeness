---
name: blind-draft
description: Use for architecture or design work where Craig wants a second opinion from Codex. Triggers - "blind draft", "get codex's take", "architect this with codex", "design review with astra", "second opinion on the design". Codex (Astra) drafts from the same brief without seeing Claude's draft; Claude compares both and shows Craig the gaps.
---
# blind-draft

## 1. Brief
Agree the brief with Craig first: problem, constraints, non-goals, context files, decisions already made. Write it to a file. Both drafts get exactly this brief.

## 2. Start Astra
`agent codex -m gpt-6-astra -e high -C <repo> - < brief.md`, in the background, read-only. If it fails (capacity or other error), run it again on `gpt-6-sol` and say so in the report.

## 3. Write Claude's draft
Write Claude's draft before reading any Astra output. Save it to the Obsidian note before you open Astra's answer.

## 4. Compare
When both drafts exist, list:
- agreements (short)
- disagreements
- points only one draft covers

For each disagreement and one-sided point, give Claude's recommendation and the reason.

## 5. Back-and-forth (optional)
For a disputed point, send Astra Claude's counter-argument:
`agent codex --resume <session> -m gpt-6-astra -e high "<counter-argument>"`
Max 2 rounds per point. Concede when Astra is right.

## 6. Craig decides
Show Craig the gap list: both positions and Claude's pick for each. Record his decisions in the note.

## 7. Record
One Obsidian note per `Agents/README.md` (kind: blind-draft): brief, Claude draft, Astra draft, gap table, decisions.
