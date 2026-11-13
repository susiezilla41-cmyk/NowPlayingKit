import Combine
import Foundation
import MusicKit
import UIKit
import MediaPlayer

public enum NowPlayingError: Error {
    case noCurrentEntry
    case unauthorized
}

public struct NowPlayingData: Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String?
    public let artworkURL: URL?
    public let playbackTime: TimeInterval
    public let duration: TimeInterval

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        artworkURL: URL? = nil,
        playbackTime: TimeInterval = 0,
        duration: TimeInterval = 1
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.playbackTime = playbackTime
        self.duration = duration
    }
}

public final class NowPlayingManager: ObservableObject, @unchecked Sendable {
    public static let shared = NowPlayingManager()

    private let player = MPMusicPlayerController.systemMusicPlayer

    @Published public private(set) var isPlaying = false
    @Published public private(set) var debugStatus = "Waiting for playback information..."

    private let playbackStateSubject = PassthroughSubject<Bool, Never>()

    public var playbackStatePublisher: AnyPublisher<Bool, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    private init() {
        isPlaying = player.playbackState == .playing
        debugStatus = "Initial playback state: \(player.playbackState.rawValue)"

        player.beginGeneratingPlaybackNotifications()
        playbackStateSubject.send(isPlaying)
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        let notifications: [Notification.Name] = [
            UIApplication.didBecomeActiveNotification,
            .MPMusicPlayerControllerPlaybackStateDidChange,
            .MPMusicPlayerControllerNowPlayingItemDidChange
        ]

        for notification in notifications {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePlaybackStateChange),
                name: notification,
                object: nil
            )
        }
    }

    private func checkAndUpdatePlaybackState() {
        let currentState = player.playbackState == .playing

        debugStatus = "Playback state: \(player.playbackState.rawValue)"

        if isPlaying != currentState {
            isPlaying = currentState
            playbackStateSubject.send(currentState)
        }
    }

    @objc private func handlePlaybackStateChange() {
        checkAndUpdatePlaybackState()
    }

    public func authorize() async -> MusicAuthorization.Status {
        debugStatus = "Requesting music permissions..."

        let musicStatus = await MusicAuthorization.request()

        let mediaStatus: MPMediaLibraryAuthorizationStatus =
            await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

        debugStatus = "MusicKit: \(musicStatus). Media Library: \(mediaStatus.rawValue)"

        if mediaStatus == .authorized {
            checkAndUpdatePlaybackState()
        }

        return musicStatus
    }

    public func getCurrentPlayback() async throws -> NowPlayingData {
        guard MusicAuthorization.currentStatus == .authorized,
              MPMediaLibrary.authorizationStatus() == .authorized else {
            debugStatus = "ERROR: Music permission not authorized"
            throw NowPlayingError.unauthorized
        }

        checkAndUpdatePlaybackState()

        guard let item = player.nowPlayingItem else {
            debugStatus = "No current item detected by MediaPlayer"
            throw NowPlayingError.noCurrentEntry
        }

        debugStatus = "Detected: \(item.title ?? "Unknown title") — \(item.artist ?? "Unknown artist")"

        return NowPlayingData(
            id: String(item.persistentID),
            title: item.title ?? "Unknown Title",
            artist: item.artist ?? "Unknown Artist",
            album: item.albumTitle,
            artworkURL: nil,
            playbackTime: player.currentPlaybackTime,
            duration: max(item.playbackDuration, 1)
        )
    }

    deinit {
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }
}

extension SystemMusicPlayer {
    public static let playbackStateDidChangeNotification =
        NSNotification.Name("SystemMusicPlayerPlaybackStateDidChange")
}
