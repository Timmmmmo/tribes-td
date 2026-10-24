#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""把 web/src 下的四个文件打成一个自包含的 web/index.html。

为什么要单文件：托管方（CloudStudio 网关）用分享码换一个 Cookie 才放行子资源请求。
如果页面再去请求 js/core.js / content.json，某些浏览器（微信内置浏览器、
iOS 严格隐私模式）不落 Cookie，子请求就会 403 —— 页面白屏。
内联之后整页只有 1 个请求，任何环境都能开，file:// 双击也能开。

用法：
    python tools/build_web.py          # 生成 web/index.html + web/dev.html
"""

import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, "web")
SRC = os.path.join(WEB, "src")

JS_ORDER = ["core.js", "render.js", "main.js"]


def read(path):
    with io.open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def build_single_file():
    shell = read(os.path.join(SRC, "shell.html"))
    content = json.loads(read(os.path.join(SRC, "content.json")))

    parts = []
    # 数据先注入：main.js 启动时优先读 window.__CONTENT__，不再发网络请求
    parts.append("<script>window.__CONTENT__ = " + json.dumps(
        content, ensure_ascii=False, separators=(",", ":")) + ";</script>")
    for name in JS_ORDER:
        body = read(os.path.join(SRC, "js", name))
        # 防止脚本内容里出现 </script> 提前截断
        body = body.replace("</script>", "<\\/script>")
        parts.append("<script>\n" + body + "\n</script>")

    html = shell.replace("{{PAYLOAD}}", "\n".join(parts))
    out = os.path.join(WEB, "index.html")
    write(out, html)
    return out, len(html.encode("utf-8"))


def build_dev_page():
    """本地开发用：仍然分开加载，改完刷新就见效，不用重打包。"""
    shell = read(os.path.join(SRC, "shell.html"))
    parts = ["<script>window.__CONTENT_URL__ = 'src/content.json';</script>"]
    for name in JS_ORDER:
        parts.append('<script src="src/js/%s"></script>' % name)
    out = os.path.join(WEB, "dev.html")
    write(out, shell.replace("{{PAYLOAD}}", "\n".join(parts)))
    return out


if __name__ == "__main__":
    path, size = build_single_file()
    print("wrote %s (%.1f KB, 1 request)" % (path, size / 1024.0))
    print("wrote %s" % build_dev_page())
