// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

public import OperationContext
public import Vapor

extension Request {
    /// Typed values carried with this request across Vapor's responder tasks.
    ///
    /// Defaults to an empty context. Middleware can add values before calling the next
    /// responder. Bind this context with `OperationContext.withContext` around route work
    /// that reads task-local values, such as token propagation or database settings.
    public var operationContext: OperationContext {
        get { storage[OperationContextStorageKey.self] ?? OperationContext() }
        set { storage[OperationContextStorageKey.self] = newValue }
    }
}

private enum OperationContextStorageKey: StorageKey {
    typealias Value = OperationContext
}
