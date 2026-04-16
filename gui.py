#!/usr/bin/env python3
"""Aluen's Macro — GUI launcher"""

import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import subprocess, threading, os, re, webbrowser, json
try:
    from PIL import Image, ImageTk
    _PIL = True
except ImportError:
    _PIL = False

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
MACRO_SH      = os.path.join(SCRIPT_DIR, "macro.sh")
_CORE_MACRO   = os.path.join(SCRIPT_DIR, "modules", "core", "macro.sh")
CONFIG_FILE    = os.path.expanduser("~/.config/sols_rng/config.conf")
TEMPLATES_FILE = os.path.expanduser("~/.config/sols_rng/cal_templates.json")
LOGO_PNG    = os.path.join(SCRIPT_DIR, "modules", "core", "logo.png")

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
    "STARFALL","CORRUPTION","NULL","EGGLAND",
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
    for m in re.finditer(r'^(\w+)=\((.*?)\)', _raw(), re.MULTILINE | re.DOTALL):
        arrays[m.group(1)] = re.findall(r'"([^"]*)"', m.group(2))
    return arrays

def save_scalar(key, value):
    content = _raw()
    line = f'{key}="{value}"'
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
        self.geometry("880x600")
        self.minsize(760, 500)
        self.configure(bg=BG)
        self.option_add("*tearOff", False)

        self._proc     = None
        self._running  = False
        self._cfg      = read_config()
        self._arrs     = read_arrays()
        self._vars     = {}
        self._avars    = {}
        self._inv      = set()

        self._logo_lg  = _load_img(100)
        _ico           = _load_img(32)
        if _ico: self.iconphoto(True, _ico)

        self._build()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── Layout ────────────────────────────────────────────────────────────────
    def _build(self):
        # ── Header ────────────────────────────────────────────────────────────
        hdr = tk.Frame(self, bg=BG2, pady=0)
        hdr.pack(fill="x")

        tk.Label(hdr, text="Aluen's Macro", font=("Segoe UI", 12, "bold"),
                 bg=BG2, fg=FG, pady=10).pack(side="left", padx=16)

        self._stop_btn = _btn(hdr, "■  Stop", self._stop,
                              bg=BG3, padx=14, pady=6, state="disabled")
        self._stop_btn.pack(side="right", padx=(4,12))

        self._start_btn = _btn(hdr, "▶  Start", self._start,
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
        nb.add(t1, text="Main")
        nb.add(t2, text="Settings")
        nb.add(t4, text="Special Thanks")
        nb.add(t3, text="About")

        self._tab_main(t1)
        self._tab_settings(t2)
        self._tab_about(t3)
        self._tab_thanks(t4)

        # ── Footer ────────────────────────────────────────────────────────────
        tk.Frame(self, bg=BORDER, height=1).pack(fill="x")
        foot = tk.Frame(self, bg=BG2, pady=4)
        foot.pack(fill="x")
        tk.Label(foot, text=f"v{VERSION}", font=("Segoe UI", 8),
                 bg=BG2, fg=FG2).pack(side="left", padx=12)

    # ── Tab 1 ─────────────────────────────────────────────────────────────────
    def _tab_main(self, p):
        body = tk.Frame(p, bg=BG)
        body.pack(fill="both", expand=True, padx=14, pady=12)

        # Left panel
        left = tk.Frame(body, bg=BG, width=265)
        left.pack(side="left", fill="y", padx=(0,14))
        left.pack_propagate(False)

        self._sec(left, "Modules")
        self._toggle_row(left, "Merchant",           "MERCHANT_ENABLED")
        self._toggle_row(left, "AntiAFK",            "ANTIAFK_ENABLED",            "ANTIAFK_INTERVAL",            300)
        self._toggle_row(left, "Strange Controller", "STRANGE_CONTROLLER_ENABLED", "STRANGE_CONTROLLER_INTERVAL", 1200)
        self._toggle_row(left, "Biome Randomizer",   "BIOME_RANDOMIZER_ENABLED",   "BIOME_RANDOMIZER_INTERVAL",   2100)

        self._sec(left, "Discord")
        self._field(left, "Webhook URL",   "WEBHOOK_URL")
        self._field(left, "Server Invite", "SERVER_INVITE")

        _btn(left, "Save", self._save, bg=ACCENT, fg="#1e1e2e", font=FS,
             padx=14, pady=5).pack(anchor="w", pady=(14,0))

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

        self._sec(q, "Discord", **px)
        self._field(q, "Webhook URL",   "WEBHOOK_URL",   **px)
        self._field(q, "Server Invite", "SERVER_INVITE", **px)


        self._sec(q, "AntiAFK", **px)
        self._toggle_row(q, "Enabled", "ANTIAFK_ENABLED", "ANTIAFK_INTERVAL", 300, **px)

        self._sec(q, "Merchant", **px)
        self._toggle_row(q, "Enabled", "MERCHANT_ENABLED", "MERCHANT_INTERVAL", 300, **px)

        self._sec2(q, "Calibration", **px)
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
        ]:
            self._coord_row(q, lbl, kx, ky, **px)

        self._sec2(q, "Auto-buy — Mari",   **px); self._item_cbs(q, "MARI_BUY_ITEMS",   MARI_ALL_ITEMS,   **px)
        self._sec2(q, "Auto-buy — Jester", **px); self._item_cbs(q, "JESTER_BUY_ITEMS", JESTER_ALL_ITEMS, **px)

        self._sec(q, "Strange Controller", **px)
        self._toggle_row(q, "Enabled", "STRANGE_CONTROLLER_ENABLED", "STRANGE_CONTROLLER_INTERVAL", 1200, **px)

        self._sec(q, "Biome Randomizer", **px)
        self._toggle_row(q, "Enabled", "BIOME_RANDOMIZER_ENABLED", "BIOME_RANDOMIZER_INTERVAL", 2100, **px)

        self._sec(q, "Biome Notifications", **px)
        self._sec2(q, "Mute (checked = won't notify)", **px)
        self._biome_cbs(q, "NOTIFY_ONLY", invert=True, **px)
        self._sec2(q, "Ping role for biomes", **px)
        self._biome_cbs_ro(q, {"GLITCHED","DREAMSPACE","CYBERSPACE"}, **px)

        _btn(q, "  Save all settings  ", self._save,
             bg=ACCENT, fg="#1e1e2e", font=FB, padx=14, pady=7
             ).pack(anchor="w", padx=18, pady=18)

        sf.bind_scroll(q)

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
        _btn(row, "Reset", lambda vx=vx, vy=vy: (vx.set("0"), vy.set("0")),
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
    ]

    _DEFAULT_TPL = {
        "MERCHANT_CAL_INV_X":        "29",
        "MERCHANT_CAL_INV_Y":        "516",
        "MERCHANT_CAL_ITEMS_TAB_X":  "1258",
        "MERCHANT_CAL_ITEMS_TAB_Y":  "347",
        "MERCHANT_CAL_SEARCH_X":     "1002",
        "MERCHANT_CAL_SEARCH_Y":     "386",
        "MERCHANT_CAL_ITEM_X":       "841",
        "MERCHANT_CAL_ITEM_Y":       "484",
        "MERCHANT_CAL_USE_X":        "682",
        "MERCHANT_CAL_USE_Y":        "591",
        "MERCHANT_CAL_DIALOG_X":     "792",
        "MERCHANT_CAL_DIALOG_Y":     "861",
        "MERCHANT_CAL_SHOP_X":       "637",
        "MERCHANT_CAL_SHOP_Y":       "933",
        "MERCHANT_CAL_BUY_X":        "1122",
        "MERCHANT_CAL_BUY_Y":        "667",
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
                                      values=names, width=18, state="readonly",
                                      font=FS)
        self._tpl_cb.pack(side="left", padx=(0, 6))

        _btn(row, "Load",   self._tpl_apply,  font=FS, padx=8,  pady=2).pack(side="left", padx=(0,4))
        _btn(row, "Save",   self._tpl_save,   font=FS, padx=8,  pady=2).pack(side="left", padx=(0,4))
        _btn(row, "Delete", self._tpl_delete, font=FS, padx=8,  pady=2).pack(side="left")

    def _tpl_apply(self):
        name = self._tpl_var.get()
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
        dlg = tk.Toplevel(self)
        dlg.title("Save template")
        dlg.attributes("-topmost", True)
        dlg.resizable(False, False)
        dlg.configure(bg=BG)
        dlg.geometry("260x90+200+200")

        tk.Label(dlg, text="Template name:", font=FS, bg=BG, fg=FG
                 ).pack(anchor="w", padx=14, pady=(12,2))
        current = self._tpl_var.get()
        v = tk.StringVar(value="" if current == "1920x1080" else current)
        frame, entry = _entry(dlg, v)
        frame.pack(fill="x", padx=14)
        entry.focus_set()

        def _do(event=None):
            name = v.get().strip()
            if not name:
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
            dlg.destroy()
            self._log_line(f"[Templates] Saved: {name}", "ok")

        dlg.bind("<Return>", _do)
        dlg.bind("<Escape>", lambda e: dlg.destroy())
        _btn(dlg, "Save", _do, bg=ACCENT, fg="#1e1e2e",
             font=FS, padx=12, pady=3).pack(anchor="e", padx=14, pady=6)

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

    def _item_cbs(self, p, key, items, padx=0, pady=0):
        sel = {s.lower() for s in self._arrs.get(key,[])}
        self._avars[key] = {}
        wrap = tk.Frame(p, bg=BG2, padx=6, pady=4)
        wrap.pack(fill="x", padx=padx, pady=(0, 8))
        for item in items:
            v = tk.BooleanVar(value=item.lower() in sel)
            self._avars[key][item] = v
            row = tk.Frame(wrap, bg=BG2)
            row.pack(fill="x")
            tk.Checkbutton(row, text=item, variable=v,
                           bg=BG2, fg=FG, selectcolor=BG3,
                           activebackground=BG2, activeforeground=FG,
                           highlightthickness=0, bd=0, relief="flat",
                           font=FS, cursor="hand2", anchor="w"
                           ).pack(fill="x", padx=4, pady=1)

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

    def _biome_cbs(self, p, key, invert=False, padx=0, pady=0):
        sel = {s.upper() for s in self._arrs.get(key,[])}
        if invert: self._inv.add(key)
        self._avars[key] = {}
        grid = tk.Frame(p, bg=BG)
        grid.pack(fill="x", padx=padx, pady=(0,6))
        for i, biome in enumerate(ALL_BIOMES):
            checked = (bool(sel) and biome not in sel) if invert else (biome in sel)
            v = tk.BooleanVar(value=checked)
            self._avars[key][biome] = v
            r, c = divmod(i, 4)
            _checks(grid, biome, v).grid(row=r, column=c, sticky="w", padx=4, pady=1)

    # ── Actions ───────────────────────────────────────────────────────────────
    def _save(self):
        bools = {"ANTIAFK_ENABLED",
                 "STRANGE_CONTROLLER_ENABLED","BIOME_RANDOMIZER_ENABLED"}
        for k, v in self._vars.items():
            val = v.get()
            save_scalar(k, ("true" if val else "false") if k in bools else str(val))
        for k, ivars in self._avars.items():
            chosen = [i for i,v in ivars.items() if not v.get()] if k in self._inv \
                else [i for i,v in ivars.items() if v.get()]
            save_array(k, chosen)
        self._log_line("[GUI] Settings saved.", "ok")

    def _start(self):
        if self._running: return
        if not os.path.exists(MACRO_SH):
            messagebox.showerror("Error", f"macro.sh not found:\n{MACRO_SH}"); return
        self._save(); self._clear_log()
        self._running = True; self._refresh()
        self._proc = subprocess.Popen(
            ["bash", MACRO_SH, "--monitor"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, cwd=SCRIPT_DIR)
        threading.Thread(target=self._stream, daemon=True).start()

    def _stop(self):
        if self._proc and self._proc.poll() is None: self._proc.terminate()
        self._running = False; self._refresh()
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
        finally:
            self.after(0, lambda: (setattr(self,"_running",False), self._refresh()))

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

    def _on_close(self):
        self._stop(); self.destroy()

if __name__ == "__main__":
    App().mainloop()
