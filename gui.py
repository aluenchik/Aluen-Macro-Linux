#!/usr/bin/env python3
"""Aluen's Macro — GUI launcher"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import subprocess, threading, os, re, sys, webbrowser, json, urllib.request, signal
try:
    from PIL import Image, ImageTk
    _PIL = True
except ImportError:
    _PIL = False
try:
    from pynput import keyboard as _kb
    _PYNPUT = True
except ImportError:
    _PYNPUT = False

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
MACRO_SH      = os.path.join(SCRIPT_DIR, "macro.sh")
_CORE_MACRO   = os.path.join(SCRIPT_DIR, "modules", "core", "macro.sh")
CONFIG_FILE    = os.path.expanduser("~/.config/sols_rng/config.conf")
TEMPLATES_FILE = os.path.expanduser("~/.config/sols_rng/cal_templates.json")
STATS_FILE     = os.path.expanduser("~/.config/sols_rng/stats.json")
LOGO_PNG       = os.path.join(SCRIPT_DIR, "modules", "core", "logo.png")
LIVE_CONF      = "/tmp/sols_rng_live.conf"

_LIVE_KEYS = ("MERCHANT_ENABLED", "STRANGE_CONTROLLER_ENABLED", "BIOME_RANDOMIZER_ENABLED")

def _read_version() -> str:
    for path in (_CORE_MACRO, MACRO_SH):
        try:
            with open(path) as f:
                for line in f:
                    m = re.match(r'^VERSION="?([^"]+)"?', line.strip())
                    if m:
                        return m.group(1)
        except OSError:
            pass
    return "?"

VERSION = _read_version()

def _load_img(size: int):
    if not _PIL or not os.path.exists(LOGO_PNG):
        return None
    try:
        img = Image.open(LOGO_PNG).resize((size, size), Image.LANCZOS)
        return ImageTk.PhotoImage(img)
    except Exception:
        return None

# ── Item / biome lists ────────────────────────────────────────────────────────
MARI_ALL_ITEMS = [
    "Lucky Potion","Lucky Potion L","Lucky Potion XL",
    "Speed Potion","Speed Potion L","Speed Potion XL",
    "Mixed Potion",
    "Fortune Spoid I","Fortune Spoid II","Fortune Spoid III",
    "Gear A","Gear B",
    "Lucky Penny","Void Coin",
]
JESTER_ALL_ITEMS = [
    "Lucky Potion","Speed Potion","Random Potion Sack","Stella's Star",
    "Rune of Wind","Rune of Frost","Rune of Rainstorm","Rune of Hell",
    "Rune of Galaxy","Rune of Corruption","Rune of Nothing","Rune of Everything",
    "Strange Potion I","Strange Potion II","Stella's Candle","Oblivion Potion",
    "Potion of Bound","Merchant Tracker","Heavenly Potion",
]

ALL_BIOMES = [
    "WINDY","SNOWY","RAINY","SANDSTORM","HELL","HEAVEN",
    "STARFALL","CORRUPTION","NULL","GLITCHED","DREAMSPACE","CYBERSPACE",
    "SINGULARITY",
]

# ── Palette ───────────────────────────────────────────────────────────────────
BG     = "#1e1e2e"
BG2    = "#27273d"
BG3    = "#383854"
BORDER = "#45475a"
FG     = "#cdd6f4"
FG2    = "#6c7086"
ACCENT = "#89b4fa"
GREEN  = "#a6e3a1"
RED    = "#f38ba8"
YELLOW = "#f9e2af"

F      = ("Segoe UI", 10)
FB     = ("Segoe UI", 10, "bold")
FS     = ("Segoe UI", 9)
FT     = ("Segoe UI", 11, "bold")
MONO   = ("Monospace", 9)

# ── Config I/O ────────────────────────────────────────────────────────────────
def _raw():
    return open(CONFIG_FILE).read() if os.path.exists(CONFIG_FILE) else ""

def read_config():
    cfg, in_arr = {}, False
    for line in _raw().splitlines():
        s = line.strip()
        if re.match(r'^\w+=\($', s) or (re.match(r'^\w+=\(', s) and not s.endswith(')')):
            in_arr = True; continue
        if in_arr:
            if s == ')': in_arr = False
            continue
        m = re.match(r'^(\w+)=(.*)$', s)
        if m:
            cfg[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return cfg

def read_arrays():
    arrays = {}
    # Tolerate optional `declare -a` / `declare -ag` prefix — bash's
    # `declare -p` and some hand-edited configs use it. Without this,
    # `declare -ag PING_FOR=(...)` in the file silently fails to parse.
    for m in re.finditer(r'^(?:declare\s+(?:-[agA]+\s+)+)?(\w+)=\((.*?)\)',
                         _raw(), re.MULTILINE | re.DOTALL):
        arrays[m.group(1)] = re.findall(r'"([^"]*)"', m.group(2))
    return arrays

def save_scalar(key, value):
    content = _raw()
    # Escape regex backreference markers in value so \1, \g<...> etc. don't get
    # interpreted by re.sub.
    safe_value = re.sub(r'\\', r'\\\\', str(value))
    line = f'{key}="{safe_value}"'
    p1 = re.compile(rf'^{re.escape(key)}="[^"]*"', re.MULTILINE)
    p2 = re.compile(rf'^{re.escape(key)}=[^\n]*',  re.MULTILINE)
    if p1.search(content):   content = p1.sub(line, content)
    elif p2.search(content): content = p2.sub(line, content)
    else:                    content += f'\n{line}\n'
    open(CONFIG_FILE, "w").write(content)

def save_array(key, items):
    content = _raw()
    inner   = "\n".join(f'    "{i}"' for i in items)
    new_val = f'{key}=(\n{inner}\n)' if items else f'{key}=()'
    pat     = re.compile(rf'^{re.escape(key)}=\(.*?\)', re.MULTILINE | re.DOTALL)
    content = pat.sub(new_val, content) if pat.search(content) else content + f'\n{new_val}\n'
    open(CONFIG_FILE, "w").write(content)

# ── Scrollable frame ──────────────────────────────────────────────────────────
class ScrollFrame(tk.Frame):
    def __init__(self, parent, **kw):
        super().__init__(parent, bg=BG, **kw)
        self._c = tk.Canvas(self, bg=BG, highlightthickness=0, bd=0)
        sb = ttk.Scrollbar(self, orient="vertical", command=self._c.yview)
        self.inner = tk.Frame(self._c, bg=BG)
        self._win_id = self._c.create_window((0,0), window=self.inner, anchor="nw")
        self._c.configure(yscrollcommand=sb.set)
        self._c.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.inner.bind("<Configure>", lambda e: self._c.configure(scrollregion=self._c.bbox("all")))
        self._c.bind("<Configure>",    lambda e: self._c.itemconfig(self._win_id, width=e.width))
        for w in (self._c, self.inner, self):
            w.bind("<Button-4>", lambda e: self._c.yview_scroll(-1,"units"))
            w.bind("<Button-5>", lambda e: self._c.yview_scroll( 1,"units"))

    def bind_scroll(self, w):
        w.bind("<Button-4>", lambda e: self._c.yview_scroll(-1,"units"))
        w.bind("<Button-5>", lambda e: self._c.yview_scroll( 1,"units"))
        for c in w.winfo_children(): self.bind_scroll(c)

# ── Helpers ───────────────────────────────────────────────────────────────────
def _btn(parent, text, cmd, bg=None, fg=FG, font=F, **kw):
    return tk.Button(parent, text=text, command=cmd, bg=bg or BG3, fg=fg,
                     font=font, relief="flat", bd=0, highlightthickness=0,
                     activebackground=BORDER, activeforeground=FG,
                     cursor="hand2", **kw)

def _entry(parent, var, width=None, **kw):
    f = tk.Frame(parent, bg=BORDER, padx=1, pady=1)
    e = tk.Entry(f, textvariable=var, bg=BG2, fg=FG, insertbackground=FG,
                 relief="flat", bd=0, highlightthickness=0,
                 font=FS, **({"width": width} if width else {}), **kw)
    e.pack(fill="x" if not width else None)
    return f, e

def _check(parent, text, var, **kw):
    return tk.Checkbutton(parent, text=text, variable=var,
                          bg=BG, fg=FG, selectcolor=BG3,
                          activebackground=BG, activeforeground=FG,
                          highlightthickness=0, bd=0, relief="flat",
                          font=F, cursor="hand2", **kw)

def _checks(parent, text, var, **kw):
    """Small font checkbutton."""
    return tk.Checkbutton(parent, text=text, variable=var,
                          bg=BG, fg=FG, selectcolor=BG3,
                          activebackground=BG, activeforeground=FG,
                          highlightthickness=0, bd=0, relief="flat",
                          font=FS, cursor="hand2", **kw)

# ── App ───────────────────────────────────────────────────────────────────────
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Aluen's Macro")
        self.geometry("960x650")
        self.minsize(820, 620)
        self.configure(bg=BG)
        self.option_add("*tearOff", False)

        self._proc          = None
        self._running       = False
        self._cfg           = read_config()
        self._arrs          = read_arrays()
        self._vars          = {}
        self._avars         = {}
        self._inv           = set()
        self._custom_items  = []   # list of {"name": str, "cooldown": str}
        self._custom_items_frame = None
        self._biome_counts  = {}
        self._biome_labels  = {}

        self._logo_lg  = _load_img(100)
        _ico           = _load_img(32)
        if _ico: self.iconphoto(True, _ico)

        self._sudo_ok = False        # True if passwordless sudo is available
        self._sudo_marker = "/tmp/sols_rng_sudo_ok"
        self._sudo_refresh_id = None # after() handle for timestamp refresher
        self._sudo_refresh_interval = 240_000  # 4 min (timestamp default = 5 min)

        self._build()
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self.bind_all("<F1>", lambda e: self._start())
        self.bind_all("<F2>", lambda e: self._stop())
        self.bind_all("<Control-z>", lambda e: self._stop())
        threading.Thread(target=self._check_update, daemon=True).start()
        # Probe sudo capability off the UI thread (non-blocking). The banner
        # is shown once the probe finishes; user can choose to grant or skip.
        threading.Thread(target=self._probe_sudo, daemon=True).start()

        # Global hotkeys (work even when the GUI window is not focused, e.g.
        # while Roblox is in the foreground). pynput runs in its own thread
        # and dispatches back to the Tk main thread via after().
        self._kbd_listener = None
        if _PYNPUT:
            try:
                self._kbd_listener = _kb.Listener(
                    on_press=self._on_global_key,
                    daemon=True,
                )
                self._kbd_listener.start()
            except Exception as e:
                print(f"[GUI] Failed to start global keyboard listener: {e}")
                self._kbd_listener = None

    def _on_global_key(self, key):
        """Global hotkey handler. Runs on pynput's thread — marshal to Tk."""
        try:
            if key == _kb.Key.f1:
                self.after(0, self._start)
            elif key == _kb.Key.f2:
                self.after(0, self._stop)
        except Exception:
            pass

    # ── Layout ────────────────────────────────────────────────────────────────
    def _build(self):
        # ── Header ────────────────────────────────────────────────────────────
        hdr = tk.Frame(self, bg=BG2, pady=0)
        hdr.pack(fill="x")

        tk.Label(hdr, text="Aluen's Macro", font=("Segoe UI", 12, "bold"),
                 bg=BG2, fg=FG, pady=10).pack(side="left", padx=16)

        self._stop_btn = _btn(hdr, "■  Stop  [F2]", self._stop,
                              bg=BG3, padx=14, pady=6, state="disabled")
        self._stop_btn.pack(side="right", padx=(4,12))

        self._start_btn = _btn(hdr, "▶  Start  [F1]", self._start,
                               bg=GREEN, fg="#1e1e2e", font=FB, padx=14, pady=6)
        self._start_btn.pack(side="right", padx=4)

        self._status = tk.Label(hdr, text="● Stopped", font=FB,
                                bg=BG2, fg=RED)
        self._status.pack(side="right", padx=16)

        # thin separator
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")

        # ── Notebook ──────────────────────────────────────────────────────────
        st = ttk.Style(self)
        st.theme_use("default")
        st.configure("TNotebook",      background=BG,  borderwidth=0, tabmargins=0)
        st.configure("TNotebook.Tab",  background=BG2, foreground=FG2,
                     padding=[16, 7],  font=F,
                     focuscolor=BG,    borderwidth=0,  highlightthickness=0)
        st.map("TNotebook.Tab",
               background=[("selected", BG),   ("active", BG3)],
               foreground=[("selected", FG),   ("active", FG)],
               focuscolor=[("selected", BG),   ("active", BG3)])
        st.configure("TCombobox",
                     fieldbackground=BG2, background=BG3, foreground=FG,
                     selectbackground=BG3, selectforeground=FG,
                     arrowcolor=FG2, borderwidth=0, relief="flat")
        st.map("TCombobox",
               fieldbackground=[("readonly", BG2)],
               foreground=[("readonly", FG)],
               background=[("readonly", BG3), ("active", BG3)])
        self.option_add("*TCombobox*Listbox.background",   BG2)
        self.option_add("*TCombobox*Listbox.foreground",   FG)
        self.option_add("*TCombobox*Listbox.selectBackground", BG3)
        self.option_add("*TCombobox*Listbox.selectForeground", FG)
        self.option_add("*TCombobox*Listbox.font",         FS)
        st.configure("Vertical.TScrollbar", background=BG3, troughcolor=BG2,
                     arrowcolor=FG2, borderwidth=0, relief="flat")

        nb = ttk.Notebook(self)
        nb.pack(fill="both", expand=True)

        # Uniform tab widths — stretch to fill window
        st = ttk.Style()
        st.configure("TNotebook.Tab", width=20, anchor="center")

        t1 = tk.Frame(nb, bg=BG)
        t2 = tk.Frame(nb, bg=BG)
        t3 = tk.Frame(nb, bg=BG)
        t4 = tk.Frame(nb, bg=BG)
        t5 = tk.Frame(nb, bg=BG)
        t6 = tk.Frame(nb, bg=BG)
        nb.add(t1, text="Main")
        nb.add(t2, text="Settings")
        nb.add(t5, text="Webhooks")
        nb.add(t6, text="Calibration")
        nb.add(t4, text="Special Thanks")
        nb.add(t3, text="About")

        self._tab_main(t1)
        self._tab_settings(t2)
        self._tab_about(t3)
        self._tab_thanks(t4)
        self._tab_webhooks(t5)
        self._tab_calibration(t6)

        # ── Footer ────────────────────────────────────────────────────────────
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")
        foot = tk.Frame(self, bg=BG2, pady=4)
        foot.pack(fill="x")
        tk.Label(foot, text=f"v{VERSION}", font=("Segoe UI", 8),
                 bg=BG2, fg=FG2).pack(side="left", padx=12)

        # Sudo status (clickable to revoke)
        self._sudo_lbl = tk.Label(foot, text="", font=("Segoe UI", 8),
                                  bg=BG2, fg=FG2, cursor="hand2")
        self._sudo_lbl.pack(side="right", padx=12)
        self._sudo_lbl.bind("<Button-1>", lambda e: self._revoke_sudo())
        self._refresh_sudo_label()

    # ── Tab 1 ─────────────────────────────────────────────────────────────────
    def _tab_main(self, p):
        body = tk.Frame(p, bg=BG)
        body.pack(fill="both", expand=True, padx=14, pady=12)

        # Left panel — fixed width, no scroll (content fits in normal window sizes).
        left = tk.Frame(body, bg=BG, width=265)
        left.pack_propagate(False)   # freeze width BEFORE pack
        left.pack(side="left", fill="y", padx=(0,14))

        self._sec(left, "Modules")
        self._toggle_row(left, "Merchant",           "MERCHANT_ENABLED")
        self._toggle_row(left, "AntiAFK",            "ANTIAFK_ENABLED",            "ANTIAFK_INTERVAL",            300)
        self._toggle_row(left, "Strange Controller", "STRANGE_CONTROLLER_ENABLED", "STRANGE_CONTROLLER_INTERVAL", 1200)
        self._toggle_row(left, "Biome Randomizer",   "BIOME_RANDOMIZER_ENABLED",   "BIOME_RANDOMIZER_INTERVAL",   2100)

        _btn(left, "Save", self._save, bg=ACCENT, fg="#1e1e2e", font=FS,
             padx=14, pady=5).pack(anchor="w", pady=(14,0))

        # Session
        self._sec(left, "Session")
        session_row = tk.Frame(left, bg=BG)
        session_row.pack(fill="x")
        tk.Label(session_row, text="Time", font=FS, bg=BG, fg=FG2).pack(side="left")
        self._session_lbl = tk.Label(session_row, text="00:00:00", font=FS, bg=BG, fg=FG)
        self._session_lbl.pack(side="right")
        self._session_start = None
        self._session_timer_id = None

        biomes_row = tk.Frame(left, bg=BG)
        biomes_row.pack(fill="x", pady=(2, 0))
        tk.Label(biomes_row, text="Biomes", font=FS, bg=BG, fg=FG2).pack(side="left")
        self._session_biomes_lbl = tk.Label(biomes_row, text="0", font=FB, bg=BG, fg=ACCENT)
        self._session_biomes_lbl.pack(side="right")

        # Biome counter
        self._sec(left, "Biome Stats")
        self._biome_counts, self._total_biomes = self._load_stats()
        self._biome_session = {b: 0 for b in ALL_BIOMES}

        grid = tk.Frame(left, bg=BG)
        grid.pack(fill="x")
        self._biome_labels = {}          # biome → total_lbl
        SUPER_RARE = {"GLITCHED", "DREAMSPACE", "CYBERSPACE", "SINGULARITY"}
        for i, biome in enumerate(ALL_BIOMES):
            r, c = divmod(i, 2)
            cell = tk.Frame(grid, bg=BG)
            cell.grid(row=r, column=c, sticky="ew", padx=(0, 8), pady=1)
            grid.columnconfigure(c, weight=1)
            name_fg = ACCENT if biome in SUPER_RARE else FG2
            cnt_fg  = ACCENT if biome in SUPER_RARE else FG
            tk.Label(cell, text=biome, font=FS, bg=BG, fg=name_fg,
                     anchor="w").pack(side="left")
            lbl_t = tk.Label(cell, text=str(self._biome_counts.get(biome, 0)),
                             font=FS, bg=BG, fg=cnt_fg, anchor="e")
            lbl_t.pack(side="right")
            self._biome_labels[biome] = lbl_t

        # Separator + Total
        tk.Frame(left, bg=BORDER, height=1).pack(fill="x", pady=(6, 0))
        total_row = tk.Frame(left, bg=BG)
        total_row.pack(fill="x", pady=(4, 0))
        tk.Label(total_row, text="Total Biomes", font=FB, bg=BG, fg=FG2).pack(side="left")
        self._total_lbl = tk.Label(total_row, text=str(self._total_biomes),
                                   font=FB, bg=BG, fg=ACCENT)
        self._total_lbl.pack(side="right")

        # Right panel — log
        right = tk.Frame(body, bg=BG)
        right.pack(fill="both", expand=True)

        bar = tk.Frame(right, bg=BG)
        bar.pack(fill="x", pady=(0,6))
        tk.Label(bar, text="Log", font=FB, bg=BG, fg=FG).pack(side="left")
        _btn(bar, "Clear", self._clear_log, font=FS, padx=10, pady=2
             ).pack(side="right")

        log_frame = tk.Frame(right, bg=BORDER, padx=1, pady=1)
        log_frame.pack(fill="both", expand=True)
        self._log = scrolledtext.ScrolledText(
            log_frame, bg="#11111b", fg=FG, font=MONO,
            insertbackground=FG, relief="flat", bd=0,
            highlightthickness=0, state="disabled", wrap="word")
        self._log.pack(fill="both", expand=True)
        for tag, col in (("ok",GREEN),("warn",YELLOW),("error",RED),("info",FG)):
            self._log.tag_config(tag, foreground=col)

    # ── Tab 2 ─────────────────────────────────────────────────────────────────
    def _tab_settings(self, p):
        sf = ScrollFrame(p)
        sf.pack(fill="both", expand=True)
        q  = sf.inner
        px = dict(padx=18, pady=0)

        self._sec(q, "AntiAFK", **px)
        self._toggle_row(q, "Enabled", "ANTIAFK_ENABLED", "ANTIAFK_INTERVAL", 300, **px)

        self._sec(q, "Merchant", **px)
        self._toggle_row(q, "Enabled", "MERCHANT_ENABLED", "MERCHANT_INTERVAL", 300, **px)
        self._sec2(q, "Auto-buy — Mari",   **px); self._item_cbs(q, "MARI_BUY_ITEMS",   "MARI_MAX_ITEMS",   MARI_ALL_ITEMS,   **px)
        self._sec2(q, "Auto-buy — Jester", **px); self._item_cbs(q, "JESTER_BUY_ITEMS", "JESTER_MAX_ITEMS", JESTER_ALL_ITEMS, **px)

        _btn(q, "Save merchant settings", self._save,
             bg=ACCENT, fg="#1e1e2e", font=FS, padx=12, pady=5
             ).pack(anchor="w", padx=18, pady=(8, 4))

        self._sec(q, "Using Items", **px)
        self._toggle_row(q, "Strange Controller", "STRANGE_CONTROLLER_ENABLED", "STRANGE_CONTROLLER_INTERVAL", 1200, **px)
        self._toggle_row(q, "Biome Randomizer",   "BIOME_RANDOMIZER_ENABLED",   "BIOME_RANDOMIZER_INTERVAL",   2100, **px)

        self._sec2(q, "Custom items", **px)
        self._custom_items = [
            {"name": e.split("|")[0], "cooldown": e.split("|")[1]}
            for e in self._arrs.get("CUSTOM_USE_ITEMS", []) if "|" in e
        ]
        self._custom_items_frame = tk.Frame(q, bg=BG)
        self._custom_items_frame.pack(fill="x", padx=18, pady=(0, 4))
        self._rebuild_custom_items()

        add_row = tk.Frame(q, bg=BG)
        add_row.pack(fill="x", padx=18, pady=(4, 0))
        self._new_item_name = tk.StringVar()
        self._new_item_cd   = tk.StringVar(value="300")
        tk.Label(add_row, text="Name:", font=FS, bg=BG, fg=FG2).pack(side="left", padx=(0,4))
        nf, _ = _entry(add_row, self._new_item_name, width=22)
        nf.pack(side="left", padx=(0, 8))
        tk.Label(add_row, text="every", font=FS, bg=BG, fg=FG2).pack(side="left", padx=(0,4))
        cf, _ = _entry(add_row, self._new_item_cd, width=6)
        cf.pack(side="left", padx=(0,4))
        tk.Label(add_row, text="s", font=FS, bg=BG, fg=FG2).pack(side="left", padx=(0,8))
        _btn(add_row, "+ Add", self._add_custom_item,
             bg=GREEN, fg="#1e1e2e", font=FS, padx=10, pady=2).pack(side="left")

        self._sec(q, "Biome Notifications", **px)
        self._sec2(q, "Mute (checked = won't notify)", **px)
        # Biomes that always ping → never muteable. Kept in sync with
        # the bash core's `PING_FOR` defaults in modules/core/settings.sh.
        # If the user's config still has an older PING_FOR (missing
        # SINGULARITY), we union with the full default so legacy configs
        # still hide these from the mute grid.
        ping_for = {b.upper() for b in self._arrs.get("PING_FOR", [])}
        ping_default = {"GLITCHED", "DREAMSPACE", "CYBERSPACE", "SINGULARITY"}
        self._biome_cbs(q, "NOTIFY_ONLY", invert=True,
                        exclude=ping_for | ping_default, **px)
        self._sec2(q, "Ping for biomes", **px)
        self._biome_cbs_ro(q, ping_for | ping_default, **px)

        _btn(q, "  Save all settings  ", self._save,
             bg=ACCENT, fg="#1e1e2e", font=FB, padx=14, pady=7
             ).pack(anchor="w", padx=18, pady=18)

        sf.bind_scroll(q)

    # ── Tab Webhooks ──────────────────────────────────────────────────────────
    def _tab_calibration(self, p):
        q  = tk.Frame(p, bg=BG)
        q.pack(fill="both", expand=True)
        px = dict(padx=18, pady=0)

        self._sec(q, "Calibration", **px)
        self._tpl_bar(q, **px)
        for lbl, kx, ky in [
            ("Inventory button",  "MERCHANT_CAL_INV_X",       "MERCHANT_CAL_INV_Y"),
            ("Items tab",         "MERCHANT_CAL_ITEMS_TAB_X",  "MERCHANT_CAL_ITEMS_TAB_Y"),
            ("Search box",        "MERCHANT_CAL_SEARCH_X",     "MERCHANT_CAL_SEARCH_Y"),
            ("Item slot",         "MERCHANT_CAL_ITEM_X",       "MERCHANT_CAL_ITEM_Y"),
            ("Use button",        "MERCHANT_CAL_USE_X",        "MERCHANT_CAL_USE_Y"),
            ("Dialogue button",   "MERCHANT_CAL_DIALOG_X",     "MERCHANT_CAL_DIALOG_Y"),
            ("Shop button",       "MERCHANT_CAL_SHOP_X",       "MERCHANT_CAL_SHOP_Y"),
            ("Purchase button",   "MERCHANT_CAL_BUY_X",        "MERCHANT_CAL_BUY_Y"),
            ("Set to max button", "MERCHANT_CAL_MAX_X",        "MERCHANT_CAL_MAX_Y"),
        ]:
            self._coord_row(q, lbl, kx, ky, **px)

        _btn(q, "Save calibration", self._save,
             bg=ACCENT, fg="#1e1e2e", font=FS, padx=12, pady=5
             ).pack(anchor="w", padx=18, pady=(8, 4))

    def _tab_webhooks(self, p):
        f = tk.Frame(p, bg=BG)
        f.pack(fill="both", expand=True, padx=24, pady=20)

        self._sec(f, "Discord Webhooks")

        # Webhook URL
        tk.Label(f, text="Webhook URL", font=FS, bg=BG, fg=FG2).pack(anchor="w")
        wh_row = tk.Frame(f, bg=BG)
        wh_row.pack(fill="x", pady=(2, 10))
        if "WEBHOOK_URL" not in self._vars:
            self._vars["WEBHOOK_URL"] = tk.StringVar(value=self._cfg.get("WEBHOOK_URL", ""))
        wh_var = self._vars["WEBHOOK_URL"]
        wh_frame = tk.Frame(wh_row, bg=BORDER, padx=1, pady=1)
        wh_frame.pack(side="left", fill="x", expand=True, padx=(0, 6))
        self._wh_entry = tk.Entry(wh_frame, textvariable=wh_var, bg=BG2, fg=FG,
                                  insertbackground=FG, relief="flat", bd=0,
                                  highlightthickness=0, font=FS, show="•")
        self._wh_entry.pack(fill="x")
        _btn(wh_row, "Show", lambda: self._toggle_secret(self._wh_entry, self._wh_show_btn),
             font=FS, padx=8, pady=2).pack(side="left")
        self._wh_show_btn = wh_row.winfo_children()[-1]

        # Server Invite
        tk.Label(f, text="Server Invite (VIP link)", font=FS, bg=BG, fg=FG2).pack(anchor="w")
        inv_row = tk.Frame(f, bg=BG)
        inv_row.pack(fill="x", pady=(2, 10))
        if "SERVER_INVITE" not in self._vars:
            self._vars["SERVER_INVITE"] = tk.StringVar(value=self._cfg.get("SERVER_INVITE", ""))
        inv_var = self._vars["SERVER_INVITE"]
        inv_frame = tk.Frame(inv_row, bg=BORDER, padx=1, pady=1)
        inv_frame.pack(side="left", fill="x", expand=True, padx=(0, 6))
        self._inv_entry = tk.Entry(inv_frame, textvariable=inv_var, bg=BG2, fg=FG,
                                   insertbackground=FG, relief="flat", bd=0,
                                   highlightthickness=0, font=FS, show="•")
        self._inv_entry.pack(fill="x")
        _btn(inv_row, "Show", lambda: self._toggle_secret(self._inv_entry, self._inv_show_btn),
             font=FS, padx=8, pady=2).pack(side="left")
        self._inv_show_btn = inv_row.winfo_children()[-1]

        btn_row = tk.Frame(f, bg=BG)
        btn_row.pack(anchor="w", pady=(16, 0))
        _btn(btn_row, "Save", self._save, bg=ACCENT, fg="#1e1e2e", font=FB,
             padx=14, pady=7).pack(side="left", padx=(0, 8))
        _btn(btn_row, "Test Webhook", self._test_webhook, font=FS,
             padx=12, pady=7).pack(side="left")

    def _test_webhook(self):
        url = self._vars.get("WEBHOOK_URL", tk.StringVar()).get().strip()
        if not url:
            messagebox.showwarning("Test Webhook", "Webhook URL is empty.")
            return
        def _send():
            try:
                import datetime
                has_logo = os.path.isfile(LOGO_PNG)
                embed = {
                    "title": "Macro Status",
                    "description": "# Webhook test!",
                    "color": 5763719,
                    "footer": {"text": f"Aluen's Macro v{VERSION}"},
                    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
                if has_logo:
                    embed["thumbnail"] = {"url": "attachment://logo.png"}
                    embed["footer"]["icon_url"] = "attachment://logo.png"
                payload = json.dumps({"embeds": [embed]})

                if has_logo:
                    result = subprocess.run(
                        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                         "-X", "POST",
                         "-F", f"payload_json={payload}",
                         "-F", f"files[0]=@{LOGO_PNG};filename=logo.png",
                         url],
                        capture_output=True, text=True, timeout=10
                    )
                else:
                    result = subprocess.run(
                        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                         "-X", "POST", "-H", "Content-Type: application/json",
                         "-d", payload, url],
                        capture_output=True, text=True, timeout=10
                    )
                code = result.stdout.strip()
            except Exception as ex:
                code = str(ex)
            ok = code in ("200", "204")
            self.after(0, lambda: messagebox.showinfo("Test Webhook", "Webhook OK!") if ok
                else messagebox.showerror("Test Webhook", f"Failed: HTTP {code}"))
        threading.Thread(target=_send, daemon=True).start()

    def _toggle_secret(self, entry, btn):
        if entry.cget("show") == "•":
            entry.configure(show="")
            btn.configure(text="Hide")
        else:
            entry.configure(show="•")
            btn.configure(text="Show")

    # ── Tab 3 ─────────────────────────────────────────────────────────────────
    def _tab_about(self, p):
        f = tk.Frame(p, bg=BG)
        f.pack(expand=True)

        if self._logo_lg:
            tk.Label(f, image=self._logo_lg, bg=BG).pack(pady=(30,10))

        tk.Label(f, text="Aluen's Macro", font=("Segoe UI", 20, "bold"),
                 bg=BG, fg=FG).pack()
        tk.Label(f, text="Linux biome detector", font=("Segoe UI", 10),
                 bg=BG, fg=FG2).pack(pady=(2,0))

        tk.Frame(f, bg=BORDER, height=1, width=280).pack(pady=20)

        _urls = {
            "Source":  "https://github.com/aluenchik/Aluen-Macro-Linux",
            "Discord": "https://discord.gg/nQFyFsRPaG",
        }
        for lbl, val, is_link in [
            ("Author",  "Aluen",                                    False),
            ("Platform","Linux",                                     False),
            ("Game",    "Sol's RNG",                                 False),
            ("Source",  "github.com/aluenchik/Aluen-Macro-Linux",   True),
            ("Discord", "discord.gg/nQFyFsRPaG",                    True),
        ]:
            row = tk.Frame(f, bg=BG)
            row.pack(fill="x", pady=2)
            tk.Label(row, text=f"{lbl}:", font=("Segoe UI", 9, "bold"),
                     bg=BG, fg=FG2, width=10, anchor="e").pack(side="left", padx=(60,8))
            if is_link:
                link = tk.Label(row, text=val, font=("Segoe UI", 9, "underline"),
                                bg=BG, fg=ACCENT, anchor="w", cursor="hand2")
                link.pack(side="left")
                link.bind("<Button-1>", lambda e, u=_urls[lbl]: webbrowser.open(u))
            else:
                tk.Label(row, text=val, font=("Segoe UI", 9),
                         bg=BG, fg=FG, anchor="w").pack(side="left")

    # ── Tab 4 ─────────────────────────────────────────────────────────────────
    def _tab_thanks(self, p):
        f = tk.Frame(p, bg=BG)
        f.pack(expand=True)

        tk.Label(f, text="Special Thanks", font=("Segoe UI", 16, "bold"),
                 bg=BG, fg=FG).pack(pady=(40, 4))
        tk.Label(f, text="people who made this project possible",
                 font=("Segoe UI", 9), bg=BG, fg=FG2).pack()

        tk.Frame(f, bg=BORDER, height=1, width=300).pack(pady=20)

        # ── Donate block ──────────────────────────────────────────────────────
        _donate_url = "https://www.roblox.com/games/1314228996/hepimouse1s-Place#!/store"
        donate_box = tk.Frame(f, bg=BG2, padx=20, pady=12)
        donate_box.pack(pady=(0, 16), ipadx=10)
        tk.Label(donate_box, text="Support the project",
                 font=("Segoe UI", 10, "bold"), bg=BG2, fg=FG).pack()
        tk.Label(donate_box, text="Buy items in the Roblox store",
                 font=("Segoe UI", 8), bg=BG2, fg=FG2).pack(pady=(2, 8))
        link = tk.Label(donate_box, text="Open store →",
                        font=("Segoe UI", 9, "underline"),
                        bg=BG2, fg=ACCENT, cursor="hand2")
        link.pack()
        link.bind("<Button-1>", lambda e: webbrowser.open(_donate_url))


    # ── Widget factories ──────────────────────────────────────────────────────
    def _sec(self, p, title, padx=0, pady=0):
        tk.Label(p, text=title, font=FT, bg=BG, fg=ACCENT
                 ).pack(anchor="w", padx=padx, pady=(16,1))
        tk.Frame(p, bg=ACCENT, height=1).pack(fill="x", padx=padx, pady=(0,8))

    def _sec2(self, p, title, padx=0, pady=0):
        tk.Label(p, text=title, font=("Segoe UI", 9, "bold"),
                 bg=BG, fg=FG2).pack(anchor="w", padx=padx, pady=(10,3))

    def _field(self, p, label, key, padx=0, pady=0):
        tk.Label(p, text=label, font=FS, bg=BG, fg=FG2
                 ).pack(anchor="w", padx=padx)
        if key in self._vars:
            v = self._vars[key]
        else:
            v = tk.StringVar(value=self._cfg.get(key, ""))
            self._vars[key] = v
        frame, _ = _entry(p, v)
        frame.pack(fill="x", padx=padx, pady=(2,8))

    def _toggle_row(self, p, label, bk, ik=None, default=None, padx=0, pady=0):
        row = tk.Frame(p, bg=BG)
        row.pack(fill="x", padx=padx, pady=3)
        if bk in self._vars:
            bv = self._vars[bk]
        else:
            bv = tk.BooleanVar(value=self._cfg.get(bk,"false").lower()=="true")
            self._vars[bk] = bv
        _check(row, label, bv).pack(side="left")
        if not ik and default is None:
            tk.Label(row, text="configure in Settings", font=("Segoe UI", 8),
                     bg=BG, fg=FG2).pack(side="right", padx=(0,4))
        if ik:
            if ik in self._vars:
                iv = self._vars[ik]
            else:
                iv = tk.StringVar(value=self._cfg.get(ik, str(default or "")))
                self._vars[ik] = iv
            tk.Label(row, text="s", font=FS, bg=BG, fg=FG2).pack(side="right", padx=(0,4))
            frame, _ = _entry(row, iv, width=6)
            frame.pack(side="right", padx=(0,4))
            tk.Label(row, text="every", font=FS, bg=BG, fg=FG2).pack(side="right", padx=(0,4))

    def _coord_row(self, p, label, kx, ky, padx=0, pady=0):
        row = tk.Frame(p, bg=BG)
        row.pack(fill="x", padx=padx, pady=2)
        tk.Label(row, text=label, font=FS, bg=BG, fg=FG,
                 width=20, anchor="w").pack(side="left")
        vx = tk.StringVar(value=self._cfg.get(kx, "0"))
        vy = tk.StringVar(value=self._cfg.get(ky, "0"))
        self._vars[kx] = vx
        self._vars[ky] = vy
        for v, lbl in ((vx,"X"),(vy,"Y")):
            tk.Label(row, text=lbl, font=FS, bg=BG, fg=FG2).pack(side="left", padx=(10,3))
            frame, _ = _entry(row, v, width=6)
            frame.pack(side="left")
        _btn(row, "Pick", lambda vx=vx, vy=vy: self._pick_coord(vx, vy),
             font=("Segoe UI", 8), padx=6, pady=1
             ).pack(side="left", padx=(8, 0))
        _btn(row, "Reset", lambda vx=vx, vy=vy, kx=kx, ky=ky: (
                 vx.set(self._DEFAULT_TPL.get(kx, "0")),
                 vy.set(self._DEFAULT_TPL.get(ky, "0"))),
             font=("Segoe UI", 8), padx=6, pady=1
             ).pack(side="left", padx=(4, 0))

    def _pick_coord(self, vx, vy):
        """Show a fullscreen overlay; on click fill vx/vy with screen coords."""
        overlay = tk.Toplevel(self)
        overlay.attributes("-fullscreen", True)
        overlay.attributes("-alpha", 0.35)
        overlay.configure(bg="#000000")
        overlay.attributes("-topmost", True)
        overlay.config(cursor="crosshair")

        tk.Label(overlay, text="Click anywhere to set the coordinate",
                 font=("Segoe UI", 14), bg="#000000", fg="#ffffff").place(
                 relx=0.5, rely=0.5, anchor="center")

        def _pick(event):
            vx.set(str(event.x_root))
            vy.set(str(event.y_root))
            overlay.destroy()

        def _cancel(event=None):
            overlay.destroy()

        overlay.bind("<Button-1>", _pick)
        overlay.bind("<Escape>", _cancel)
        overlay.focus_force()

    # ── Calibration templates ─────────────────────────────────────────────────
    _CAL_KEYS = [
        "MERCHANT_CAL_INV_X","MERCHANT_CAL_INV_Y",
        "MERCHANT_CAL_ITEMS_TAB_X","MERCHANT_CAL_ITEMS_TAB_Y",
        "MERCHANT_CAL_SEARCH_X","MERCHANT_CAL_SEARCH_Y",
        "MERCHANT_CAL_ITEM_X","MERCHANT_CAL_ITEM_Y",
        "MERCHANT_CAL_USE_X","MERCHANT_CAL_USE_Y",
        "MERCHANT_CAL_DIALOG_X","MERCHANT_CAL_DIALOG_Y",
        "MERCHANT_CAL_SHOP_X","MERCHANT_CAL_SHOP_Y",
        "MERCHANT_CAL_BUY_X","MERCHANT_CAL_BUY_Y",
        "MERCHANT_CAL_MAX_X","MERCHANT_CAL_MAX_Y",
    ]

    _DEFAULT_TPL = {
        "MERCHANT_CAL_INV_X":        "35",
        "MERCHANT_CAL_INV_Y":        "510",
        "MERCHANT_CAL_ITEMS_TAB_X":  "1247",
        "MERCHANT_CAL_ITEMS_TAB_Y":  "340",
        "MERCHANT_CAL_SEARCH_X":     "960",
        "MERCHANT_CAL_SEARCH_Y":     "368",
        "MERCHANT_CAL_ITEM_X":       "846",
        "MERCHANT_CAL_ITEM_Y":       "463",
        "MERCHANT_CAL_USE_X":        "683",
        "MERCHANT_CAL_USE_Y":        "574",
        "MERCHANT_CAL_DIALOG_X":     "773",
        "MERCHANT_CAL_DIALOG_Y":     "849",
        "MERCHANT_CAL_SHOP_X":       "589",
        "MERCHANT_CAL_SHOP_Y":       "936",
        "MERCHANT_CAL_BUY_X":        "1041",
        "MERCHANT_CAL_BUY_Y":        "648",
        "MERCHANT_CAL_MAX_X":        "1300",
        "MERCHANT_CAL_MAX_Y":        "614",
    }

    def _tpl_load(self):
        data = {"1920x1080": self._DEFAULT_TPL}
        if os.path.exists(TEMPLATES_FILE):
            try:
                saved = json.loads(open(TEMPLATES_FILE).read())
                data.update(saved)
            except Exception:
                pass
        return data

    def _tpl_save_file(self, data):
        os.makedirs(os.path.dirname(TEMPLATES_FILE), exist_ok=True)
        open(TEMPLATES_FILE, "w").write(json.dumps(data, indent=2))

    def _tpl_bar(self, p, padx=0, pady=0):
        row = tk.Frame(p, bg=BG)
        row.pack(fill="x", padx=padx, pady=(0, 8))

        tpls = self._tpl_load()
        names = list(tpls.keys())
        self._tpl_var = tk.StringVar(value=names[0] if names else "")
        self._tpl_cb  = ttk.Combobox(row, textvariable=self._tpl_var,
                                      values=names, width=18, font=FS)
        self._tpl_cb.pack(side="left", padx=(0, 6))

        _btn(row, "Load",   self._tpl_apply,  font=FS, padx=8,  pady=2).pack(side="left", padx=(0,4))
        _btn(row, "Save",   self._tpl_save,   font=FS, padx=8,  pady=2).pack(side="left", padx=(0,4))
        _btn(row, "Delete", self._tpl_delete, font=FS, padx=8,  pady=2).pack(side="left")

    def _tpl_apply(self):
        name = self._tpl_var.get().strip()
        if not name:
            return
        tpls = self._tpl_load()
        if name not in tpls:
            return
        for k, v in tpls[name].items():
            if k in self._vars:
                self._vars[k].set(v)
        self._log_line(f"[Templates] Loaded: {name}", "ok")

    def _tpl_save(self):
        name = self._tpl_var.get().strip()
        if not name:
            messagebox.showwarning("Save template", "Enter a template name first.")
            return
        if name == "1920x1080":
            messagebox.showinfo("Save template", "Cannot overwrite the default template.")
            return
        tpls = self._tpl_load()
        tpls[name] = {k: self._vars[k].get() for k in self._CAL_KEYS if k in self._vars}
        self._tpl_save_file(tpls)
        names = list(tpls.keys())
        self._tpl_cb["values"] = names
        self._tpl_var.set(name)
        self._log_line(f"[Templates] Saved: {name}", "ok")

    def _tpl_delete(self):
        name = self._tpl_var.get()
        if not name:
            return
        if name == "1920x1080":
            messagebox.showinfo("Delete template", "Cannot delete the default template.")
            return
        if not messagebox.askyesno("Delete template", f'Delete "{name}"?'):
            return
        tpls = self._tpl_load()
        tpls.pop(name, None)
        self._tpl_save_file(tpls)
        names = list(tpls.keys())
        self._tpl_cb["values"] = names
        self._tpl_var.set(names[0] if names else "")
        self._log_line(f"[Templates] Deleted: {name}", "warn")

    _ITEM_COLORS = {
        "Lucky Potion":       "#72BF5E",
        "Lucky Potion L":     "#72BF5E",
        "Lucky Potion XL":    "#72BF5E",
        "Speed Potion":       "#6E99CA",
        "Speed Potion L":     "#6E99CA",
        "Speed Potion XL":    "#6E99CA",
        "Mixed Potion":       "#33FFDA",
        "Fortune Spoid I":    "#7CE364",
        "Fortune Spoid II":   "#7CE364",
        "Fortune Spoid III":  "#7CE364",
        "Gear A":             "#585b70",
        "Gear B":             "#585b70",
        "Lucky Penny":        "#72BF5E",
        "Void Coin":          "#A66CFF",
        "Random Potion Sack": "#FFFFFF",
        "Stella's Star":      "#E0FFA6",
        "Rune of Wind":       "#7CD4AC",
        "Rune of Frost":      "#B3FFFA",
        "Rune of Rainstorm":  "#4E64B7",
        "Rune of Hell":       "#BD594A",
        "Rune of Galaxy":     "#825CFF",
        "Rune of Corruption": "#9A7AC5",
        "Rune of Nothing":    "#585858",
        "Rune of Everything": "#F7F7F7",
        "Strange Potion I":   "#484095",
        "Strange Potion II":  "#484095",
        "Stella's Candle":    "#977DC4",
        "Oblivion Potion":    "#4F4386",
        "Potion of Bound":    "#4481EC",
        "Merchant Tracker":   "#615E5E",
        "Heavenly Potion":    "#FF98DC",
    }

    def _item_cbs(self, p, key, max_key, items, padx=0, **_):
        sel     = {s.lower() for s in self._arrs.get(key,     [])}
        sel_max = {s.lower() for s in self._arrs.get(max_key, [])}
        self._avars[key]     = {}
        self._avars[max_key] = {}

        outer = tk.Frame(p, bg=BG2, padx=6, pady=6)
        outer.pack(fill="x", padx=padx, pady=(0, 8))

        COLS = 2
        n_rows = -(-len(items) // COLS)  # ceil division
        for i, item in enumerate(items):
            v     = tk.BooleanVar(value=item.lower() in sel)
            v_max = tk.BooleanVar(value=item.lower() in sel_max)
            self._avars[key][item]     = v
            self._avars[max_key][item] = v_max
            color = self._ITEM_COLORS.get(item, FG)
            r, c = i % n_rows, i // n_rows
            outer.columnconfigure(c, weight=1)

            SEL_BG = "#313244"
            cell = tk.Frame(outer, bg=SEL_BG if v.get() else BG3, padx=6, pady=4)
            cell.grid(row=r, column=c, sticky="ew", padx=3, pady=2)

            cb = tk.Checkbutton(cell, text=item, variable=v,
                                bg=cell.cget("bg"), fg=color,
                                selectcolor=BG2,
                                activebackground=cell.cget("bg"),
                                activeforeground=color,
                                highlightthickness=0, bd=0, relief="flat",
                                font=FS, cursor="hand2", anchor="w")
            cb.pack(side="left", fill="x", expand=True)

            cb_max = tk.Checkbutton(cell, text="max", variable=v_max,
                                    bg=cell.cget("bg"), fg=FG2,
                                    selectcolor=BG2,
                                    activebackground=cell.cget("bg"),
                                    activeforeground=ACCENT,
                                    highlightthickness=0, bd=0, relief="flat",
                                    font=("Segoe UI", 8), cursor="hand2")
            cb_max.pack(side="right")

            def _upd(*_, var=v, frm=cell, w=cb, wm=cb_max):
                bg = SEL_BG if var.get() else BG3
                frm.configure(bg=bg)
                w.configure(bg=bg, activebackground=bg)
                wm.configure(bg=bg, activebackground=bg)

            v.trace_add("write", _upd)

    def _biome_cbs_ro(self, p, checked, padx=0, pady=0):
        grid = tk.Frame(p, bg=BG)
        grid.pack(fill="x", padx=padx, pady=(0,6))
        for i, b in enumerate(sorted(checked)):
            v = tk.BooleanVar(value=True)
            cb = tk.Checkbutton(grid, text=b, variable=v, bg=BG,
                                fg=FG2, selectcolor=BG3, activebackground=BG,
                                activeforeground=FG2, highlightthickness=0, bd=0, font=FS)
            cb.grid(row=0, column=i, sticky="w", padx=4)
            cb.bind("<Button-1>", lambda e: "break")  # read-only

    def _biome_cbs(self, p, key, invert=False, padx=0, pady=0, exclude=None):
        sel = {s.upper() for s in self._arrs.get(key,[])}
        if invert: self._inv.add(key)
        self._avars[key] = {}
        exclude = {b.upper() for b in (exclude or [])}
        grid = tk.Frame(p, bg=BG)
        grid.pack(fill="x", padx=padx, pady=(0,6))
        for i, biome in enumerate(ALL_BIOMES):
            if biome in exclude:
                continue
            checked = (bool(sel) and biome not in sel) if invert else (biome in sel)
            v = tk.BooleanVar(value=checked)
            self._avars[key][biome] = v
            r, c = divmod(i, 4)
            _checks(grid, biome, v).grid(row=r, column=c, sticky="w", padx=4, pady=1)

    # ── Custom items ──────────────────────────────────────────────────────────
    def _rebuild_custom_items(self):
        if not self._custom_items_frame:
            return
        for w in self._custom_items_frame.winfo_children():
            w.destroy()
        if not self._custom_items:
            tk.Label(self._custom_items_frame, text="No custom items",
                     font=FS, bg=BG, fg=FG2).pack(anchor="w", padx=4, pady=2)
            return
        for i, item in enumerate(self._custom_items):
            row = tk.Frame(self._custom_items_frame, bg=BG3, padx=6, pady=4)
            row.pack(fill="x", pady=2)
            color = self._ITEM_COLORS.get(item["name"], FG)
            tk.Label(row, text=item["name"], font=FS, bg=BG3, fg=color,
                     anchor="w").pack(side="left", expand=True, fill="x")
            tk.Label(row, text=f"every {item['cooldown']}s", font=FS,
                     bg=BG3, fg=FG2).pack(side="left", padx=8)
            _btn(row, "✕", lambda i=i: self._del_custom_item(i),
                 bg=BG3, fg=RED, font=FS, padx=6, pady=1).pack(side="right")

    def _add_custom_item(self):
        name = self._new_item_name.get().strip()
        cd   = self._new_item_cd.get().strip()
        if not name:
            return
        if not cd.isdigit() or int(cd) < 1:
            cd = "300"
        self._custom_items.append({"name": name, "cooldown": cd})
        self._new_item_name.set("")
        self._rebuild_custom_items()

    def _del_custom_item(self, i):
        self._custom_items.pop(i)
        self._rebuild_custom_items()

    # ── Actions ───────────────────────────────────────────────────────────────
    def _save(self):
        bools = {"ANTIAFK_ENABLED",
                 "MERCHANT_ENABLED",
                 "STRANGE_CONTROLLER_ENABLED", "BIOME_RANDOMIZER_ENABLED"}
        for k, v in self._vars.items():
            val = v.get()
            save_scalar(k, ("true" if val else "false") if k in bools else str(val))
        for k, ivars in self._avars.items():
            chosen = [i for i,v in ivars.items() if not v.get()] if k in self._inv \
                else [i for i,v in ivars.items() if v.get()]
            save_array(k, chosen)
        save_array("CUSTOM_USE_ITEMS",
                   [f"{it['name']}|{it['cooldown']}" for it in self._custom_items])
        self._log_line("[GUI] Settings saved.", "ok")

    def _write_live_conf(self, *_):
        if not self._running or self._proc is None:
            return
        lines = []
        for k in _LIVE_KEYS:
            v = self._vars.get(k)
            if v is not None:
                lines.append(f'{k}={"true" if v.get() else "false"}')
        try:
            with open(LIVE_CONF, "w") as f:
                f.write("\n".join(lines) + "\n")
            os.kill(self._proc.pid, signal.SIGUSR1)
        except OSError:
            pass

    def _remove_live_conf(self):
        try:
            os.remove(LIVE_CONF)
        except OSError:
            pass

    def _start(self):
        if self._running: return
        if not os.path.exists(MACRO_SH):
            messagebox.showerror("Error", f"macro.sh not found:\n{MACRO_SH}"); return
        self._save(); self._clear_log(); self._reset_biome_counter()
        # Attach live-conf traces to module toggles
        for k in _LIVE_KEYS:
            v = self._vars.get(k)
            if v is not None:
                v.trace_add("write", self._write_live_conf)
        self._running = True; self._refresh()
        self._write_live_conf()
        self._proc = subprocess.Popen(
            ["bash", MACRO_SH, "--monitor"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, cwd=SCRIPT_DIR,
            start_new_session=True)   # own process group → can kill all children
        threading.Thread(target=self._stream, daemon=True).start()
        self._start_session_timer()

    def _stop(self):
        # Remove live-conf traces
        for k in _LIVE_KEYS:
            v = self._vars.get(k)
            if v is not None:
                for tid in v.trace_info():
                    try: v.trace_remove(tid[0], tid[1])
                    except Exception: pass
        self._remove_live_conf()
        if self._proc and self._proc.poll() is None:
            try:
                os.killpg(os.getpgid(self._proc.pid), signal.SIGTERM)
            except OSError:
                self._proc.terminate()
        self._running = False; self._refresh()
        if self._session_timer_id:
            self.after_cancel(self._session_timer_id)
            self._session_timer_id = None
        self._log_line("[GUI] Monitoring stopped.", "warn")

    def _stream(self):
        try:
            for line in self._proc.stdout:
                line = line.rstrip("\n")
                ll   = line.lower()
                tag  = ("ok"    if any(k in ll for k in ("✓","[✓]","started","loaded","sent","done")) else
                        "error" if any(k in ll for k in ("error","not found","invalid","failed","http 4")) else
                        "warn"  if any(k in ll for k in ("[!]","disabled","skipping","timeout")) else
                        "info")
                self.after(0, self._log_line, line, tag)
                m = re.search(r">> Biome started: (.+)$", line)
                if m:
                    biome = m.group(1).strip()
                    self.after(0, self._inc_biome, biome)
        finally:
            self.after(0, lambda: (setattr(self,"_running",False), self._refresh()))

    def _load_stats(self):
        try:
            with open(STATS_FILE) as f:
                data = json.loads(f.read())
        except Exception:
            data = {}
        # Defensive: stats.json can be empty/null or have wrong shape.
        if not isinstance(data, dict):
            data = {}
        biome_counts = data.get("biome_counts") or {}
        if not isinstance(biome_counts, dict):
            biome_counts = {}
        counts = {b: biome_counts.get(b, 0) for b in ALL_BIOMES}
        total  = data.get("total_biomes")
        if not isinstance(total, int):
            total = sum(counts.values())
        return counts, total

    def _save_stats(self):
        os.makedirs(os.path.dirname(STATS_FILE), exist_ok=True)
        try:
            with open(STATS_FILE) as f:
                data = json.loads(f.read())
        except Exception:
            data = {}
        data["total_biomes"]  = self._total_biomes
        data["biome_counts"]  = dict(self._biome_counts)
        open(STATS_FILE, "w").write(json.dumps(data))

    def _inc_biome(self, biome):
        key = biome.upper()
        self._biome_counts[key]  = self._biome_counts.get(key, 0) + 1
        self._biome_session[key] = self._biome_session.get(key, 0) + 1
        if key in self._biome_labels:
            self._biome_labels[key].configure(text=str(self._biome_counts[key]))
        self._total_biomes += 1
        self._total_lbl.configure(text=str(self._total_biomes))
        session_total = sum(self._biome_session.values())
        self._session_biomes_lbl.configure(text=str(session_total))
        self._save_stats()

    def _reset_biome_counter(self):
        for b in ALL_BIOMES:
            self._biome_session[b] = 0
        self._session_biomes_lbl.configure(text="0")
        self._session_lbl.configure(text="00:00:00")

    def _start_session_timer(self):
        import time
        self._session_start = time.time()
        self._tick_session_timer()

    def _tick_session_timer(self):
        if not self._running or self._session_start is None:
            return
        import time
        elapsed = int(time.time() - self._session_start)
        h, m, s = elapsed // 3600, (elapsed % 3600) // 60, elapsed % 60
        self._session_lbl.configure(text=f"{h:02d}:{m:02d}:{s:02d}")
        self._session_timer_id = self.after(1000, self._tick_session_timer)

    def _log_line(self, text, tag="info"):
        self._log.configure(state="normal")
        self._log.insert("end", text+"\n", tag)
        self._log.see("end")
        self._log.configure(state="disabled")

    def _clear_log(self):
        self._log.configure(state="normal")
        self._log.delete("1.0","end")
        self._log.configure(state="disabled")

    def _refresh(self):
        if self._running:
            self._status.configure(text="● Running", fg=GREEN)
            self._start_btn.configure(state="disabled", bg=BG3, fg=FG2)
            self._stop_btn.configure(state="normal",   bg=RED,  fg="#1e1e2e")
        else:
            self._status.configure(text="● Stopped", fg=RED)
            self._start_btn.configure(state="normal",   bg=GREEN, fg="#1e1e2e")
            self._stop_btn.configure(state="disabled",  bg=BG3,   fg=FG2)

    def _check_update(self):
        url = "https://api.github.com/repos/aluenchik/Aluen-Macro-Linux/releases/latest"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Aluen-Macro-GUI"})
            with urllib.request.urlopen(req, timeout=5) as r:
                import json as _json
                data = _json.loads(r.read().decode())
            latest = data.get("tag_name", "").lstrip("v")
            def _ver(s):
                try: return tuple(int(x) for x in s.split("."))
                except ValueError: return (0,)
            if latest and _ver(latest) > _ver(VERSION):
                self.after(0, self._show_update_banner, latest)
        except Exception:
            pass

    def _show_update_banner(self, latest):
        bar = tk.Frame(self, bg=YELLOW, pady=4)
        bar.pack(fill="x", before=self.winfo_children()[1])
        tk.Label(bar, text=f"Update available: v{latest}  (you have v{VERSION})",
                 font=FB, bg=YELLOW, fg="#1e1e2e").pack(side="left", padx=12)
        _btn(bar, "✕", bar.destroy,
             bg=YELLOW, fg="#1e1e2e", font=FS, padx=6, pady=2).pack(side="right", padx=(0,4))
        _btn(bar, "View on GitHub", lambda: webbrowser.open(
                 "https://github.com/aluenchik/Aluen-Macro-Linux/releases"),
             bg="#1e1e2e", fg=YELLOW, font=FS, padx=10, pady=2).pack(side="right", padx=8)

    # ── sudo bootstrap ────────────────────────────────────────────────────────
    # Background probe → on success, mark _sudo_ok silently. On failure,
    # show a banner asking the user to grant sudo (optional — fishing and
    # some screenshot paths need it).
    def _probe_sudo(self):
        try:
            r = subprocess.run(
                ["sudo", "-n", "true"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=3,
            )
            if r.returncode == 0:
                # Refresh timestamp so subsequent calls stay cached for a while.
                subprocess.run(["sudo", "-n", "-v"], timeout=3,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._sudo_ok = True
                self._mark_sudo()
                return
        except Exception:
            pass
        # Probe failed — surface a banner asking the user to grant sudo.
        self.after(0, self._show_sudo_banner)

    def _show_sudo_banner(self):
        bar = tk.Frame(self, bg=YELLOW, pady=4)
        bar.pack(fill="x", before=self.winfo_children()[1])
        tk.Label(bar,
                 text="Sudo access recommended (needed for screen capture on Wayland)",
                 font=FS, bg=YELLOW, fg="#1e1e2e").pack(side="left", padx=12)
        _btn(bar, "Skip", bar.destroy,
             bg=YELLOW, fg="#1e1e2e", font=FS, padx=8, pady=2
             ).pack(side="right", padx=(0,4))
        _btn(bar, "Grant sudo", lambda: (bar.destroy(), self._request_sudo_password()),
             bg="#1e1e2e", fg=YELLOW, font=FS, padx=10, pady=2
             ).pack(side="right", padx=8)

    def _request_sudo_password(self):
        """Ask the user for the sudo password in a modal dialog and run sudo -v.

        After success, the timestamp is cached (default 5 min) so subsequent
        grim/screenshot calls in fishing_vision.py don't re-prompt.

        Safe to call from a Tk callback (e.g. <Button-1>): the dialog body is
        built and grab_set is deferred via after_idle so the Toplevel is
        fully mapped by the time the grab fires. Synchronous grab_set inside
        a Button-1 handler fails with "window not viewable".
        """
        dlg = tk.Toplevel(self)
        dlg.title("Grant sudo")
        dlg.configure(bg=BG)
        dlg.transient(self)
        dlg.resizable(False, False)
        # Make sure geometry/visibility are processed before we grab.
        dlg.update_idletasks()

        def _grab():
            try:
                dlg.wait_visibility()
                dlg.grab_set()
                pw_entry.focus_set()
            except tk.TclError:
                pass
        dlg.after_idle(_grab)

        frm = tk.Frame(dlg, bg=BG, padx=20, pady=16)
        frm.pack(fill="both", expand=True)
        tk.Label(frm, text="Grant sudo for screen capture",
                 font=FB, bg=BG, fg=FG).pack(anchor="w")
        tk.Label(frm,
                 text="Used by fishing & screenshot modules on Wayland.\n"
                      "Your password is not stored — only the sudo timestamp.",
                 font=FS, bg=BG, fg=FG2, justify="left"
                 ).pack(anchor="w", pady=(4, 12))

        pw_var = tk.StringVar()
        pw_frame, pw_entry = _entry(frm, pw_var, width=36, show="•")
        pw_frame.pack(fill="x", pady=(0, 4))
        # pw_entry.focus_set() is called by _grab after the window is mapped.

        status = tk.Label(frm, text="", font=FS, bg=BG, fg=YELLOW)
        status.pack(anchor="w", pady=(0, 8))

        def _submit():
            pw = pw_var.get()
            if not pw:
                status.configure(text="Enter your password.", fg=YELLOW)
                return
            status.configure(text="Verifying...", fg=FG2)
            def _run():
                try:
                    r = subprocess.run(
                        ["sudo", "-S", "-v"],
                        input=pw + "\n", text=True,
                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                        timeout=10,
                    )
                    # sudo -S writes the prompt to stderr; ignore that.
                    # Returncode 0 means password was accepted.
                    ok = r.returncode == 0
                except Exception as ex:
                    ok = False
                    err = str(ex)
                else:
                    err = ""
                def _done():
                    if ok:
                        self._sudo_ok = True
                        self._mark_sudo()
                        dlg.destroy()
                    else:
                        status.configure(text="Wrong password or sudo not allowed.", fg=RED)
                self.after(0, _done)
            threading.Thread(target=_run, daemon=True).start()

        btn_row = tk.Frame(frm, bg=BG)
        btn_row.pack(fill="x", pady=(4, 0))
        _btn(btn_row, "Cancel", dlg.destroy, font=FS, padx=12, pady=4
             ).pack(side="right", padx=(8, 0))
        _btn(btn_row, "OK", _submit, bg=ACCENT, fg="#1e1e2e", font=FB,
             padx=14, pady=4).pack(side="right")

        pw_entry.bind("<Return>", lambda e: _submit())
        dlg.bind("<Escape>", lambda e: dlg.destroy())

    def _mark_sudo(self):
        """Touch the marker file so bash modules know sudo is cached.

        Also schedules a recurring `sudo -n -v` call to refresh the timestamp
        every ~4 minutes — keeps fishing/screenshot working unattended for
        days without re-prompting for the password.
        """
        try:
            with open(self._sudo_marker, "w") as f:
                f.write(str(os.getpid()))
        except OSError:
            pass
        self._refresh_sudo_label()
        self._log_line(f"[Sudo] Cached (PID={os.getpid()}). Refreshing every "
                       f"{self._sudo_refresh_interval // 1000}s so it never "
                       f"expires.", "ok")
        self._schedule_sudo_refresh()

    def _refresh_sudo_label(self):
        """Update the clickable footer indicator."""
        if not hasattr(self, "_sudo_lbl"):
            return
        if self._sudo_ok:
            self._sudo_lbl.configure(text="● Sudo cached (click to revoke)",
                                     fg=GREEN)
        else:
            self._sudo_lbl.configure(text="○ Sudo not granted (click to grant)",
                                     fg=FG2)

    def _revoke_sudo(self):
        """Drop sudo cache, marker file, and stop the refresher.

        If sudo isn't currently granted, opens the password dialog instead
        so the user can grant it by clicking the indicator.

        Best-effort: also calls `sudo -K` to invalidate the timestamp so
        any subsequent `sudo grim` from the running macro will fail
        immediately rather than hanging on a password prompt.
        """
        if not self._sudo_ok:
            # Nothing cached — clicking the indicator grants instead of revokes.
            self._request_sudo_password()
            return

        # Stop the timestamp refresher first.
        if self._sudo_refresh_id is not None:
            try: self.after_cancel(self._sudo_refresh_id)
            except Exception: pass
            self._sudo_refresh_id = None
        self._sudo_ok = False

        # Remove marker file so bash modules know.
        try: os.remove(self._sudo_marker)
        except OSError: pass

        # Invalidate sudo timestamp immediately. -K clears the cached
        # credentials so the next sudo call fails fast (no prompt).
        try:
            subprocess.run(["sudo", "-K"], timeout=5,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

        # Also kill any stale sudo askpass helper / dialogs that may be open.
        try:
            subprocess.run(["pkill", "-f", "sudo.*askpass"],
                           timeout=2, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        except Exception:
            pass

        self._refresh_sudo_label()
        self._log_line("[Sudo] Access revoked. Timestamp cleared.", "warn")

    def _schedule_sudo_refresh(self):
        """Schedule the next sudo -v refresh on the Tk main loop."""
        if self._sudo_refresh_id is not None:
            try:
                self.after_cancel(self._sudo_refresh_id)
            except Exception:
                pass
        self._sudo_refresh_id = self.after(
            self._sudo_refresh_interval, self._refresh_sudo_timestamp)

    def _refresh_sudo_timestamp(self):
        """Background thread target: run sudo -n -v to extend the cache."""
        self._sudo_refresh_id = None
        if not self._sudo_ok:
            return
        def _run():
            try:
                r = subprocess.run(
                    ["sudo", "-n", "-v"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    timeout=5,
                )
                if r.returncode == 0 and self._sudo_ok:
                    self.after(0, lambda: self._log_line(
                        "[Sudo] Timestamp refreshed — AFK safe.", "info"))
                    # Reschedule next refresh; keep the chain alive.
                    self.after(0, self._schedule_sudo_refresh)
                else:
                    # Cache lost (password policy changed, sudoers rotated, etc.).
                    # Drop the marker and surface a banner so the user can re-grant.
                    self._sudo_ok = False
                    try: os.remove(self._sudo_marker)
                    except OSError: pass
                    self.after(0, lambda: self._log_line(
                        "[Sudo] Cache expired — re-grant required.", "warn"))
                    self.after(0, self._refresh_sudo_label)
                    self.after(0, self._show_sudo_banner)
            except Exception:
                # Transient error — try again next tick.
                if self._sudo_ok:
                    self.after(0, self._schedule_sudo_refresh)
        threading.Thread(target=_run, daemon=True).start()

    def _on_close(self):
        self._stop()
        if self._sudo_refresh_id is not None:
            try: self.after_cancel(self._sudo_refresh_id)
            except Exception: pass
            self._sudo_refresh_id = None
        if self._kbd_listener is not None:
            try: self._kbd_listener.stop()
            except Exception: pass
            self._kbd_listener = None
        try:
            os.remove(self._sudo_marker)
        except OSError:
            pass
        self.destroy()

if __name__ == "__main__":
    app = App()
    try:
        app.mainloop()
    except KeyboardInterrupt:
        # Ctrl+C in terminal — exit cleanly without traceback
        try:
            app._on_close()
        except Exception:
            pass
        sys.exit(0)
