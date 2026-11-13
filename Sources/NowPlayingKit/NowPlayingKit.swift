
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

public final class NowPlayingManager: @unchecked Sendable {
    public static let shared = NowPlayingManager()

    private let player = MPMusicPlayerController.systemMusicPlayer

    @Published public private(set) var isPlaying = false

    private let playbackStateSubject = PassthroughSubject<Bool, Never>()

    public var playbackStatePublisher: AnyPublisher<Bool, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    private init() {
        isPlaying = player.playbackState == .playing
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

        if isPlaying != currentState {
            isPlaying = currentState
            playbackStateSubject.send(currentState)
        }
    }

    @objc private func handlePlaybackStateChange() {
        checkAndUpdatePlaybackState()
    }

    public func authorize() async -> MusicAuthorization.Status {
        let musicStatus = await MusicAuthorization.request()

        let mediaStatus: MPMediaLibraryAuthorizationStatus =
            await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

        if mediaStatus == .authorized {
            checkAndUpdatePlaybackState()
        }

        return musicStatus
    }

    public func getCurrentPlayback() async throws -> NowPlayingData {
        guard MusicAuthorization.currentStatus == .authorized,
              MPMediaLibrary.authorizationStatus() == .authorized else {
            throw NowPlayingError.unauthorized
        }

        print("DEBUG: Playback state: \(player.playbackState.rawValue)")
        print("DEBUG: Current item: \(String(describing: player.nowPlayingItem?.title))")

        guard let item = player.nowPlayingItem else {
            throw NowPlayingError.noCurrentEntry
        }

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
