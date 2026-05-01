# Contributing

This repository is the marketplace index for Spirit Agent extensions. It is not the place to host extension source code, build outputs, or packaged artifacts.

There are two separate steps if you want your extension to appear in this marketplace:

1. Publish a valid npm package.
2. Open a pull request to list that package in this repository.

## 1. Publish Your Extension Package

The source of truth for extension metadata is the published npm package's package.json, especially the spiritExtension field.

At minimum, your package.json should include:

```json
{
  "name": "@your-scope/your-package-name",
  "version": "0.1.0",
  "description": "One-line extension description.",
  "author": {
    "name": "your-name"
  },
  "repository": {
    "type": "git",
    "url": "git+https://github.com/your-org/your-repo.git"
  },
  "homepage": "https://github.com/your-org/your-repo#readme",
  "keywords": ["spirit-agent", "extension"],
  "spiritExtension": {
    "schemaVersion": 1,
    "displayName": "Your Extension Name",
    "supportedHosts": ["cli", "desktop"],
    "requestedCapabilities": ["your-capability"]
  }
}
```

### Required Spirit Agent Metadata

The current registry builder reads these fields from the published package:

- spiritExtension.schemaVersion
- spiritExtension.displayName
- spiritExtension.supportedHosts
- spiritExtension.requestedCapabilities

The marketplace also uses normal npm package metadata such as:

- name
- version
- description
- author
- repository
- homepage
- keywords
- optional spiritExtension.icon

If spiritExtension is missing, the registry build will fail for that package version.

### Real Example

The existing example extension in this repository maps to the published npm package @n123999/spirit-agent-extension-system-message-demo.

Its published package metadata currently includes:

- name: @n123999/spirit-agent-extension-system-message-demo
- version: 0.1.0
- spiritExtension.schemaVersion: 1
- spiritExtension.displayName: System message demo
- spiritExtension.supportedHosts: cli, desktop
- spiritExtension.requestedCapabilities: system-prompt

### Publish Checklist

Before asking to be listed here, make sure:

1. Your package is already published on npm.
2. The version you want listed is publicly available on npm.
3. package.json contains a valid spiritExtension object.
4. description, repository, homepage, and author are filled in accurately.
5. If you use spiritExtension.icon, the referenced file is included in the published package.

## 2. List the Package in This Marketplace

After the npm package exists, open a pull request against this repository.

### What To Add

Create one folder for your extension under registry/extensions/<extension-id>/ with these files:

- entry.json
- README.md

Do not manually edit generated files:

- registry/catalog.json
- registry/extensions/<extension-id>/detail.json

Those files are generated locally by the repository scripts.

### entry.json

Marketplace governance data lives in entry.json. This file does not duplicate all npm metadata. It mainly records:

- extensionId
- packageName
- status
- featured
- defaultVersion
- defaultReviewStatus
- versions[].version
- versions[].channel
- versions[].reviewStatus
- optional versions[].changelog

Current status values:

- listed
- hidden
- deprecated
- blocked

Current channel values:

- stable
- preview
- experimental

Current review status values:

- unverified
- verified
- revoked

Example:

```json
{
  "$schema": "../../../schemas/marketplace-entry.schema.json",
  "schemaVersion": 1,
  "extensionId": "your-scope.your-extension",
  "packageName": "@your-scope/your-package-name",
  "status": "listed",
  "featured": false,
  "defaultVersion": "0.1.0",
  "defaultReviewStatus": "unverified",
  "versions": [
    {
      "version": "0.1.0",
      "channel": "stable",
      "reviewStatus": "unverified",
      "changelog": {
        "summary": "Initial public release.",
        "body": "- Initial public release."
      }
    }
  ]
}
```

### extensionId Rules

The current schema requires this format:

- two dot-separated segments at minimum
- lowercase letters and digits
- dots or hyphens allowed inside each segment

For example:

- n123999.system-message-demo
- yourteam.some-extension

packageName and extensionId must both be unique across the repository.

### Marketplace README

Add a registry-facing README at registry/extensions/<extension-id>/README.md.

This README is intended for marketplace detail pages. Keep it focused on:

- what the extension does
- package name
- default approved version
- compatibility
- capability requests
- any notes contributors or users should see in the marketplace

### Generate Artifacts

After adding or changing an entry, regenerate the derived files locally:

```powershell
./scripts/build-registry.ps1
```

This script:

1. Pulls npm metadata for the explicitly listed versions.
2. Rebuilds registry/catalog.json.
3. Rebuilds registry/extensions/<extension-id>/detail.json.
4. Validates consistency.

## Pull Request Checklist

Please make sure your pull request includes all of the following:

1. A new or updated registry/extensions/<extension-id>/entry.json.
2. A new or updated registry/extensions/<extension-id>/README.md.
3. Regenerated registry/catalog.json and registry/extensions/<extension-id>/detail.json.
4. Only versions that are already published on npm.
5. Accurate review state and release channel for each listed version.

## What Not To Commit

Please do not add any of the following to this repository:

- extension source trees
- dist outputs
- ZIP files
- tarballs
- other binary distribution artifacts

This repository only indexes published extension packages and stores marketplace review data.

## Review Notes

Opening a pull request does not guarantee listing. Marketplace review may request changes before a package version is approved or verified.
