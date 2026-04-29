## Repository Scope

- Treat this repository as an npm-backed marketplace index for Spirit Agent extensions.
- Keep marketplace entry files under registry/extensions/.
- Do not add extension source trees, dist outputs, ZIP files, or other binary distribution artifacts to the repository.

## Source Of Truth

- Extension metadata lives in each published npm package's package.json under spiritExtension.
- Registry entry files should only store marketplace governance and package resolution data.
- Do not duplicate displayName, description, supportedHosts, or requestedCapabilities in registry entries unless an explicit marketplace override is required.

## Documentation Boundaries

- Keep README.md minimal and repository-facing.
- Do not put workflow notes, temporary migration rationale, or agent process instructions into README files.
- Put durable agent guidance in this file instead of expanding repository READMEs.

## Registry Layout

- registry/extensions/*.json stores one marketplace entry per extension.
- registry/index.json is the generated aggregate index consumed by clients.
- schemas/*.schema.json defines the registry file shapes.
- scripts/build-index.ps1 regenerates registry/index.json from registry/extensions/*.json.

## Editing Guidance

- Prefer structural changes that preserve the repository root for future docs, schemas, and tooling.
- Update schemas and the build script together when the entry shape changes.
- Regenerate registry/index.json after editing any registry/extensions/*.json file.
- Keep packageName and extensionId unique across all entries.