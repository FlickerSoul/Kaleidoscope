//
//  IntoSource.swift
//
//
//  Created by Larry Zeng on 12/21/23.
//

import Foundation

extension String: Into {
    public typealias IntoType = LexerProtocol.Source

    public func into() -> IntoType {
        return self.data(using: .utf32BigEndian)!.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }
}

extension [UInt32]: Into {
    public typealias IntoType = LexerProtocol.Source

    public func into() -> IntoType {
        return self
    }
}
