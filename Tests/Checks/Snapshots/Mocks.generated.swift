// Generated using Sourcery 2.3.0 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT


import Combine
import Foundation

// Mock member names are the requirement's declared name plus a suffix: `func load()` gives
// `loadCallCount`, `loadArgs` and `loadHandler`; `var name` gives `nameGetCount`, `nameSetCount`,
// `nameGetHandler` and the store `_name`. Where a prefix is not the declared name — an overload,
// a return-type discriminator, `sourcery: methodName` — a comment carrying both spellings
// sits above the witness and in the index under that class's `// MARK:` line.

// MARK: - AnalyticsTracking
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class AudioSessionConfiguringMock: AudioSessionConfiguring {

    // MARK: - Variables
    var recordPermission: RecordPermission {
        recordPermissionGetCount += 1
        if let handler = recordPermissionGetHandler {
            return handler()
        }
        return _recordPermission
    }
    var recordPermissionGetCount: Int = 0
    var recordPermissionGetHandler: (() -> RecordPermission)? = nil
    var _recordPermission: RecordPermission

    // MARK: - Initializer
    init(recordPermission: RecordPermission) {
        self._recordPermission = recordPermission
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
@MainActor
final class CaptureDependencyMock: CaptureDependency {

    // MARK: - Variables
    var analytics: AnalyticsTracking {
        analyticsGetCount += 1
        if let handler = analyticsGetHandler {
            return handler()
        }
        return _analytics
    }
    var analyticsGetCount: Int = 0
    var analyticsGetHandler: (() -> AnalyticsTracking)? = nil
    var _analytics: AnalyticsTracking
    var draft: String {
        get {
            draftGetCount += 1
            if let handler = draftGetHandler {
                return handler()
            }
            return _draft
        }
        set {
            draftSetCount += 1
            _draft = newValue
        }
    }
    var draftGetCount: Int = 0
    var draftGetHandler: (() -> String)? = nil
    var draftSetCount: Int = 0
    var _draft: String = ""
    nonisolated var installationId: String {
        installationIdGetCount += 1
        if let handler = installationIdGetHandler {
            return handler()
        }
        return _installationId
    }
    nonisolated(unsafe) var installationIdGetCount: Int = 0
    nonisolated(unsafe) var installationIdGetHandler: (() -> String)? = nil
    nonisolated(unsafe) var _installationId: String = ""
    var memoryRepository: MemoryRepositoryProtocol {
        memoryRepositoryGetCount += 1
        if let handler = memoryRepositoryGetHandler {
            return handler()
        }
        return _memoryRepository
    }
    var memoryRepositoryGetCount: Int = 0
    var memoryRepositoryGetHandler: (() -> MemoryRepositoryProtocol)? = nil
    var _memoryRepository: MemoryRepositoryProtocol

    // MARK: - Initializer
    init(analytics: AnalyticsTracking, memoryRepository: MemoryRepositoryProtocol) {
        self._analytics = analytics
        self._memoryRepository = memoryRepository
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class DetailPresentingMock: DetailPresenting {

    // MARK: - Variables
    var policy: (any DetailSheet & DetailPolicy)? {
        policyGetCount += 1
        if let handler = policyGetHandler {
            return handler()
        }
        return _policy
    }
    var policyGetCount: Int = 0
    var policyGetHandler: (() -> (any DetailSheet & DetailPolicy)?)? = nil
    var _policy: (any DetailSheet & DetailPolicy)? = nil
    var restoredSheet: (any DetailSheet)? {
        restoredSheetGetCount += 1
        if let handler = restoredSheetGetHandler {
            return handler()
        }
        return _restoredSheet
    }
    var restoredSheetGetCount: Int = 0
    var restoredSheetGetHandler: (() -> (any DetailSheet)?)? = nil
    var _restoredSheet: (any DetailSheet)? = nil

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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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

// MARK: - FrameRetaining
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class FrameRetainingMock: FrameRetaining {

    // MARK: - Variables
    var frames: AnyPublisher<FeedAudioPlayer, Never> {
        framesGetCount += 1
        return Deferred { [weak self, subject = framesSubject] () -> AnyPublisher<FeedAudioPlayer, Never> in
            self?.framesSubscribeCount += 1
            if let handler = self?.framesGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.framesOutputCount += 1
            self?.framesOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.framesCompletionCount += 1 }, receiveCancel: { [weak self] in self?.framesSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var framesGetCount: Int = 0
    var framesGetHandler: (() -> AnyPublisher<FeedAudioPlayer, Never>)? = nil
    var framesSubscribeCount: Int = 0
    var framesSubscribeCancelCount: Int = 0
    var framesOutputCount: Int = 0
    var framesOutputHandler: ((FeedAudioPlayer) -> Void)? = nil
    var framesCompletionCount: Int = 0
    lazy var framesSubject = PassthroughSubject<FeedAudioPlayer, Never>()

    // MARK: - Methods
    func replay(tag: String) -> AnyPublisher<FeedAudioPlayer, Never> {
        replayCallCount += 1
        if let __replayHandler = self.replayHandler {
            return __replayHandler(tag)
        }
        return Deferred { [weak self, subject = replaySubject] () -> AnyPublisher<FeedAudioPlayer, Never> in
            self?.replaySubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.replayOutputCount += 1
            self?.replayOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.replayCompletionCount += 1 }, receiveCancel: { [weak self] in self?.replaySubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var replayCallCount: Int = 0
    var replayHandler: ((_ tag: String) -> (AnyPublisher<FeedAudioPlayer, Never>))? = nil
    var replaySubscribeCount: Int = 0
    var replaySubscribeCancelCount: Int = 0
    var replayOutputCount: Int = 0
    var replayOutputHandler: ((FeedAudioPlayer) -> Void)? = nil
    var replayCompletionCount: Int = 0
    lazy var replaySubject = PassthroughSubject<FeedAudioPlayer, Never>()
}

// MARK: - FrameStreaming
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class FrameStreamingMock: FrameStreaming {

    // MARK: - Variables
    var frames: AnyPublisher<FeedAudioPlayer, Never> {
        framesGetCount += 1
        return Deferred { [weak self, subject = framesSubject] () -> AnyPublisher<FeedAudioPlayer, Never> in
            self?.framesSubscribeCount += 1
            if let handler = self?.framesGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.framesOutputCount += 1
            self?.framesOutputs.append(value)
            self?.framesOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.framesCompletionCount += 1 }, receiveCancel: { [weak self] in self?.framesSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var framesGetCount: Int = 0
    var framesGetHandler: (() -> AnyPublisher<FeedAudioPlayer, Never>)? = nil
    var framesSubscribeCount: Int = 0
    var framesSubscribeCancelCount: Int = 0
    var framesOutputCount: Int = 0
    var framesOutputs: [FeedAudioPlayer] = []
    var framesOutputHandler: ((FeedAudioPlayer) -> Void)? = nil
    var framesCompletionCount: Int = 0
    lazy var framesSubject = PassthroughSubject<FeedAudioPlayer, Never>()
    var rawFrames: AnyPublisher<FeedAudioPlayer, Never> {
        rawFramesGetCount += 1
        return Deferred { [weak self, subject = rawFramesSubject] () -> AnyPublisher<FeedAudioPlayer, Never> in
            self?.rawFramesSubscribeCount += 1
            if let handler = self?.rawFramesGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.rawFramesOutputCount += 1
            self?.rawFramesOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.rawFramesCompletionCount += 1 }, receiveCancel: { [weak self] in self?.rawFramesSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var rawFramesGetCount: Int = 0
    var rawFramesGetHandler: (() -> AnyPublisher<FeedAudioPlayer, Never>)? = nil
    var rawFramesSubscribeCount: Int = 0
    var rawFramesSubscribeCancelCount: Int = 0
    var rawFramesOutputCount: Int = 0
    var rawFramesOutputHandler: ((FeedAudioPlayer) -> Void)? = nil
    var rawFramesCompletionCount: Int = 0
    lazy var rawFramesSubject = PassthroughSubject<FeedAudioPlayer, Never>()

    // MARK: - Methods
    func replay(tag: String) -> AnyPublisher<FeedAudioPlayer, Never> {
        replayCallCount += 1
        if let __replayHandler = self.replayHandler {
            return __replayHandler(tag)
        }
        return Deferred { [weak self, subject = replaySubject] () -> AnyPublisher<FeedAudioPlayer, Never> in
            self?.replaySubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.replayOutputCount += 1
            self?.replayOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.replayCompletionCount += 1 }, receiveCancel: { [weak self] in self?.replaySubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var replayCallCount: Int = 0
    var replayHandler: ((_ tag: String) -> (AnyPublisher<FeedAudioPlayer, Never>))? = nil
    var replaySubscribeCount: Int = 0
    var replaySubscribeCancelCount: Int = 0
    var replayOutputCount: Int = 0
    var replayOutputHandler: ((FeedAudioPlayer) -> Void)? = nil
    var replayCompletionCount: Int = 0
    lazy var replaySubject = PassthroughSubject<FeedAudioPlayer, Never>()
}

// MARK: - MainDependency
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class MainDependencyMock: MainDependency {

    // MARK: - Variables
    var analytics: AnalyticsTracking {
        analyticsGetCount += 1
        if let handler = analyticsGetHandler {
            return handler()
        }
        return _analytics
    }
    var analyticsGetCount: Int = 0
    var analyticsGetHandler: (() -> AnalyticsTracking)? = nil
    var _analytics: AnalyticsTracking
    var memoryRepository: MemoryRepositoryProtocol {
        memoryRepositoryGetCount += 1
        if let handler = memoryRepositoryGetHandler {
            return handler()
        }
        return _memoryRepository
    }
    var memoryRepositoryGetCount: Int = 0
    var memoryRepositoryGetHandler: (() -> MemoryRepositoryProtocol)? = nil
    var _memoryRepository: MemoryRepositoryProtocol
    var pushNotificationRepository: PushNotificationRepositoryProtocol {
        pushNotificationRepositoryGetCount += 1
        if let handler = pushNotificationRepositoryGetHandler {
            return handler()
        }
        return _pushNotificationRepository
    }
    var pushNotificationRepositoryGetCount: Int = 0
    var pushNotificationRepositoryGetHandler: (() -> PushNotificationRepositoryProtocol)? = nil
    var _pushNotificationRepository: PushNotificationRepositoryProtocol
    var themeProvider: ThemeProviding {
        themeProviderGetCount += 1
        if let handler = themeProviderGetHandler {
            return handler()
        }
        return _themeProvider
    }
    var themeProviderGetCount: Int = 0
    var themeProviderGetHandler: (() -> ThemeProviding)? = nil
    var _themeProvider: ThemeProviding
    var userRepository: UserRepositoryProtocol {
        userRepositoryGetCount += 1
        if let handler = userRepositoryGetHandler {
            return handler()
        }
        return _userRepository
    }
    var userRepositoryGetCount: Int = 0
    var userRepositoryGetHandler: (() -> UserRepositoryProtocol)? = nil
    var _userRepository: UserRepositoryProtocol

    // MARK: - Initializer
    init(analytics: AnalyticsTracking, memoryRepository: MemoryRepositoryProtocol, pushNotificationRepository: PushNotificationRepositoryProtocol, themeProvider: ThemeProviding, userRepository: UserRepositoryProtocol) {
        self._analytics = analytics
        self._memoryRepository = memoryRepository
        self._pushNotificationRepository = pushNotificationRepository
        self._themeProvider = themeProvider
        self._userRepository = userRepository
    }
}

// MARK: - MediaStaging
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class MemoryEventStreamingMock: MemoryEventStreaming {

    // MARK: - Variables
    var latestDrop: AnyPublisher<MemoryDrop, Never> {
        latestDropGetCount += 1
        return Deferred { [weak self, subject = latestDropSubject] () -> AnyPublisher<MemoryDrop, Never> in
            self?.latestDropSubscribeCount += 1
            if let handler = self?.latestDropGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.latestDropOutputCount += 1
            self?.latestDropOutputs.append(value)
            self?.latestDropOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.latestDropCompletionCount += 1 }, receiveCancel: { [weak self] in self?.latestDropSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var latestDropGetCount: Int = 0
    var latestDropGetHandler: (() -> AnyPublisher<MemoryDrop, Never>)? = nil
    var latestDropSubscribeCount: Int = 0
    var latestDropSubscribeCancelCount: Int = 0
    var latestDropOutputCount: Int = 0
    var latestDropOutputs: [MemoryDrop] = []
    var latestDropOutputHandler: ((MemoryDrop) -> Void)? = nil
    var latestDropCompletionCount: Int = 0
    lazy var latestDropSubject = PassthroughSubject<MemoryDrop, Never>()
}

// MARK: - MemoryRepositoryProtocol
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class MemoryRepositoryProtocolMock: MemoryRepositoryProtocol {

    // MARK: - Variables
    var isRefreshing: AnyPublisher<Bool, Never> {
        isRefreshingGetCount += 1
        return Deferred { [weak self, subject = isRefreshingSubject] () -> AnyPublisher<Bool, Never> in
            self?.isRefreshingSubscribeCount += 1
            if let handler = self?.isRefreshingGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.isRefreshingOutputCount += 1
            self?.isRefreshingOutputs.append(value)
            self?.isRefreshingOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.isRefreshingCompletionCount += 1 }, receiveCancel: { [weak self] in self?.isRefreshingSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var isRefreshingGetCount: Int = 0
    var isRefreshingGetHandler: (() -> AnyPublisher<Bool, Never>)? = nil
    var isRefreshingSubscribeCount: Int = 0
    var isRefreshingSubscribeCancelCount: Int = 0
    var isRefreshingOutputCount: Int = 0
    var isRefreshingOutputs: [Bool] = []
    var isRefreshingOutputHandler: ((Bool) -> Void)? = nil
    var isRefreshingCompletionCount: Int = 0
    lazy var isRefreshingSubject = PassthroughSubject<Bool, Never>()
    var ownMemories: AnyPublisher<[MemoryDrop], Never> {
        ownMemoriesGetCount += 1
        return Deferred { [weak self, subject = ownMemoriesSubject] () -> AnyPublisher<[MemoryDrop], Never> in
            self?.ownMemoriesSubscribeCount += 1
            if let handler = self?.ownMemoriesGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.ownMemoriesOutputCount += 1
            self?.ownMemoriesOutputs.append(value)
            self?.ownMemoriesOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.ownMemoriesCompletionCount += 1 }, receiveCancel: { [weak self] in self?.ownMemoriesSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var ownMemoriesGetCount: Int = 0
    var ownMemoriesGetHandler: (() -> AnyPublisher<[MemoryDrop], Never>)? = nil
    var ownMemoriesSubscribeCount: Int = 0
    var ownMemoriesSubscribeCancelCount: Int = 0
    var ownMemoriesOutputCount: Int = 0
    var ownMemoriesOutputs: [[MemoryDrop]] = []
    var ownMemoriesOutputHandler: (([MemoryDrop]) -> Void)? = nil
    var ownMemoriesCompletionCount: Int = 0
    lazy var ownMemoriesSubject = PassthroughSubject<[MemoryDrop], Never>()

    // MARK: - Methods
    func delete(id: String) -> AnyPublisher<Void, Error> {
        deleteCallCount += 1
        deleteArgs.append(id)
        if let __deleteHandler = self.deleteHandler {
            return __deleteHandler(id)
        }
        return Deferred { [weak self, subject = deleteSubject] () -> AnyPublisher<(), Error> in
            self?.deleteSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.deleteOutputCount += 1
            self?.deleteOutputs.append(value)
            self?.deleteOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.deleteCompletionCount += 1 }, receiveCancel: { [weak self] in self?.deleteSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var deleteCallCount: Int = 0
    var deleteArgs: [String] = []
    var deleteHandler: ((_ id: String) -> (AnyPublisher<Void, Error>))? = nil
    var deleteSubscribeCount: Int = 0
    var deleteSubscribeCancelCount: Int = 0
    var deleteOutputCount: Int = 0
    var deleteOutputs: [()] = []
    var deleteOutputHandler: ((()) -> Void)? = nil
    var deleteCompletionCount: Int = 0
    lazy var deleteSubject = PassthroughSubject<(), Error>()
    func fetch(id: String) -> AnyPublisher<MemoryDrop?, Error> {
        fetchCallCount += 1
        fetchArgs.append(id)
        if let __fetchHandler = self.fetchHandler {
            return __fetchHandler(id)
        }
        return Deferred { [weak self, subject = fetchSubject] () -> AnyPublisher<MemoryDrop?, Error> in
            self?.fetchSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.fetchOutputCount += 1
            self?.fetchOutputs.append(value)
            self?.fetchOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.fetchCompletionCount += 1 }, receiveCancel: { [weak self] in self?.fetchSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var fetchCallCount: Int = 0
    var fetchArgs: [String] = []
    var fetchHandler: ((_ id: String) -> (AnyPublisher<MemoryDrop?, Error>))? = nil
    var fetchSubscribeCount: Int = 0
    var fetchSubscribeCancelCount: Int = 0
    var fetchOutputCount: Int = 0
    var fetchOutputs: [MemoryDrop?] = []
    var fetchOutputHandler: ((MemoryDrop?) -> Void)? = nil
    var fetchCompletionCount: Int = 0
    lazy var fetchSubject = PassthroughSubject<MemoryDrop?, Error>()
    func share(id: String) -> AnyPublisher<String, Error> {
        shareCallCount += 1
        shareArgs.append(id)
        if let __shareHandler = self.shareHandler {
            return __shareHandler(id)
        }
        return Deferred { [weak self, subject = shareSubject] () -> AnyPublisher<String, Error> in
            self?.shareSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.shareOutputCount += 1
            self?.shareOutputs.append(value)
            self?.shareOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.shareCompletionCount += 1 }, receiveCancel: { [weak self] in self?.shareSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var shareCallCount: Int = 0
    var shareArgs: [String] = []
    var shareHandler: ((_ id: String) -> (AnyPublisher<String, Error>))? = nil
    var shareSubscribeCount: Int = 0
    var shareSubscribeCancelCount: Int = 0
    var shareOutputCount: Int = 0
    var shareOutputs: [String] = []
    var shareOutputHandler: ((String) -> Void)? = nil
    var shareCompletionCount: Int = 0
    lazy var shareSubject = PassthroughSubject<String, Error>()
    func token() -> AnyPublisher<String, Error> {
        tokenCallCount += 1
        if let __tokenHandler = self.tokenHandler {
            return __tokenHandler()
        }
        return Deferred { [weak self, subject = tokenSubject] () -> AnyPublisher<String, Error> in
            self?.tokenSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.tokenOutputCount += 1
            self?.tokenOutputs.append(value)
            self?.tokenOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.tokenCompletionCount += 1 }, receiveCancel: { [weak self] in self?.tokenSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var tokenCallCount: Int = 0
    var tokenHandler: (() -> (AnyPublisher<String, Error>))? = nil
    var tokenSubscribeCount: Int = 0
    var tokenSubscribeCancelCount: Int = 0
    var tokenOutputCount: Int = 0
    var tokenOutputs: [String] = []
    var tokenOutputHandler: ((String) -> Void)? = nil
    var tokenCompletionCount: Int = 0
    lazy var tokenSubject = CurrentValueSubject<String, Error>("")
}

// MARK: - NamingAnnotated
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
// Not named after their declaration:
//   `refresh()` members are named `reloadNow*` — `/// sourcery: methodName = "reloadNow"`
final class NamingAnnotatedMock: NamingAnnotated {

    // MARK: - Methods
    // `refresh()` members are named `reloadNow*` — `/// sourcery: methodName = "reloadNow"`
    func refresh() {
        reloadNowCallCount += 1
        if let __reloadNowHandler = self.reloadNowHandler {
            __reloadNowHandler()
        }
    }
    var reloadNowCallCount: Int = 0
    var reloadNowHandler: (() -> ())? = nil
    func reset() {
        resetCallCount += 1
        if let __resetHandler = self.resetHandler {
            __resetHandler()
        }
    }
    var resetCallCount: Int = 0
    var resetHandler: (() -> ())? = nil
}

// MARK: - NamingKeywords
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class NamingKeywordsMock: NamingKeywords {

    // MARK: - Variables
    var `default`: Int {
        get {
            defaultGetCount += 1
            if let handler = defaultGetHandler {
                return handler()
            }
            return _default
        }
        set {
            defaultSetCount += 1
            _default = newValue
        }
    }
    var defaultGetCount: Int = 0
    var defaultGetHandler: (() -> Int)? = nil
    var defaultSetCount: Int = 0
    var _default: Int = 0

    // MARK: - Methods
    func `do`() {
        doCallCount += 1
        if let __doHandler = self.doHandler {
            __doHandler()
        }
    }
    var doCallCount: Int = 0
    var doHandler: (() -> ())? = nil
    func `repeat`(times: Int) {
        repeatCallCount += 1
        repeatArgs.append(times)
        if let __repeatHandler = self.repeatHandler {
            __repeatHandler(times)
        }
    }
    var repeatCallCount: Int = 0
    var repeatArgs: [Int] = []
    var repeatHandler: ((_ times: Int) -> ())? = nil
}

// MARK: - NamingManyToOne
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class NamingManyToOneMock: NamingManyToOne {

    // MARK: - Methods
    func loadData() {
        loadDataCallCount += 1
        if let __loadDataHandler = self.loadDataHandler {
            __loadDataHandler()
        }
    }
    var loadDataCallCount: Int = 0
    var loadDataHandler: (() -> ())? = nil
    func load_data() {
        load_dataCallCount += 1
        if let __load_dataHandler = self.load_dataHandler {
            __load_dataHandler()
        }
    }
    var load_dataCallCount: Int = 0
    var load_dataHandler: (() -> ())? = nil
}

// MARK: - NamingOverloads
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
// Not named after their declaration:
//   `end(at:)` members are named `endAt*` — overload of `end`, argument labels appended
//   `end(atDocument:)` members are named `endAtDocument*` — overload of `end`, argument labels appended
//   `reference(forURL:)` members are named `referenceForURL*` — overload of `reference`, argument labels appended
//   `reference(withPath:)` members are named `referenceWithPath*` — overload of `reference`, argument labels appended
final class NamingOverloadsMock: NamingOverloads {

    // MARK: - Methods
    func end() {
        endCallCount += 1
        if let __endHandler = self.endHandler {
            __endHandler()
        }
    }
    var endCallCount: Int = 0
    var endHandler: (() -> ())? = nil
    // `end(at:)` members are named `endAt*` — overload of `end`, argument labels appended
    func end(at fieldValues: [String]) {
        endAtCallCount += 1
        endAtArgs.append(fieldValues)
        if let __endAtHandler = self.endAtHandler {
            __endAtHandler(fieldValues)
        }
    }
    var endAtCallCount: Int = 0
    var endAtArgs: [[String]] = []
    var endAtHandler: ((_ fieldValues: [String]) -> ())? = nil
    // `end(atDocument:)` members are named `endAtDocument*` — overload of `end`, argument labels appended
    func end(atDocument document: String) {
        endAtDocumentCallCount += 1
        endAtDocumentArgs.append(document)
        if let __endAtDocumentHandler = self.endAtDocumentHandler {
            __endAtDocumentHandler(document)
        }
    }
    var endAtDocumentCallCount: Int = 0
    var endAtDocumentArgs: [String] = []
    var endAtDocumentHandler: ((_ document: String) -> ())? = nil
    // `reference(forURL:)` members are named `referenceForURL*` — overload of `reference`, argument labels appended
    func reference(forURL url: String) {
        referenceForURLCallCount += 1
        referenceForURLArgs.append(url)
        if let __referenceForURLHandler = self.referenceForURLHandler {
            __referenceForURLHandler(url)
        }
    }
    var referenceForURLCallCount: Int = 0
    var referenceForURLArgs: [String] = []
    var referenceForURLHandler: ((_ url: String) -> ())? = nil
    // `reference(withPath:)` members are named `referenceWithPath*` — overload of `reference`, argument labels appended
    func reference(withPath path: String) {
        referenceWithPathCallCount += 1
        referenceWithPathArgs.append(path)
        if let __referenceWithPathHandler = self.referenceWithPathHandler {
            __referenceWithPathHandler(path)
        }
    }
    var referenceWithPathCallCount: Int = 0
    var referenceWithPathArgs: [String] = []
    var referenceWithPathHandler: ((_ path: String) -> ())? = nil
}

// MARK: - NamingReturnTypes
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
// Not named after their declaration:
//   `data()` members are named `dataStringAny*` — overload of `data` returning `[String: Any]`
//   `data()` members are named `dataStringAnyOptional*` — overload of `data` returning `[String: Any]?`
final class NamingReturnTypesMock: NamingReturnTypes {

    // MARK: - Methods
    // `data()` members are named `dataStringAny*` — overload of `data` returning `[String: Any]`
    func data() -> [String: Any] {
        dataStringAnyCallCount += 1
        if let __dataStringAnyHandler = self.dataStringAnyHandler {
            return __dataStringAnyHandler()
        }
        return [:]
    }
    var dataStringAnyCallCount: Int = 0
    var dataStringAnyHandler: (() -> ([String: Any]))? = nil
    // `data()` members are named `dataStringAnyOptional*` — overload of `data` returning `[String: Any]?`
    func data() -> [String: Any]? {
        dataStringAnyOptionalCallCount += 1
        if let __dataStringAnyOptionalHandler = self.dataStringAnyOptionalHandler {
            return __dataStringAnyOptionalHandler()
        }
        return nil
    }
    var dataStringAnyOptionalCallCount: Int = 0
    var dataStringAnyOptionalHandler: (() -> ([String: Any]?))? = nil
}

// MARK: - NamingUnderscores
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class NamingUnderscoresMock: NamingUnderscores {

    // MARK: - Variables
    var setting4_2: Int {
        get {
            setting4_2GetCount += 1
            if let handler = setting4_2GetHandler {
                return handler()
            }
            return _setting4_2
        }
        set {
            setting4_2SetCount += 1
            _setting4_2 = newValue
        }
    }
    var setting4_2GetCount: Int = 0
    var setting4_2GetHandler: (() -> Int)? = nil
    var setting4_2SetCount: Int = 0
    var _setting4_2: Int = 0

    // MARK: - Methods
    func perform1_0() {
        perform1_0CallCount += 1
        if let __perform1_0Handler = self.perform1_0Handler {
            __perform1_0Handler()
        }
    }
    var perform1_0CallCount: Int = 0
    var perform1_0Handler: (() -> ())? = nil
    func perform2_0(value: Int) {
        perform2_0CallCount += 1
        perform2_0Args.append(value)
        if let __perform2_0Handler = self.perform2_0Handler {
            __perform2_0Handler(value)
        }
    }
    var perform2_0CallCount: Int = 0
    var perform2_0Args: [Int] = []
    var perform2_0Handler: ((_ value: Int) -> ())? = nil
}

// MARK: - NamingUppercase
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class NamingUppercaseMock: NamingUppercase {

    // MARK: - Methods
    func ID() -> String {
        IDCallCount += 1
        if let __IDHandler = self.IDHandler {
            return __IDHandler()
        }
        return ""
    }
    var IDCallCount: Int = 0
    var IDHandler: (() -> (String))? = nil
    func URLSession() -> String {
        URLSessionCallCount += 1
        if let __URLSessionHandler = self.URLSessionHandler {
            return __URLSessionHandler()
        }
        return ""
    }
    var URLSessionCallCount: Int = 0
    var URLSessionHandler: (() -> (String))? = nil
}

// MARK: - NotificationSignalling
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class NotificationSignallingMock: NotificationSignalling {

    // MARK: - Variables
    var badgeCount: AnyPublisher<Int, Never> {
        badgeCountGetCount += 1
        return Deferred { [weak self, subject = badgeCountSubject] () -> AnyPublisher<Int, Never> in
            self?.badgeCountSubscribeCount += 1
            if let handler = self?.badgeCountGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.badgeCountOutputCount += 1
            self?.badgeCountOutputs.append(value)
            self?.badgeCountOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.badgeCountCompletionCount += 1 }, receiveCancel: { [weak self] in self?.badgeCountSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var badgeCountGetCount: Int = 0
    var badgeCountGetHandler: (() -> AnyPublisher<Int, Never>)? = nil
    var badgeCountSubscribeCount: Int = 0
    var badgeCountSubscribeCancelCount: Int = 0
    var badgeCountOutputCount: Int = 0
    var badgeCountOutputs: [Int] = []
    var badgeCountOutputHandler: ((Int) -> Void)? = nil
    var badgeCountCompletionCount: Int = 0
    lazy var badgeCountSubject = CurrentValueSubject<Int, Never>(0)
    var friendGraphChanged: AnyPublisher<Void, Never> {
        friendGraphChangedGetCount += 1
        return Deferred { [weak self, subject = friendGraphChangedSubject] () -> AnyPublisher<(), Never> in
            self?.friendGraphChangedSubscribeCount += 1
            if let handler = self?.friendGraphChangedGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.friendGraphChangedOutputCount += 1
            self?.friendGraphChangedOutputs.append(value)
            self?.friendGraphChangedOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.friendGraphChangedCompletionCount += 1 }, receiveCancel: { [weak self] in self?.friendGraphChangedSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var friendGraphChangedGetCount: Int = 0
    var friendGraphChangedGetHandler: (() -> AnyPublisher<Void, Never>)? = nil
    var friendGraphChangedSubscribeCount: Int = 0
    var friendGraphChangedSubscribeCancelCount: Int = 0
    var friendGraphChangedOutputCount: Int = 0
    var friendGraphChangedOutputs: [()] = []
    var friendGraphChangedOutputHandler: ((()) -> Void)? = nil
    var friendGraphChangedCompletionCount: Int = 0
    lazy var friendGraphChangedSubject = PassthroughSubject<(), Never>()
}

// MARK: - PlaybackObserving
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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

// MARK: - PropertyEffectful
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class PropertyEffectfulMock: PropertyEffectful {

    // MARK: - Variables
    var config: String {
        get async throws {
            configGetCount += 1
            if let handler = configGetHandler {
                return try await handler()
            }
            return _config
        }
    }
    var configGetCount: Int = 0
    var configGetHandler: (() async throws -> String)? = nil
    var _config: String = ""
    var loader: ThemeProviding {
        get async {
            loaderGetCount += 1
            if let handler = loaderGetHandler {
                return await handler()
            }
            return _loader
        }
    }
    var loaderGetCount: Int = 0
    var loaderGetHandler: (() async -> ThemeProviding)? = nil
    var _loader: ThemeProviding
    var plain: String {
        plainGetCount += 1
        if let handler = plainGetHandler {
            return handler()
        }
        return _plain
    }
    var plainGetCount: Int = 0
    var plainGetHandler: (() -> String)? = nil
    var _plain: String = ""
    var secret: String {
        get throws {
            secretGetCount += 1
            if let handler = secretGetHandler {
                return try handler()
            }
            return _secret
        }
    }
    var secretGetCount: Int = 0
    var secretGetHandler: (() throws -> String)? = nil
    var _secret: String = ""
    var token: String {
        get async {
            tokenGetCount += 1
            if let handler = tokenGetHandler {
                return await handler()
            }
            return _token
        }
    }
    var tokenGetCount: Int = 0
    var tokenGetHandler: (() async -> String)? = nil
    var _token: String = ""

    // MARK: - Initializer
    init(loader: ThemeProviding) {
        self._loader = loader
    }
}

// MARK: - PropertyShaped
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class PropertyShapedMock: PropertyShaped {

    // MARK: - Variables
    var buildNumber: Int {
        buildNumberGetCount += 1
        if let handler = buildNumberGetHandler {
            return handler()
        }
        return _buildNumber
    }
    var buildNumberGetCount: Int = 0
    var buildNumberGetHandler: (() -> Int)? = nil
    let _buildNumber: Int = 0
    var cursor: Int {
        get {
            cursorGetCount += 1
            if let handler = cursorGetHandler {
                return handler()
            }
            fatalError("cursorGetHandler expected to be set.")
        }
        set {
            cursorSetCount += 1
        }
    }
    var cursorGetCount: Int = 0
    var cursorGetHandler: (() -> Int)? = nil
    var cursorSetCount: Int = 0
    var draft: String {
        get {
            draftGetCount += 1
            if let handler = draftGetHandler {
                return handler()
            }
            return _draft
        }
        set {
            draftSetCount += 1
            _draft = newValue
        }
    }
    var draftGetCount: Int = 0
    var draftGetHandler: (() -> String)? = nil
    var draftSetCount: Int = 0
    var _draft: String = ""
    var identifier: String {
        identifierGetCount += 1
        if let handler = identifierGetHandler {
            return handler()
        }
        return _identifier
    }
    var identifierGetCount: Int = 0
    var identifierGetHandler: (() -> String)? = nil
    var _identifier: String = ""
    var snapshot: [String: Int] {
        snapshotGetCount += 1
        if let handler = snapshotGetHandler {
            return handler()
        }
        fatalError("snapshotGetHandler expected to be set.")
    }
    var snapshotGetCount: Int = 0
    var snapshotGetHandler: (() -> [String: Int])? = nil
    var themeProvider: ThemeProviding {
        themeProviderGetCount += 1
        if let handler = themeProviderGetHandler {
            return handler()
        }
        return _themeProvider
    }
    var themeProviderGetCount: Int = 0
    var themeProviderGetHandler: (() -> ThemeProviding)? = nil
    var _themeProvider: ThemeProviding

    // MARK: - Initializer
    init(themeProvider: ThemeProviding) {
        self._themeProvider = themeProvider
    }
}

// MARK: - PushNotificationRepositoryProtocol
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
@MainActor
final class PushNotificationRepositoryProtocolMock: PushNotificationRepositoryProtocol {

    // MARK: - Variables
    var authorizationStatus: RecordPermission {
        authorizationStatusGetCount += 1
        if let handler = authorizationStatusGetHandler {
            return handler()
        }
        return _authorizationStatus
    }
    var authorizationStatusGetCount: Int = 0
    var authorizationStatusGetHandler: (() -> RecordPermission)? = nil
    var _authorizationStatus: RecordPermission
    nonisolated var installationId: String {
        installationIdGetCount += 1
        if let handler = installationIdGetHandler {
            return handler()
        }
        return _installationId
    }
    nonisolated(unsafe) var installationIdGetCount: Int = 0
    nonisolated(unsafe) var installationIdGetHandler: (() -> String)? = nil
    nonisolated(unsafe) var _installationId: String = ""
    var isNotificationsEnabled: Bool {
        isNotificationsEnabledGetCount += 1
        if let handler = isNotificationsEnabledGetHandler {
            return handler()
        }
        return _isNotificationsEnabled
    }
    var isNotificationsEnabledGetCount: Int = 0
    var isNotificationsEnabledGetHandler: (() -> Bool)? = nil
    var _isNotificationsEnabled: Bool = false

    // MARK: - Initializer
    init(authorizationStatus: RecordPermission) {
        self._authorizationStatus = authorizationStatus
    }

    // MARK: - Methods
    func deregisterCurrentDevice() -> AnyPublisher<Void, Error> {
        deregisterCurrentDeviceCallCount += 1
        if let __deregisterCurrentDeviceHandler = self.deregisterCurrentDeviceHandler {
            return __deregisterCurrentDeviceHandler()
        }
        return Deferred { [weak self, subject = deregisterCurrentDeviceSubject] () -> AnyPublisher<(), Error> in
            self?.deregisterCurrentDeviceSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.deregisterCurrentDeviceOutputCount += 1
            self?.deregisterCurrentDeviceOutputs.append(value)
            self?.deregisterCurrentDeviceOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.deregisterCurrentDeviceCompletionCount += 1 }, receiveCancel: { [weak self] in self?.deregisterCurrentDeviceSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var deregisterCurrentDeviceCallCount: Int = 0
    var deregisterCurrentDeviceHandler: (() -> (AnyPublisher<Void, Error>))? = nil
    var deregisterCurrentDeviceSubscribeCount: Int = 0
    var deregisterCurrentDeviceSubscribeCancelCount: Int = 0
    var deregisterCurrentDeviceOutputCount: Int = 0
    var deregisterCurrentDeviceOutputs: [()] = []
    var deregisterCurrentDeviceOutputHandler: ((()) -> Void)? = nil
    var deregisterCurrentDeviceCompletionCount: Int = 0
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class RootDependencyMock: RootDependency {
}

// MARK: - TimelineBuildable
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class TimelineDependencyMock: TimelineDependency {

    // MARK: - Variables
    var analytics: AnalyticsTracking {
        analyticsGetCount += 1
        if let handler = analyticsGetHandler {
            return handler()
        }
        return _analytics
    }
    var analyticsGetCount: Int = 0
    var analyticsGetHandler: (() -> AnalyticsTracking)? = nil
    var _analytics: AnalyticsTracking
    var audioSessionConfigurer: AudioSessionConfiguring {
        audioSessionConfigurerGetCount += 1
        if let handler = audioSessionConfigurerGetHandler {
            return handler()
        }
        return _audioSessionConfigurer
    }
    var audioSessionConfigurerGetCount: Int = 0
    var audioSessionConfigurerGetHandler: (() -> AudioSessionConfiguring)? = nil
    var _audioSessionConfigurer: AudioSessionConfiguring
    var memoryRepository: MemoryRepositoryProtocol {
        memoryRepositoryGetCount += 1
        if let handler = memoryRepositoryGetHandler {
            return handler()
        }
        return _memoryRepository
    }
    var memoryRepositoryGetCount: Int = 0
    var memoryRepositoryGetHandler: (() -> MemoryRepositoryProtocol)? = nil
    var _memoryRepository: MemoryRepositoryProtocol
    var themeProvider: ThemeProviding {
        themeProviderGetCount += 1
        if let handler = themeProviderGetHandler {
            return handler()
        }
        return _themeProvider
    }
    var themeProviderGetCount: Int = 0
    var themeProviderGetHandler: (() -> ThemeProviding)? = nil
    var _themeProvider: ThemeProviding
    var userRepository: UserRepositoryProtocol {
        userRepositoryGetCount += 1
        if let handler = userRepositoryGetHandler {
            return handler()
        }
        return _userRepository
    }
    var userRepositoryGetCount: Int = 0
    var userRepositoryGetHandler: (() -> UserRepositoryProtocol)? = nil
    var _userRepository: UserRepositoryProtocol

    // MARK: - Initializer
    init(analytics: AnalyticsTracking, audioSessionConfigurer: AudioSessionConfiguring, memoryRepository: MemoryRepositoryProtocol, themeProvider: ThemeProviding, userRepository: UserRepositoryProtocol) {
        self._analytics = analytics
        self._audioSessionConfigurer = audioSessionConfigurer
        self._memoryRepository = memoryRepository
        self._themeProvider = themeProvider
        self._userRepository = userRepository
    }
}

// MARK: - UploadScheduling
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
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
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
@MainActor
final class UserRepositoryProtocolMock: UserRepositoryProtocol {

    // MARK: - Variables
    var meStream: AnyPublisher<UserSummary?, Never> {
        meStreamGetCount += 1
        return Deferred { [weak self, subject = meStreamSubject] () -> AnyPublisher<UserSummary?, Never> in
            self?.meStreamSubscribeCount += 1
            if let handler = self?.meStreamGetHandler {
                return handler()
            }
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.meStreamOutputCount += 1
            self?.meStreamOutputs.append(value)
            self?.meStreamOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.meStreamCompletionCount += 1 }, receiveCancel: { [weak self] in self?.meStreamSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var meStreamGetCount: Int = 0
    var meStreamGetHandler: (() -> AnyPublisher<UserSummary?, Never>)? = nil
    var meStreamSubscribeCount: Int = 0
    var meStreamSubscribeCancelCount: Int = 0
    var meStreamOutputCount: Int = 0
    var meStreamOutputs: [UserSummary?] = []
    var meStreamOutputHandler: ((UserSummary?) -> Void)? = nil
    var meStreamCompletionCount: Int = 0
    lazy var meStreamSubject = PassthroughSubject<UserSummary?, Never>()

    // MARK: - Methods
    func bootstrap(displayName: String?) -> AnyPublisher<Void, Error> {
        bootstrapCallCount += 1
        bootstrapArgs.append(displayName)
        if let __bootstrapHandler = self.bootstrapHandler {
            return __bootstrapHandler(displayName)
        }
        return Deferred { [weak self, subject = bootstrapSubject] () -> AnyPublisher<(), Error> in
            self?.bootstrapSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.bootstrapOutputCount += 1
            self?.bootstrapOutputs.append(value)
            self?.bootstrapOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.bootstrapCompletionCount += 1 }, receiveCancel: { [weak self] in self?.bootstrapSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var bootstrapCallCount: Int = 0
    var bootstrapArgs: [String?] = []
    var bootstrapHandler: ((_ displayName: String?) -> (AnyPublisher<Void, Error>))? = nil
    var bootstrapSubscribeCount: Int = 0
    var bootstrapSubscribeCancelCount: Int = 0
    var bootstrapOutputCount: Int = 0
    var bootstrapOutputs: [()] = []
    var bootstrapOutputHandler: ((()) -> Void)? = nil
    var bootstrapCompletionCount: Int = 0
    lazy var bootstrapSubject = PassthroughSubject<(), Error>()
    func registerDevice(token: String, platform: String) -> AnyPublisher<Void, Error> {
        registerDeviceCallCount += 1
        registerDeviceArgs.append((token: token, platform: platform))
        if let __registerDeviceHandler = self.registerDeviceHandler {
            return __registerDeviceHandler(token, platform)
        }
        return Deferred { [weak self, subject = registerDeviceSubject] () -> AnyPublisher<(), Error> in
            self?.registerDeviceSubscribeCount += 1
            return subject.eraseToAnyPublisher()
        }
        .handleEvents(receiveOutput: { [weak self] value in
            self?.registerDeviceOutputCount += 1
            self?.registerDeviceOutputs.append(value)
            self?.registerDeviceOutputHandler?(value)
        }, receiveCompletion: { [weak self] _ in self?.registerDeviceCompletionCount += 1 }, receiveCancel: { [weak self] in self?.registerDeviceSubscribeCancelCount += 1 })
        .eraseToAnyPublisher()
    }
    var registerDeviceCallCount: Int = 0
    var registerDeviceArgs: [(token: String, platform: String)] = []
    var registerDeviceHandler: ((_ token: String, _ platform: String) -> (AnyPublisher<Void, Error>))? = nil
    var registerDeviceSubscribeCount: Int = 0
    var registerDeviceSubscribeCancelCount: Int = 0
    var registerDeviceOutputCount: Int = 0
    var registerDeviceOutputs: [()] = []
    var registerDeviceOutputHandler: ((()) -> Void)? = nil
    var registerDeviceCompletionCount: Int = 0
    lazy var registerDeviceSubject = PassthroughSubject<(), Error>()
}

// MARK: - VocabularyCanonical
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class VocabularyCanonicalMock: VocabularyCanonical {

    // MARK: - Variables
    var identifier: String {
        identifierGetCount += 1
        if let handler = identifierGetHandler {
            return handler()
        }
        return _identifier
    }
    var identifierGetCount: Int = 0
    var identifierGetHandler: (() -> String)? = nil
    var _identifier: String = ""

    // MARK: - Methods
    func refresh() {
        refreshCallCount += 1
        if let __refreshHandler = self.refreshHandler {
            __refreshHandler()
        }
    }
    var refreshCallCount: Int = 0
    var refreshHandler: (() -> ())? = nil
}

// MARK: - VocabularyLegacyObjc
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class VocabularyLegacyObjcMock: NSObject, VocabularyLegacyObjc {

    // MARK: - Methods
    func flush() {
        flushCallCount += 1
        if let __flushHandler = self.flushHandler {
            __flushHandler()
        }
    }
    var flushCallCount: Int = 0
    var flushHandler: (() -> ())? = nil
}

// MARK: - VocabularyObjc
// Members are the requirement's declared name plus a suffix — `load` gives `loadCallCount`,
// `loadArgs`, `loadHandler`; `name` gives `nameGetCount`, `nameSetCount`, `nameGetHandler`, `_name`.
final class VocabularyObjcMock: NSObject, VocabularyObjc {

    // MARK: - Methods
    func reload() {
        reloadCallCount += 1
        if let __reloadHandler = self.reloadHandler {
            __reloadHandler()
        }
    }
    var reloadCallCount: Int = 0
    var reloadHandler: (() -> ())? = nil
}
