---
name: skill-helper
description: Helper for creating new Copilot CLI skills
---

# Skill Helper

Create new skills for GitHub Copilot CLI.

## Skill Location

Skills must be placed in: `/home/nandi/.copilot/skills/<skill-name>/SKILL.md`

## Skill Template

```markdown
---
name: my-skill-name
description: Brief description shown in skill list
---

# Skill Title

Detailed instructions for the skill.

## Commands

```bash
# Example commands
```

## Usage Notes

- Additional context
- Configuration requirements
```

## Creating a New Skill

```bash
SKILL_NAME="my-new-skill"
mkdir -p /home/nandi/.copilot/skills/$SKILL_NAME
cat > /home/nandi/.copilot/skills/$SKILL_NAME/SKILL.md << 'EOF'
---
name: my-new-skill
description: Description here
---

# My New Skill

Instructions here.
EOF
```

## Required Fields

1. **Frontmatter** (between `---` markers):
   - `name`: Skill identifier (used to invoke with `/skill name`)
   - `description`: Brief description shown in skill list

2. **Body**: Markdown content with instructions, commands, examples

## Existing Skills

| Skill | Location | Purpose |
|-------|----------|---------|
| roc-compiler | ~/.copilot/skills/roc-compiler/ | Use Zig-based Roc interpreter |
| roc-syntax | ~/.copilot/skills/roc-syntax/ | Roc language syntax reference |
| roc-zulip | ~/.copilot/skills/roc-zulip/ | Read Roc Zulip chat messages |
| context-summary | ~/.copilot/skills/context-summary/ | Summarize context for new sessions |

## Tips

- Keep skill names lowercase with hyphens
- Description should be one line, under 80 chars
- Include example commands that can be copy-pasted
- Reference config files or environment variables needed
- After creating, reload the CLI session to pick up new skills
