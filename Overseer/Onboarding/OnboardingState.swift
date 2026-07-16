import Foundation
import Observation
import SwiftUI

@Observable
final class OnboardingState {
    let steps: [OnboardingStep]
    var currentStepIndex: Int
    var isDismissed: Bool = false

    var currentStep: OnboardingStep {
        steps[currentStepIndex]
    }

    var canGoNext: Bool {
        currentStepIndex < steps.count - 1
    }

    var canGoBack: Bool {
        currentStepIndex > 0
    }

    var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    var progress: Double {
        let completed = steps.filter { $0.isCompleted || $0.isSkipped }.count
        return Double(completed) / Double(steps.count)
    }

    var allSkipped: Bool {
        steps.allSatisfy { $0.isSkipped }
    }

    var allCompleted: Bool {
        steps.allSatisfy { $0.isCompleted || $0.isSkipped }
    }

    init(steps: [OnboardingStep]) {
        self.steps = steps
        self.currentStepIndex = 0
    }

    func next() {
        guard canGoNext else { return }
        currentStepIndex += 1
    }

    func back() {
        guard canGoBack else { return }
        currentStepIndex -= 1
    }

    func skipCurrent() {
        currentStep.isSkipped = true
        currentStep.isCompleted = false
        if canGoNext {
            next()
        }
    }

    func completeCurrent() {
        currentStep.isCompleted = true
        if canGoNext {
            next()
        }
    }

    func dismiss() {
        isDismissed = true
    }
}
