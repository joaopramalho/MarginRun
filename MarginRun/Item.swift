//
//  Item.swift
//  MarginRun
//
//  Created by João Pedro da Silva Ramalho on 31/08/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
