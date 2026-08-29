const elements = Object.fromEntries([
    "account-name", "message", "current", "current-title", "current-episode", "rewatch",
    "mapping", "search-form", "search", "results", "activity-section", "activity", "empty",
    "connect", "open-app"
].map(id => [id, document.getElementById(id)]));

let popupState = null;
let activeTabID = null;
let activeTabPrivate = false;
let currentAwaiting = null;

function message(key, substitutions) {
    return browser.i18n.getMessage(key, substitutions) || key;
}

function localize() {
    document.documentElement.lang = browser.i18n.getUILanguage().split("-")[0];
    document.querySelectorAll("[data-i18n]").forEach(element => {
        element.textContent = message(element.dataset.i18n);
    });
    document.querySelectorAll("[data-i18n-placeholder]").forEach(element => {
        element.placeholder = message(element.dataset.i18nPlaceholder);
    });
}

function show(element, visible = true) {
    element.classList.toggle("hidden", !visible);
}

function callout(text, kind = "warning") {
    elements.message.className = `callout ${kind}`;
    elements.message.textContent = text;
    show(elements.message, Boolean(text));
}

function outcomeText(activity) {
    if (activity.outcome === "alreadyUpToDate") return message("already_up_to_date");
    if (activity.kind === "rewatch") return message("rewatch_synced");
    return message("saved_to_anilist");
}

function renderActivity(items) {
    elements.activity.replaceChildren();
    for (const item of items.slice(0, 3)) {
        const row = document.createElement("li");
        const title = document.createElement("span");
        title.className = "activity-title";
        title.textContent = item.title;
        const detail = document.createElement("span");
        detail.className = "activity-detail";
        detail.textContent = `${message("episode", String(item.episode))} · ${outcomeText(item)}`;
        const time = document.createElement("time");
        time.className = "activity-time";
        const date = new Date(item.occurredAt);
        time.dateTime = item.occurredAt;
        time.textContent = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(date);
        row.append(title, detail, time);
        elements.activity.append(row);
    }
    show(elements["activity-section"], items.length > 0);
}

function render(response) {
    popupState = response;
    const state = response?.state || {};
    const context = response?.context;
    if (context && !Number.isInteger(context.mediaID)) {
        const mapping = state.mappings?.find(item => item.seriesKey === context.seriesKey);
        if (mapping) context.mediaID = mapping.mediaID;
    }
    elements["account-name"].textContent = state.connected
        ? state.account?.name || message("connected")
        : message("not_connected");
    show(elements.connect, !state.connected);

    show(elements.current, Boolean(context));
    show(elements.empty, !context);
    if (context) {
        elements["current-title"].textContent = context.sourceTitle || message("anime365_episode");
        elements["current-episode"].textContent = Number.isInteger(context.episode)
            ? message("episode", String(context.episode))
            : message("episode_not_identified");
        show(elements.rewatch, state.connected && Number.isInteger(context.mediaID));
    }

    const awaiting = state.pending?.find(item => item.state === "awaitingMapping" && (!context || item.seriesKey === context.seriesKey));
    currentAwaiting = awaiting || null;
    show(elements.mapping, Boolean(awaiting));
    if (awaiting && !elements.search.value) elements.search.value = awaiting.sourceTitle;

    if (!response?.ok) {
        callout(response?.private ? message("private_browsing") : response?.error || message("native_unavailable"), "error");
    } else if (state.conflicts?.length) {
        callout(message("sync_conflict"), "error");
    } else if (state.pending?.some(item => item.state === "reconnect")) {
        callout(message("reconnect_to_finish"));
    } else if (state.pending?.some(item => item.state === "retrying")) {
        callout(message("saved_will_retry"));
    } else if (awaiting) {
        callout(message("mapping_needed"));
    } else {
        show(elements.message, false);
    }
    renderActivity(state.activity || []);
}

async function send(command) {
    const response = await browser.runtime.sendMessage({
        type: "nativeCommand", command, tabId: activeTabID, isPrivate: activeTabPrivate
    });
    render(response);
    return response;
}

async function load() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    activeTabID = tabs[0]?.id ?? null;
    activeTabPrivate = Boolean(tabs[0]?.incognito);
    render(await browser.runtime.sendMessage({
        type: "getPopupState", tabId: activeTabID, isPrivate: activeTabPrivate
    }));
}

elements["search-form"].addEventListener("submit", async event => {
    event.preventDefault();
    const query = elements.search.value.trim();
    if (query.length < 2) return;
    elements.results.textContent = message("searching");
    const response = await browser.runtime.sendMessage({
        type: "nativeCommand",
        command: { command: "searchMedia", query },
        tabId: activeTabID,
        isPrivate: activeTabPrivate
    });
    elements.results.replaceChildren();
    if (!response.ok) {
        elements.results.textContent = response.error;
        return;
    }
    const awaiting = currentAwaiting;
    if (!awaiting) return;
    for (const result of response.results || []) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "result";
        const title = document.createElement("span");
        title.className = "result-title";
        title.textContent = result.title;
        const meta = document.createElement("span");
        meta.className = "result-meta";
        meta.textContent = [result.year, result.format, result.episodes ? message("episodes", String(result.episodes)) : null]
            .filter(Boolean).join(" · ");
        button.append(title, meta);
        button.addEventListener("click", () => send({
            command: "confirmMapping",
            seriesKey: awaiting.seriesKey,
            sourceTitle: awaiting.sourceTitle,
            mediaID: result.id,
            aniListTitle: result.title
        }));
        elements.results.append(button);
    }
    if (!elements.results.childElementCount) {
        elements.results.textContent = message("no_results");
    }
});

elements.rewatch.addEventListener("click", () => {
    const mediaID = popupState?.context?.mediaID;
    if (Number.isInteger(mediaID)) send({ command: "startRewatch", mediaID });
});

function openApp(route) {
    window.location.href = `anisync://${route}`;
}
elements.connect.addEventListener("click", () => openApp("connect"));
elements["open-app"].addEventListener("click", () => openApp("open"));

localize();
load().catch(error => callout(error.message, "error"));
