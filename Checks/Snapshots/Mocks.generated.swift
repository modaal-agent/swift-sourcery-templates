// Generated using Sourcery 2.3.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT


import Combine
import Foundation

// MARK: - AnalyticsTracking
final class AnalyticsTrackingMock: AnalyticsTracking, @unchecked Sendable {

    // MARK: - Methods
    func identify(uid: String) {
        identifyCallCount += 1
        identifyArgs.append(uid)
        if let __identifyHandler = self.identifyHandler {
            __identifyHandler(uid)
        }
    }
    var identifyCallCount: Int = 0
    var identifyArgs: [String] = []
    var identifyHandler: ((_ uid: String) -> ())? = nil
    func reset() {
        resetCallCount += 1
        if let __resetHandler = self.resetHandler {
            __resetHandler()
        }
    }
    var resetCallCount: Int = 0
    var resetHandler: (() -> ())? = nil
    func track(_ name: String) {
        trackCallCount += 1
        trackArgs.append(name)
        if let __trackHandler = self.trackHandler {
            __trackHandler(name)
        }
    }
    var trackCallCount: Int = 0
    var trackArgs: [String] = []
    var trackHandler: ((_ name: String) -> ())? = nil
}

// MARK: - AppServicesAPNSHandlerRegistering
@MainActor
final class AppServicesAPNSHandlerRegisteringMock: AppServicesAPNSHandlerRegistering {

    // MARK: - Methods
    func registerAPNSNotificationsHandler(_ tag: String, priority: Int) -> AnyCancellable {
        registerAPNSNotificationsHandlerCallCount += 1
        registerAPNSNotificationsHandlerArgs.append((tag: tag, priority: priority))
        if let __registerAPNSNotificationsHandlerHandler = self.registerAPNSNotificationsHandlerHandler {
            return __registerAPNSNotificationsHandlerHandler(tag, priority)
        }
        return AnyCancellable { [weak self] in
            self?.registerAPNSNotificationsHandlerCancelCallCount += 1
            self?.registerAPNSNotificationsHandlerCancelHandler?()
        }
    }
    var registerAPNSNotificationsHandlerCallCount: Int = 0
    var registerAPNSNotificationsHandlerArgs: [(tag: String, priority: Int)] = []
    var registerAPNSNotificationsHandlerHandler: ((_ tag: String, _ priority: Int) -> (AnyCancellable))? = nil
    var registerAPNSNotificationsHandlerCancelCallCount: Int = 0
    var registerAPNSNotificationsHandlerCancelHandler: (() -> ())? = nil
}

// MARK: - AppServicesRegistering
@MainActor
final class AppServicesRegisteringMock: AppServicesRegistering {

    // MARK: - Methods
    func handlersDidRegister() {
        handlersDidRegisterCallCount += 1
        if let __handlersDidRegisterHandler = self.handlersDidRegisterHandler {
            __handlersDidRegisterHandler()
        }
    }
    var handlersDidRegisterCallCount: Int = 0
    var handlersDidRegisterHandler: (() -> ())? = nil
    func registerAPNSNotificationsHandler(_ tag: String, priority: Int) -> AnyCancellable {
        registerAPNSNotificationsHandlerCallCount += 1
        registerAPNSNotificationsHandlerArgs.append((tag: tag, priority: priority))
        if let __registerAPNSNotificationsHandlerHandler = self.registerAPNSNotificationsHandlerHandler {
            return __registerAPNSNotificationsHandlerHandler(tag, priority)
        }
        return AnyCancellable { [weak self] in
            self?.registerAPNSNotificationsHandlerCancelCallCount += 1
            self?.registerAPNSNotificationsHandlerCancelHandler?()
        }
    }
    var registerAPNSNotificationsHandlerCallCount: Int = 0
    var registerAPNSNotificationsHandlerArgs: [(tag: String, priority: Int)] = []
    var registerAPNSNotificationsHandlerHandler: ((_ tag: String, _ priority: Int) -> (AnyCancellable))? = nil
    var registerAPNSNotificationsHandlerCancelCallCount: Int = 0
    var registerAPNSNotificationsHandlerCancelHandler: (() -> ())? = nil
    func registerURLHandler(_ tag: String, priority: Int) -> AnyCancellable {
        registerURLHandlerCallCount += 1
        registerURLHandlerArgs.append((tag: tag, priority: priority))
        if let __registerURLHandlerHandler = self.registerURLHandlerHandler {
            return __registerURLHandlerHandler(tag, priority)
        }
        return AnyCancellable { [weak self] in
            self?.registerURLHandlerCancelCallCount += 1
            self?.registerURLHandlerCancelHandler?()
        }
    }
    var registerURLHandlerCallCount: Int = 0
    var registerURLHandlerArgs: [(tag: String, priority: Int)] = []
    var registerURLHandlerHandler: ((_ tag: String, _ priority: Int) -> (AnyCancellable))? = nil
    var registerURLHandlerCancelCallCount: Int = 0
    var registerURLHandlerCancelHandler: (() -> ())? = nil
}

// MARK: - AppServicesURLHandlerRegistering
@MainActor
final class AppServicesURLHandlerRegisteringMock: AppServicesURLHandlerRegistering {

    // MARK: - Methods
    func registerURLHandler(_ tag: String, priority: Int) -> AnyCancellable {
        registerURLHandlerCallCount += 1
        registerURLHandlerArgs.append((tag: tag, priority: priority))
        if let __registerURLHandlerHandler = self.registerURLHandlerHandler {
            return __registerURLHandlerHandler(tag, priority)
        }
        return AnyCancellable { [weak self] in
            self?.registerURLHandlerCancelCallCount += 1
            self?.registerURLHandlerCancelHandler?()
        }
    }
    var registerURLHandlerCallCount: Int = 0
    var registerURLHandlerArgs: [(tag: String, priority: Int)] = []
    var registerURLHandlerHandler: ((_ tag: String, _ priority: Int) -> (AnyCancellable))? = nil
    var registerURLHandlerCancelCallCount: Int = 0
    var registerURLHandlerCancelHandler: (() -> ())? = nil
}

// MARK: - AudioSessionConfiguring
final class AudioSessionConfiguringMock: AudioSessionConfiguring {

    // MARK: - Variables
    var recordPermission: RecordPermission

    // MARK: - Initializer
    init(recordPermission: RecordPermission) {
        self.recordPermission = recordPermission
    }

    // MARK: - Methods
    func activatePlayback() {
        activatePlaybackCallCount += 1
        if let __activatePlaybackHandler = self.activatePlaybackHandler {
            __activatePlaybackHandler()
        }
    }
    var activatePlaybackCallCount: Int = 0
    var activatePlaybackHandler: (() -> ())? = nil
    func activateRecording() throws {
        activateRecordingCallCount += 1
        if let __activateRecordingHandler = self.activateRecordingHandler {
            try __activateRecordingHandler()
        }
    }
    var activateRecordingCallCount: Int = 0
    var activateRecordingHandler: (() throws -> ())? = nil
    func requestRecordPermission(_ handler: @escaping (Bool) -> Void) {
        requestRecordPermissionCallCount += 1
        if let __requestRecordPermissionHandler = self.requestRecordPermissionHandler {
            __requestRecordPermissionHandler(handler)
        }
    }
    var requestRecordPermissionCallCount: Int = 0
    var requestRecordPermissionHandler: ((_ handler: @escaping (Bool) -> Void) -> ())? = nil
}

// MARK: - CaptureDependency
@MainActor
final class CaptureDependencyMock: CaptureDependency {

    // MARK: - Variables
    var analytics: AnalyticsTracking
    var draft: String = "" {
        didSet {
            draftSetCount += 1
        }
    }
    var draftSetCount: Int = 0
    nonisolated(unsafe) var installationId: String = ""
    var memoryRepository: MemoryRepositoryProtocol

    // MARK: - Initializer
    init(analytics: AnalyticsTracking, memoryRepository: MemoryRepositoryProtocol) {
        self.analytics = analytics
        self.memoryRepository = memoryRepository
    }

    // MARK: - Methods
    func discard(reason: String) {
        discardCallCount += 1
        discardArgs.append(reason)
        if let __discardHandler = self.discardHandler {
            __discardHandler(reason)
        }
    }
    var discardCallCount: Int = 0
    var discardArgs: [String] = []
    var discardHandler: ((_ reason: String) -> ())? = nil
    nonisolated func ping() {
        pingCallCount += 1
        if let __pingHandler = self.pingHandler {
            __pingHandler()
        }
    }
    nonisolated(unsafe) var pingCallCount: Int = 0
    nonisolated(unsafe) var pingHandler: (() -> ())? = nil
    func stage(_ fileName: String, retries: Int) async throws -> URL {
        stageCallCount += 1
        stageArgs.append((fileName: fileName, retries: retries))
        if let __stageHandler = self.stageHandler {
            return try await __stageHandler(fileName, retries)
        }
        fatalError("stageHandler expected to be set.")
    }
    var stageCallCount: Int = 0
    var stageArgs: [(fileName: String, retries: Int)] = []
    var stageHandler: ((_ fileName: String, _ retries: Int) async throws -> (URL))? = nil
}

// MARK: - DetailPresenting
final class DetailPresentingMock: DetailPresenting {

    // MARK: - Variables
    var policy: (any DetailSheet & DetailPolicy)? = nil
    var restoredSheet: (any DetailSheet)? = nil

    // MARK: - Methods
    func present(sheet: (any DetailSheet)?, onDismiss: @escaping ((any DetailSheet)?) -> Void) -> (any DetailSheet)? {
        presentCallCount += 1
        presentArgs.append(sheet)
        if let __presentHandler = self.presentHandler {
            return __presentHandler(sheet, onDismiss)
        }
        return nil
    }
    var presentCallCount: Int = 0
    var presentArgs: [(any DetailSheet)?] = []
    var presentHandler: ((_ sheet: (any DetailSheet)?, _ onDismiss: @escaping ((any DetailSheet)?) -> Void) -> ((any DetailSheet)?))? = nil
    func presentAll(_ sheets: [any DetailSheet]) -> [any DetailSheet] {
        presentAllCallCount += 1
        presentAllArgs.append(sheets)
        if let __presentAllHandler = self.presentAllHandler {
            return __presentAllHandler(sheets)
        }
        return []
    }
    var presentAllCallCount: Int = 0
    var presentAllArgs: [[any DetailSheet]] = []
    var presentAllHandler: ((_ sheets: [any DetailSheet]) -> ([any DetailSheet]))? = nil
}

// MARK: - DiagnosticsReporting
@MainActor
final class DiagnosticsReportingMock: DiagnosticsReporting {

    // MARK: - Methods
    nonisolated func accumulate(into total: inout Int) {
        accumulateCallCount += 1
        accumulateArgs.append(total)
        if let __accumulateHandler = self.accumulateHandler {
            __accumulateHandler(&total)
        }
    }
    nonisolated(unsafe) var accumulateCallCount: Int = 0
    nonisolated(unsafe) var accumulateArgs: [Int] = []
    nonisolated(unsafe) var accumulateHandler: ((_ total: inout Int) -> ())? = nil
    func flush() {
        flushCallCount += 1
        if let __flushHandler = self.flushHandler {
            __flushHandler()
        }
    }
    var flushCallCount: Int = 0
    var flushHandler: (() -> ())? = nil
    nonisolated func report(_ code: String, detail: String?) {
        reportCallCount += 1
        reportArgs.append((code: code, detail: detail))
        if let __reportHandler = self.reportHandler {
            __reportHandler(code, detail)
        }
    }
    nonisolated(unsafe) var reportCallCount: Int = 0
    nonisolated(unsafe) var reportArgs: [(code: String, detail: String?)] = []
    nonisolated(unsafe) var reportHandler: ((_ code: String, _ detail: String?) -> ())? = nil
}

// MARK: - MainDependency
final class MainDependencyMock: MainDependency {

    // MARK: - Variables
    var analytics: AnalyticsTracking
    var memoryRepository: MemoryRepositoryProtocol
    var pushNotificationRepository: PushNotificationRepositoryProtocol
    var themeProvider: ThemeProviding
    var userRepository: UserRepositoryProtocol

    // MARK: - Initializer
    init(analytics: AnalyticsTracking, memoryRepository: MemoryRepositoryProtocol, pushNotificationRepository: PushNotificationRepositoryProtocol, themeProvider: ThemeProviding, userRepository: UserRepositoryProtocol) {
        self.analytics = analytics
        self.memoryRepository = memoryRepository
        self.pushNotificationRepository = pushNotificationRepository
        self.themeProvider = themeProvider
        self.userRepository = userRepository
    }
}

// MARK: - MediaStaging
final class MediaStagingMock: MediaStaging {

    // MARK: - Methods
    func discardAll() async {
        discardAllCallCount += 1
        if let __discardAllHandler = self.discardAllHandler {
            await __discardAllHandler()
        }
    }
    var discardAllCallCount: Int = 0
    var discardAllHandler: (() async -> ())? = nil
    func stage(fileName: String) async -> String {
        stageCallCount += 1
        stageArgs.append(fileName)
        if let __stageHandler = self.stageHandler {
            return await __stageHandler(fileName)
        }
        return ""
    }
    var stageCallCount: Int = 0
    var stageArgs: [String] = []
    var stageHandler: ((_ fileName: String) async -> (String))? = nil
    func upload(fileName: String) async throws -> URL {
        uploadCallCount += 1
        uploadArgs.append(fileName)
        if let __uploadHandler = self.uploadHandler {
            return try await __uploadHandler(fileName)
        }
        fatalError("uploadHandler expected to be set.")
    }
    var uploadCallCount: Int = 0
    var uploadArgs: [String] = []
    var uploadHandler: ((_ fileName: String) async throws -> (URL))? = nil
    func validate(fileName: String) throws {
        validateCallCount += 1
        validateArgs.append(fileName)
        if let __validateHandler = self.validateHandler {
            try __validateHandler(fileName)
        }
    }
    var validateCallCount: Int = 0
    var validateArgs: [String] = []
    var validateHandler: ((_ fileName: String) throws -> ())? = nil
}

// MARK: - MemoryEventStreaming
final class MemoryEventStreamingMock: MemoryEventStreaming {

    // MARK: - Variables
    var latestDrop: AnyPublisher<MemoryDrop, Never> {
        latestDropGetCount += 1
        if let handler = latestDropGetHandler {
            return handler()
        }
        return latestDropSubject.eraseToAnyPublisher()
    }
    var latestDropGetCount: Int = 0
    var latestDropGetHandler: (() -> AnyPublisher<MemoryDrop, Never>)? = nil
    lazy var latestDropSubject = PassthroughSubject<MemoryDrop, Never>()
}

// MARK: - MemoryRepositoryProtocol
final class MemoryRepositoryProtocolMock: MemoryRepositoryProtocol {

    // MARK: - Variables
    var isRefreshing: AnyPublisher<Bool, Never> {
        isRefreshingGetCount += 1
        if let handler = isRefreshingGetHandler {
            return handler()
        }
        return isRefreshingSubject.eraseToAnyPublisher()
    }
    var isRefreshingGetCount: Int = 0
    var isRefreshingGetHandler: (() -> AnyPublisher<Bool, Never>)? = nil
    lazy var isRefreshingSubject = CurrentValueSubject<Bool, Never>(false)
    var ownMemories: AnyPublisher<[MemoryDrop], Never> {
        ownMemoriesGetCount += 1
        if let handler = ownMemoriesGetHandler {
            return handler()
        }
        return ownMemoriesSubject.eraseToAnyPublisher()
    }
    var ownMemoriesGetCount: Int = 0
    var ownMemoriesGetHandler: (() -> AnyPublisher<[MemoryDrop], Never>)? = nil
    lazy var ownMemoriesSubject = CurrentValueSubject<[MemoryDrop], Never>([])

    // MARK: - Methods
    func delete(id: String) -> AnyPublisher<Void, Error> {
        deleteCallCount += 1
        deleteArgs.append(id)
        if let __deleteHandler = self.deleteHandler {
            return __deleteHandler(id)
        }
        return deleteSubject.eraseToAnyPublisher()
    }
    var deleteCallCount: Int = 0
    var deleteArgs: [String] = []
    var deleteHandler: ((_ id: String) -> (AnyPublisher<Void, Error>))? = nil
    lazy var deleteSubject = PassthroughSubject<(), Error>()
    func fetch(id: String) -> AnyPublisher<MemoryDrop?, Error> {
        fetchCallCount += 1
        fetchArgs.append(id)
        if let __fetchHandler = self.fetchHandler {
            return __fetchHandler(id)
        }
        return fetchSubject.eraseToAnyPublisher()
    }
    var fetchCallCount: Int = 0
    var fetchArgs: [String] = []
    var fetchHandler: ((_ id: String) -> (AnyPublisher<MemoryDrop?, Error>))? = nil
    lazy var fetchSubject = CurrentValueSubject<MemoryDrop?, Error>(nil)
}

// MARK: - NotificationSignalling
final class NotificationSignallingMock: NotificationSignalling {

    // MARK: - Variables
    var badgeCount: AnyPublisher<Int, Never> {
        badgeCountGetCount += 1
        if let handler = badgeCountGetHandler {
            return handler()
        }
        return badgeCountSubject.eraseToAnyPublisher()
    }
    var badgeCountGetCount: Int = 0
    var badgeCountGetHandler: (() -> AnyPublisher<Int, Never>)? = nil
    lazy var badgeCountSubject = CurrentValueSubject<Int, Never>(0)
    var friendGraphChanged: AnyPublisher<Void, Never> {
        friendGraphChangedGetCount += 1
        if let handler = friendGraphChangedGetHandler {
            return handler()
        }
        return friendGraphChangedSubject.eraseToAnyPublisher()
    }
    var friendGraphChangedGetCount: Int = 0
    var friendGraphChangedGetHandler: (() -> AnyPublisher<Void, Never>)? = nil
    lazy var friendGraphChangedSubject = PassthroughSubject<(), Never>()
}

// MARK: - PlaybackObserving
final class PlaybackObservingMock: PlaybackObserving {

    // MARK: - Methods
    func adopt(_ player: FeedAudioPlayer) {
        adoptCallCount += 1
        if let __adoptHandler = self.adoptHandler {
            __adoptHandler(player)
        }
    }
    var adoptCallCount: Int = 0
    var adoptHandler: ((_ player: FeedAudioPlayer) -> ())? = nil
    func attach(_ player: FeedAudioPlayer) {
        attachCallCount += 1
        attachArgs.append(player)
        if let __attachHandler = self.attachHandler {
            __attachHandler(player)
        }
    }
    var attachCallCount: Int = 0
    var attachArgs: [FeedAudioPlayer] = []
    var attachHandler: ((_ player: FeedAudioPlayer) -> ())? = nil
}

// MARK: - PlaybackRetaining
final class PlaybackRetainingMock: PlaybackRetaining {

    // MARK: - Methods
    func release(tag: String) {
        releaseCallCount += 1
        if let __releaseHandler = self.releaseHandler {
            __releaseHandler(tag)
        }
    }
    var releaseCallCount: Int = 0
    var releaseHandler: ((_ tag: String) -> ())? = nil
    func retain(_ player: FeedAudioPlayer) {
        retainCallCount += 1
        if let __retainHandler = self.retainHandler {
            __retainHandler(player)
        }
    }
    var retainCallCount: Int = 0
    var retainHandler: ((_ player: FeedAudioPlayer) -> ())? = nil
}

// MARK: - PushNotificationRepositoryProtocol
@MainActor
final class PushNotificationRepositoryProtocolMock: PushNotificationRepositoryProtocol {

    // MARK: - Variables
    var authorizationStatus: RecordPermission
    nonisolated(unsafe) var installationId: String = ""
    var isNotificationsEnabled: Bool = false

    // MARK: - Initializer
    init(authorizationStatus: RecordPermission) {
        self.authorizationStatus = authorizationStatus
    }

    // MARK: - Methods
    func deregisterCurrentDevice() -> AnyPublisher<Void, Error> {
        deregisterCurrentDeviceCallCount += 1
        if let __deregisterCurrentDeviceHandler = self.deregisterCurrentDeviceHandler {
            return __deregisterCurrentDeviceHandler()
        }
        return deregisterCurrentDeviceSubject.eraseToAnyPublisher()
    }
    var deregisterCurrentDeviceCallCount: Int = 0
    var deregisterCurrentDeviceHandler: (() -> (AnyPublisher<Void, Error>))? = nil
    lazy var deregisterCurrentDeviceSubject = PassthroughSubject<(), Error>()
    nonisolated func requestPermission() {
        requestPermissionCallCount += 1
        if let __requestPermissionHandler = self.requestPermissionHandler {
            __requestPermissionHandler()
        }
    }
    nonisolated(unsafe) var requestPermissionCallCount: Int = 0
    nonisolated(unsafe) var requestPermissionHandler: (() -> ())? = nil
    func setNotificationsEnabled(_ enabled: Bool) {
        setNotificationsEnabledCallCount += 1
        setNotificationsEnabledArgs.append(enabled)
        if let __setNotificationsEnabledHandler = self.setNotificationsEnabledHandler {
            __setNotificationsEnabledHandler(enabled)
        }
    }
    var setNotificationsEnabledCallCount: Int = 0
    var setNotificationsEnabledArgs: [Bool] = []
    var setNotificationsEnabledHandler: ((_ enabled: Bool) -> ())? = nil
}

// MARK: - RootDependency
final class RootDependencyMock: RootDependency {
}

// MARK: - TimelineBuildable
final class TimelineBuildableMock: TimelineBuildable {

    // MARK: - Methods
    func build(withTag tag: String) -> ViewShellChild {
        buildCallCount += 1
        buildArgs.append(tag)
        if let __buildHandler = self.buildHandler {
            return __buildHandler(tag)
        }
        fatalError("buildHandler expected to be set.")
    }
    var buildCallCount: Int = 0
    var buildArgs: [String] = []
    var buildHandler: ((_ tag: String) -> (ViewShellChild))? = nil
}

// MARK: - TimelineDependency
final class TimelineDependencyMock: TimelineDependency {

    // MARK: - Variables
    var analytics: AnalyticsTracking
    var audioSessionConfigurer: AudioSessionConfiguring
    var memoryRepository: MemoryRepositoryProtocol
    var themeProvider: ThemeProviding
    var userRepository: UserRepositoryProtocol

    // MARK: - Initializer
    init(analytics: AnalyticsTracking, audioSessionConfigurer: AudioSessionConfiguring, memoryRepository: MemoryRepositoryProtocol, themeProvider: ThemeProviding, userRepository: UserRepositoryProtocol) {
        self.analytics = analytics
        self.audioSessionConfigurer = audioSessionConfigurer
        self.memoryRepository = memoryRepository
        self.themeProvider = themeProvider
        self.userRepository = userRepository
    }
}

// MARK: - UploadScheduling
final class UploadSchedulingMock: UploadScheduling {

    // MARK: - Methods
    func schedule(fileName: String, completion: @escaping @Sendable (Bool) -> Void) {
        scheduleCallCount += 1
        scheduleArgs.append(fileName)
        if let __scheduleHandler = self.scheduleHandler {
            __scheduleHandler(fileName, completion)
        }
    }
    var scheduleCallCount: Int = 0
    var scheduleArgs: [String] = []
    var scheduleHandler: ((_ fileName: String, _ completion: @escaping @Sendable (Bool) -> Void) -> ())? = nil
}

// MARK: - UserRepositoryProtocol
@MainActor
final class UserRepositoryProtocolMock: UserRepositoryProtocol {

    // MARK: - Variables
    var meStream: AnyPublisher<UserSummary?, Never> {
        meStreamGetCount += 1
        if let handler = meStreamGetHandler {
            return handler()
        }
        return meStreamSubject.eraseToAnyPublisher()
    }
    var meStreamGetCount: Int = 0
    var meStreamGetHandler: (() -> AnyPublisher<UserSummary?, Never>)? = nil
    lazy var meStreamSubject = CurrentValueSubject<UserSummary?, Never>(nil)

    // MARK: - Methods
    func bootstrap(displayName: String?) -> AnyPublisher<Void, Error> {
        bootstrapCallCount += 1
        bootstrapArgs.append(displayName)
        if let __bootstrapHandler = self.bootstrapHandler {
            return __bootstrapHandler(displayName)
        }
        return bootstrapSubject.eraseToAnyPublisher()
    }
    var bootstrapCallCount: Int = 0
    var bootstrapArgs: [String?] = []
    var bootstrapHandler: ((_ displayName: String?) -> (AnyPublisher<Void, Error>))? = nil
    lazy var bootstrapSubject = PassthroughSubject<(), Error>()
    func registerDevice(token: String, platform: String) -> AnyPublisher<Void, Error> {
        registerDeviceCallCount += 1
        registerDeviceArgs.append((token: token, platform: platform))
        if let __registerDeviceHandler = self.registerDeviceHandler {
            return __registerDeviceHandler(token, platform)
        }
        return registerDeviceSubject.eraseToAnyPublisher()
    }
    var registerDeviceCallCount: Int = 0
    var registerDeviceArgs: [(token: String, platform: String)] = []
    var registerDeviceHandler: ((_ token: String, _ platform: String) -> (AnyPublisher<Void, Error>))? = nil
    lazy var registerDeviceSubject = PassthroughSubject<(), Error>()
}
