import Foundation
import Testing
@testable import RemoteTV

/// Tests for the pure helpers in the Samsung service layer: the transient-network
/// classification that drives the connect retry policy, and the regex scraper used
/// on DIAL XML / Lounge responses.
struct SamsungTVServiceTests {

    // MARK: - isTransientNetworkError

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .cannotConnectToHost,
        .timedOut,
        .cannotFindHost,
    ])
    func transientURLErrorsAreRetried(code: URLError.Code) {
        #expect(SamsungTVService.isTransientNetworkError(URLError(code)))
    }

    @Test func nonTransientURLErrorIsNotRetried() {
        #expect(!SamsungTVService.isTransientNetworkError(URLError(.badServerResponse)))
    }

    @Test func serviceErrorsAreNeverTransient() {
        // Token/auth failures must propagate to connect()'s re-pair path, not retry.
        #expect(!SamsungTVService.isTransientNetworkError(TVServiceError.tokenRejected))
        #expect(!SamsungTVService.isTransientNetworkError(TVServiceError.pairingRejected))
    }

    // MARK: - firstRegexMatch

    @Test func extractsScreenIdFromDIALStateDocument() {
        let xml = "<service><name>YouTube</name><additionalData><screenId>abc-123-def</screenId></additionalData></service>"
        #expect(firstRegexMatch(in: xml, pattern: "<screenId>([^<]+)</screenId>") == "abc-123-def")
    }

    @Test func extractsLoungeSessionIdsFromBindResponse() {
        let body = #"[[0,["c","SID-VALUE","",8]],[1,["S","GSESSION-VALUE"]]]"#
        #expect(firstRegexMatch(in: body, pattern: "\"c\",\"([^\"]+)\"") == "SID-VALUE")
        #expect(firstRegexMatch(in: body, pattern: "\"S\",\"([^\"]+)\"") == "GSESSION-VALUE")
    }

    @Test func returnsNilWhenPatternAbsent() {
        #expect(firstRegexMatch(in: "<service/>", pattern: "<screenId>([^<]+)</screenId>") == nil)
    }

    @Test func returnsNilWithoutCaptureGroup() {
        #expect(firstRegexMatch(in: "abc", pattern: "abc") == nil)
    }
}
