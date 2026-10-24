"""多线程分段下载器 —— 给慢网络用。

单连接只有 ~13 KB/s，但并发能叠加，所以把文件切成很多段并行拉，
每段独立重试、支持断点续传（已存在的段文件会跳过）。

用法：
    python tools/fetch_parallel.py <url> <输出文件> [每路字节数] [并发数]
"""

import io
import os
import sys
import threading
import time
import urllib.error
import urllib.request

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) tribes-td-fetch"


def head_size(url: str) -> int:
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        n = r.headers.get("Content-Length")
        if not n:
            raise SystemExit("服务器没返回 Content-Length，不能分段")
        return int(n)


def fetch_range(url: str, start: int, end: int, path: str, tries: int = 6) -> None:
    if os.path.exists(path) and os.path.getsize(path) == end - start + 1:
        return
    for attempt in range(tries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Range": "bytes=%d-%d" % (start, end)}
            )
            with urllib.request.urlopen(req, timeout=90) as r, io.open(path, "wb") as f:
                while True:
                    buf = r.read(65536)
                    if not buf:
                        break
                    f.write(buf)
            if os.path.getsize(path) == end - start + 1:
                return
        except (urllib.error.URLError, OSError, TimeoutError) as e:
            if attempt == tries - 1:
                raise
            print("  重试 %d 段（%s）: %s" % (attempt + 1, os.path.basename(path), e), flush=True)
            time.sleep(1.5 * (attempt + 1))


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    url, out = sys.argv[1], sys.argv[2]
    chunk = int(sys.argv[3]) if len(sys.argv) > 3 else 1 << 20
    workers = int(sys.argv[4]) if len(sys.argv) > 4 else 12

    total = head_size(url)
    print("总大小 %.1f MB，分 %d 段、%d 并发" % (total / 1048576, (total + chunk - 1) // chunk, workers), flush=True)

    tmp = out + ".parts"
    os.makedirs(tmp, exist_ok=True)
    jobs = []
    idx = 0
    for start in range(0, total, chunk):
        end = min(start + chunk - 1, total - 1)
        jobs.append((start, end, os.path.join(tmp, "p%05d" % idx)))
        idx += 1

    lock = threading.Lock()
    cursor = [0]
    started = time.time()

    def worker() -> None:
        while True:
            with lock:
                if cursor[0] >= len(jobs):
                    return
                job = jobs[cursor[0]]
                cursor[0] += 1
            fetch_range(url, job[0], job[1], job[2])

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(workers)]
    for t in threads:
        t.start()

    last = 0
    while any(t.is_alive() for t in threads):
        time.sleep(10)
        done = sum(os.path.getsize(j[2]) for j in jobs if os.path.exists(j[2]))
        el = time.time() - started
        print("  %.1f / %.1f MB  %.0f KB/s" % (done / 1048576, total / 1048576, done / el / 1024 if el else 0), flush=True)
        last = done
    for t in threads:
        t.join()

    done = sum(os.path.getsize(j[2]) for j in jobs if os.path.exists(j[2]))
    if done != total:
        raise SystemExit("大小不对：%d != %d" % (done, total))

    with io.open(out, "wb") as w:
        for job in jobs:
            with io.open(job[2], "rb") as r:
                while True:
                    buf = r.read(1 << 20)
                    if not buf:
                        break
                    w.write(buf)
    import shutil

    shutil.rmtree(tmp, ignore_errors=True)
    el = time.time() - started
    print("完成 %.1f MB，用时 %.0fs，平均 %.0f KB/s" % (total / 1048576, el, total / el / 1024), flush=True)


if __name__ == "__main__":
    main()
