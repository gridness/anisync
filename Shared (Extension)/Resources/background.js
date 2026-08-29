const NATIVE_APP = "me.heeka.anisync";
const contexts = new Map();

async function native(command) {
    try {
        return await browser.runtime.sendNativeMessage(NATIVE_APP, command);
    } catch (error) {
        return { ok: false, error: error?.message || "AniSync could not reach its macOS app." };
    }
}

function tabID(sender) {
    return sender?.tab?.id;
}

async function contextFor(tab) {
    if (!Number.isInteger(tab)) return null;
    if (contexts.has(tab)) return contexts.get(tab);
    try {
        const metadata = await browser.tabs.sendMessage(tab, { type: "getPageMetadata" }, { frameId: 0 });
        return metadata ? mergeMetadata(tab, metadata) : null;
    } catch (_) {
        return null;
    }
}

function mergeMetadata(tab, incoming) {
    const previous = contexts.get(tab) || {};
    const merged = {
        seriesKey: incoming?.seriesKey || previous.seriesKey,
        sourceTitle: incoming?.sourceTitle && incoming.sourceTitle !== "Unknown anime"
            ? incoming.sourceTitle
            : previous.sourceTitle || incoming?.sourceTitle,
        episode: Number.isInteger(incoming?.episode) ? incoming.episode : previous.episode,
        mediaID: Number.isInteger(incoming?.mediaID) ? incoming.mediaID : previous.mediaID
    };
    contexts.set(tab, merged);
    return merged;
}

async function setBadge(tab, response) {
    if (!Number.isInteger(tab)) return;
    const state = response?.state;
    let text = "";
    let color = "#3478F6";
    if (!response?.ok || state?.conflicts?.length) {
        text = "!";
        color = "#C9342F";
    } else if (state?.pending?.some(item => item.state === "awaitingMapping")) {
        text = "?";
        color = "#A05A00";
    } else if (state?.pending?.length) {
        text = "•";
        color = "#A05A00";
    } else {
        text = "✓";
        color = "#237A3B";
    }
    await browser.action.setBadgeBackgroundColor({ tabId: tab, color });
    await browser.action.setBadgeText({ tabId: tab, text });
    if (text === "✓") {
        setTimeout(() => browser.action.setBadgeText({ tabId: tab, text: "" }), 2400);
    }
}

browser.runtime.onMessage.addListener(async (request, sender) => {
    const tab = tabID(sender);
    const isPrivate = Boolean(request?.isPrivate || sender?.tab?.incognito);
    if (request?.type === "pageMetadata") {
        if (isPrivate) return { ok: false, private: true };
        if (Number.isInteger(tab)) mergeMetadata(tab, request.metadata);
        return { ok: true };
    }
    if (request?.type === "qualifiedPlayback") {
        if (isPrivate) return { ok: false, private: true, error: "AniSync does not run in Private Browsing." };
        const metadata = mergeMetadata(tab, request.metadata);
        if (!metadata.seriesKey || !Number.isInteger(metadata.episode)) {
            return { ok: false, error: "AniSync could not identify this episode." };
        }
        const response = await native({ command: "qualifyPlayback", ...metadata });
        await setBadge(tab, response);
        return response;
    }
    if (request?.type === "getPopupState") {
        const response = await native({ command: "getState" });
        const requestedTab = Number.isInteger(request.tabId) ? request.tabId : tab;
        if (isPrivate) {
            return { ...response, ok: false, private: true, error: "AniSync does not run in Private Browsing.", context: null };
        }
        return { ...response, context: await contextFor(requestedTab) };
    }
    if (request?.type === "nativeCommand") {
        if (isPrivate) return { ok: false, private: true, error: "AniSync does not run in Private Browsing." };
        const response = await native(request.command || {});
        const requestedTab = Number.isInteger(request.tabId) ? request.tabId : tab;
        await setBadge(requestedTab, response);
        return { ...response, context: await contextFor(requestedTab) };
    }
    return { ok: false, error: "Unknown AniSync extension message." };
});

browser.tabs?.onRemoved?.addListener(tab => contexts.delete(tab));
browser.runtime.onStartup.addListener(() => native({ command: "retryPending" }));
browser.alarms.onAlarm.addListener(alarm => {
    if (alarm.name === "retryPending") native({ command: "retryPending" });
});
browser.alarms.create("retryPending", { periodInMinutes: 1 });
native({ command: "retryPending" });
