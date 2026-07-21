import Foundation
import Observation

@Observable
final class OnboardingStep {
    let id: String
    let title: String
    var isCompleted: Bool
    var isSkipped: Bool
    var isValid: Bool

    init(id: String, title: String, isCompleted: Bool = false, isSkipped: Bool = false, isValid: Bool = true) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isSkipped = isSkipped
        self.isValid = isValid
    }
}
