// Generated using Sourcery 2.3.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT


import Combine
import Foundation

// MARK: - AppServicesRegisteringComponent
@MainActor
final class AppServicesRegisteringComponent: AppServicesRegistering {
    private let dependency: AppServicesRegistering

    init(dependency: AppServicesRegistering) {
        self.dependency = dependency
    }
    func handlersDidRegister() {
        dependency.handlersDidRegister()
    }
    func registerAPNSNotificationsHandler(_ tag: String, priority: Int) -> AnyCancellable {
        dependency.registerAPNSNotificationsHandler(tag, priority: priority)
    }
    func registerURLHandler(_ tag: String, priority: Int) -> AnyCancellable {
        dependency.registerURLHandler(tag, priority: priority)
    }
}

// MARK: - CaptureComponent
@MainActor
final class CaptureComponent: CaptureDependency {
    nonisolated(unsafe) private let dependency: CaptureDependency

    init(dependency: CaptureDependency) {
        self.dependency = dependency
    }
    var analytics: AnalyticsTracking { dependency.analytics }
    var draft: String {
        get { dependency.draft }
        set { dependency.draft = newValue }
    }
    nonisolated var installationId: String { dependency.installationId }
    var memoryRepository: MemoryRepositoryProtocol { dependency.memoryRepository }
    func discard(reason: String) {
        dependency.discard(reason: reason)
    }
    nonisolated func ping() {
        dependency.ping()
    }
    func stage(_ fileName: String, retries: Int) async throws -> URL {
        try await dependency.stage(fileName, retries: retries)
    }
}

// MARK: - DetailPresentingComponent
final class DetailPresentingComponent: DetailPresenting {
    private let dependency: DetailPresenting

    init(dependency: DetailPresenting) {
        self.dependency = dependency
    }
    var policy: (any DetailSheet & DetailPolicy)? { dependency.policy }
    var restoredSheet: (any DetailSheet)? { dependency.restoredSheet }
    func present(sheet: (any DetailSheet)?, onDismiss: @escaping ((any DetailSheet)?) -> Void) -> (any DetailSheet)? {
        dependency.present(sheet: sheet, onDismiss: onDismiss)
    }
    func presentAll(_ sheets: [any DetailSheet]) -> [any DetailSheet] {
        dependency.presentAll(sheets)
    }
}

// MARK: - MainComponentBase
class MainComponentBase: MainDependency {
    let dependency: MainDependency

    init(dependency: MainDependency) {
        self.dependency = dependency
    }
    var analytics: AnalyticsTracking { dependency.analytics }
    var memoryRepository: MemoryRepositoryProtocol { dependency.memoryRepository }
    var pushNotificationRepository: PushNotificationRepositoryProtocol { dependency.pushNotificationRepository }
    var themeProvider: ThemeProviding { dependency.themeProvider }
    var userRepository: UserRepositoryProtocol { dependency.userRepository }
}

// MARK: - OnboardingComponent
public final class OnboardingComponent: OnboardingFlowDependency {
    private let dependency: OnboardingFlowDependency

    public init(dependency: OnboardingFlowDependency) {
        self.dependency = dependency
    }
    public var themeProvider: ThemeProviding { dependency.themeProvider }
}

// MARK: - ProfileComponent
final class ProfileComponent: ProfileDependency {
    private let dependency: ProfileDependency

    init(dependency: ProfileDependency) {
        self.dependency = dependency
    }
    var cachedUser: UserSummary? { dependency.cachedUser }
    var currentUser: UserSummary {
        get async throws { try await dependency.currentUser }
    }
}

// MARK: - RegistrationComponent
final class RegistrationComponent: RegistrationDependency {
    private let dependency: RegistrationDependency

    init(dependency: RegistrationDependency) {
        self.dependency = dependency
    }
    var themeProvider: ThemeProviding { dependency.themeProvider }
    func accumulate(into total: inout Int) {
        dependency.accumulate(into: &total)
    }
    func encode<T: Encodable>(_ value: T) throws -> Data {
        try dependency.encode(value)
    }
    func retry(after delay: TimeInterval, attempts: Int) {
        dependency.retry(after: delay, attempts: attempts)
    }
    func schedule(fileName: String, completion: @escaping @Sendable (Bool) -> Void) {
        dependency.schedule(fileName: fileName, completion: completion)
    }
    func submit(_ code: String) {
        dependency.submit(code)
    }
    func withRetries(_ body: () throws -> Void) rethrows {
        try dependency.withRetries(body)
    }
}

// MARK: - TimelineComponent
final class TimelineComponent: TimelineDependency {
    private let dependency: TimelineDependency

    init(dependency: TimelineDependency) {
        self.dependency = dependency
    }
    var analytics: AnalyticsTracking { dependency.analytics }
    var audioSessionConfigurer: AudioSessionConfiguring { dependency.audioSessionConfigurer }
    var memoryRepository: MemoryRepositoryProtocol { dependency.memoryRepository }
    var themeProvider: ThemeProviding { dependency.themeProvider }
    var userRepository: UserRepositoryProtocol { dependency.userRepository }
}
