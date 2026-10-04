# swift-authentication-vapor

[![Documentation](https://img.shields.io/badge/docc-read_documentation-blue)](https://swiftpackageindex.com/swift-microservices/swift-authentication-vapor/documentation)

Binding who is calling on Vapor: a bearer token, proved and logged in to the request.

```swift
.package(url: "https://github.com/swift-microservices/swift-authentication-vapor.git", from: "0.3.0"),
```

```swift
.product(name: "AuthenticationVapor", package: "swift-authentication-vapor"),
```

## The middleware

`BearerAuthenticationMiddleware` reads the `Authorization` header, proves the token with an
`Authenticator<String, Identity>` from [swift-authentication](https://github.com/swift-microservices/swift-authentication),
and sets the identity in two places:

- the request's `auth`, which `GuardMiddleware`, `req.auth.require`, and route handlers read;
- the request's `serviceContext`, as a `Principal<Identity, String>` under
  `PrincipalKey<Identity, String>`.

```swift
let userRoutes = app.grouped(
    BearerAuthenticationMiddleware(authenticator: JWTAuthenticator<AppToken>(keys: keys))
)

userRoutes.grouped(AppToken.guardMiddleware()).get("account") { req in
    try req.auth.require(AppToken.self)
}
```

The identity is any `Authenticatable`, so Vapor's own guard and require helpers work on it
unchanged. A request with no token continues anonymously, which is what an open route needs:
signing in mints the first token and has no caller yet. `Authenticator.authenticate(_:)` returns
an identity or throws. A failed authentication ends the request with `401 Unauthorized` before the route
runs. Requiring a caller is a route's decision, made with `guardMiddleware()`. Keep sign-in and refresh
routes outside the authenticated group, so an expired token a client still attaches cannot
block recovery.

## The request's context, not the task's

Vapor 4 bridges its responder chain through event-loop futures, so a task-local bound in
middleware does not reach a route. The request's `serviceContext` is the one that does, which is
also how Vapor's own tracing middleware carries its span. Work that reads
`ServiceContext.current`, such as an outgoing gRPC call presenting the token onward through
swift-authentication-grpc, is run under it:

```swift
try await ServiceContext.withValue(req.serviceContext) {
    try await upstream.call(request)
}
```

## Backend calls

mTLS secures connections to backend services. Forward the original user JWT only on upstream
user RPC descriptors, where the receiving service verifies it and the owning use case checks
permissions. User database settings follow the user operation.

## Requirements

Swift 6.3, macOS 15 or Linux. Vapor 4.122, swift-authentication 0.3.

Vapor 4 links full Foundation, including its internationalization libraries (still true of
4.122.2), so unlike the other swift-authentication packages this one has no Foundation linking
check in CI. Its own code needs no Foundation.

## Development

```sh
swift test
swift-format lint --strict --recursive Sources Tests    # what the soundness check runs
```

## Contributing

Pull requests are welcome. Keep a change focused, prove new behaviour with a test, and label the
pull request with its semantic version impact.

## License

MIT. See [LICENSE](LICENSE).
