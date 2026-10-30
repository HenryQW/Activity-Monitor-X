---
title: Release
description: How a release of Activity Monitor X is made and put on Homebrew.
---

A tag starts a release. The GitHub Actions workflow `.github/workflows/release.yml` runs on the `xcode-27` runner (Apple silicon).

## Make a release

1. Write the new version in `VERSION`, for example `0.2.0`, and commit it.
2. Tag the commit with the same version, then push the tag:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow stops if the tag is not `v` followed by the version in `VERSION`.

## What the workflow does

1. It runs the tests.
2. It builds the app and the helper, signs them with the release certificate, and makes the disk image.
3. It publishes a GitHub release with `AMX-<version>.dmg`, its SHA-256 file `AMX-<version>.dmg.sha256`, and `AMX.dmg`. The download link on the home page always points to the `AMX.dmg` of the latest release.
4. If `TAP_TOKEN` is set, it writes the new version and checksum into `Casks/amx.rb` in `HenryQW/homebrew-tap`.

## Signing

A release has no Developer ID signature, so Apple does not notarize it. macOS blocks the downloaded app at the first launch, and users remove the quarantine flag or click Open Anyway (see [Install](/install#open-amx-the-first-time)).

## The release certificate

The helper runs as root, and it can quit processes. So it accepts only callers that are signed with the same certificate as itself. Each release must be signed with one stable certificate: the app and `amx` of a release then work with its helper, and nothing else can talk to the helper. The release certificate is a self-signed code-signing certificate. The workflow gets it, with its private key, from the repository secrets.

## The secrets

Set these in the repository settings, under Secrets and variables > Actions:

| Secret | What it holds |
| --- | --- |
| `RELEASE_CERT_P12` | The release certificate and its private key, as a `.p12` file in base64. |
| `RELEASE_CERT_PASSWORD` | The password of that `.p12` file. |
| `TAP_TOKEN` | A fine-grained token with write access to the contents of `HenryQW/homebrew-tap`. Without it the release still publishes, and the tap does not change. |

`Scripts/make-release-cert.sh` makes the release certificate once and prints the two values for `RELEASE_CERT_P12` and `RELEASE_CERT_PASSWORD`. Keep the `.p12` file out of the repository.

## The Homebrew tap

The tap is the repository `HenryQW/homebrew-tap`. The workflow writes `Casks/amx.rb` from the template `Packaging/homebrew/amx.rb`. Users install with:

```sh
brew trust --tap henryqw/tap && brew install --cask henryqw/tap/amx
```

A tap is a public GitHub repository whose name starts with `homebrew-`. `brew trust --tap henryqw/tap` lets Homebrew load casks from it. `brew install --cask henryqw/tap/amx` clones `github.com/HenryQW/homebrew-tap` (the first time only), reads `Casks/amx.rb`, downloads the disk image from the GitHub release, checks its SHA-256, copies the app to `/Applications`, and links `amx`. `brew update` gets new versions of the cask. Homebrew does not review a tap. The tap and the `amx` repository must be public: Homebrew downloads without a GitHub sign-in.

To check the cask before a release, fill in the template and run `brew style` on it.

The official Homebrew cask repository does not take AMX: it accepts only apps that pass Gatekeeper, so it needs a Developer ID and notarization.
