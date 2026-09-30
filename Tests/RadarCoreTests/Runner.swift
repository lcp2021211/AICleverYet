import Foundation

private enum CheckError: Error { case missingValue }
@MainActor private enum Results { static var failures = 0 }

@MainActor func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    Results.failures += 1
    print("FAIL \(file):\(line): \(message)")
}
@MainActor func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a != b { fail("\(a) != \(b)", file: file, line: line) }
}
@MainActor func expectNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if a == b { fail("Unexpected equal values: \(a)", file: file, line: line) }
}
@MainActor func expectNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) {
    if a != nil { fail("Expected nil", file: file, line: line) }
}
@MainActor func expectNotNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) {
    if a == nil { fail("Unexpected nil", file: file, line: line) }
}
@MainActor func expectTrue(_ a: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !a { fail("Expected true", file: file, line: line) }
}
@MainActor func expectFalse(_ a: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if a { fail("Expected false", file: file, line: line) }
}
func unwrap<T>(_ a: T?) throws -> T {
    guard let a else { throw CheckError.missingValue }
    return a
}

@main struct Runner {
    @MainActor static func main() async {
        let checks = RadarChecks()
        var cases: [(String, () async throws -> Void)] = [
            ("Real JSON / exact effort history", { try checks.testRealPayloadAndExactEffortHistory() }),
            ("Delta timestamps / sparse history", { checks.testHistoryDeltaUsesTimestampAndRequiresCoverage() }),
            ("No startup traffic / deduplication / independent TTLs", { try await checks.testNoStartupOrClosedRequestsAndIndependentTTLs() }),
            ("Close cancels / late response rejected", { try await checks.testClosingCancelsAndRejectsLateResult() }),
            ("Partial failure / offline disk cache", { try await checks.testPartialFailureKeepsCurrentAndDiskCacheSurvivesOffline() }),
            ("Selection is local / explicit refresh", { try await checks.testSelectionDoesNotFetchAndManualRefreshIsExplicit() }),
            ("Harness mapping / insufficient samples / DSH history", { try checks.testHarnessMappingAndInsufficientSamples() }),
            ("Local harness switching / unavailable rows / per-harness memory", { try await checks.testHarnessSwitchingIsLocalAndKeepsUnavailableRows() }),
            ("Legacy cache upgrade without startup traffic", { try await checks.testLegacyHistoryCacheRefreshesOnlyAfterOpening() })
        ]
        if ProcessInfo.processInfo.environment["GPT_IQ_LIVE_TEST"] == "1" {
            cases.append(("Live API", { try await checks.testLiveAPIWhenRequested() }))
        }
        for (name, run) in cases {
            let before = Results.failures
            do { try await run() }
            catch { fail("\(name): \(error)") }
            if Results.failures == before { print("PASS \(name)") }
        }
        print("\(cases.count) checks, \(Results.failures) failures")
        exit(Results.failures == 0 ? 0 : 1)
    }
}
