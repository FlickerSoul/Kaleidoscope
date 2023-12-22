//
//  Node+CustomStringConvertible.swift
//
//
//  Created by Larry Zeng on 12/22/23.
//

extension Node: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Leaf(let content):
            return content.description
        case .Branch(let content):
            return content.description
        case .Seq(let content):
            return content.description
        }
    }
}
