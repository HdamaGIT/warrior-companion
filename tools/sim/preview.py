"""Visual preview for the headless simulator (D-011, agreed for M5).

Turns the frame layout recorded by lua/wowenv.lua into a self-contained HTML snapshot:
anchors are resolved to screen rectangles the way the client does (bottom-left origin, y up),
then drawn as boxes, colour textures, status bars and text.

It shows structure, placement, text and visibility. It does not reproduce Blizzard art, fonts or
templates: textures with a file path are drawn as hatched placeholders, and frames created from a
template are flagged, because the simulator does not know what the template adds.
"""
from __future__ import annotations

import html
import re
from dataclasses import dataclass
from datetime import datetime

STRATA = ["WORLD", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP"]
DEFAULT_FONT_SIZE = 12
# Font objects the add-on may name; sizes and colours approximate the defaults.
FONT_OBJECTS = {
    "GameFontNormal": (12, (1.0, 0.82, 0.0)),
    "GameFontNormalSmall": (10, (1.0, 0.82, 0.0)),
    "GameFontNormalLarge": (16, (1.0, 0.82, 0.0)),
    "GameFontHighlight": (12, (1.0, 1.0, 1.0)),
    "GameFontHighlightSmall": (10, (1.0, 1.0, 1.0)),
    "GameFontHighlightLarge": (16, (1.0, 1.0, 1.0)),
    "GameFontDisable": (12, (0.5, 0.5, 0.5)),
    "GameFontRed": (12, (1.0, 0.1, 0.1)),
    "GameFontGreen": (12, (0.1, 1.0, 0.1)),
}


@dataclass
class Rect:
    left: float
    bottom: float
    width: float
    height: float

    @property
    def right(self) -> float:
        return self.left + self.width

    @property
    def top(self) -> float:
        return self.bottom + self.height


def _fractions(point: str) -> tuple[float, float]:
    """Horizontal and vertical position of an anchor point within a rect (0 = left/bottom)."""
    h = 0.0 if point.endswith("LEFT") else 1.0 if point.endswith("RIGHT") else 0.5
    v = 1.0 if point.startswith("TOP") else 0.0 if point.startswith("BOTTOM") else 0.5
    return h, v


def font_of(frame: dict) -> tuple[float, tuple]:
    size, colour = FONT_OBJECTS.get(frame.get("fontObject") or "", (DEFAULT_FONT_SIZE, (1.0, 0.82, 0.0)))
    if frame.get("fontSize"):
        size = frame["fontSize"]
    if frame.get("textColor"):
        colour = tuple(frame["textColor"][:3])
    return size, colour


_ESCAPES = re.compile(r"\|c([0-9a-fA-F]{2})([0-9a-fA-F]{6})|\|r|\|T.*?\|t|\|H.*?\|h|\|h|\|n")


def plain_length(text: str) -> int:
    return len(_ESCAPES.sub("", text))


class Layout:
    """Resolves recorded anchors to rectangles. Problems found on the way go to `warnings`."""

    def __init__(self, frames: list[dict], screen: tuple[int, int]):
        self.frames = {f["id"]: f for f in frames}
        self.screen = Rect(0, 0, screen[0], screen[1])
        self.warnings: list[str] = []
        self._rects: dict[int, Rect | None] = {}
        self._resolving: set[int] = set()

    def label(self, frame: dict) -> str:
        return frame.get("name") or f"{frame['type']}#{frame['id']}"

    def rect(self, frame_id: int) -> Rect | None:
        if frame_id in self._rects:
            return self._rects[frame_id]
        frame = self.frames[frame_id]
        if frame.get("name") == "UIParent":
            self._rects[frame_id] = self.screen
            return self.screen
        if frame_id in self._resolving:
            self.warnings.append(f"{self.label(frame)}: anchor loop")
            return None
        self._resolving.add(frame_id)
        result = self._resolve(frame)
        self._resolving.discard(frame_id)
        self._rects[frame_id] = result
        return result

    def _resolve(self, frame: dict) -> Rect | None:
        points = frame.get("points") or []
        if not points:
            return None
        xs: list[tuple[float, float]] = []
        ys: list[tuple[float, float]] = []
        for p in points:
            target = p.get("relativeTo") or frame.get("parent")
            relative = self.rect(target) if target else self.screen
            if relative is None:
                continue
            rh, rv = _fractions(p["relativePoint"])
            fh, fv = _fractions(p["point"])
            xs.append((fh, relative.left + rh * relative.width + (p.get("x") or 0)))
            ys.append((fv, relative.bottom + rv * relative.height + (p.get("y") or 0)))
        if not xs:
            return None
        natural_w, natural_h = self._natural_size(frame)
        left, width = self._axis(xs, natural_w)
        bottom, height = self._axis(ys, natural_h)
        return Rect(left, bottom, width, height)

    @staticmethod
    def _axis(constraints: list[tuple[float, float]], natural: float) -> tuple[float, float]:
        distinct = {}
        for fraction, coordinate in constraints:
            distinct[fraction] = coordinate
        if len(distinct) >= 2:
            (f1, c1), (f2, c2) = sorted(distinct.items())[0], sorted(distinct.items())[-1]
            size = (c2 - c1) / (f2 - f1)
            return c1 - f1 * size, size
        fraction, coordinate = next(iter(distinct.items()))
        return coordinate - fraction * natural, natural

    def _natural_size(self, frame: dict) -> tuple[float, float]:
        width, height = frame.get("width") or 0, frame.get("height") or 0
        if frame["type"] == "FontString" and frame.get("text"):
            size, _ = font_of(frame)
            width = width or plain_length(frame["text"]) * size * 0.55
            height = height or size * 1.25
        return width, height

    def depth(self, frame: dict) -> int:
        depth, parent = 0, frame.get("parent")
        while parent:
            depth += 1
            parent = self.frames[parent].get("parent")
        return depth

    def strata(self, frame: dict) -> int:
        while frame:
            if frame.get("strata") in STRATA:
                return STRATA.index(frame["strata"])
            frame = self.frames.get(frame.get("parent")) if frame.get("parent") else None
        return STRATA.index("MEDIUM")


def _rgba(colour, alpha: float = 1.0) -> str:
    r, g, b = (max(0, min(1, float(c))) for c in colour[:3])
    a = float(colour[3]) if len(colour) > 3 and colour[3] is not None else 1.0
    return f"rgba({round(r * 255)},{round(g * 255)},{round(b * 255)},{a * alpha:.3f})"


def wow_text_to_html(text: str, default_colour: str) -> str:
    """Renders |cAARRGGBB colour codes as spans, drops texture and hyperlink escapes, keeps |n line breaks."""
    out, depth, pos = [], 0, 0
    for match in _ESCAPES.finditer(text):
        out.append(html.escape(text[pos:match.start()]))
        token = match.group(0)
        if match.group(2):
            out.append(f'<span style="color:#{match.group(2)}">')
            depth += 1
        elif token == "|r" and depth:
            out.append("</span>")
            depth -= 1
        elif token == "|n":
            out.append("<br>")
        pos = match.end()
    out.append(html.escape(text[pos:]))
    out.append("</span>" * depth)
    return f'<span style="color:{default_colour}">{"".join(out)}</span>'


SKIP_NAMES = {"UIParent", "GameTooltip"}


def render(frames: list[dict], screen=(1920, 1080), title="Warrior Workshop", subtitle="") -> tuple[str, list[str]]:
    """Returns (html, warnings) for a list of frames from sim.dumpFrames()."""
    layout = Layout(frames, screen)
    width, height = screen
    drawables, rows = [], []
    has_children = {f.get("parent") for f in frames}
    ordered = sorted(
        (f for f in frames if f.get("name") not in SKIP_NAMES),
        key=lambda f: (layout.strata(f), (f.get("level") or 0) + layout.depth(f), f["type"] == "FontString", f["id"]),
    )
    for frame in ordered:
        label = layout.label(frame)
        rect = layout.rect(frame["id"])
        visible = bool(frame.get("visible"))
        if frame.get("template"):
            layout.warnings.append(f"{label}: template {frame['template']} is not simulated (drawn bare)")
        if rect is None:
            if visible and frame["type"] != "Frame" or (visible and (frame.get("text") or frame.get("color"))):
                layout.warnings.append(f"{label}: visible but has no anchor, so the client would not draw it")
            is_logic_only = frame["type"] == "Frame" and not frame.get("width") and frame["id"] not in has_children
            if not is_logic_only:  # plain event frames have no layout by design
                rows.append((label, frame, None, visible))
            continue
        rows.append((label, frame, rect, visible))
        if visible and (rect.right <= 0 or rect.left >= width or rect.top <= 0 or rect.bottom >= height):
            layout.warnings.append(f"{label}: entirely off-screen")
        if visible and (rect.width <= 0 or rect.height <= 0) and frame["type"] != "FontString":
            layout.warnings.append(f"{label}: zero size")
        drawables.append((frame, rect, label, visible))

    layout.warnings.extend(_overlaps(layout, drawables))
    full_view = Rect(0, 0, width, height)
    full = [_element(f, r, lbl, vis, full_view) for f, r, lbl, vis in drawables]
    close_view = _bounds([r for f, r, lbl, vis in drawables if vis], full_view)
    close = [_element(f, r, lbl, vis, close_view) for f, r, lbl, vis in drawables] if close_view else []
    warnings = sorted(set(layout.warnings))
    return _page(full, close, close_view, rows, warnings, screen, title, subtitle), warnings


def _top_level(layout: Layout, frame: dict) -> dict | None:
    """The ancestor (or the frame itself) whose parent is UIParent; None for parentless frames."""
    while frame.get("parent"):
        parent = layout.frames[frame["parent"]]
        if parent.get("name") == "UIParent":
            return frame
        frame = parent
    return None


def _overlaps(layout: Layout, drawables) -> list[str]:
    """Warns when visible pieces of two different UIParent children overlap.

    Every visible frame belongs to its top-level container (the ancestor parented to UIParent).
    Pieces are compared only across containers, so rows hanging outside their own container still
    count against other containers, but a container is never compared with its own children.
    Reports the largest overlap per pair of containers.
    """
    groups: dict[int, dict] = {}
    for frame, rect, _, visible in drawables:
        if not visible or rect.width <= 0 or rect.height <= 0:
            continue
        top = _top_level(layout, frame)
        if top is None:
            continue
        group = groups.setdefault(top["id"], {"frame": top, "rects": [], "hint": None})
        group["rects"].append(rect)
        if not group["hint"] and frame.get("text"):
            group["hint"] = _ESCAPES.sub("", frame["text"])

    def name(group):
        return layout.label(group["frame"]) + (f" (“{group['hint']}”)" if group["hint"] else "")

    ordered = sorted(groups.values(), key=lambda g: g["frame"]["id"])
    warnings = []
    for i, a in enumerate(ordered):
        for b in ordered[i + 1:]:
            best = None
            for ra in a["rects"]:
                for rb in b["rects"]:
                    w = min(ra.right, rb.right) - max(ra.left, rb.left)
                    h = min(ra.top, rb.top) - max(ra.bottom, rb.bottom)
                    if w > 0 and h > 0 and (best is None or w * h > best[0] * best[1]):
                        best = (w, h)
            if best:
                warnings.append(f"{name(a)} overlaps {name(b)} by {best[0]:.0f}x{best[1]:.0f}")
    return warnings


def _bounds(rects: list[Rect], screen: Rect, margin: float = 24) -> Rect | None:
    """Bounding box of the visible frames, padded and clipped to the screen; None if nothing is visible."""
    rects = [r for r in rects if r.width > 0 and r.height > 0]
    if not rects:
        return None
    left = max(screen.left, min(r.left for r in rects) - margin)
    bottom = max(screen.bottom, min(r.bottom for r in rects) - margin)
    right = min(screen.right, max(r.right for r in rects) + margin)
    top = min(screen.top, max(r.top for r in rects) + margin)
    if right <= left or top <= bottom:
        return None
    return Rect(left, bottom, right - left, top - bottom)


def _element(frame: dict, rect: Rect, label: str, visible: bool, view: Rect) -> str:
    """One absolutely positioned element, placed in percentages of `view` (the screen or a close-up)."""
    width, height = view.width, view.height
    style = [
        f"left:{(rect.left - view.left) / width * 100:.4f}%",
        f"top:{(view.top - rect.top) / height * 100:.4f}%",
        f"width:{max(rect.width, 0) / width * 100:.4f}%",
        f"height:{max(rect.height, 0) / height * 100:.4f}%",
    ]
    if frame.get("alpha") is not None:
        style.append(f"opacity:{frame['alpha']}")
    classes = ["f", f"t-{frame['type'].lower()}"]
    if not visible:
        classes.append("hidden")
    inner = ""
    kind = frame["type"]
    if kind == "Texture":
        colour = frame.get("color") or frame.get("vertexColor")
        if colour and not frame.get("texture"):
            style.append(f"background:{_rgba(colour)}")
        else:
            classes.append("art")
            if colour:
                style.append(f"--tint:{_rgba(colour)}")
    elif kind == "FontString":
        size, colour = font_of(frame)
        justify = {"LEFT": "flex-start", "RIGHT": "flex-end"}.get(frame.get("justifyH") or "", "center")
        style.append(f"font-size:calc({size} / {width} * 100cqw)")
        style.append(f"justify-content:{justify}")
        inner = wow_text_to_html(frame.get("text") or "", _rgba(colour))
    elif kind == "StatusBar":
        lo, hi, value = frame.get("min") or 0, frame.get("max") or 1, frame.get("value") or 0
        fill = 0 if hi == lo else max(0.0, min(1.0, (value - lo) / (hi - lo)))
        bar = _rgba(frame.get("barColor") or (0.2, 0.7, 0.2))
        inner = f'<div class="fill" style="width:{fill * 100:.2f}%;background:{bar}"></div>'
    if kind in ("Frame", "Button", "StatusBar", "CheckButton"):
        if frame.get("backdropColor"):
            style.append(f"background:{_rgba(frame['backdropColor'])}")
            classes.append("solid")
        if frame.get("borderColor"):
            style.append(f"border:1px solid {_rgba(frame['borderColor'])}")
            classes.append("solid")
    tip = f"{label} ({kind}) {rect.width:.0f}x{rect.height:.0f} at {rect.left:.0f},{rect.bottom:.0f}"
    if frame.get("texture"):
        tip += f" texture={frame['texture']}"
    return (f'<div class="{" ".join(classes)}" style="{";".join(style)}" title="{html.escape(tip)}" '
            f'data-label="{html.escape(label)}">{inner}</div>')


def _page(items, close, close_view, rows, warnings, screen, title, subtitle) -> str:
    width, height = screen
    if close_view:
        close_html = (f'<section><h2>Close-up <span class="muted">({close_view.width:.0f}×{close_view.height:.0f} '
                      f'around the visible frames)</span></h2><div class="screen close" '
                      f'style="aspect-ratio:{close_view.width:.0f}/{close_view.height:.0f}">{"".join(close)}</div></section>')
    else:
        close_html = '<section><h2>Close-up</h2><p class="muted">Nothing is visible.</p></section>'
    row_html = []
    for label, frame, rect, visible in rows:
        where = "not drawn (no anchor)" if rect is None else f"{rect.width:.0f}x{rect.height:.0f} @ {rect.left:.0f},{rect.bottom:.0f}"
        state = "shown" if visible else "hidden"
        text = f" — “{html.escape(_ESCAPES.sub('', frame['text']))}”" if frame.get("text") else ""
        row_html.append(f'<li class="{state}"><b>{html.escape(label)}</b> <span>{frame["type"]} · {state} · {where}</span>{text}</li>')
    warn_html = "".join(f"<li>{html.escape(w)}</li>" for w in warnings) or "<li class='ok'>No layout problems found.</li>"
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} preview</title>
<style>
  :root {{ --bg:#0e1116; --panel:#171b22; --text:#e6e6e6; --muted:#8b93a1; --warn:#f0b429; --line:#2a303b; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; padding:16px; background:var(--bg); color:var(--text); font:14px/1.45 system-ui, sans-serif; }}
  header {{ display:flex; flex-wrap:wrap; gap:8px 20px; align-items:baseline; margin-bottom:12px; }}
  h1 {{ font-size:18px; margin:0; }}
  .muted {{ color:var(--muted); font-size:13px; }}
  label {{ font-size:13px; color:var(--muted); cursor:pointer; }}
  .close {{ max-width:900px; margin:0 auto; }}
  .screen {{ position:relative; width:100%; aspect-ratio:{width}/{height}; container-type:inline-size; overflow:hidden;
            border:1px solid var(--line); border-radius:6px;
            background: radial-gradient(ellipse at 50% 60%, #2b3a2e 0%, #1a2420 55%, #0d1210 100%); }}
  .f {{ position:absolute; }}
  .t-frame, .t-button, .t-checkbutton {{ outline:1px dashed rgba(120,170,255,.35); }}
  .solid {{ outline:none; }}
  .no-outlines .t-frame, .no-outlines .t-button, .no-outlines .t-checkbutton {{ outline:none; }}
  .t-fontstring {{ display:flex; align-items:center; white-space:nowrap; font-family:"Friz Quadrata TT", Georgia, serif;
                   text-shadow:1px 1px 0 #000; overflow:visible; }}
  .t-statusbar {{ background:rgba(0,0,0,.5); }}
  .fill {{ height:100%; }}
  .art {{ background:repeating-linear-gradient(45deg, rgba(255,255,255,.10) 0 6px, rgba(255,255,255,.03) 6px 12px);
          box-shadow: inset 0 0 0 100vmax var(--tint, transparent); }}
  .hidden {{ display:none; }}
  .show-hidden .hidden {{ display:flex; opacity:.3; outline:1px dashed #f66; }}
  .f:hover {{ outline:2px solid #4af !important; z-index:1000; }}
  section {{ margin-top:16px; background:var(--panel); border:1px solid var(--line); border-radius:6px; padding:12px 16px; }}
  h2 {{ font-size:15px; margin:0 0 8px; }}
  ul {{ margin:0; padding-left:18px; }}
  li span {{ color:var(--muted); font-size:12px; }}
  li.hidden {{ display:list-item; color:var(--muted); }}
  .warnings li {{ color:var(--warn); }}
  .warnings li.ok {{ color:#7bd88f; }}
  @media (max-width:600px) {{ body {{ padding:8px; }} }}
</style>
</head>
<body>
<header>
  <h1>{html.escape(title)}</h1>
  <span class="muted">{html.escape(subtitle)} · {width}×{height} · {stamp}</span>
  <label><input type="checkbox" id="outlines" checked> frame outlines</label>
  <label><input type="checkbox" id="hidden"> show hidden frames</label>
</header>
{close_html}
<section><h2>Full screen</h2>
<div class="screen" id="screen">
{chr(10).join(items)}
</div></section>
<p class="muted">Simulator preview: layout, text and visibility only. Blizzard art, fonts and templates are not drawn,
so check the real look in game.</p>
<section class="warnings"><h2>Layout warnings</h2><ul>{warn_html}</ul></section>
<section><h2>Frames ({len(rows)})</h2><ul>{"".join(row_html)}</ul></section>
<script>
  const screens = document.querySelectorAll(".screen");
  const toggle = (cls, on) => screens.forEach(s => s.classList.toggle(cls, on));
  document.getElementById("outlines").addEventListener("change", e => toggle("no-outlines", !e.target.checked));
  document.getElementById("hidden").addEventListener("change", e => toggle("show-hidden", e.target.checked));
</script>
</body>
</html>
"""
