import Foundation
import LeafiyUICore

private let appBundle = LeafiyLocalization.moduleBundle(package: "Fifi", target: "Fifi")
func L(_ key: String) -> String { LeafiyLocalization.string(key, bundle: appBundle) }
