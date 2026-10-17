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
  and `req.auth.require`, and `request.operationContext`, for everything downstream. Keep both in
  step. The task-local `OperationContext` is also bound, but Vapor 4's future-bridged responder
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

## CI

The standard library CI from the swift-microservices delivery skill
([library-ci.md](https://github.com/swift-microservices/skills/blob/main/skills/delivering-swift-services/references/library-ci.md)).
Exceptions:

- No Foundation-linking job: the one library product, `AuthenticationVapor`, depends on Vapor 4
  (4.122), which links full Foundation, so the check would have nothing left to build. Owned code
  uses FoundationEssentials where available, and the static SDK builds still run. Revisit with Vapor
  5.
