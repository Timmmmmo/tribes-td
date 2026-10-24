"""把中文字体裁成「只含游戏里真正用到的字」的子集。

为什么需要：Web 导出里 SystemFont 拿不到系统字体，中文全变豆腐块。
而完整 Noto Sans SC 有几 MB，塞进 pck 又会拖慢首屏。
这个项目一共只用到两三百个不同的字，裁完通常 100 KB 上下。

用法：
    python tools/subset_font.py <源字体.otf> <输出.ttf>
"""

import glob
import io
import os
import subprocess
import sys


def collect_chars(root: str) -> str:
    chars = set()

    # 所有可能出现在界面上的文本：数值表 + GDScript 里的字符串字面量
    paths = [os.path.join(root, "data", "content.json")]
    paths += glob.glob(os.path.join(root, "game", "*.gd"))
    paths += glob.glob(os.path.join(root, "addons", "td_core", "*.gd"))

    for p in paths:
        with io.open(p, encoding="utf-8") as f:
            chars.update(f.read())

    # 只保留可打印字符，去掉控制符
    keep = {c for c in chars if c.isprintable() and c != "\ufeff"}
    # 数字和常用符号始终带上
    keep.update("0123456789/%.,:·+-×()（）")
    return "".join(sorted(keep))


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    text = collect_chars(root)
    tmp = os.path.join(os.path.dirname(dst), "_chars.txt")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(text)

    cmd = [
        sys.executable, "-m", "fontTools.subset", src,
        "--text-file=" + tmp,
        "--output-file=" + dst,
        "--layout-features=*",
        "--name-IDs=*",
        "--drop-tables+=DSIG",
        "--no-hinting",
        "--desubroutinize",
    ]
    print("子集化 %d 个字符 ..." % len(text), flush=True)
    subprocess.run(cmd, check=True)

    os.remove(tmp)
    print("写出 %s  原始 %.1f KB -> 子集 %.1f KB" % (
        dst, os.path.getsize(src) / 1024, os.path.getsize(dst) / 1024), flush=True)


if __name__ == "__main__":
    main()
