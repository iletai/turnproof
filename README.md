# Turnproof

<!-- One line: what the app does. -->

## Setup

```bash
brew install xcodegen swiftlint
bundle install
cp .env.example .env && chmod 600 .env          # fill values, never commit
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # if the app has build-time secrets
xcodegen generate && open Turnproof.xcodeproj
```

## Environments

| Scheme | Bundle id | Backend | Ships to |
|---|---|---|---|
| `Turnproof-Dev` | `com.iletai.turnproof.dev` | Dev | TestFlight (on every push to `develop`) |
| `Turnproof-Staging` | `com.iletai.turnproof.staging` | Prod | TestFlight (on push to `release/*`, `hotfix/*`) |
| `Turnproof` | `com.iletai.turnproof` | Prod | App Store (on tag `x.y.z`) |

fastlane: `bundle exec fastlane <lane> --env dev|staging|prod` (lanes from [iletai/ios-shared](https://github.com/iletai/ios-shared)).

## Branches

`feature/*` → PR into `develop` → `release/x.y.z` (version bump) → PR into `main` → tag `x.y.z` on the merge commit → merge `main` back into `develop`. Hotfix: `hotfix/x.y.z` from `main`. Conventional commits.

Store text lives in `fastlane/metadata/`; screenshots come from `bundle exec fastlane screenshots --env prod`.
