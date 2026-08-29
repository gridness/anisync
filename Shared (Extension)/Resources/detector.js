(function (root) {
    "use strict";

    const SUPPORTED_HOSTS = new Set([
        "smotret-anime.org",
        "smotret-anime.app",
        "anime-365.ru"
    ]);

    function parseLocation(rawURL) {
        let url;
        try {
            url = new URL(rawURL);
        } catch (_) {
            return null;
        }
        if (url.protocol !== "https:" || !SUPPORTED_HOSTS.has(url.hostname)) return null;

        const parts = url.pathname.split("/").filter(Boolean);
        const catalogIndex = parts.indexOf("catalog");
        if (catalogIndex < 0 || !parts[catalogIndex + 1]) return null;
        const catalogMatch = parts[catalogIndex + 1].match(/-(\d+)$/);
        if (!catalogMatch) return null;

        const episodeSegment = parts[catalogIndex + 2] || "";
        const labelWithoutID = episodeSegment.replace(/-\d+$/, "");
        const numberMatch = labelWithoutID.match(/(?:^|[^\d])(\d+(?:[.,]\d+)?)(?:[^\d]|$)/);
        const parsedNumber = numberMatch ? Number(numberMatch[1].replace(",", ".")) : null;
        const special = /(?:special|speshl|спешл|recap|дайджест|ova|ona)/i.test(labelWithoutID);
        const movie = /(?:movie|film|фильм|polnometrazh|полнометраж)/i.test(labelWithoutID);
        const episode = special
            ? null
            : Number.isInteger(parsedNumber) && parsedNumber > 0
                ? parsedNumber
                : movie ? 1 : null;

        return {
            host: url.hostname,
            seriesKey: `catalog:${catalogMatch[1]}`,
            episode,
            episodeLabel: labelWithoutID
        };
    }

    function integerText(value) {
        if (typeof value !== "string") return null;
        const clean = value.trim();
        if (!/^\d+$/.test(clean)) return null;
        const number = Number(clean);
        return Number.isInteger(number) && number > 0 ? number : null;
    }

    function contentOf(document, selectors) {
        for (const selector of selectors) {
            const element = document.querySelector(selector);
            const value = element?.getAttribute("content") || element?.textContent;
            if (value?.trim()) return value.trim();
        }
        return null;
    }

    function extractMediaID(document) {
        const anchors = document.querySelectorAll('a[href*="anilist.co/anime/"]');
        for (const anchor of anchors) {
            const match = anchor.href.match(/^https:\/\/(?:www\.)?anilist\.co\/anime\/(\d+)(?:\/|$)/i);
            if (match) return Number(match[1]);
        }
        return null;
    }

    function cleanTitle(title) {
        if (!title) return "Unknown anime";
        return title
            .replace(/\s*[|—–-]\s*(?:Anime365|Смотреть аниме).*$/i, "")
            .replace(/^Смотреть\s+/i, "")
            .trim() || "Unknown anime";
    }

    function extractDocumentMetadata(document, rawURL) {
        const location = parseLocation(rawURL);
        if (!location) return null;

        const episodeText = contentOf(document, [
            'meta[property="ya:ovs:episode"]',
            'meta[itemprop="episodeNumber"]',
            '[itemprop="episodeNumber"]',
            '[data-episode-number].active'
        ]);
        const episode = integerText(episodeText || "") || location.episode;
        const sourceTitle = cleanTitle(contentOf(document, [
            'meta[property="ya:ovs:original_name"]',
            'meta[property="og:title"]',
            'h1[itemprop="name"]',
            '.m-catalog-view-info h1',
            'h1'
        ]) || document.title);

        return {
            seriesKey: location.seriesKey,
            sourceTitle,
            episode,
            mediaID: extractMediaID(document)
        };
    }

    function isQualifiedPlayback(video) {
        const duration = Number(video?.duration);
        const currentTime = Number(video?.currentTime);
        return Boolean(
            video &&
            !video.paused &&
            !video.ended &&
            Number.isFinite(duration) &&
            duration > 0 &&
            Number.isFinite(currentTime) &&
            currentTime / duration >= 0.8
        );
    }

    const api = { SUPPORTED_HOSTS, parseLocation, extractDocumentMetadata, isQualifiedPlayback };
    root.AniSyncDetector = api;
    if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
