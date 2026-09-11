# ``AuthenticationVapor``

Binding who is calling on Vapor: a bearer token, proved and logged in to the request.

## Overview

``BearerAuthenticationMiddleware`` reads the `Authorization` header, proves the token with an
`Authenticator<String, Identity>` from swift-authentication, and sets the identity in two
places: the request's `auth`, which `GuardMiddleware`, `req.auth.require`, and route handlers
read, and the request's and task's `ServiceContext` as a `Principal<Identity, String>`, which
everything downstream reads, including outgoing gRPC calls that present the same token onward.

The identity is any `Authenticatable`, so Vapor's own guard and require helpers work on it
unchanged.

## Example

```swift
app.middleware.use(BearerAuthenticationMiddleware(authenticator: authenticator))

app.grouped(AppToken.guardMiddleware()).get("account") { req in
    try req.auth.require(AppToken.self)
}
```

## Topics

### Middleware

- ``BearerAuthenticationMiddleware``

### Design

- <doc:TheRequestsContext>
