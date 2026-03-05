# Worker Tools — Quick Reference

## find-skills: Your First Stop for Unknown Problems

If you encounter a task or problem where you don't know the best approach, **check for a skill first** before improvising.

The `find-skills` skill is your package manager for extending capabilities. When assigned, it gives you access to the `skills` CLI.

### When to use it

- You're asked to do something outside your current skill set
- You're unsure of the best tool or workflow for a task
- You want to check if a specialized skill exists before doing it manually

### How to use it

```bash
# Search for relevant skills
skills find [query]

# Install a skill (use exact owner/repo@skill format from search results)
skills add <owner/repo@skill> -g -y
```

Examples:
- Need to work with React? → `skills find react`
- Need to write tests? → `skills find testing`
- Need to review a PR? → `skills find pr review`
- Need to deploy something? → `skills find deploy`

### Priority rule

> **If `find-skills` is in your `skills/` directory, always search before attempting an unfamiliar task.**
> Read `skills/find-skills/SKILL.md` for full usage details.

Installed skills are automatically synced to MinIO and persist across restarts.

---

Add local notes below — SSH aliases, hostnames, credentials paths, or anything environment-specific that helps you do your job.
