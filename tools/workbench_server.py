#!/usr/bin/env python3
"""Serve the asset workbench, store uploads, and push them to the archive repo."""
import json
import os
import re
import shutil
import subprocess
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = Path(os.environ.get("WORKBENCH_REPO", "/tmp/AI-game-explore"))
REMOTE = "https://github.com/nancywu5-hk/AI-game--explore.git"
MAX_BYTES = 20 * 1024 * 1024
KINDS = {
    "art": {"dir": ROOT / "assets" / "art", "ext": {"png", "jpg", "jpeg", "webp", "gif"}},
    "audio": {"dir": ROOT / "assets" / "audio", "ext": {"wav", "mp3", "ogg"}},
}
LOCK = threading.Lock()


def git(*args: str) -> str:
    done = subprocess.run(
        ["git", "-C", str(REPO), *args],
        capture_output=True,
        text=True,
    )
    if done.returncode != 0:
        detail = (done.stderr or done.stdout or "git 失败").strip()
        raise RuntimeError(detail)
    return done.stdout.strip()


def ensure_repo() -> None:
    if (REPO / ".git").is_dir():
        return
    REPO.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", REMOTE, str(REPO)], check=True)


def safe_name(raw: str) -> str:
    base = Path(raw).name.strip()
    if not base or base in {".", ".."} or "/" in raw or "\\" in raw:
        raise ValueError("文件名不能包含路径")
    if len(base) > 80 or not re.fullmatch(r"[^/\\]+", base):
        raise ValueError("文件名不可用")
    return base


def mirror(path: Path) -> None:
    rel = path.relative_to(ROOT)
    dest = REPO / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, dest)


def list_files(folder: Path) -> list[str]:
    if not folder.is_dir():
        return []
    names = []
    for item in sorted(folder.iterdir()):
        if item.is_file() and not item.name.startswith("."):
            names.append(item.name)
    return names


def repo_status() -> dict:
    ensure_repo()
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    sha = git("rev-parse", "--short", "HEAD")
    porcelain = git("status", "--porcelain", "--", "assets")
    pending = [line[3:] for line in porcelain.splitlines() if line.strip()]
    return {
        "remote": REMOTE,
        "branch": branch,
        "sha": sha,
        "art": list_files(KINDS["art"]["dir"]),
        "audio": list_files(KINDS["audio"]["dir"]),
        "pending": pending,
    }


def send_json(handler: SimpleHTTPRequestHandler, code: int, payload: dict) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/api/repo":
            try:
                with LOCK:
                    send_json(self, 200, {"ok": True, **repo_status()})
            except Exception as exc:
                send_json(self, 500, {"ok": False, "error": str(exc)})
            return
        super().do_GET()

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/upload":
            self.upload()
            return
        if path == "/api/commit":
            self.commit()
            return
        self.send_error(404)

    def upload(self) -> None:
        query = self.path.split("?", 1)[1] if "?" in self.path else ""
        params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
        from urllib.parse import unquote

        kind = params.get("kind", "")
        if kind not in KINDS:
            send_json(self, 400, {"ok": False, "error": "只能上传美术或音效"})
            return
        try:
            name = safe_name(unquote(params.get("name", "")))
        except ValueError as exc:
            send_json(self, 400, {"ok": False, "error": str(exc)})
            return
        ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
        if ext not in KINDS[kind]["ext"]:
            send_json(self, 400, {"ok": False, "error": "这个格式不能放进" + ("美术" if kind == "art" else "音效")})
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BYTES:
            send_json(self, 400, {"ok": False, "error": "文件为空，或超过 20MB"})
            return
        data = self.rfile.read(length)
        folder = KINDS[kind]["dir"]
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / name
        with LOCK:
            target.write_bytes(data)
            ensure_repo()
            mirror(target)
        send_json(self, 200, {"ok": True, "file": f"assets/{kind}/{name}"})

    def commit(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            send_json(self, 400, {"ok": False, "error": "提交说明无法读取"})
            return
        message = str(data.get("message", "")).strip()
        if not message:
            send_json(self, 400, {"ok": False, "error": "提交说明不能为空"})
            return
        if len(message) > 200:
            send_json(self, 400, {"ok": False, "error": "提交说明请控制在 200 字内"})
            return
        try:
            with LOCK:
                ensure_repo()
                for folder in (KINDS["art"]["dir"], KINDS["audio"]["dir"]):
                    if not folder.is_dir():
                        continue
                    for item in folder.iterdir():
                        if item.is_file() and not item.name.startswith("."):
                            mirror(item)
                git("add", "--", "assets")
                porcelain = git("status", "--porcelain", "--", "assets")
                if not porcelain.strip():
                    send_json(self, 400, {"ok": False, "error": "没有新的美术或音效要提交"})
                    return
                git("commit", "-m", message)
                git("push", "origin", "HEAD")
                sha = git("rev-parse", "HEAD")
            send_json(self, 200, {
                "ok": True,
                "sha": sha,
                "url": f"https://github.com/nancywu5-hk/AI-game--explore/commit/{sha}",
            })
        except Exception as exc:
            send_json(self, 500, {"ok": False, "error": str(exc)})


if __name__ == "__main__":
    for spec in KINDS.values():
        spec["dir"].mkdir(parents=True, exist_ok=True)
    port = 8770
    print(f"工作台 http://127.0.0.1:{port}/outputs/游戏资产版本管理工作台.html")
    print(f"提交目标 {REMOTE}")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
