//
//  MenuDismissEnvironment.swift
//  PiHoleControls
//
//  Created by Georg Kreimer on 11/27/25.
//

import SwiftUI

private struct DismissMenuKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var dismissMenu: (() -> Void)? {
        get { self[DismissMenuKey.self] }
        set { self[DismissMenuKey.self] = newValue }
    }
}
