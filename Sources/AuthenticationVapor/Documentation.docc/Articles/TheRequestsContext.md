# The request's context

Where the proven identity goes on Vapor, and why it is the request that carries it.

## Two readers, two places

Vapor code reads an identity through `req.auth`: `req.auth.require`, `req.auth.get`, and
`GuardMiddleware` all look there, which is why the middleware's identity is any
`Authenticatable`. Transport-independent adapters, such as outgoing gRPC propagation, read a
`ServiceContext`. User use cases receive the verified identity explicitly from their handler.
``BearerAuthenticationMiddleware`` sets both.

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
        try await orders.list()
    }
}
```

Inside that closure, swift-authentication-grpc's propagation interceptor finds the principal and
presents the original token on upstream user RPC descriptors.

## User routes

Apply bearer authentication and `guardMiddleware()` to user routes. Missing credentials continue
unbound; failed verification returns `401 Unauthorized`. The guard requires an identity before
the handler runs, and the owning use case checks user permissions and resource access. Keep
sign-in and refresh routes outside this group, so an expired token a client still attaches
cannot block recovery.
