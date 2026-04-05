//
//  Sequence+Extensions.swift
//  OctoCmd
//
//  Created by Khoa Le on 28/04/2023.
//

import Foundation

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}
