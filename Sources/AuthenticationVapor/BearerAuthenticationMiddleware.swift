//
//  BearerAuthenticationMiddleware.swift
//  swift-authentication-vapor
//
//  Created by Zaid Rahhawi on 9/11/26.
//

import Authentication
import ServiceContextModule
import Vapor

/// Binds the principal a bearer token proves, for the length of the request.
///
/// The token is read from the `Authorization` header. A request with no token continues
/// anonymously, which is what an open route needs. A token the authenticator declines continues
/// unbound. A token it refuses fails the request with `401 Unauthorized`, because absent and
/// invalid are not the same thing.
///
/// The proven identity is set in two places: the request's `auth`, which `GuardMiddleware`,
/// `req.auth.require`, and route handlers read, and the request's `serviceContext`, under
/// `PrincipalKey<Identity, String>`. Vapor 4 bridges its responder chain through event-loop
/// futures, so a task-local bound here does not reach a route; the request's context is the one
/// that does. Work that reads `ServiceContext.current`, such as an outgoing gRPC call presenting
/// the token onward, is run under it:
///
/// ```swift
/// try await ServiceContext.withValue(req.serviceContext) {
///     try await upstream.call(request)
/// }
/// ```
///
/// ```swift
/// app.middleware.use(BearerAuthenticationMiddleware(authenticator: authenticator))
///
/// app.grouped(AppToken.guardMiddleware()).get("account") { req in
///     try req.auth.require(AppToken.self)
/// }
/// ```
///
/// This is an `AsyncMiddleware` rather than one of Vapor's `AsyncBearerAuthenticator`s because
/// the latter call the next responder themselves, and the principal has to be bound around that
/// call. Vapor has its own `Authenticator` protocol, so the one from swift-authentication is
/// spelled `Authentication.Authenticator` here.
public struct BearerAuthenticationMiddleware<Identity: Authenticatable & Sendable>: AsyncMiddleware {
    private let authenticator: any Authentication.Authenticator<String, Identity>

    /// - Parameter authenticator: Proves the token, such as a `JWTAuthenticator`.
    public init(authenticator: any Authentication.Authenticator<String, Identity>) {
        self.authenticator = authenticator
    }

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let token = request.headers.bearerAuthorization?.token else {
            return try await next.respond(to: request)
        }

        guard let identity = try await authenticate(token) else {
            return try await next.respond(to: request)
        }

        request.auth.login(identity)

        var serviceContext = ServiceContext.current ?? request.serviceContext
        serviceContext[PrincipalKey<Identity, String>.self] = Principal(identity: identity, credential: token)
        request.serviceContext = serviceContext

        return try await ServiceContext.withValue(serviceContext) {
            try await next.respond(to: request)
        }
    }

    /// The rejection is an `Abort` rather than the authenticator's error, which carries no status
    /// and would be reported as a server fault: the wrong answer for the most ordinary request a
    /// client makes, one holding a token that has expired.
    private func authenticate(_ token: String) async throws -> Identity? {
        do {
            return try await authenticator.authenticate(token)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired token.")
        }
    }
}
