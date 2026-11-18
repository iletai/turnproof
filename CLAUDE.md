# CLAUDE.md

## What this app is

<!-- One paragraph: what Turnproof does and for whom. -->

## Architecture

- `App/` — SwiftUI app target. `Features/<Name>/` per screen.
- `Packages/` — local Swift packages (add to `project.yml` `packages:` + target `dependencies:`).
- Own libraries (navigation, update prompt, StoreKit): see skill `iletai-libs`.

## Conventions

- iOS 18+, Swift 6 strict concurrency.
- `project.yml` is the source of truth; run `xcodegen generate` after editing it (`*.xcodeproj` is not committed).
- Environments Dev / Staging / Prod (Staging uses the Prod backend): schemes `Turnproof-Dev`, `Turnproof-Staging`, `Turnproof`; configs `{Debug,Release}-{Dev,Staging,Prod}`; per-env values only in `Config/{Dev,Staging,Prod}.xcconfig` (+ `Backend-Prod.xcconfig`). Read the env via `AppConfiguration.environment`. Never add schemes/configs outside this set.
- Secrets only in `.env` (gitignored); non-secret fastlane values in `fastlane/.env.default` + `fastlane/.env.{dev,staging,prod}`.
- Build-time values: xcconfig variable → `project.yml` `info.properties` → `AppConfiguration`. Never `INFOPLIST_KEY_<custom>` (Xcode drops it).
- Log with `Log.<area>` (os.Logger), not `print`.
- Heavy builds/screenshots run on GitHub Actions, not locally.

## Release

Git Flow: `feature/*` → `develop` → `release/x.y.z` → `main` + tag `x.y.z`; `hotfix/x.y.z` from `main`. Lanes come from `iletai/ios-shared` (`--env dev|staging|prod`). Workflows: `ci.yml`, `deploy-{dev,staging,prod}.yml`.
Release steps: skill `app-store-release`. Signing: skill `ios-cicd-signing`.
