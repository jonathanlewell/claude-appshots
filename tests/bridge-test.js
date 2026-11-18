// Self-check for the Chrome bridge extension against a mocked Chrome. Run: tests/run.sh
const src = require("fs").readFileSync(__dirname + "/../chrome-extension/background.js", "utf8");
let on = {}, grouped = [], done = [], queue = [];
const titles = { 77: "Claude desktop app", 88: "Work" };
let tabs = [
  { id: 1, url: "https://github.com/x", title: "GitHub", active: false, groupId: -1, lastAccessed: 5 },
  { id: 2, url: "https://app.example.com/cal?a=1&b=2", title: "Calendar", active: true, groupId: -1, lastAccessed: 9 },
  { id: 3, url: "https://app.example.com/cal?a=1&b=2", title: "Calendar", active: false, groupId: -1, lastAccessed: 1 },
  { id: 4, url: "chrome://newtab/", title: "New tab", active: true, groupId: 77, lastAccessed: 10 },
];
global.chrome = {
  tabGroups: {
    TAB_GROUP_ID_NONE: -1,
    onCreated: { addListener: (f) => (on.group = f) },
    onUpdated: { addListener: (f) => (on.groupUpdated = f) },
    get: async (id) => ({ id, title: titles[id] ?? "" }),
  },
  tabs: {
    onCreated: { addListener: (f) => (on.created = f) },
    onUpdated: { addListener: (f) => (on.updated = f) },
    query: async () => tabs.map((t) => ({ ...t })),
    group: async ({ groupId, tabIds }) => { grouped.push(tabIds[0]); tabs.find((t) => t.id === tabIds[0]).groupId = groupId; },
  },
  runtime: {
    sendNativeMessage: async (h, m) => {
      if (m.cmd === "pending") return { captures: queue };
      if (m.cmd === "done") { done.push(...m.times); queue = queue.filter((c) => !m.times.includes(c.time)); }
      return { ok: true };
    },
  },
};
eval(src);
const tick = () => new Promise((r) => setTimeout(r, 20));
let failed = 0;
const check = (name, ok) => { console.log((ok ? "ok   " : "FAIL ") + name); if (!ok) failed++; };
(async () => {
  queue = [{ time: 1, url: "app.example.com/cal?a=1&b=2", windowTitle: "Calendar - Google Chrome – J" },
           { time: 2, url: "nomatch.example", windowTitle: "GitHub - Google Chrome – J" }];
  on.group({ id: 77 }); await tick();
  check("moves every waiting capture", grouped.join() === "2,1");
  check("picks the active, most recent duplicate", !grouped.includes(3));
  check("falls back to the window title", grouped.includes(1));
  check("marks them done", done.join() === "1,2" && queue.length === 0);
  grouped = []; on.updated(9, { groupId: 77 }, { groupId: 77 }); await tick();
  check("does nothing with an empty queue", grouped.length === 0);
  on.updated(9, { groupId: -1 }, { groupId: -1 }); on.created({ groupId: -1 }); await tick();
  check("ignores tabs leaving groups", grouped.length === 0);
  queue = [{ time: 4, url: "github.com/x", windowTitle: "" }]; tabs.find((t) => t.id === 1).groupId = -1;
  on.updated(4, { status: "loading", url: "https://shop.example/page" }, { id: 4, groupId: 77, url: "https://shop.example/page" }); await tick();
  check("ignores ordinary page loads in Claude's group", grouped.length === 0 && queue.length === 1);
  on.updated(4, { status: "loading", url: "https://example.com/" }, { id: 4, groupId: 77, url: "https://example.com/" }); await tick();
  check("wakes when a grouped tab loads a placeholder", grouped.join() === "1");
  grouped = []; queue = [{ time: 5, url: "github.com/x", windowTitle: "" }]; tabs.find((t) => t.id === 1).groupId = -1;
  on.updated(9, { status: "loading" }, { id: 9, groupId: -1 }); await tick();
  check("ignores ungrouped tabs loading", grouped.length === 0);
  queue = [{ time: 3, url: "gone.example", windowTitle: "Gone - Google Chrome" }];
  on.created({ groupId: 77 }); await tick();
  check("keeps a capture whose tab isn't open", queue.length === 1 && grouped.length === 0);
  queue = [{ time: 6, url: "github.com/x", windowTitle: "" }]; grouped = [];
  on.group({ id: 88 }); on.groupUpdated({ id: 88 }); await tick();
  check("leaves his own groups alone", grouped.length === 0 && queue.length === 1);
  titles[99] = ""; on.group({ id: 99 }); await tick();
  titles[99] = "Claude"; on.groupUpdated({ id: 99 }); await tick();
  check("waits for Claude's group to be named", grouped.join() === "1" && queue.length === 0);
  // Tab 1 now sits in Claude group 99 (another session). A new Claude group must not take it.
  titles[55] = "Claude"; grouped = []; done = [];
  queue = [{ time: 7, url: "github.com/x", windowTitle: "" }];
  on.group({ id: 55 }); await tick();
  check("leaves a tab in another Claude group", grouped.length === 0 && tabs.find((t) => t.id === 1).groupId === 99);
  check("and lets that note go", done.join() === "7" && queue.length === 0);
  // His own group isn't Claude's: a captured tab there still moves.
  queue = [{ time: 8, url: "app.example.com/cal?a=1&b=2", windowTitle: "" }]; tabs.find((t) => t.id === 2).groupId = 88;
  on.group({ id: 55 }); await tick();
  check("still takes a tab from his own group", grouped.join() === "2");
  process.exit(failed ? 1 : 0);
})();
