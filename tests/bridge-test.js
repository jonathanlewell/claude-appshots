// Self-check for the Chrome bridge extension against a mocked Chrome. Run: tests/run.sh
// Group names are deliberately session-style ("⌛Fix login page"): the bridge
// must never depend on a group's name (Claude in Chrome 1.0.107 renames them).
const src = require("fs").readFileSync(__dirname + "/../chrome-extension/background.js", "utf8");
let onUpdated, grouped = [], done = [], queue = [], logs = [], store = {};
let tabs = [
  { id: 1, url: "https://github.com/x", title: "GitHub", active: false, groupId: -1, lastAccessed: 5 },
  { id: 2, url: "https://app.example.com/cal?a=1&b=2", title: "Calendar", active: true, groupId: -1, lastAccessed: 9 },
  { id: 3, url: "https://app.example.com/cal?a=1&b=2", title: "Calendar", active: false, groupId: -1, lastAccessed: 1 },
  { id: 4, url: "chrome://newtab/", title: "New tab", active: true, groupId: 77, lastAccessed: 10 },   // session A: "⌛Fix login page"
  { id: 5, url: "chrome://newtab/", title: "New tab", active: true, groupId: 66, lastAccessed: 10 },   // session B: "✅Weekly report"
  { id: 6, url: "https://mail.example/", title: "Mail", active: false, groupId: 88, lastAccessed: 3 }, // the user's own group "Work"
];
global.chrome = {
  tabGroups: { TAB_GROUP_ID_NONE: -1 },
  runtime: {
    getManifest: () => ({ version: "9.9" }),
    sendNativeMessage: async (h, m) => {
      if (m.cmd === "pending") return { captures: queue };
      if (m.cmd === "done") { done.push(...m.times); queue = queue.filter((c) => !m.times.includes(c.time)); }
      if (m.cmd === "log") logs.push(m.msg);
      return { ok: true };
    },
  },
  storage: { session: { get: async (k) => ({ [k]: store[k] }), set: async (o) => Object.assign(store, o) } },
  tabs: {
    onUpdated: { addListener: (f) => (onUpdated = f) },
    query: async () => tabs.map((t) => ({ ...t })),
    group: async ({ groupId, tabIds }) => { grouped.push(tabIds[0]); tabs.find((t) => t.id === tabIds[0]).groupId = groupId; },
  },
};
eval(src);
const tick = () => new Promise((r) => setTimeout(r, 30));
const request = (tabId, url, extra = {}) => { onUpdated(tabId, { url, ...extra }, { ...tabs.find((t) => t.id === tabId), url }); return tick(); };
const reset = () => { grouped = []; done = []; logs = []; };
const t0 = Date.parse("2026-11-19T06:44:14.747Z") / 1000;
let failed = 0;
const check = (name, ok) => { console.log((ok ? "ok   " : "FAIL ") + name); if (!ok) failed++; };
(async () => {
  queue = [{ time: t0 + 0.4, stamp: "2026-11-19T06-44-14.747Z", url: "app.example.com/cal?a=1&b=2", windowTitle: "Calendar - Google Chrome – J" },
           { time: t0 + 26, stamp: "2026-11-19T06-44-40.415Z", url: "nomatch.example", windowTitle: "GitHub - Google Chrome – J" }];
  await request(4, "https://example.com/", { status: "loading" });
  check("ordinary loads do nothing", grouped.length === 0 && queue.length === 2);
  await request(4, "https://example.com/#appshots-handoff=2026-11-19T06-44-40.415Z", { status: "loading" });
  check("moves only the requested capture", grouped.join() === "1" && queue.length === 1);
  check("falls back to the window title", tabs.find((t) => t.id === 1).groupId === 77);
  check("logs with the bridge version", logs.some((l) => l.startsWith("v9.9 handoff: 1 moved")));
  reset();
  await request(4, "https://example.com/#appshots-handoff=2026-11-19T06-44-14.747Z");
  check("same-page # change works too", grouped.join() === "2" && done.length === 1 && queue.length === 0);
  check("picks the active, most recent duplicate", !grouped.includes(3));

  reset();
  queue = [{ time: t0 + 1.2, url: "github.com/x", windowTitle: "" }]; // old app: no stamp in the note
  tabs.find((t) => t.id === 1).groupId = 88;
  await request(5, "https://example.com/#appshots-handoff=2026-11-19T06-44-14.747Z", { status: "loading" });
  check("a note without a stamp matches by time", grouped.join() === "1" && tabs.find((t) => t.id === 1).groupId === 66);
  check("takes a tab from the user's own group", queue.length === 0);

  reset();
  queue = [{ time: t0 + 100, stamp: "2026-11-19T06-45-54.000Z", url: "github.com/x", windowTitle: "" }];
  await request(4, "https://example.com/#appshots-handoff=2026-11-19T06-45-54.000Z", { status: "loading" });
  check("never takes a tab from another session's group", grouped.length === 0 && tabs.find((t) => t.id === 1).groupId === 66);
  check("and says so", logs.some((l) => l.includes("another Claude session's group")) && queue.length === 1);

  reset();
  queue = [{ time: t0 + 200, stamp: "2026-11-19T06-47-34.000Z", url: "mail.example", windowTitle: "" },
           { time: t0 + 300, stamp: "2026-11-19T06-49-14.000Z", url: "app.example.com/cal?a=1&b=2", windowTitle: "" }];
  tabs.find((t) => t.id === 2).groupId = -1;
  await request(4, "https://example.com/#appshots-handoff=2026-11-19T06-47-34.000Z,2026-11-19T06-49-14.000Z", { status: "loading" });
  check("several stamps move several tabs", grouped.join() === "6,2");

  reset();
  queue = [{ time: t0 + 400, stamp: "2026-11-19T06-50-54.000Z", url: "github.com/x", windowTitle: "" }];
  tabs.find((t) => t.id === 1).groupId = -1;
  await request(4, "https://example.com/#appshots-handoff=2026-11-19T07-00-00.000Z", { status: "loading" });
  check("a stamp with no waiting capture moves nothing", grouped.length === 0 && logs.some((l) => l.includes("no waiting capture")));
  await request(4, "https://example.com/#appshots-handoff", { status: "loading" });
  check("no stamp means the newest capture", grouped.join() === "1");

  reset();
  queue = [{ time: t0 + 500, stamp: "2026-11-19T06-52-34.000Z", url: "github.com/x", windowTitle: "" }];
  tabs.find((t) => t.id === 1).groupId = -1;
  tabs.push({ id: 9, url: "chrome://newtab/", groupId: -1 });
  await request(9, "https://example.com/#appshots-handoff=2026-11-19T06-52-34.000Z", { status: "loading" });
  check("a request from an ungrouped tab does nothing", grouped.length === 0 && queue.length === 1);
  await request(4, "https://evil.example/#appshots-handoff=2026-11-19T06-52-34.000Z", { status: "loading" });
  check("only example.com counts as a request", grouped.length === 0);
  process.exit(failed ? 1 : 0);
})();
