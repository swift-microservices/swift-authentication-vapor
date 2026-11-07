# Swift Authentication for Vapor

[![Documentation](https://img.shields.io/badge/docc-read_documentation-blue)](https://swiftpackageindex.com/swift-microservices/swift-authentication-vapor/documentation)
[![Release](https://img.shields.io/github/v/release/swift-microservices/swift-authentication-vapor)](https://github.com/swift-microservices/swift-authentication-vapor/releases)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fswift-microservices%2Fswift-authentication-vapor%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/swift-microservices/swift-authentication-vapor)
[![CI](https://github.com/swift-microservices/swift-authentication-vapor/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/swift-microservices/swift-authentication-vapor/actions/workflows/ci.yml)

Swift Authentication for Vapor tells a [Vapor](https://vapor.codes) route who is calling. One
middleware reads the bearer token, proves it, and logs the caller in to the request.

- 🔐 One middleware for any [swift-authentication](https://github.com/swift-microservices/swift-authentication)
  `Authenticator`, such as a JWT verifier
- 🤝 Works with Vapor's own `req.auth`, `guardMiddleware()` and `req.auth.require`
- 📦 Swift Package Manager, on Vapor 4.122, swift-authentication 1.0 and
  swift-operation-context 1.0
- 🐧 Linux (x86_64, aarch64 and the static SDK) and macOS 15+
- 🔧 Swift 6.3+ with strict concurrency

🔗 Jump to:
- 📖 [Overview](#-overview)
- 🏁 [Getting Started](#-getting-started)
- 📘 [Documentation](#-documentation)
- 🧰 [Release Info](#-release-info)
- 🛠️ [Support](#%EF%B8%8F-support)

## 📖 Overview

`BearerAuthenticationMiddleware` reads the `Authorization` header and proves the token with an
`Authenticator<String, Identity>` from swift-authentication. The authenticator returns an identity
or throws. The middleware then sets the identity in two places:

- the request's `auth`, which `GuardMiddleware`, `req.auth.require` and route handlers read;
- the request's `operationContext`, as a `Principal<Identity, String>` under
  `PrincipalKey<Identity, String>`, for work outside Vapor, such as an outgoing gRPC call that
  presents the same token onward through
  [swift-authentication-grpc](https://github.com/swift-microservices/swift-authentication-grpc).

**Key Features:**
- 🙋 **Anonymous by default**: a request with no token continues anonymously, which is what an
  open route needs: signing in mints the first token and has no caller yet
- 🚫 **Clean rejection**: a token that fails authentication ends the request with
  `401 Unauthorized` before the route runs
- 🛂 **Your routes decide**: requiring a caller is a route's decision, made with
  `guardMiddleware()`; roles and permissions stay in the application
- 🤝 **Vapor-native identity**: the identity is any `Authenticatable`, so Vapor's own guard and
  require helpers work on it unchanged
- 🧵 **Context that reaches the route**: `request.operationContext` carries the principal across
  Vapor 4's responder chain, where a task-local would not

## 🏁 Getting Started

### Prerequisites

- Swift version: Swift 6.3+
- Platforms: macOS 15+ or Linux

To install/upgrade Swift, see https://www.swift.org/install/

### Adding as a dependency

Add the package, and the product to your target, in your `Package.swift` file. The examples below
also verify JSON Web Tokens with
[swift-authentication-jwt](https://github.com/swift-microservices/swift-authentication-jwt):

```swift
dependencies: [
    .package(url: "https://github.com/swift-microservices/swift-authentication-vapor.git", from: "1.0.0"),
    .package(url: "https://github.com/swift-microservices/swift-authentication-jwt.git", from: "1.0.0"),
    .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.7.1"),
],
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "AuthenticationVapor", package: "swift-authentication-vapor"),
            .product(name: "AuthenticationJWT", package: "swift-authentication-jwt"),
            .product(name: "JWTKit", package: "jwt-kit"),
        ]
    )
]
```

### Usage

Add `BearerAuthenticationMiddleware` to the route group for your users, with a `JWTAuthenticator`
that verifies their tokens. `AppToken` is your own token payload:

```swift
import AuthenticationJWT
import AuthenticationVapor
import JWTKit
import Vapor

// Your token payload. `Authenticatable` lets Vapor's guard and require helpers read it.
struct AppToken: JWTPayload, Authenticatable {
    let sub: SubjectClaim
    let exp: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

func routes(_ app: Application, publicKey: EdDSA.PublicKey) async throws {
    let keys = JWTKeyCollection()
    await keys.add(eddsa: publicKey)

    // Keep sign-in and refresh routes outside this group, so an expired token
    // a client still attaches cannot block recovery.
    let userRoutes = app.grouped(
        BearerAuthenticationMiddleware(authenticator: JWTAuthenticator<AppToken>(keys: keys))
    )

    // `guardMiddleware()` makes this route require a caller.
    userRoutes.grouped(AppToken.guardMiddleware()).get("account") { req in
        let token = try req.auth.require(AppToken.self)
        return token.sub.value
    }
}
```

#### Reading the principal from the request's context

The middleware also records a `Principal`, the identity together with the token as presented, in
`req.operationContext`. Read it there, and run work that reads `OperationContext.current` under
that context:

```swift
import Authentication
import AuthenticationVapor
import OperationContext
import Vapor

func orderRoutes(_ userRoutes: any RoutesBuilder, orders: OrdersClient) {
    userRoutes.get("whoami") { req in
        guard let principal = req.operationContext[PrincipalKey<AppToken, String>.self] else {
            throw Abort(.unauthorized)
        }
        return principal.identity.sub.value
    }

    userRoutes.get("orders") { req in
        // `OrdersClient` stands for your own client for a backend service. Inside this closure,
        // swift-authentication-grpc's interceptor finds the principal and presents
        // the original token on upstream user RPCs.
        try await OperationContext.withContext(req.operationContext) {
            try await orders.list()
        }
    }
}
```

Vapor 4 bridges its responder chain through event-loop futures, so a task-local bound in
middleware does not reach a route. `request.operationContext` lives in request storage instead: it
starts empty, and the middleware adds the principal to it, keeping values that earlier middleware
recorded.

When a route calls backend services, mTLS secures those connections. Forward the original user
JWT only on upstream user RPC descriptors, where the receiving service verifies it and the owning
use case checks permissions. User database settings follow the user operation.

#### Testing with a stub authenticator

Any `Authenticator<String, Identity>` works, so tests can prove tokens from a table with
[VaporTesting](https://docs.vapor.codes/advanced/testing/). Vapor has its own `Authenticator`
protocol, so spell this one `Authentication.Authenticator`:

```swift
import Authentication
import AuthenticationVapor
import JWTKit
import Testing
import Vapor
import VaporTesting

struct StubAuthenticator: Authentication.Authenticator {
    struct Refused: Error {}

    func authenticate(_ token: String) throws -> AppToken {
        guard token == "alice-token" else { throw Refused() }
        return AppToken(sub: "alice", exp: ExpirationClaim(value: .distantFuture))
    }
}

@Test func accountRequiresACaller() async throws {
    try await withApp { app in
        app.grouped(BearerAuthenticationMiddleware(authenticator: StubAuthenticator()))
            .grouped(AppToken.guardMiddleware())
            .get("account") { req in try req.auth.require(AppToken.self).sub.value }

        try await app.testing().test(.GET, "account") { response in
            #expect(response.status == .unauthorized)
        }
        try await app.testing().test(.GET, "account", headers: ["Authorization": "Bearer alice-token"]) { response in
            #expect(response.body.string == "alice")
        }
    }
}
```

## 📘 Documentation

- [API Documentation](https://swiftpackageindex.com/swift-microservices/swift-authentication-vapor/documentation) -
  the full API reference on Swift Package Index
- [The request's context](https://swiftpackageindex.com/swift-microservices/swift-authentication-vapor/documentation/authenticationvapor/therequestscontext) -
  where the proven identity goes on Vapor, and why it is the request that carries it

Related packages:

- [swift-authentication](https://github.com/swift-microservices/swift-authentication) - the
  `Authenticator`, `Principal` and `PrincipalKey` types this package binds
- [swift-authentication-jwt](https://github.com/swift-microservices/swift-authentication-jwt) -
  `JWTAuthenticator`, used in the examples above
- [swift-authentication-grpc](https://github.com/swift-microservices/swift-authentication-grpc) -
  presents the principal's token onward on outgoing gRPC calls
- [swift-operation-context](https://github.com/swift-microservices/swift-operation-context) -
  the `OperationContext` that `req.operationContext` holds

## 🧰 Release Info

- Versioning: follows [Semantic Versioning](https://semver.org). The public API is stable from
  1.0.0 and only a major release breaks it; CI checks every pull request for API breakage.
- Release notes: on [GitHub Releases](https://github.com/swift-microservices/swift-authentication-vapor/releases).
- Swift versions: CI tests Swift 6.3 and 6.4, plus nightly toolchains, on Linux x86_64 and
  aarch64, and builds with the static Linux SDK.
- Foundation: Vapor 4 links full Foundation, including its internationalization libraries (still
  true of 4.122.2), so unlike the other swift-authentication packages this one has no Foundation
  linking check in CI. Its own code needs no Foundation.

## 🛠️ Support

If you have any questions or need help, feel free to reach out by
[opening an issue](https://github.com/swift-microservices/swift-authentication-vapor/issues).

Pull requests are welcome. Keep a change focused, prove new behaviour with a test, and label the
pull request with its semantic version impact.

### Development

```sh
swift test
swift-format lint --strict --recursive Sources Tests    # what the soundness check runs
```

## License

MIT. See [LICENSE](LICENSE).
