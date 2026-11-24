import XCTest
@testable import Kumogakure

@MainActor
final class AmbientAudioManagerTests: XCTestCase {
    private func makeSUT() -> (
        manager: AmbientAudioManager,
        session: MockAudioSession,
        scheduler: ManualTestScheduler,
        createdPlayers: () -> [MockAudioPlayer]
    ) {
        let clock = MockClock()
        let scheduler = ManualTestScheduler(clock: clock)
        let session = MockAudioSession()
        var players: [MockAudioPlayer] = []

        let manager = AmbientAudioManager(
            sessionManager: session,
            playerFactory: { url in
                let player = MockAudioPlayer(url: url)
                players.append(player)
                return player
            },
            resourceLocator: { sound in
                sound.resourceFileName.map { URL(fileURLWithPath: "/tmp/\($0).m4a") }
            },
            scheduler: scheduler,
            notificationCenter: NotificationCenter(),
            fadeOutDuration: 1.5,
            previewDuration: 2.0
        )

        return (manager, session, scheduler, { players })
    }

    func testSoundNoneNeverTouchesAVAudioSession() {
        let sut = makeSUT()

        sut.manager.play(sound: .none)
        sut.manager.playPreview(sound: .none)
        sut.manager.stopWithFadeOut()
        sut.manager.stopImmediately()

        XCTAssertEqual(sut.session.configureCount, 0)
        XCTAssertTrue(sut.session.setActiveCalls.isEmpty)
        XCTAssertTrue(sut.createdPlayers().isEmpty)
        XCTAssertFalse(sut.manager.isPlaying)
    }

    func testLoopingPlaybackAndFadeOutDeactivatesSession() {
        let sut = makeSUT()

        sut.manager.play(sound: .rain)

        XCTAssertEqual(sut.session.configureCount, 1)
        XCTAssertEqual(sut.session.setActiveCalls, [.init(active: true, notifyOthers: false)])
        XCTAssertTrue(sut.manager.isPlaying)

        let player = sut.createdPlayers().first
        XCTAssertEqual(player?.numberOfLoops, -1)
        XCTAssertEqual(player?.playCount, 1)

        sut.manager.stopWithFadeOut()
        XCTAssertFalse(sut.manager.isPlaying)
        XCTAssertEqual(player?.fadeOutCalls.first?.volume, 0)
        XCTAssertEqual(player?.fadeOutCalls.first?.duration, 1.5)
        XCTAssertEqual(player?.stopCount, 0)

        sut.scheduler.advance(by: 1.5)
        XCTAssertEqual(player?.stopCount, 1)
        XCTAssertEqual(
            sut.session.setActiveCalls,
            [
                .init(active: true, notifyOthers: false),
                .init(active: false, notifyOthers: true),
            ]
        )
    }

    func testNewPlaybackCancelsPendingFadeOutTask() {
        let sut = makeSUT()

        sut.manager.play(sound: .rain)
        sut.manager.stopWithFadeOut()

        sut.scheduler.advance(by: 0.5)
        sut.manager.play(sound: .nightWind)

        sut.scheduler.advance(by: 2.0)

        XCTAssertTrue(sut.manager.isPlaying)
        XCTAssertEqual(sut.manager.currentSound, .nightWind)
        XCTAssertEqual(sut.createdPlayers().last?.stopCount, 0)
        XCTAssertEqual(sut.session.setActiveCalls.last?.active, true)
    }

    func testInterruptionPausesAndResumesWhenShouldResume() {
        let sut = makeSUT()
        sut.manager.play(sound: .rain)
        let player = sut.createdPlayers().first

        sut.manager.handleAudioInterruption(began: true, shouldResume: false)
        XCTAssertFalse(sut.manager.isPlaying)
        XCTAssertEqual(player?.pauseCount, 1)

        sut.manager.handleAudioInterruption(began: false, shouldResume: true)
        XCTAssertTrue(sut.manager.isPlaying)
        XCTAssertEqual(player?.playCount, 2)

        sut.manager.handleAudioInterruption(began: true, shouldResume: false)
        sut.manager.handleAudioInterruption(began: false, shouldResume: false)
        XCTAssertFalse(sut.manager.isPlaying)
        XCTAssertEqual(player?.playCount, 2)
    }

    func testPreviewStopsAutomaticallyAfterTwoSeconds() {
        let sut = makeSUT()

        sut.manager.playPreview(sound: .nightWind)
        let player = sut.createdPlayers().first
        XCTAssertEqual(player?.numberOfLoops, 0)
        XCTAssertTrue(sut.manager.isPlaying)

        sut.scheduler.advance(by: 2.0)
        XCTAssertFalse(sut.manager.isPlaying)
        XCTAssertEqual(player?.stopCount, 1)
        XCTAssertEqual(sut.session.setActiveCalls.last?.active, false)
    }
}
