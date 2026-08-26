import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension Codemagic {
    /// One page of `GET /builds` — the API's own unit: at most 30 builds, plus where
    /// the page after it starts.
    struct BuildsPage: Sendable {
        public let builds: [Build]
        /// Offset the following page starts at, read off the response's `nextPageUrl`
        /// (whose cursor is a `skip=` query item); `nil` on the last page.
        public let nextOffset: Int?
    }

    /// Result of a builds listing that may have spanned several pages.
    struct PagedBuilds: Sendable {
        /// Builds, newest first — branch-filtered and capped to the requested limit.
        public let builds: [Build]
        /// Offset to resume from when the server still had builds left; `nil` when the
        /// listing reached the end of the history.
        public let nextOffset: Int?
    }

    /// One page of builds for an application, starting `offset` builds into the history.
    ///
    /// `offset` is sent as the API's own `skip` query item — the same one its
    /// `nextPageUrl` cursor uses — so the skipping happens server-side.
    func buildsPage(appId: String, offset: Int = 0) async throws -> BuildsPage {
        var components = URLComponents(
            url: Codemagic.baseURL.appendingPathComponent("builds"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "appId", value: appId)]
            + (offset > 0 ? [URLQueryItem(name: "skip", value: String(offset))] : [])
        guard let url = components?.url else { throw CodemagicError.invalidURL(appId) }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "x-auth-token")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CodemagicError.badResponse(http.statusCode)
        }
        let page = try JSONDecoder().decode(BuildsPageBody.self, from: data)
        return BuildsPage(
            builds: page.builds,
            nextOffset: page.nextPageUrl.flatMap(Codemagic.offset(inCursor:))
        )
    }

    /// Builds for an application, newest first, starting `offset` builds in.
    ///
    /// The API serves 30 builds per call (there is no page-size parameter), so a larger
    /// `limit` walks the pages it hands back; `nil` walks to the end of the history.
    /// `maxPages` bounds that walk — worth having because `branch` is filtered client-side,
    /// so a rare branch can otherwise cross the whole history. When builds are left on the
    /// server, `nextOffset` is the offset that resumes exactly after the last one returned.
    ///
    /// Paging is positional, not anchored to a build: a build started between two calls
    /// shifts the history down, so a resumed listing can repeat one. The API offers no
    /// stable cursor (`skip` is all there is), so callers that care must de-duplicate by id.
    func builds(
        appId: String,
        branch: String? = nil,
        limit: Int?,
        offset: Int = 0,
        maxPages: Int = 20
    ) async throws -> PagedBuilds {
        guard limit.map({ $0 > 0 }) ?? true, maxPages > 0, offset >= 0 else {
            return PagedBuilds(builds: [], nextOffset: nil)
        }

        var collected: [Build] = []
        /// Builds walked past since `offset` — including ones the branch filter dropped,
        /// so the resume offset lines up with the server's own numbering.
        var consumed = 0
        var cursor = offset
        var pages = 0
        var serverHasMore = true

        pages: while pages < maxPages {
            let page = try await buildsPage(appId: appId, offset: cursor)
            pages += 1

            for (index, build) in page.builds.enumerated() {
                consumed += 1
                if branch == nil || build.branch == branch { collected.append(build) }
                guard let limit, collected.count >= limit else { continue }
                let restOfPage = page.builds.count - (index + 1)
                serverHasMore = restOfPage > 0 || page.nextOffset != nil
                break pages
            }

            guard let pageAfter = page.nextOffset, !page.builds.isEmpty else {
                serverHasMore = false     // end of the history
                break
            }
            cursor = pageAfter            // keep walking by the server's own cursor
        }

        return PagedBuilds(builds: collected, nextOffset: serverHasMore ? offset + consumed : nil)
    }

    /// The `skip` value carried by a `nextPageUrl` cursor.
    static func offset(inCursor cursor: String) -> Int? {
        URLComponents(string: cursor)?.queryItems?
            .first { $0.name == "skip" }
            .flatMap { $0.value }
            .flatMap(Int.init)
    }
}

/// Decoding shape of a `GET /builds` page.
struct BuildsPageBody: Decodable {
    let builds: [Codemagic.Build]
    let nextPageUrl: String?
}
