# Project Guidelines

## Commit Messages

- Conventional Commits: `type` and optional `scope` are in English; **subject and body must be in English** (except code identifiers, paths, API names, etc.).
- `subject`: one-line summary in English, no trailing period.
- `body`: optional; describe **the content and impact of this change** (user-visible behavior, external semantics, compatibility, etc.) in English.
- **`body` format**: If a body is provided, it **must** use `-` bullet points, **one item per line**; no trailing period per item; **do not** write it as a continuous prose paragraph.
- **Describe only the diff against the parent commit**: both subject and body should describe what this commit actually changed and what impact it brings relative to the previous version; do not include iterative narrative from the current session.
- **Forbidden mismatched comparisons**: If code that was just added in the same commit and did not exist in the parent commit is later revised during the session, **do not** write in the subject or body things like "avoid duplication with existing X" or "switch to reading Y to remove duplication" — the parent commit has no X, and Git cannot see this relationship, so it is a mismatched description.
- `scope`: English, optional; represents a module, package, or subsystem, e.g. `registry`, `schemas`, `scripts`, `ci`. Omit the parenthesis segment if no suitable scope.
- Multiple scopes: only use when the change cannot be split into multiple commits. Separate multiple scopes with a comma followed by a space, e.g. `(registry, schemas)`.
- Do not use multiple scopes to summarize "changed a lot of files" or as a substitute for splitting commits; multiple scopes are allowed only when multiple independent modules are genuinely modified and cannot be separated.
- If there are too many scopes, either reduce to the single most relevant scope or remove all scopes; do not stack a long list of scopes.

Example (`body`):

```
feat(registry): add example extension entry and detail

- Add marketplace entry for the example extension to registry/catalog.json
- Add detail manifest with readme reference and version metadata
```

❌ Mismatched: `add entry helper to validate manifest and avoid duplicate schema checks` — the parent commit had no duplicate checks; this is a subsequent rewrite narrative from the session and is unrelated to the diff.

### Passing Multi-line Subjects / Bodies via Command Line

- **PowerShell**: use a literal here-string `@' … '@` passed to `git commit -m`
- **bash**: use `git commit -m "$(cat <<'EOF' … EOF)"`

PowerShell example:

```powershell
git commit -m @'
feat(registry): example subject

- first body item
- second body item
'@
```

bash example:

```bash
git commit -m "$(cat <<'EOF'
feat(registry): example subject

- first body item
- second body item
EOF
)"
```
