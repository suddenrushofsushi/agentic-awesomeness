---
name: blind-draft
description: Use for architecture or design work where Craig wants a second opinion from Codex. Triggers - "blind draft", "get codex's take", "architect this with codex", "design review with sol", "second opinion on the design". Codex (Sol 6.1) drafts from the same brief without seeing Claude's draft; Claude compares both and shows Craig the gaps.
---
# blind-draft

## 1. Brief
Agree the brief with Craig first: problem, constraints, non-goals, context files, decisions already made. Write it to a file. Both drafts get exactly this brief.

## 2. Start Sol
`agent codex -m gpt-6.1-sol -e high -C <repo> - < brief.md`, in the background, read-only. If it fails (capacity or other error), run it once more. If it fails again, tell Craig.

## 3. Write Claude's draft
Write Claude's draft before reading any Sol output. Save it to the Obsidian note before you open Sol's answer.

## 4. Compare
When both drafts exist, list:
- agreements (short)
- disagreements
- points only one draft covers

For each disagreement and one-sided point, give Claude's recommendation and the reason.

## 5. Back-and-forth (optional)
For a disputed point, send Sol Claude's counter-argument:
`agent codex --resume <session> -m gpt-6.1-sol -e high "<counter-argument>"`
Max 2 rounds per point. Concede when Sol is right.

## 6. Craig decides
Show Craig the gap list: both positions and Claude's pick for each. Record his decisions in the note.

## 7. Record
One Obsidian note per `Agents/README.md` (kind: blind-draft): brief, Claude draft, Sol draft, gap table, decisions.
