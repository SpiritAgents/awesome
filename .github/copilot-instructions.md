## Repository Scope

- Treat this repository as a source marketplace for Spirit Agent extensions.
- Keep extension source under extensions/<extension-folder>/.
- Do not add ZIP files or other binary distribution artifacts to the repository.

## Documentation Boundaries

- Keep README.md minimal and repository-facing.
- Do not put workflow notes, temporary migration rationale, or agent process instructions into README files.
- Put durable agent guidance in this file instead of expanding repository READMEs.

## Extension Layout

- Each extension should live in its own folder under extensions/.
- Each extension folder should contain spirit-extension.json and its implementation files.
- Keep extension-specific documentation inside that extension folder.

## Editing Guidance

- Prefer structural changes that preserve the repository root for future docs, schemas, and tooling.
- When reorganizing marketplace content, keep source directories as the canonical content and avoid duplicate packaged outputs.