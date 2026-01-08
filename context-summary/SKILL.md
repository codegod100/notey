---
name: context-summary
description: Use when context window is getting full. Creates a summary file and instructions for starting a new session.
---

# Context Summary Skill

Use this skill when the context window is filling up (~70-80% full) to create a handoff document for a new session.

## When to Use

- When you notice the context window is getting full (check with `/context`)
- Before starting a complex new task when context is already heavy
- When the user asks to "save context" or "create summary"

## What to Create

Create a file at `.copilot/session-summary.md` in the current working directory with:

### 1. Current State Summary
- What repository/project we're working in
- What branch we're on
- Current date/time

### 2. Completed Work
- Tasks completed this session
- Files created or modified
- PRs or issues created
- Key decisions made

### 3. In-Progress Work
- Current task being worked on
- What step we're at
- Any blockers or issues encountered

### 4. Important Context
- Key findings or discoveries
- Technical decisions and their rationale
- Gotchas or things to remember
- Links to relevant issues/PRs

### 5. Next Steps
- What should be done next
- Any pending questions for the user
- Suggested starting prompt for new session

## Template

```markdown
# Session Summary - [DATE]

## Repository
- Path: [path]
- Branch: [branch]

## Completed This Session
- [ ] Task 1
- [ ] Task 2

## Currently Working On
[Description of current task and status]

## Key Context
- [Important finding 1]
- [Important finding 2]

## Files Changed
- `path/to/file1.ext` - [what changed]
- `path/to/file2.ext` - [what changed]

## Relevant Links
- Issue #123: [title]
- PR #456: [title]

## Next Steps
1. [Next step 1]
2. [Next step 2]

## Suggested Prompt for New Session
> [Prompt to paste into new session to continue work]
```

## Instructions for User

After creating the summary, tell the user:

1. The summary has been saved to `.copilot/session-summary.md`
2. To start a new session, run `copilot` and paste the suggested prompt
3. Optionally, they can `@.copilot/session-summary.md` to include full context
