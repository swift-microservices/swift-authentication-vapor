# The request's context

Where the proven identity goes on Vapor, and why it is the request that carries it.

## Two readers, two places

Vapor code reads an identity through `req.auth`: `req.auth.require`, `req.auth.get`, and
`GuardMiddleware` all look there, which is why the middleware's identity is any
`Authenticatable`. Everything that is not Vapor, a use case, a repository, an outgoing gRPC
call, reads a `ServiceContext`. ``BearerAuthenticationMiddleware`` sets both.

## The request, not the task

Vapor 4 bridges its responder chain through event-loop futures. A middleware that binds a
task-local and calls the next responder does not hand that task-local to the route, because the
route runs in a task the framework starts from a future callback. The middleware binds the
task-local anyway, for the parts of the chain that are async end to end, but what reliably
reaches a route is `request.serviceContext`. That is the same field Vapor's own tracing
middleware uses to carry its span, for the same reason. The principal is added to the
request's existing context, so a span or other value an earlier middleware recorded there is
kept.

So a route that needs the principal for something outside Vapor runs that work under the
request's context:

```swift
app.get("orders") { req in
    try await ServiceContext.withValue(req.serviceContext) {
        try await orders.list(request)
    }
}
```

Inside that closure, swift-authentication-grpc's propagation interceptor finds the principal and
presents the token onward, exactly as it would in a gRPC service.

## Open routes and protected routes

A request with no token continues anonymously. `Authenticator.authenticate(_:)` returns an
identity or throws; a failed authentication ends the request with `401 Unauthorized` before the
route runs. Requiring a caller is a route's decision, made with `guardMiddleware()` on the
routes that need one.
