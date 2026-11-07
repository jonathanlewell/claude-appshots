// Claude Appshots bridge.
//
// When Jonathan captures a Chrome tab with Claude Appshots, the Appshots agent
// leaves a short note (URL, window title, time) that the native host hands
// over on request (several captures can be waiting). Claude in Chrome can only control tabs inside its own tab
// group, so as soon as a tab group is created or a tab joins one (which is
// what Claude in Chrome does when it starts work), this moves the captured tab
// into that group. Claude then controls the real tab, as Codex Appshots does.
// Every capture from the last 15 minutes is moved; each is used once.

const HOST = "com.jonathanlewell.claude_appshots";
const NONE = chrome.tabGroups.TAB_GROUP_ID_NONE;
let busy = false;

const norm = (u) => (u || "").replace(/^https?:\/\//, "").replace(/#.*$/, "").replace(/\/$/, "");

async function ask(msg) {
  try { return await chrome.runtime.sendNativeMessage(HOST, msg); }
  catch (e) { return null; }
}

async function findCapturedTab(note, tabs) {
  const want = norm(note.url);
  let matches = want ? tabs.filter((t) => norm(t.url) === want) : [];
  if (!matches.length && note.windowTitle) {
    matches = tabs.filter((t) => t.title && note.windowTitle.startsWith(t.title + " - Google Chrome"));
  }
  // Prefer the tab that was showing when he captured it: active, most recently used.
  matches.sort((a, b) => (b.active - a.active) || ((b.lastAccessed || 0) - (a.lastAccessed || 0)));
  return matches[0];
}

async function onGroupActivity(groupId) {
  if (groupId == null || groupId === NONE || busy) return;
  busy = true;
  try {
    const res = await ask({ cmd: "pending" });
    const notes = (res && res.captures) || [];
    if (!notes.length) return;
    const tabs = await chrome.tabs.query({});
    const handled = [];
    for (const note of notes) {
      const tab = await findCapturedTab(note, tabs);
      if (!tab) { await ask({ cmd: "log", msg: "no open tab matches a captured page" }); continue; }
      if (tab.groupId !== groupId) await chrome.tabs.group({ groupId, tabIds: [tab.id] });
      tab.groupId = groupId;
      handled.push(note.time);
    }
    if (handled.length) await ask({ cmd: "done", times: handled });
  } catch (e) {
    await ask({ cmd: "log", msg: "could not move a tab: " + e });
  } finally {
    busy = false;
  }
}

chrome.tabGroups.onCreated.addListener((g) => onGroupActivity(g.id));
chrome.tabs.onCreated.addListener((t) => { if (t.groupId !== NONE) onGroupActivity(t.groupId); });
chrome.tabs.onUpdated.addListener((id, info) => { if ("groupId" in info) onGroupActivity(info.groupId); });
