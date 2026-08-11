//
//  AppLaunchDecisionsTests.swift
//  PostgresGUITests
//
//  Unit tests for shouldShowWelcomeScreen, including the fileProfileCount parameter.
//

import Foundation
import Testing
@testable import PostgresGUI

@Suite("AppLaunchDecisions")
struct AppLaunchDecisionsTests {

    @Suite("shouldShowWelcomeScreen")
    struct ShouldShowWelcomeScreenTests {

        @Test func showsWelcomeWhenNoConnectionsAndNoFileProfiles() {
            let result = shouldShowWelcomeScreen(
                connectionCount: 0,
                isShowingConnectionForm: false,
                fileProfileCount: 0
            )
            #expect(result == true)
        }

        @Test func hidesWelcomeWhenHasPostgresConnection() {
            let result = shouldShowWelcomeScreen(
                connectionCount: 1,
                isShowingConnectionForm: false,
                fileProfileCount: 0
            )
            #expect(result == false)
        }

        @Test func hidesWelcomeWhenHasFileProfile() {
            let result = shouldShowWelcomeScreen(
                connectionCount: 0,
                isShowingConnectionForm: false,
                fileProfileCount: 1
            )
            #expect(result == false)
        }

        @Test func hidesWelcomeWhenConnectionFormShowing() {
            let result = shouldShowWelcomeScreen(
                connectionCount: 0,
                isShowingConnectionForm: true,
                fileProfileCount: 0
            )
            #expect(result == false)
        }

        @Test func hidesWelcomeWhenBothConnectionAndFileProfile() {
            let result = shouldShowWelcomeScreen(
                connectionCount: 1,
                isShowingConnectionForm: false,
                fileProfileCount: 1
            )
            #expect(result == false)
        }

        @Test func backwardCompatDefaultFileProfileCountShowsWelcomeWhenNoConnections() {
            // Verify the default = 0 parameter keeps old call sites working
            let result = shouldShowWelcomeScreen(
                connectionCount: 0,
                isShowingConnectionForm: false
            )
            #expect(result == true)
        }

        @Test func backwardCompatDefaultFileProfileCountHidesWelcomeWhenHasConnections() {
            let result = shouldShowWelcomeScreen(
                connectionCount: 1,
                isShowingConnectionForm: false
            )
            #expect(result == false)
        }
    }
}
