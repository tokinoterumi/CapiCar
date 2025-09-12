//
//  Item.swift
//  CapiCar for YOS
//
//  Created by Terumi on 9/2/07.
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
