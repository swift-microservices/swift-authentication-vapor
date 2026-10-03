# Repository guidelines

This package binds principals on Vapor. Read this before changing anything.

## What this package is

- One product, `AuthenticationVapor`: `BearerAuthenticationMiddleware`, an `AsyncMiddleware`
  over any `Authenticatable & Sendable` identity, taking any `Authentication.Authenticator<String, Identity>`.
  Vapor has its own `Authenticator` protocol, so the one from swift-authentication is always
  spelled with its module.
- It is an `AsyncMiddleware`, not one of Vapor's `AsyncBearerAuthenticator`s, because those call
  the next responder themselves and the principal has to be bound around that call.
- It sets the identity in both places Vapor code reads it: `request.auth`, for `GuardMiddleware`
  and `req.auth.require`, and `request.serviceContext`, for everything downstream. Keep both in
  step. The task-local `ServiceContext` is also bound, but Vapor 4's future-bridged responder
  chain does not carry it to routes; do not write tests that assume it does.
- Authentication returns an identity or throws. An identity binds; a failure ends the request
  with `Abort(.unauthorized)` before the route runs. A request with no token never reaches
  the authenticator and continues anonymously.
- The `Authorization` header is read with Vapor's own `headers.bearerAuthorization`; this package
  parses nothing itself.

## Application standard

- Apply bearer middleware and user guards to user routes. Owning use cases authorize users.
- Backend RPC connections use mandatory mTLS. Forward the original user JWT only on user
  descriptors; each receiving service verifies it. User database settings follow user operations.
- Keep public, user, and internal RPC audiences separate and internal listeners private.

## What does not belong here

- Authorization. Requiring a caller is `guardMiddleware()`'s job on the routes that need one;
  roles and permissions are the application's.
- A credential format. swift-authentication-jwt provides user JWT verification.
- Backend transport configuration. Composition roots own mandatory mTLS, explicit CA trust,
  and certificate reloader lifecycle for outgoing service RPCs.
- Vapor 5. It is in alpha on a 6.4 toolchain; this package targets Vapor 4 until 5 ships.

## Swift

- Swift 6.3, strict concurrency, `Sendable` everywhere it is meaningful.
- Tests use Swift Testing over VaporTesting's in-memory application: the middleware, a route that
  reports what it saw, and a guarded route. No server is started.
- Doc comments on every public declaration; the DocC catalog is the long-form explanation.
- Use the checked-in `.swift-format`, copied exactly from apple/swift-temporal-sdk at
  `508797b5468dbc532f77c317bf9df0cb3231f5c1`: four-space indentation, 150-column lines,
  and ordered imports. Format all tracked Swift files, including `Package.swift`, and run
  `swift-format lint --strict`. Public documentation remains a repository requirement even
  though this formatter does not enforce it.
- File headers use the compact license format documented below.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases, created by the Auto Release workflow: run it by hand on `main`
  and it computes the next version from the labels of the pull requests merged since the last
  release, tags it, and writes the notes from `.github/release.yml`. A major bump is refused
  there and is cut by hand.
- Consumers pin by tag, never by branch or path.

## Library CI profile

- This repository profile overrides general service CI and formatting defaults. Libraries
  never commit `Package.resolved`; CI resolves released dependencies from the manifest.
- PRs run documentation, formatting, compact license-header, shellcheck, and yamllint checks.
  Automatic API-breakage checking is disabled by project choice; SemVer labels still describe
  the public API impact. The docs workflow adds the DocC plugin only in its temporary checkout.
- PRs and main pushes run Linux tests on Swift 6.3 and 6.4, next/main snapshots, release builds,
  and static Linux SDK checks. CI has no scheduled runs. Require supported stable checks in
  branch protection; snapshot failures remain visible and advisory unless maintainers
  explicitly require them.
- CI is Linux-only by project choice. macOS and other Apple-platform builds/tests are
  outside this pipeline; Linux success does not establish Apple-platform compatibility.
- Shared library workflows and the SwiftNIO SemVer action follow `@main` by project choice.
  Soundness uses its release tag, and standard Actions use major-version tags. These moving
  references include upstream changes; do not describe them as immutable.
- Dependabot checks weekly, targets main, and labels workflow-update PRs `semver/none`.
- Use the three-line MIT header matched by `.license_header_template`. Keep the tools-version
  directive first in `Package.swift`, followed by that header. `.licenseignore` excludes the
  manifest (the upstream checker requires a header at line one) and the plain-text `LICENSE`.
- Full Foundation linking is an upstream Vapor 4 dependency exception; retain the static
  SDK compatibility build and use FoundationEssentials in our own code where available.
