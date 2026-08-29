(function () {
    "use strict";

    const detector = globalThis.AniSyncDetector;
    if (!detector) return;

    const observedVideos = new WeakSet();
    const sentKeys = new Set();
    let lastMetadataSignature = "";

    function pageURLFor(video) {
        const value = video?.dataset?.pageUrl || document.location.href;
        try {
            return new URL(value, document.location.href).href;
        } catch (_) {
            return document.location.href;
        }
    }

    function metadataFor(video) {
        return detector.extractDocumentMetadata(document, pageURLFor(video));
    }

    function announcePage() {
        const metadata = metadataFor(null);
        if (!metadata) return;
        const signature = JSON.stringify(metadata);
        if (signature === lastMetadataSignature) return;
        lastMetadataSignature = signature;
        browser.runtime.sendMessage({ type: "pageMetadata", metadata }).catch(() => {});
    }

    function check(video) {
        if (!detector.isQualifiedPlayback(video)) return;
        const metadata = metadataFor(video);
        if (!metadata?.seriesKey || !Number.isInteger(metadata.episode)) return;
        const key = `${metadata.seriesKey}:${metadata.episode}`;
        if (sentKeys.has(key)) return;
        sentKeys.add(key);
        browser.runtime.sendMessage({ type: "qualifiedPlayback", metadata }).catch(() => {
            sentKeys.delete(key);
        });
    }

    function observe(video) {
        if (observedVideos.has(video)) return;
        observedVideos.add(video);
        for (const event of ["timeupdate", "playing", "seeked", "durationchange"]) {
            video.addEventListener(event, () => check(video), { passive: true });
        }
        check(video);
    }

    function scan() {
        announcePage();
        document.querySelectorAll("video").forEach(observe);
    }

    scan();
    const observer = new MutationObserver(scan);
    observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
    window.addEventListener("pageshow", scan, { passive: true });

    browser.runtime.onMessage.addListener(request => {
        if (request?.type === "getPageMetadata") return Promise.resolve(metadataFor(null));
        return undefined;
    });
})();
