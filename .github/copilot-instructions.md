## Repository Scope

- Treat this repository as an npm-backed marketplace index for Spirit Agent extensions.
- Keep marketplace entry files under registry/extensions/.
- Do not add extension source trees, dist outputs, ZIP files, or other binary distribution artifacts to the repository.

## Source Of Truth

- Extension metadata lives in each published npm package's package.json under spiritExtension.
- Registry entry files should only store marketplace governance data, explicit approved versions, and extension-level marketplace review state.
- Do not duplicate displayName, description, supportedHosts, or requestedCapabilities in registry entries unless an explicit marketplace override is required.

## Documentation Boundaries

- Keep README.md minimal and repository-facing.
- Do not put workflow notes, temporary migration rationale, or agent process instructions into README files.
- Put durable agent guidance in this file instead of expanding repository READMEs.

## Registry Layout

- registry/extensions/<extension-id>/entry.json stores one marketplace entry per extension.
- registry/extensions/<extension-id>/README.md stores the marketplace-facing README for that extension.
- registry/catalog.json is the lightweight generated catalog consumed by marketplace list UIs.
- registry/extensions/<extension-id>/detail.json stores the hydrated detail artifact for that extension.
- schemas/*.schema.json defines the registry file shapes.
- scripts/validate-registry.ps1 validates registry/extensions/<extension-id>/entry.json and checks shared fields against registry/catalog.json and registry/extensions/<extension-id>/detail.json without npm network access.
- scripts/build-catalog.ps1 hydrates registry/catalog.json and registry/extensions/<extension-id>/detail.json from the explicit versions listed in registry/extensions/<extension-id>/entry.json.
- scripts/build-registry.ps1 validates registry state and rebuilds generated registry artifacts locally.

## Editing Guidance

- Prefer structural changes that preserve the repository root for future docs, schemas, and tooling.
- Update schemas and the build script together when the entry shape changes.
- Keep extension README content in registry/extensions/<extension-id>/README.md and reference it from generated detail artifacts instead of embedding full markdown into catalog.json.
- Regenerate registry/catalog.json and registry/extensions/<extension-id>/detail.json locally after editing any registry/extensions/<extension-id>/entry.json file or when published npm metadata changes.
- Do not manually edit registry/catalog.json or registry/extensions/<extension-id>/detail.json.
- Keep CI free of npm network requests; only local generation should hydrate the catalog.
- Keep defaultReviewStatus extension-scoped in entry/detail/catalog, and keep versions[].reviewStatus version-scoped.
- Keep packageName and extensionId unique across all entries.