// Self-check for the Chrome bridge extension against a mocked Chrome. Run: tests/run.sh
const src = require("fs").readFileSync(__dirname + "/../chrome-extension/background.js", "utf8");
let on = {}, grouped = [], done = [], queue = [];
let tabs = [
  { id: 1, url: "https://github.com/x", title: "GitHub", active: false, groupId: -1, lastAccessed: 5 },
  { id: 2, url: "https://app.example.com/cal?a=1&b=2", title: "Calendar", active: true, groupId: -1, lastAccessed: 9 },
  { id: 3, url: "https://app.example.com/cal?a=1&b=2", title: "Calendar", active: false, groupId: -1, lastAccessed: 1 },
  { id: 4, url: "chrome://newtab/", title: "New tab", active: true, groupId: 77, lastAccessed: 10 },
];
global.chrome = {
  tabGroups: { TAB_GROUP_ID_NONE: -1, onCreated: { addListener: (f) => (on.group = f) } },
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
  on.updated(4, { status: "loading" }, { id: 4, groupId: 77 }); await tick();
  check("wakes when a grouped tab loads", grouped.join() === "1");
  grouped = []; queue = [{ time: 5, url: "github.com/x", windowTitle: "" }]; tabs.find((t) => t.id === 1).groupId = -1;
  on.updated(9, { status: "loading" }, { id: 9, groupId: -1 }); await tick();
  check("ignores ungrouped tabs loading", grouped.length === 0);
  queue = [{ time: 3, url: "gone.example", windowTitle: "Gone - Google Chrome" }];
  on.created({ groupId: 77 }); await tick();
  check("keeps a capture whose tab isn't open", queue.length === 1 && grouped.length === 0);
  process.exit(failed ? 1 : 0);
})();
