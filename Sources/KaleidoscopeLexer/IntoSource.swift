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
        return self.map { $0.unicodeScalars.first!.value }
    }
}

extension [UInt32]: Into {
    public typealias IntoType = LexerProtocol.Source

    public func into() -> IntoType {
        return self
    }
}
