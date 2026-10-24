"""从 Godot 的 export_templates.tpz 里只抽出需要的模板，不下载整包。

背景：官方模板包 1.2 GB，而这台机器到 GitHub 的单连接速度只有十几 KB/s。
但 .tpz 本质是个 zip，所以可以：

  1. 只拉文件尾部 64 KB，解析 End of Central Directory，拿到中央目录位置；
  2. 只拉中央目录，列出所有条目的名字、压缩大小、本地头偏移；
  3. 只拉需要的那几个条目的字节区间（分段并发），单独解压。

实际只传输几十 MB 而不是 1.2 GB。所有区间请求都是多线程的——单连接太慢。

用法：
    python tools/fetch_templates.py <tpz_url> <输出目录> [名字过滤...]
"""

import io
import os
import struct
import sys
import threading
import time
import urllib.request
import zlib

UA = "Mozilla/5.0 tribes-td-templates"
WORKERS = 16
SEG = 1 << 20


def _get(url: str, start: int, end: int, tries: int = 6) -> bytes:
    last = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Range": "bytes=%d-%d" % (start, end)}
            )
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(1.0 + attempt)
    raise SystemExit("拉取失败 [%d-%d]: %s" % (start, end, last))


def fetch(url: str, start: int, end: int) -> bytes:
    """并发拉取 [start, end] 闭区间。"""
    total = end - start + 1
    if total <= 2 * SEG:
        return _get(url, start, end)

    segs = []
    s = start
    while s <= end:
        e = min(s + SEG - 1, end)
        segs.append((s, e))
        s = e + 1

    out = [None] * len(segs)
    lock = threading.Lock()
    cursor = [0]

    def worker() -> None:
        while True:
            with lock:
                if cursor[0] >= len(segs):
                    return
                i = cursor[0]
                cursor[0] += 1
            a, b = segs[i]
            out[i] = _get(url, a, b)

    threads = [threading.Thread(target=worker, daemon=True)
               for _ in range(min(WORKERS, len(segs)))]
    for t in threads:
        t.start()

    done = 0
    while any(t.is_alive() for t in threads):
        time.sleep(8)
        got = sum(len(x) for x in out if x)
        if got > done + 4 * SEG:
            done = got
            print("    ... %d / %d MB" % (got // SEG, total // SEG), flush=True)
    for t in threads:
        t.join()

    blob = b"".join(out)
    if len(blob) != total:
        raise SystemExit("区间长度不对 %d != %d" % (len(blob), total))
    return blob


def fetch_size(url: str) -> int:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return int(r.headers["Content-Length"])


def find_eocd(url: str, total: int):
    """返回 (中央目录偏移, 中央目录长度, 条目数)。"""
    tail_len = min(total, 65557)
    tail = _get(url, total - tail_len, total - 1)
    i = tail.rfind(b"PK\x05\x06")
    if i < 0:
        raise SystemExit("找不到 EOCD，可能不是 zip")

    (_sig, _disk, _cd_disk, _n_disk, n_total,
     cd_size, cd_off, _clen) = struct.unpack("<4s4H2LH", tail[i:i + 22])

    if cd_off != 0xFFFFFFFF and cd_size != 0xFFFFFFFF and n_total != 0xFFFF:
        return cd_off, cd_size, n_total

    # ZIP64：EOCD 往前找 locator (PK\x06\x07)，它给出 ZIP64 EOCD 记录的偏移
    j = tail.rfind(b"PK\x06\x07", 0, i)
    if j < 0:
        raise SystemExit("声明了 ZIP64 但找不到 locator")
    z64_off, = struct.unpack("<Q", tail[j + 8:j + 16])
    rec = _get(url, z64_off, z64_off + 55)
    (_sig, _sz, _vm, _vn, _d, _cdd, _nd, n_total,
     cd_size, cd_off) = struct.unpack("<4sQ2H2L4Q", rec[:56])
    return cd_off, cd_size, n_total


def list_entries(url: str, cd_off: int, cd_size: int):
    data = fetch(url, cd_off, cd_off + cd_size - 1)
    out = []
    p = 0
    while p + 46 <= len(data) and data[p:p + 4] == b"PK\x01\x02":
        (_sig, _vm, _vn, _flag, method, _mt, _md, _crc,
         csize, usize, fnlen, extralen, comlen, _dstart,
         _iattr, _eattr, loff) = struct.unpack("<4s6H3L5H2L", data[p:p + 46])
        name = data[p + 46:p + 46 + fnlen].decode("utf-8", "replace")
        extra = data[p + 46 + fnlen:p + 46 + fnlen + extralen]

        if csize == 0xFFFFFFFF or usize == 0xFFFFFFFF or loff == 0xFFFFFFFF:
            q = 0
            while q + 4 <= len(extra):
                hid, hlen = struct.unpack("<HH", extra[q:q + 4])
                body = extra[q + 4:q + 4 + hlen]
                if hid == 0x0001:
                    r = 0
                    if usize == 0xFFFFFFFF:
                        usize, = struct.unpack("<Q", body[r:r + 8]); r += 8
                    if csize == 0xFFFFFFFF:
                        csize, = struct.unpack("<Q", body[r:r + 8]); r += 8
                    if loff == 0xFFFFFFFF:
                        loff, = struct.unpack("<Q", body[r:r + 8])
                    break
                q += 4 + hlen

        out.append({"name": name, "csize": csize, "usize": usize,
                    "method": method, "loff": loff})
        p += 46 + fnlen + extralen + comlen
    return out


def extract_one(url: str, e: dict, out_dir: str) -> None:
    base = os.path.basename(e["name"])
    target = os.path.join(out_dir, base)
    if os.path.exists(target) and os.path.getsize(target) == e["usize"]:
        print("  已有 %s，跳过" % base, flush=True)
        return

    head = _get(url, e["loff"], e["loff"] + 29)
    fnlen, extralen = struct.unpack("<HH", head[26:30])
    data_off = e["loff"] + 30 + fnlen + extralen
    blob = fetch(url, data_off, data_off + e["csize"] - 1)

    if e["method"] == 0:
        payload = blob
    elif e["method"] == 8:
        payload = zlib.decompress(blob, -15)
    else:
        raise SystemExit("不支持的压缩方式 %d" % e["method"])

    with io.open(target, "wb") as f:
        f.write(payload)
    print("  %-46s %7.1f MB" % (base, len(payload) / 1048576), flush=True)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    url, out_dir = sys.argv[1], sys.argv[2]
    filters = sys.argv[3:] or ["/web", "version.txt"]

    os.makedirs(out_dir, exist_ok=True)
    total = fetch_size(url)
    print("模板包 %.1f MB，先取中央目录..." % (total / 1048576), flush=True)

    cd_off, cd_size, n = find_eocd(url, total)
    entries = list_entries(url, cd_off, cd_size)
    print("共 %d 个条目，中央目录 %.1f KB" % (len(entries), cd_size / 1024), flush=True)

    picked = [e for e in entries if any(f in e["name"] for f in filters)]
    if not picked:
        raise SystemExit("没有条目匹配 %s" % filters)
    want = sum(e["csize"] for e in picked)
    print("匹配 %d 个，只需下载 %.1f MB：" % (len(picked), want / 1048576), flush=True)
    for e in picked:
        print("  - %s (%.1f MB)" % (e["name"], e["csize"] / 1048576), flush=True)

    for e in picked:
        extract_one(url, e, out_dir)
    print("完成，写到 %s" % out_dir, flush=True)


if __name__ == "__main__":
    main()
