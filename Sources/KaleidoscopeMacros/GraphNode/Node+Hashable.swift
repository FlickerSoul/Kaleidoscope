//
//  Node+Hashable.swift
//
//
//  Created by Larry Zeng on 12/22/23.
//

extension Node: Hashable {
    public static func == (lhs: Node, rhs: Node) -> Bool {
        switch (lhs, rhs) {
        case (.Leaf(let lhsLeaf), .Leaf(let rhsLeaf)):
            return lhsLeaf == rhsLeaf
        case (.Branch(let lhsBranch), .Branch(let rhsBranch)):
            return lhsBranch == rhsBranch
        case (.Seq(let lhsSeq), .Seq(let rhsSeq)):
            return lhsSeq == rhsSeq
        case _:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .Leaf(let leaf):
            leaf.hash(into: &hasher)
        case .Branch(let branch):
            branch.hash(into: &hasher)
        case .Seq(let seq):
            seq.hash(into: &hasher)
        }
    }
}
