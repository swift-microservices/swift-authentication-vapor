//
//  BearerAuthenticationMiddlewareTests.swift
//  swift-authentication-vapor
//
//  Created by Zaid Rahhawi on 9/11/26.
//

import Authentication
import AuthenticationVapor
import ServiceContextModule
import Testing
import Vapor
import VaporTesting

@Suite
struct BearerAuthenticationMiddlewareTests {
    struct Claims: Authenticatable, Sendable, Equatable {
        let subject: String
    }

    /// An authenticator over a table: a known token proves its claims, an unknown one is
    /// declined, and a token in the refused set throws.
    struct TableAuthenticator: Authentication.Authenticator {
        struct Refused: Error {}

        let identities: [String: Claims]
        let refused: Set<String>

        func authenticate(_ token: String) throws -> Claims? {
            if refused.contains(token) {
                throw Refused()
            }
            return identities[token]
        }
    }

    let middleware = BearerAuthenticationMiddleware<Claims>(
        authenticator: TableAuthenticator(identities: ["alice-token": Claims(subject: "alice")], refused: ["expired-token"])
    )

    /// Runs one request against an app with the middleware and a route that reports what it saw:
    /// the logged-in identity and the principal in the request's `serviceContext`, or `-` for
    /// none. The task-local `ServiceContext` is not asserted: Vapor 4 bridges its responder chain
    /// through event-loop futures, so a task-local bound in middleware does not reach a route.
    func whoami(authorization: String?) async throws -> (status: HTTPStatus, body: String) {
        try await withApp { app in
            app.middleware.use(middleware)
            app.get("whoami") { request in
                let principal = request.serviceContext[PrincipalKey<Claims, String>.self]
                return "\(request.auth.get(Claims.self)?.subject ?? "-") \(principal?.identity.subject ?? "-") \(principal?.credential ?? "-")"
            }

            var headers = HTTPHeaders()
            if let authorization {
                headers.add(name: .authorization, value: authorization)
            }
            var result: (status: HTTPStatus, body: String) = (.internalServerError, "")
            try await app.testing().test(.GET, "whoami", headers: headers) { response in
                result = (response.status, response.body.string)
            }
            return result
        }
    }

    @Test("A request with no token continues anonymously")
    func noTokenContinuesAnonymously() async throws {
        let response = try await whoami(authorization: nil)

        #expect(response.status == .ok)
        #expect(response.body == "- - -")
    }

    @Test("A proved token logs the identity in and binds the principal")
    func provedTokenLogsInAndBindsPrincipal() async throws {
        let response = try await whoami(authorization: "Bearer alice-token")

        #expect(response.status == .ok)
        #expect(response.body == "alice alice alice-token")
    }

    @Test("A declined token continues unbound")
    func declinedTokenContinuesUnbound() async throws {
        let response = try await whoami(authorization: "Bearer unknown-token")

        #expect(response.status == .ok)
        #expect(response.body == "- - -")
    }

    @Test("A refused token is 401 Unauthorized before the route runs")
    func refusedTokenIsUnauthorized() async throws {
        let response = try await whoami(authorization: "Bearer expired-token")

        #expect(response.status == .unauthorized)
    }

    @Test("A proved token satisfies the guard on a protected route")
    func provedTokenPassesGuard() async throws {
        try await withApp { app in
            app.middleware.use(middleware)
            app.grouped(Claims.guardMiddleware()).get("protected") { request in
                try request.auth.require(Claims.self).subject
            }

            try await app.testing().test(.GET, "protected") { response in
                #expect(response.status == .unauthorized)
            }
            try await app.testing().test(.GET, "protected", headers: ["Authorization": "Bearer alice-token"]) { response in
                #expect(response.status == .ok)
                #expect(response.body.string == "alice")
            }
        }
    }
}
