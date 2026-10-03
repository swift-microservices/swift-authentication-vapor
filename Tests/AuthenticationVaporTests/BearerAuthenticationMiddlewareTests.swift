// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

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

    /// An authenticator over a table: known tokens prove their claims; unknown or
    /// refused tokens throw.
    struct TableAuthenticator: Authentication.Authenticator {
        struct Refused: Error {}

        let identities: [String: Claims]
        let refused: Set<String>

        func authenticate(_ token: String) throws -> Claims {
            if refused.contains(token) {
                throw Refused()
            }
            guard let identity = identities[token] else {
                throw Refused()
            }
            return identity
        }
    }

    let middleware = BearerAuthenticationMiddleware<Claims>(
        authenticator: TableAuthenticator(identities: ["alice-token": Claims(subject: "alice")], refused: ["expired-token"])
    )

    /// Runs one request and reports the identity and principal observed by the route.
    ///
    /// The route returns the logged-in identity and the principal in the request's
    /// `serviceContext`, or `-` for none. The task-local `ServiceContext` is not asserted: Vapor 4 bridges its responder chain
    /// through event-loop futures, so a task-local bound in middleware does not reach a route.
    func whoami(authorization: String?, handlerCalls: HandlerCalls = HandlerCalls()) async throws -> (status: HTTPStatus, body: String) {
        try await withApp { app in
            app.middleware.use(middleware)
            app.get("whoami") { request async in
                await handlerCalls.record()
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
        let calls = HandlerCalls()
        let response = try await whoami(authorization: nil, handlerCalls: calls)

        #expect(response.status == .ok)
        #expect(response.body == "- - -")
        #expect(await calls.count == 1)
    }

    @Test("A proved token logs the identity in and binds the principal")
    func provedTokenLogsInAndBindsPrincipal() async throws {
        let calls = HandlerCalls()
        let response = try await whoami(authorization: "Bearer alice-token", handlerCalls: calls)

        #expect(response.status == .ok)
        #expect(response.body == "alice alice alice-token")
        #expect(await calls.count == 1)
    }

    @Test("An unknown token is 401 Unauthorized before the route runs")
    func unknownTokenIsUnauthorized() async throws {
        let calls = HandlerCalls()
        let response = try await whoami(authorization: "Bearer unknown-token", handlerCalls: calls)

        #expect(response.status == .unauthorized)
        #expect(await calls.count == 0)
    }

    @Test("A refused token is 401 Unauthorized before the route runs")
    func refusedTokenIsUnauthorized() async throws {
        let calls = HandlerCalls()
        let response = try await whoami(authorization: "Bearer expired-token", handlerCalls: calls)

        #expect(response.status == .unauthorized)
        #expect(await calls.count == 0)
    }

    enum RequestIDKey: ServiceContextKey {
        typealias Value = String
    }

    /// Stands in for a middleware that records a value on the request's context, such as a
    /// request ID, while an unrelated task-local context is bound around the rest of the chain.
    struct RequestContextMiddleware: AsyncMiddleware {
        func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
            request.serviceContext[RequestIDKey.self] = "request-1"
            return try await ServiceContext.withValue(.topLevel) {
                try await next.respond(to: request)
            }
        }
    }

    @Test("A proved token adds the principal to the request's existing context")
    func provedTokenKeepsRequestContext() async throws {
        try await withApp { app in
            app.middleware.use(RequestContextMiddleware())
            app.middleware.use(middleware)
            app.get("context") { request in
                let requestID = request.serviceContext[RequestIDKey.self] ?? "-"
                let subject = request.serviceContext[PrincipalKey<Claims, String>.self]?.identity.subject ?? "-"
                return "\(requestID) \(subject)"
            }

            try await app.testing().test(.GET, "context", headers: ["Authorization": "Bearer alice-token"]) { response in
                #expect(response.status == .ok)
                #expect(response.body.string == "request-1 alice")
            }
        }
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

/// Counts route invocations across the framework's responder tasks.
actor HandlerCalls {
    private(set) var count = 0

    func record() {
        count += 1
    }
}
