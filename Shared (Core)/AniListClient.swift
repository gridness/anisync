import Foundation

protocol AniListAPI: Sendable {
    func viewer(token: String) async throws -> AniListAccount
    func media(id: Int, token: String) async throws -> AniListMediaSnapshot
    func save(mediaID: Int, write: DesiredWrite, token: String) async throws -> AniListEntrySnapshot
    func delete(listEntryID: Int, token: String) async throws
    func search(_ query: String, token: String?) async throws -> [MediaSearchResult]
}

struct HTTPAniListAPI: AniListAPI {
    private let endpoint = URL(string: "https://graphql.anilist.co")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func viewer(token: String) async throws -> AniListAccount {
        let query = """
        query Viewer {
          Viewer { id name avatar { medium } }
        }
        """
        let data = try await graphQL(query: query, variables: [:], token: token)
        guard let viewer = data["Viewer"] as? [String: Any],
              let id = viewer["id"] as? Int,
              let name = viewer["name"] as? String else {
            throw AniSyncError.api("AniList returned an incomplete account response.")
        }
        let avatar = (viewer["avatar"] as? [String: Any])?["medium"] as? String
        return AniListAccount(id: id, name: name, avatarURL: avatar, tokenExpiresAt: nil)
    }

    func media(id: Int, token: String) async throws -> AniListMediaSnapshot {
        let query = """
        query MediaForSync($id: Int!) {
          Media(id: $id, type: ANIME) {
            id episodes format
            title { english romaji native }
            mediaListEntry { id status progress repeat updatedAt }
          }
        }
        """
        let data = try await graphQL(query: query, variables: ["id": id], token: token)
        guard let media = data["Media"] as? [String: Any],
              let mediaID = media["id"] as? Int else {
            throw AniSyncError.api("AniList could not find this anime.")
        }
        return AniListMediaSnapshot(
            id: mediaID,
            title: preferredTitle(media["title"] as? [String: Any]) ?? "Anime \(mediaID)",
            episodes: media["episodes"] as? Int,
            format: media["format"] as? String,
            entry: entry(from: media["mediaListEntry"])
        )
    }

    func save(mediaID: Int, write: DesiredWrite, token: String) async throws -> AniListEntrySnapshot {
        let query = """
        mutation SaveProgress($mediaId: Int!, $progress: Int!, $status: MediaListStatus!, $repeat: Int) {
          SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status, repeat: $repeat) {
            id status progress repeat updatedAt
          }
        }
        """
        var variables: [String: Any] = [
            "mediaId": mediaID,
            "progress": write.progress,
            "status": write.status.rawValue
        ]
        if let repeatCount = write.repeatCount {
            variables["repeat"] = repeatCount
        }
        let data = try await graphQL(query: query, variables: variables, token: token)
        guard let snapshot = entry(from: data["SaveMediaListEntry"]) else {
            throw AniSyncError.api("AniList did not confirm the saved progress.")
        }
        return snapshot
    }

    func delete(listEntryID: Int, token: String) async throws {
        let query = """
        mutation DeleteEntry($id: Int!) {
          DeleteMediaListEntry(id: $id) { deleted }
        }
        """
        let data = try await graphQL(query: query, variables: ["id": listEntryID], token: token)
        guard let result = data["DeleteMediaListEntry"] as? [String: Any],
              result["deleted"] as? Bool == true else {
            throw AniSyncError.api("AniList did not confirm the deletion.")
        }
    }

    func search(_ query: String, token: String?) async throws -> [MediaSearchResult] {
        let graphQuery = """
        query SearchAnime($search: String!) {
          Page(page: 1, perPage: 8) {
            media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
              id episodes format seasonYear
              title { english romaji native }
              coverImage { medium }
            }
          }
        }
        """
        let data = try await graphQL(query: graphQuery, variables: ["search": query], token: token)
        let page = data["Page"] as? [String: Any]
        let media = page?["media"] as? [[String: Any]] ?? []
        return media.compactMap { item in
            guard let id = item["id"] as? Int,
                  let title = preferredTitle(item["title"] as? [String: Any]) else { return nil }
            return MediaSearchResult(
                id: id,
                title: title,
                year: item["seasonYear"] as? Int,
                format: item["format"] as? String,
                episodes: item["episodes"] as? Int,
                coverImageURL: (item["coverImage"] as? [String: Any])?["medium"] as? String
            )
        }
    }

    private func graphQL(
        query: String,
        variables: [String: Any],
        token: String?
    ) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AniSync/1.0 macOS", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables
        ])

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw AniSyncError.temporary("AniSync could not reach AniList. Your episode is saved locally and will retry.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw AniSyncError.temporary("AniList returned an invalid network response.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw AniSyncError.unauthorized
        }
        if http.statusCode == 429 {
            throw AniSyncError.rateLimited(Int(http.value(forHTTPHeaderField: "Retry-After") ?? ""))
        }
        if http.statusCode >= 500 {
            throw AniSyncError.temporary("AniList is temporarily unavailable. Your episode is saved locally and will retry.")
        }

        guard let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AniSyncError.api("AniList returned unreadable data.")
        }
        if let errors = root["errors"] as? [[String: Any]], let first = errors.first {
            let message = first["message"] as? String ?? "AniList rejected the request."
            throw AniSyncError.api(message)
        }
        guard (200..<300).contains(http.statusCode),
              let data = root["data"] as? [String: Any] else {
            throw AniSyncError.api("AniList rejected the request (HTTP \(http.statusCode)).")
        }
        return data
    }

    private func preferredTitle(_ title: [String: Any]?) -> String? {
        for key in ["english", "romaji", "native"] {
            if let value = title?[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func entry(from value: Any?) -> AniListEntrySnapshot? {
        guard let item = value as? [String: Any],
              let id = item["id"] as? Int,
              let statusString = item["status"] as? String,
              let status = AniListStatus(rawValue: statusString) else { return nil }
        return AniListEntrySnapshot(
            id: id,
            status: status,
            progress: item["progress"] as? Int ?? 0,
            repeatCount: item["repeat"] as? Int ?? 0,
            updatedAt: item["updatedAt"] as? Int ?? 0
        )
    }
}

