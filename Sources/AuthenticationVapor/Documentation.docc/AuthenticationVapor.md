# ``AuthenticationVapor``

Binding who is calling on Vapor: a bearer token, proved and logged in to the request.

## Overview

``BearerAuthenticationMiddleware`` reads the `Authorization` header, proves the token with an
`Authenticator<String, Identity>` from swift-authentication, and sets the identity in two
places: the request's `auth`, which `GuardMiddleware`, `req.auth.require`, and route handlers
read, and the request's `serviceContext` as a `Principal<Identity, String>`. A route runs work
outside Vapor, such as an outgoing gRPC call that presents the same token onward, under that
context; <doc:TheRequestsContext> explains why the task's context is not enough.

The identity is any `Authenticatable`, so Vapor's own guard and require helpers work on it
unchanged.

Authentication returns an identity or throws. A missing credential continues anonymously;
a failed authentication ends the request with `401 Unauthorized` before the handler runs.

## Backend calls

mTLS secures connections to backend services. Forward the original user JWT only on upstream
user RPC descriptors, where the receiving service verifies it and the owning use case checks
permissions. User database settings follow the user operation.

## Example

```swift
let userRoutes = app.grouped(BearerAuthenticationMiddleware(authenticator: authenticator))

userRoutes.grouped(AppToken.guardMiddleware()).get("account") { req in
    try req.auth.require(AppToken.self)
}
```

## Topics

### Middleware

- ``BearerAuthenticationMiddleware``

### Design

- <doc:TheRequestsContext>
