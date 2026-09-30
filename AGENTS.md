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

## What does not belong here

- Authorization. Requiring a caller is `guardMiddleware()`'s job on the routes that need one;
  roles and permissions are the application's.
- A credential format. Proofs are swift-authentication-jwt and swift-authentication-x509.
- Client certificates. Vapor does not expose the peer certificate to middleware; that is the
  gRPC package's concern.
- Vapor 5. It is in alpha on a 6.4 toolchain; this package targets Vapor 4 until 5 ships.

## Swift

- Swift 6.3, strict concurrency, `Sendable` everywhere it is meaningful.
- Tests use Swift Testing over VaporTesting's in-memory application: the middleware, a route that
  reports what it saw, and a guarded route. No server is started.
- Doc comments on every public declaration; the DocC catalog is the long-form explanation.
- Format with `swift-format format --in-place --recursive Sources Tests`; the soundness check on
  every pull request runs the same rules, an API breakage check against the base branch, and
  shellcheck and yamllint.
- File headers follow the existing files: name, package, author, date.

## Releases

- Every pull request carries exactly one label: `⚠️ semver/major`, `🆕 semver/minor`,
  `🔨 semver/patch`, or `semver/none`. The label check blocks merging without one.
- Releases are GitHub Releases, created by the Auto Release workflow: run it by hand on `main`
  and it computes the next version from the labels of the pull requests merged since the last
  release, tags it, and writes the notes from `.github/release.yml`. A major bump is refused
  there and is cut by hand.
- Consumers pin by tag, never by branch or path.
