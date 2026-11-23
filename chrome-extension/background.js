// Claude Appshots bridge.
//
// When you capture a Chrome tab with Claude Appshots, the Appshots agent
// leaves a short note (URL, window title, time, capture stamp) that the native
// host hands over on request. Claude in Chrome can only control tabs inside its
// own session's tab group, so the session asks for the tab: it loads
//   https://example.com/#appshots-handoff=<stamp>[,<stamp>…]
// in a tab of its group (the stamp is the time in the Appshot's file names).
// This moves those captured tabs into that tab's group. Claude then controls
// the real tab, as Codex Appshots does. The part after # never leaves Chrome.
//
// Why a request and not the group's name: since Claude in Chrome 1.0.107 a
// session's group is named after the session ("⌛Fix login page"), so names
// can't tell Claude's groups from your own or one session from another
// (tabs went to the wrong session, or nowhere).

const HOST = "com.jonathanlewell.claude_appshots";
const NONE = chrome.tabGroups.TAB_GROUP_ID_NONE;
const VERSION = chrome.runtime.getManifest().version;
const MARKER = /^https?:\/\/(www\.)?example\.com\/?#appshots-handoff=?([0-9TZ.,:-]*)$/;

const norm = (u) => (u || "").replace(/^https?:\/\//, "").replace(/#.*$/, "").replace(/\/$/, "");

async function ask(msg) {
  try { return await chrome.runtime.sendNativeMessage(HOST, msg); }
  catch (e) { return null; }
}
const log = (msg) => ask({ cmd: "log", msg: `v${VERSION} ${msg}` });

// "2026-11-19T06-44-40.415Z" (as in the file names) → seconds since 1970.
function stampTime(s) {
  const t = Date.parse(s.replace(/T(\d\d)-(\d\d)-(\d\d)/, "T$1:$2:$3"));
  return isNaN(t) ? null : t / 1000;
}

// The note for one stamp: an exact match, or (notes written before the agent
// recorded stamps) the closest note written within 30 seconds after it.
function noteFor(stamp, notes) {
  const exact = notes.find((n) => n.stamp === stamp);
  if (exact) return exact;
  const t = stampTime(stamp);
  if (t == null) return null;
  const near = notes.filter((n) => !n.stamp && n.time - t > -5 && n.time - t < 30);
  near.sort((a, b) => Math.abs(a.time - t) - Math.abs(b.time - t));
  return near[0] || null;
}

function findCapturedTab(note, tabs) {
  const want = norm(note.url);
  let matches = want ? tabs.filter((t) => norm(t.url) === want) : [];
  if (!matches.length && note.windowTitle) {
    matches = tabs.filter((t) => t.title && note.windowTitle.startsWith(t.title + " - Google Chrome"));
  }
  // Prefer the tab that was showing when it was captured: active, most recently used.
  matches.sort((a, b) => (b.active - a.active) || ((b.lastAccessed || 0) - (a.lastAccessed || 0)));
  return matches[0];
}

// Groups that have asked for a tab are Claude sessions' groups. A captured tab
// already in one of them stays there: another session is using it.
async function sessionGroups() {
  try { return (await chrome.storage.session.get("groups")).groups || []; } catch (e) { return []; }
}
async function rememberGroup(id) {
  const g = await sessionGroups();
  if (!g.includes(id)) { try { await chrome.storage.session.set({ groups: [...g, id].slice(-50) }); } catch (e) {} }
}

async function handOff(groupId, stamps) {
  if (groupId == null || groupId === NONE) { await log("handoff asked from a tab outside any group"); return; }
  await rememberGroup(groupId);
  const res = await ask({ cmd: "pending" });
  const notes = (res && res.captures) || [];
  // No stamp given: the newest capture only.
  const wanted = stamps.length ? stamps.map((s) => noteFor(s, notes))
    : notes.slice().sort((a, b) => b.time - a.time).slice(0, 1);
  const tabs = await chrome.tabs.query({});
  const others = (await sessionGroups()).filter((g) => g !== groupId);
  const handled = [];
  let moved = 0;
  for (const note of wanted) {
    if (!note) { await log("no waiting capture matches a requested stamp"); continue; }
    const tab = findCapturedTab(note, tabs);
    if (!tab) { await log("no open tab matches a captured page"); continue; }
    if (tab.groupId !== groupId && others.includes(tab.groupId)) {
      await log("left a captured tab in another Claude session's group");
      continue;
    }
    if (tab.groupId !== groupId) { await chrome.tabs.group({ groupId, tabIds: [tab.id] }); moved++; }
    tab.groupId = groupId;
    handled.push(note.time);
  }
  if (handled.length) await ask({ cmd: "done", times: handled });
  await log(`handoff: ${moved} moved, ${handled.length}/${wanted.length} requested captures now in the group`);
}

// One request at a time, none dropped.
let chain = Promise.resolve();
chrome.tabs.onUpdated.addListener((id, info, tab) => {
  // A full load reports the URL with status "loading"; a same-page # change
  // reports only the URL. Both carry it in info.url.
  const m = MARKER.exec(info.url || "");
  if (!m) return;
  const stamps = (m[2] || "").split(",").map((s) => s.trim()).filter(Boolean);
  chain = chain.then(() => handOff(tab.groupId, stamps)).catch((e) => log("could not move a tab: " + e));
});
