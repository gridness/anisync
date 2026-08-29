const test = require("node:test");
const assert = require("node:assert/strict");
const detector = require("../../Shared (Extension)/Resources/detector.js");

test("supports every confirmed Anime365 origin", () => {
    for (const host of ["smotret-anime.org", "smotret-anime.app", "anime-365.ru"]) {
        const result = detector.parseLocation(`https://${host}/catalog/example-title-77/seriya-8-991/voice-12`);
        assert.equal(result.seriesKey, "catalog:77");
        assert.equal(result.episode, 8);
    }
});

test("rejects an unrequested origin", () => {
    assert.equal(
        detector.parseLocation("https://example.com/catalog/example-title-77/seriya-8-991/voice-12"),
        null
    );
});

test("fractional and special labels are not treated as normal episodes", () => {
    const result = detector.parseLocation(
        "https://smotret-anime.org/catalog/example-title-77/seriya-8.5-991/voice-12"
    );
    assert.equal(result.episode, null);
    const special = detector.parseLocation(
        "https://smotret-anime.app/catalog/example-title-77/special-1-992/voice-12"
    );
    assert.equal(special.episode, null);
});

test("a movie is treated as episode one", () => {
    const result = detector.parseLocation(
        "https://anime-365.ru/catalog/example-movie-77/film-991/voice-12"
    );
    assert.equal(result.episode, 1);
});

test("80 percent qualifies only while actively playing", () => {
    assert.equal(detector.isQualifiedPlayback({ duration: 100, currentTime: 80, paused: false, ended: false }), true);
    assert.equal(detector.isQualifiedPlayback({ duration: 100, currentTime: 79.99, paused: false, ended: false }), false);
    assert.equal(detector.isQualifiedPlayback({ duration: 100, currentTime: 90, paused: true, ended: false }), false);
    assert.equal(detector.isQualifiedPlayback({ duration: 100, currentTime: 100, paused: false, ended: true }), false);
});

test("extracts exact AniList identity without fuzzy matching", () => {
    const titleMeta = { getAttribute: key => key === "content" ? "Example Anime" : null, textContent: "" };
    const episodeMeta = { getAttribute: key => key === "content" ? "8" : null, textContent: "" };
    const document = {
        title: "Example Anime — Anime365",
        querySelector(selector) {
            if (selector === 'meta[property="ya:ovs:episode"]') return episodeMeta;
            if (selector === 'meta[property="ya:ovs:original_name"]') return titleMeta;
            return null;
        },
        querySelectorAll(selector) {
            if (selector.includes("anilist.co")) return [{ href: "https://anilist.co/anime/12345/Example/" }];
            return [];
        }
    };
    const metadata = detector.extractDocumentMetadata(
        document,
        "https://anime-365.ru/catalog/example-title-77/seriya-8-991/voice-12"
    );
    assert.deepEqual(metadata, {
        seriesKey: "catalog:77",
        sourceTitle: "Example Anime",
        episode: 8,
        mediaID: 12345
    });
});
