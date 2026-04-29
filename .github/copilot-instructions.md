## Repository Scope

- Treat this repository as an npm-backed marketplace index for Spirit Agent extensions.
- Keep marketplace entry files under registry/extensions/.
- Do not add extension source trees, dist outputs, ZIP files, or other binary distribution artifacts to the repository.

## Source Of Truth

- Extension metadata lives in each published npm package's package.json under spiritExtension.
- Registry entry files should only store marketplace governance data and explicit approved versions.
- Do not duplicate displayName, description, supportedHosts, or requestedCapabilities in registry entries unless an explicit marketplace override is required.

## Documentation Boundaries

- Keep README.md minimal and repository-facing.
- Do not put workflow notes, temporary migration rationale, or agent process instructions into README files.
- Put durable agent guidance in this file instead of expanding repository READMEs.

## Registry Layout

- registry/extensions/*.json stores one marketplace entry per extension.
- registry/catalog.json is the hydrated generated catalog consumed by marketplace list UIs.
- schemas/*.schema.json defines the registry file shapes.
- scripts/validate-registry.ps1 validates registry/extensions/*.json and checks shared fields against registry/catalog.json without npm network access.
- scripts/build-catalog.ps1 hydrates registry/catalog.json from the explicit versions listed in registry/extensions/*.json.
- scripts/build-registry.ps1 validates registry state and rebuilds registry/catalog.json locally.

## Editing Guidance

- Prefer structural changes that preserve the repository root for future docs, schemas, and tooling.
- Update schemas and the build script together when the entry shape changes.
- Regenerate registry/catalog.json locally after editing any registry/extensions/*.json file or when published npm metadata changes.
- Do not manually edit registry/catalog.json.
- Keep CI free of npm network requests; only local generation should hydrate the catalog.
- Keep reviewStatus version-scoped and avoid marking versions as verified casually.
- Keep packageName and extensionId unique across all entries.