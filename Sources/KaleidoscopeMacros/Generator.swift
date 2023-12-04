//
//  Generator.swift
//
//
//  Created by Larry Zeng on 12/4/23.
//

import SwiftSyntax

// MARK: - Callback Result Types

public protocol GetResult {
    func get<R>() throws -> R?
}

public enum CallbackResult<T> {
    case skip
    case match(T)
}

extension CallbackResult: GetResult {
    public func get<R>() throws -> R? {
        switch self {
        case .skip: return nil
        case .match(let res): return (res as! R)
        }
    }
}

public typealias MatchCallbackType = () -> GetResult
public typealias ExactMatchCallbackType<T> = () -> CallbackResult<T>

// MARK: - Callback Type

public enum CallbackType {
    case Named(indet: String)
    case Lambda(ClosureExprSyntax)
    case Skip
}

