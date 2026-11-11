#!/usr/bin/env python3
"""Serve the asset workbench and write Wool's active skin."""
import json
import re
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SKIN = ROOT / "games" / "Wool" / "resources" / "skins" / "active_skin.json"
TRES = ROOT / "games" / "Wool" / "resources" / "skins" / "wool_skin.tres"
TINT = re.compile(r"^#[0-9a-fA-F]{6}$")


def write_tres(tint: str) -> None:
    red = int(tint[1:3], 16) / 255
    green = int(tint[3:5], 16) / 255
    blue = int(tint[5:7], 16) / 255
    line = f"tint = Color({red:.4f}, {green:.4f}, {blue:.4f}, 1)"
    text = TRES.read_text(encoding="utf-8")
    if re.search(r"^tint = .*$", text, re.M):
        text = re.sub(r"^tint = .*$", line, text, count=1, flags=re.M)
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += line + "\n"
    TRES.write_text(text, encoding="utf-8")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/skin":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self.send_error(400)
            return
        tint = str(data.get("tint", ""))
        if not TINT.match(tint):
            self.send_error(400)
            return
        payload = {
            "id": str(data.get("id", "wool"))[:32],
            "name": str(data.get("name", "原毛"))[:32],
            "tint": tint,
        }
        SKIN.parent.mkdir(parents=True, exist_ok=True)
        SKIN.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        write_tres(tint)
        body = json.dumps({"ok": True, "file": "games/Wool/resources/skins/active_skin.json"}, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    port = 8770
    print(f"工作台 http://127.0.0.1:{port}/outputs/游戏资产版本管理工作台.html")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
