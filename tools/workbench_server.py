#!/usr/bin/env python3
"""Serve the asset workbench, store uploads, and push them to the archive repo."""
import json
import os
import re
import shutil
import subprocess
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
REPO = Path(os.environ.get("WORKBENCH_REPO", "/tmp/AI-game-explore"))
REMOTE = "https://github.com/nancywu5-hk/AI-game--explore.git"
MAX_BYTES = 40 * 1024 * 1024
GAME_REL = "games/Wool-main/assets"
GAME_ROOT = ROOT / "games" / "Wool-main"
GAME_ASSETS = GAME_ROOT / "assets"
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
PLAY_LOG = ROOT / ".play.log"
PLAY = {"proc": None, "phase": "idle", "error": ""}
THUMBS = ROOT / ".thumbs"
MEDIA = {
    "png": "image", "jpg": "image", "jpeg": "image", "webp": "image", "gif": "image",
    "wav": "audio", "mp3": "audio", "ogg": "audio",
    "ttf": "font", "otf": "font",
}
GROUPS = {
    "character": "角色",
    "map": "地图",
    "ui": "界面",
    "icons": "图标",
    "sound": "音效",
    "font": "字体",
}
KINDS = {
    "art": {"dir": ROOT / "assets" / "art", "ext": {"png", "jpg", "jpeg", "webp", "gif"}},
    "audio": {"dir": ROOT / "assets" / "audio", "ext": {"wav", "mp3", "ogg"}},
}
LLM_KEY = os.environ.get("TAIJI_LLM_KEY", "021bab4e-7757-490f-877d-ca4a2c425c34")
LLM_MODELS = {
    "hy3": {
        "name": "混元3",
        "endpoint": "http://api.taiji.woa.com/openapi/v2/chat/completions",
        "url_label": "http://api.taiji.woa.com/openapi/v2",
        "desc": "混元3 · 快速响应与规范核验",
    },
    "hy4": {
        "name": "混元4",
        "endpoint": "http://api.taiji.woa.com/openapi/v2/chat/completions",
        "url_label": "http://api.taiji.woa.com/openapi/v2",
        "desc": "混元4 · 深度思考、视觉构思与严格守门",
    },
    "DeepSeek-V4-Flash-Online-32k": {
        "name": "DeepSeek-V4-Flash-Online-32k",
        "endpoint": "http://api.taiji.woa.com/openapi/chat/completions",
        "url_label": "http://api.taiji.woa.com/openapi",
        "desc": "DeepSeek V4 Flash · 32k 高速纪要与信息整理",
    },
    "GLM-5_3-Online-128k": {
        "name": "GLM-5_3-Online-128k",
        "endpoint": "http://api.taiji.woa.com/openapi/chat/completions",
        "url_label": "http://api.taiji.woa.com/openapi",
        "desc": "GLM 5.3 · 128k 超长上下文与综合项目规划",
    },
}

AGENT_DEFAULTS = {
    "PM": {
        "model": "GLM-5_3-Online-128k",
        "duty": "判断交给谁，钉住里程碑。出图和核验并行，签认和推送串行。不改仓库。",
        "prompt": (
            "你是游戏资产版本管理工作台的 PM Agent（项目经理）。\n"
            "你的核心原则：\n"
            "1. 掌控研发进度，出图与核验并行生产，签认与版本提交严格串行。\n"
            "2. 当前游戏是 Godot 2.5D Wool（羊毛人游戏），涉及角色（羊毛人、鸟、鱼）、场景（背景、铆钉）、UI（按钮）三条管线。\n"
            "3. 在制作人（真人）完成四道闸门签认前，坚决禁止版本 Agent 向 GitHub (nancywu5-hk/AI-game--explore) 推送代码。\n"
            "4. 回答干脆利落、有条理，善于把控进度和协调分工（指派 @美术、@场景、@版本、@记录员）。字数控制在 150 字以内。"
        ),
    },
    "记录员": {
        "model": "DeepSeek-V4-Flash-Online-32k",
        "duty": "只整理纪要和待办，不接执行任务。",
        "prompt": (
            "你是游戏资产版本管理工作台的记录员 Agent。\n"
            "你的核心原则：\n"
            "1. 静默记录多人多 Agent 的讨论要点、制作进展和待办清单。\n"
            "2. 你严格不承接任何具体代码或资产修改执行任务。\n"
            "3. 输出格式统一为精炼的纪要简报、待办清点或风险备忘，客观准确，字数在 120 字以内。"
        ),
    },
    "美术": {
        "model": "hy4",
        "duty": "只产候选。不装入正式目录，不写玩法代码。",
        "prompt": (
            "你是游戏资产版本管理工作台的美术 Agent。\n"
            "你的核心原则：\n"
            "1. 专注游戏视觉风格、色调搭配、精灵表切片尺寸与动作流畅度评估。\n"
            "2. 你在房间里只产出设计建议和候选图，坚决不擅自将资产装入游戏正式目录，也不直接提交仓库。\n"
            "3. 若用户需要换图，引导其在工作台美术资产页或管线页使用'替换这张表/图'上传。\n"
            "4. 展现专业的美术审美与视觉构图思考，回答控制在 150 字以内。"
        ),
    },
    "场景": {
        "model": "hy3",
        "duty": "核对白模、碰撞和正反例。不改文件。",
        "prompt": (
            "你是游戏资产版本管理工作台的场景 Agent。\n"
            "你的核心原则：\n"
            "1. 负责关卡（res://scenes/levels/level_1.tscn）的环境规范、白模走查、碰撞体积与图层顺序。\n"
            "2. 重点核验铆钉机关（普通钉 normal、加速钉 boost、生锈钉 rusty 的前后图层与物理参数）、背景图分辨率（2532×1170）。\n"
            "3. 你的职责是质检与核验，指出任何尺寸不匹配或碰撞冲突，坚决不自行改动仓库文件，回答控制在 150 字以内。"
        ),
    },
    "版本": {
        "model": "hy4",
        "duty": "真人签认后才提交。未改文件不重复提交，不自行开分支。",
        "prompt": (
            "你是游戏资产版本管理工作台的版本管理 Agent（版控守门人）。\n"
            "你的核心原则：\n"
            "1. 严格守门 GitHub 仓库（nancywu5-hk/AI-game--explore）。\n"
            "2. 恪守四道验收闸门：技术/源QA、真实运行、Agent看图、用户签认。\n"
            "3. 【铁律】未得到制作人签认（signed=false）之前，即使收到提交指令也坚决拒绝推送；未产生文件差异时不重复提交；绝不私自开分支。\n"
            "4. 当制作人已签认后，指导制作人前往工作台'提交'页核对改动明细并附写清晰的提交说明。回答控制在 150 字以内。"
        ),
    },
}

AGENT_STATE = {k: v["model"] for k, v in AGENT_DEFAULTS.items()}


def call_taiji_llm(model: str, messages: list[dict], timeout: int = 35) -> dict:
    meta = LLM_MODELS.get(model)
    if not meta:
        raise ValueError(f"未知的模型: {model}")
    url = meta["endpoint"]
    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": 800,
    }
    cmd = [
        "/usr/bin/curl",
        "-s",
        "-X", "POST",
        url,
        "-H", "Content-Type: application/json",
        "-H", f"Authorization: Bearer {LLM_KEY}",
        "--max-time", str(timeout),
        "-d", json.dumps(payload, ensure_ascii=False),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"请求大模型超时或失败 (code={res.returncode})")
    try:
        data = json.loads(res.stdout or "{}")
    except Exception:
        raise RuntimeError(f"解析大模型返回失败: {res.stdout[:160]}")

    if "error" in data:
        err = data["error"]
        msg = err.get("message") if isinstance(err, dict) else str(err)
        raise RuntimeError(f"大模型报错: {msg}")

    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError(f"大模型未返回回复: {res.stdout[:160]}")
    first = choices[0].get("message") or {}
    content = (first.get("content") or "").strip()
    think = (first.get("reasoning_content") or first.get("reasoning") or "").strip()
    if not content and think:
        # 兜底：如果 reasoning 占用了全部输出，将思考链中的结论提炼为回复
        lines = [line.strip() for line in think.splitlines() if line.strip()]
        content = lines[-1] if lines else think[:120]
    return {
        "content": content,
        "think": think,
        "model": model,
    }


def format_chat_messages(sys_prompt: str, history: list[dict], user_text: str) -> list[dict]:
    raw = []
    for h in (history or [])[-4:]:
        text = (h.get("text") or "").strip()
        if not text:
            continue
        role = "assistant" if h.get("kind") == "ai" else "user"
        who = h.get("who", "")
        content = f"[{who}]: {text}" if role == "assistant" else text
        raw.append((role, content))
    raw.append(("user", user_text))

    merged = []
    for role, content in raw:
        if not merged:
            if role != "user":
                continue
            merged.append({"role": role, "content": content})
        else:
            if merged[-1]["role"] == role:
                merged[-1]["content"] += "\n" + content
            else:
                merged.append({"role": role, "content": content})

    if not merged or merged[0]["role"] != "user":
        merged = [{"role": "user", "content": user_text}]
    elif merged[-1]["role"] != "user":
        merged.append({"role": "user", "content": user_text})

    return [{"role": "system", "content": sys_prompt}] + merged


def agent_chat(who: str, user_text: str, history: list[dict] = None, signed: bool = False) -> dict:
    if who not in AGENT_DEFAULTS:
        who = "PM"
    model = AGENT_STATE.get(who) or AGENT_DEFAULTS[who]["model"]
    cfg = AGENT_DEFAULTS[who]
    sys_prompt = cfg["prompt"]
    sys_prompt += f"\n当前项目状态：制作人签认状态 signed={str(signed).lower()}。"

    messages = format_chat_messages(sys_prompt, history, user_text)

    try:
        res = call_taiji_llm(model, messages)
        return {
            "ok": True,
            "who": who,
            "model": model,
            "text": res["content"],
            "think": res["think"],
            "duty": cfg["duty"],
        }
    except Exception as exc:
        return {
            "ok": False,
            "who": who,
            "model": model,
            "error": str(exc),
            "text": f"[{model} 调用受限] {str(exc)}",
            "think": "大模型调用异常，请检查网络或配置",
            "duty": cfg["duty"],
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


def asset_file(raw: str) -> Path:
    rel = Path(unquote(raw))
    if rel.is_absolute() or ".." in rel.parts:
        raise ValueError("路径不可用")
    full = (ROOT / rel).resolve()
    root = GAME_ASSETS.resolve()
    if root not in full.parents:
        raise ValueError("只能替换游戏资产目录里的文件")
    ext = full.suffix.lower().lstrip(".")
    if ext not in MEDIA:
        raise ValueError("这个格式不能替换")
    return full


def library() -> dict:
    files = []
    if GAME_ASSETS.is_dir():
        for item in sorted(GAME_ASSETS.rglob("*")):
            if not item.is_file() or item.name.startswith("."):
                continue
            ext = item.suffix.lower().lstrip(".")
            if ext not in MEDIA:
                continue
            rel = item.relative_to(ROOT).as_posix()
            folder = item.relative_to(GAME_ASSETS).parts[0] if item.parent != GAME_ASSETS else ""
            files.append({
                "path": rel,
                "name": item.name,
                "group": GROUPS.get(folder, "其他"),
                "kind": MEDIA[ext],
                "bytes": item.stat().st_size,
            })
    return {"files": files}


def thumb_bytes(path: Path) -> bytes:
    from PIL import Image

    Image.MAX_IMAGE_PIXELS = None
    THUMBS.mkdir(parents=True, exist_ok=True)
    stamp = int(path.stat().st_mtime)
    cache = THUMBS / f"{stamp}-{path.stat().st_size}-{path.name}.png"
    if cache.is_file():
        return cache.read_bytes()
    image = Image.open(path).convert("RGBA")
    image.thumbnail((240, 240))
    buf = BytesIO()
    image.save(buf, format="PNG")
    data = buf.getvalue()
    cache.write_bytes(data)
    return data


STATUS_LABEL = {
    "M": "修改",
    "A": "新增",
    "D": "删除",
    "R": "重命名",
    "??": "新文件",
    "MM": "修改",
    "AM": "新增",
    "AD": "删除",
}


def parse_changes(porcelain: str) -> list[dict]:
    changes = []
    for line in porcelain.splitlines():
        if len(line) < 4:
            continue
        code = line[:2].strip() or "??"
        path = line[3:]
        changes.append({
            "code": code,
            "status": STATUS_LABEL.get(code, code),
            "path": path,
        })
    return changes


def recent_commits() -> list[dict]:
    raw = git(
        "log", "-8",
        "--date=format:%Y-%m-%d %H:%M",
        "--name-status",
        "--pretty=format:---%x1f%h%x1f%s%x1f%ad%x1f%H",
    )
    commits = []
    current = None
    for line in raw.splitlines():
        if line.startswith("---\x1f"):
            if current:
                commits.append(current)
            _, sha, message, when, full = line.split("\x1f", 4)
            current = {
                "sha": sha,
                "full": full,
                "message": message,
                "date": when,
                "url": f"https://github.com/nancywu5-hk/AI-game--explore/commit/{full}",
                "files": [],
            }
            continue
        if current and line.strip():
            parts = line.split("\t")
            current["files"].append({
                "status": STATUS_LABEL.get(parts[0], parts[0]),
                "path": parts[-1],
            })
    if current:
        commits.append(current)
    return commits


def repo_status() -> dict:
    ensure_repo()
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    sha = git("rev-parse", "--short", "HEAD")
    porcelain = git("status", "--porcelain", "--", "assets", GAME_REL)
    changes = parse_changes(porcelain)
    return {
        "remote": REMOTE,
        "branch": branch,
        "sha": sha,
        "art": list_files(KINDS["art"]["dir"]),
        "audio": list_files(KINDS["audio"]["dir"]),
        "pending": [item["path"] for item in changes],
        "changes": changes,
        "commits": recent_commits(),
    }


_GODOT_VERSION = None


def godot_version() -> str:
    global _GODOT_VERSION
    if _GODOT_VERSION is not None:
        return _GODOT_VERSION
    if not GODOT.is_file():
        _GODOT_VERSION = ""
        return ""
    done = subprocess.run([str(GODOT), "--version"], capture_output=True, text=True)
    text = (done.stdout or done.stderr or "").strip()
    _GODOT_VERSION = text.splitlines()[0] if text else ""
    return _GODOT_VERSION


def play_status() -> dict:
    proc = PLAY["proc"]
    running = proc is not None and proc.poll() is None
    if PLAY["phase"] == "running" and proc is not None and not running:
        PLAY["phase"] = "failed" if proc.returncode else "idle"
        if proc.returncode:
            PLAY["error"] = "游戏窗口已退出"
    log = ""
    if PLAY_LOG.is_file():
        log = PLAY_LOG.read_text(errors="replace")[-4000:]
    return {
        "running": running or PLAY["phase"] == "importing",
        "phase": PLAY["phase"],
        "pid": proc.pid if running else None,
        "code": None if proc is None or running else proc.returncode,
        "godot": GODOT.is_file(),
        "version": godot_version(),
        "project": "games/Wool-main",
        "scene": "scenes/levels/level_1.tscn",
        "error": PLAY["error"],
        "log": log,
    }


def start_game() -> dict:
    if not GODOT.is_file():
        raise RuntimeError("这台电脑没有找到 /Applications/Godot.app")
    if not (GAME_ROOT / "project.godot").is_file():
        raise RuntimeError("没有找到 games/Wool-main/project.godot")
    proc = PLAY["proc"]
    if PLAY["phase"] == "importing" or (proc is not None and proc.poll() is None):
        return play_status()
    PLAY["error"] = ""
    PLAY["phase"] = "importing"
    if PLAY_LOG.exists():
        PLAY_LOG.unlink()

    def worker() -> None:
        try:
            imported = subprocess.Popen(
                [str(GODOT), "--headless", "--import", "--path", str(GAME_ROOT)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            PLAY["import"] = imported
            output, _ = imported.communicate()
            PLAY_LOG.write_text(output or "", errors="replace")
            if imported.returncode != 0:
                PLAY["phase"] = "failed"
                PLAY["error"] = "资源导入没有完成，游戏窗口没有打开"
                return
            launch_game()
            PLAY["phase"] = "running"
        except Exception as exc:
            PLAY["phase"] = "failed"
            PLAY["error"] = str(exc)

    if (GAME_ROOT / ".godot" / "global_script_class_cache.cfg").is_file():
        try:
            launch_game()
            PLAY["phase"] = "running"
        except Exception as exc:
            PLAY["phase"] = "failed"
            PLAY["error"] = str(exc)
        return play_status()
    threading.Thread(target=worker, daemon=True).start()
    return play_status()


def launch_game() -> None:
    log_handle = PLAY_LOG.open("a")
    log_handle.write("\n正在打开游戏窗口。\n")
    log_handle.flush()
    PLAY["log_handle"] = log_handle
    PLAY["proc"] = subprocess.Popen(
        [str(GODOT), "--path", str(GAME_ROOT), "--resolution", "1280x720"],
        stdout=log_handle,
        stderr=subprocess.STDOUT,
    )


def stop_game() -> dict:
    proc = PLAY.get("import")
    if proc is not None and proc.poll() is None:
        proc.terminate()
    proc = PLAY["proc"]
    if proc is not None and proc.poll() is None:
        proc.terminate()
    PLAY["phase"] = "idle"
    return play_status()


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
        parsed = urlparse(self.path)
        if parsed.path == "/api/repo":
            try:
                with LOCK:
                    send_json(self, 200, {"ok": True, **repo_status()})
            except Exception as exc:
                send_json(self, 500, {"ok": False, "error": str(exc)})
            return
        if parsed.path == "/api/library":
            send_json(self, 200, {"ok": True, **library()})
            return
        if parsed.path == "/api/thumb":
            self.thumb(parse_qs(parsed.query).get("path", [""])[0])
            return
        if parsed.path == "/api/play":
            send_json(self, 200, {"ok": True, **play_status()})
            return
        if parsed.path == "/api/agent/models":
            send_json(self, 200, {
                "ok": True,
                "key_masked": f"{LLM_KEY[:4]}...{LLM_KEY[-4:]}",
                "models": LLM_MODELS,
                "agents": {
                    who: {
                        "who": who,
                        "model": AGENT_STATE.get(who) or cfg["model"],
                        "duty": cfg["duty"],
                        "url_label": LLM_MODELS[AGENT_STATE.get(who) or cfg["model"]]["url_label"],
                    }
                    for who, cfg in AGENT_DEFAULTS.items()
                },
            })
            return
        super().do_GET()

    def thumb(self, raw: str) -> None:
        try:
            path = asset_file(raw)
            if path.suffix.lower().lstrip(".") not in {"png", "jpg", "jpeg", "webp", "gif"}:
                self.send_error(404)
                return
            data = thumb_bytes(path)
        except Exception:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path == "/api/upload":
            self.upload()
            return
        if path == "/api/commit":
            self.commit()
            return
        if path == "/api/replace":
            self.replace()
            return
        if path == "/api/play":
            self.play()
            return
        if path == "/api/agent/config":
            self.agent_config()
            return
        if path == "/api/agent/chat":
            self.agent_chat_api()
            return
        self.send_error(404)

    def agent_config(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            who = body.get("who", "")
            model = body.get("model", "")
            if who not in AGENT_DEFAULTS:
                send_json(self, 400, {"ok": False, "error": f"未知的 Agent: {who}"})
                return
            if model not in LLM_MODELS:
                send_json(self, 400, {"ok": False, "error": f"未知的模型: {model}"})
                return
            AGENT_STATE[who] = model
            send_json(self, 200, {
                "ok": True,
                "who": who,
                "model": model,
                "url_label": LLM_MODELS[model]["url_label"],
            })
        except Exception as exc:
            send_json(self, 500, {"ok": False, "error": str(exc)})

    def agent_chat_api(self) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            who = body.get("who", "PM")
            text = body.get("text", "")
            history = body.get("history", [])
            signed = bool(body.get("signed", False))
            res = agent_chat(who, text, history, signed)
            send_json(self, 200, res)
        except Exception as exc:
            send_json(self, 500, {"ok": False, "error": str(exc)})

    def play(self) -> None:
        action = parse_qs(urlparse(self.path).query).get("action", ["start"])[0]
        try:
            status = stop_game() if action == "stop" else start_game()
            send_json(self, 200, {"ok": True, **status})
        except Exception as exc:
            send_json(self, 500, {"ok": False, "error": str(exc)})

    def replace(self) -> None:
        parsed = urlparse(self.path)
        raw = parse_qs(parsed.query).get("path", [""])[0]
        try:
            target = asset_file(raw)
        except ValueError as exc:
            send_json(self, 400, {"ok": False, "error": str(exc)})
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_BYTES:
            send_json(self, 400, {"ok": False, "error": "文件为空，或超过 40MB"})
            return
        data = self.rfile.read(length)
        ext = target.suffix.lower().lstrip(".")
        with LOCK:
            target.write_bytes(data)
            ensure_repo()
            mirror(target)
        send_json(self, 200, {"ok": True, "file": target.relative_to(ROOT).as_posix(), "kind": MEDIA[ext]})

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
                add_paths = ["assets"]
                if (REPO / GAME_REL).exists():
                    add_paths.append(GAME_REL)
                git("add", "--", *add_paths)
                porcelain = git("status", "--porcelain", "--", "assets", GAME_REL)
                if not porcelain.strip():
                    send_json(self, 400, {"ok": False, "error": "没有要提交的资产替换"})
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
