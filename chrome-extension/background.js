// Claude Appshots bridge.
//
// When Jonathan captures a Chrome tab with Claude Appshots, the Appshots agent
// leaves a short note (URL, window title, time) that the native host hands
// over on request (several captures can be waiting). Claude in Chrome can only control tabs inside its own tab
// group, so as soon as a tab group is created, a tab joins one or a grouped tab
// loads (which is what Claude in Chrome does when it starts work), this moves the captured tab
// into that group. Claude then controls the real tab, as Codex Appshots does.
// Every capture from the last 15 minutes is moved; each is used once. A tab
// already in another Claude group stays where it is.

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

// shortcut: matches the group's name; if tabs stop moving after a Claude
// update, check what Claude in Chrome now calls its group.
async function isClaudeGroup(groupId) {
  if (groupId == null || groupId === NONE) return false;
  try { return /claude/i.test((await chrome.tabGroups.get(groupId)).title || ""); }
  catch (e) { return false; }
}

async function onGroupActivity(groupId) {
  if (groupId == null || groupId === NONE || busy) return;
  busy = true;
  try {
    // Only Claude in Chrome's group ("Claude …"), never one of his own.
    if (!(await isClaudeGroup(groupId))) return;
    const res = await ask({ cmd: "pending" });
    const notes = (res && res.captures) || [];
    if (!notes.length) return;
    const tabs = await chrome.tabs.query({});
    const handled = [];
    for (const note of notes) {
      const tab = await findCapturedTab(note, tabs);
      if (!tab) { await ask({ cmd: "log", msg: "no open tab matches a captured page" }); continue; }
      // Already in another Claude session's group: that session is using it
      // (18 November 2026 a new session pulled a tab out of a working one).
      // Leave it there and let the note go.
      if (tab.groupId !== groupId && await isClaudeGroup(tab.groupId)) {
        await ask({ cmd: "log", msg: "left a captured tab in another Claude group" });
        handled.push(note.time);
        continue;
      }
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
// A new group may only get its name a moment later.
chrome.tabGroups.onUpdated.addListener((g) => onGroupActivity(g.id));
chrome.tabs.onCreated.addListener((t) => { if (t.groupId !== NONE) onGroupActivity(t.groupId); });
// A tab joining a group, or a grouped tab loading a placeholder (Claude waking
// the bridge from a new tab or example.com), means a session wants the tab.
// Ordinary page loads don't count: another session busy in its own group
// would otherwise grab a capture meant for this one.
const PLACEHOLDER = /^(chrome:\/\/newtab\/?|https?:\/\/(www\.)?example\.com\/?)$/;
chrome.tabs.onUpdated.addListener((id, info, tab) => {
  if ("groupId" in info) onGroupActivity(info.groupId);
  else if (info.status === "loading" && PLACEHOLDER.test(info.url || tab.pendingUrl || tab.url || "")) onGroupActivity(tab.groupId);
});
