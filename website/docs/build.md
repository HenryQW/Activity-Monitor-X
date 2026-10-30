---
title: Build from source
description: Build Activity Monitor X with the Command Line Tools, run the tests, and run the docs site.
---

## Requirements

- macOS 26 or later, on a Mac with Apple silicon.
- Command Line Tools for Xcode. Run `xcode-select --install` if you do not have them. Xcode is not necessary.

## Build and install

```sh
git clone https://github.com/HenryQW/amx.git
cd amx
make cert
make install
open "/Applications/Activity Monitor X.app"
```

- `make cert` makes a self-signed code-signing certificate in your login keychain. Do this one time. macOS asks for your login password.
- `make install` builds the app, signs it with that certificate, and copies it to `/Applications`. At the first launch, the app registers its helper. Approve it as [Install](/install#approve-the-helper) tells.

The helper accepts only callers that are signed with the same certificate as itself. So a build that you sign with your certificate works only with a helper from the same certificate. The [Release](/release#the-release-certificate) page tells more.

## Other tasks

| Task | Command |
| --- | --- |
| Run the tests | `make test` |
| Build without signing | `make build` |
| Run the docs site | `cd website && pnpm install && pnpm dev` |

The version is in the `VERSION` file.

## The docs site

Cloudflare Pages builds the docs site from `main` at each push: the project runs `pnpm build` in `website` and publishes `website/dist` at [amx.henry.wang](https://amx.henry.wang). The pnpm and Node versions come from `website/package.json`.
