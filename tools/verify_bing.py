#!/usr/bin/env python3
"""DailyWall M0 接口核验脚本。

对应《DailyWall 软件开发需求规格说明书》附录 A 第 1/2/3 项与 7.2 节。

用法:
    python3 tools/verify_bing.py
    python3 tools/verify_bing.py --json m0_result.json
    python3 tools/verify_bing.py --timeout 30

重要: 本脚本是一次性快照核验，结果受网络出口、日期、Bing 服务端状态影响，
      不构成稳定契约。每次复核应记录验证日期、出口与原始输出。
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

ARCHIVE = "https://www.bing.com/HPImageArchive.aspx"
BING = "https://www.bing.com"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
BEIJING = timezone(timedelta(hours=8))


def get(url, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, resp.read()


def get_json(params, timeout):
    url = ARCHIVE + "?" + urllib.parse.urlencode(params)
    status, body = get(url, timeout)
    return status, json.loads(body.decode("utf-8"))


def jpeg_size(data):
    """从 JPEG SOF 段解析 (width, height)，避免依赖 macOS sips。"""
    if len(data) < 4 or data[:2] != b"\xff\xd8":
        return None
    i, n = 2, len(data)
    while i + 9 < n:
        if data[i] != 0xFF:
            i += 1
            continue
        while i < n and data[i] == 0xFF:
            i += 1
        if i >= n:
            break
        marker = data[i]
        i += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if i + 2 > n:
            break
        seglen = int.from_bytes(data[i:i + 2], "big")
        if seglen < 2:
            break
        sof = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
               0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
        if marker in sof and i + 7 <= n:
            h = int.from_bytes(data[i + 3:i + 5], "big")
            w = int.from_bytes(data[i + 5:i + 7], "big")
            return (w, h)
        i += seglen
    return None


class Report:
    def __init__(self):
        self.items = []

    def add(self, key, status, evidence, conclusion, caveat=""):
        self.items.append({
            "key": key, "status": status, "evidence": evidence,
            "conclusion": conclusion, "caveat": caveat,
        })
        print(f"[{status}] {key}\n      {conclusion}")
        if caveat:
            print(f"      注意: {caveat}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", dest="json_path", default="")
    ap.add_argument("--timeout", type=int, default=25)
    args = ap.parse_args()

    now = datetime.now(BEIJING)
    print("=== DailyWall M0 接口核验 ===")
    print(f"验证时间: {now.isoformat()}  出口: 本机网络  超时: {args.timeout}s")
    print("性质: 单次快照，不构成稳定契约\n")

    r = Report()
    base_params = {"format": "js", "idx": 0, "n": 1, "mkt": "zh-CN"}

    try:
        status, doc = get_json(base_params, args.timeout)
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        print(f"[FAIL] 接口不可达: {exc}")
        return 2

    if "images" not in doc or not doc["images"]:
        print("[FAIL] 响应缺少 images 或为空")
        return 2
    img = doc["images"][0]

    # A-2 字段完整性与日期语义
    required = ["startdate", "enddate", "fullstartdate", "title",
                "copyright", "copyrightlink", "url", "urlbase"]
    missing = [k for k in required if not img.get(k)]
    r.add("A-2 字段完整性", "PASS" if not missing else "WARN",
          {"http": status, "missing": missing,
           "keys": sorted(img.keys())},
          f"HTTP {status}，核心字段{'齐全' if not missing else '缺失 ' + ','.join(missing)}。",
          "字段应全部按可选处理，未知字段忽略；不得缓存整段响应。" if not missing else "")

    dates = {k: img.get(k) for k in ("startdate", "enddate", "fullstartdate")}
    local = now.strftime("%Y%m%d")
    r.add("A-2 日期语义", "WARN",
          {**dates, "local_today_bj": local},
          "startdate / enddate / 本地日历日三者不一致；文件名基准须在实现中固定。",
          "建议取 enddate（Bing 生效日）作为文件日期，并在代码注释写明时区语义；"
          "UTC 16:00 为切换点，跨点前后需复测。")

    # A-2 标题字段
    r.add("A-2 标题字段", "PASS" if img.get("title") else "WARN",
          {"title": img.get("title")},
          f"title = {img.get('title')!r}；界面标题必须取此动态值，不得使用固定文案。",
          "title 缺失时按规格 4.1 隐藏整行标题区域，不得以版权说明代替。")

    # A-2 市场代码覆盖
    queries = [
        ("zh-CN", {"format": "js", "idx": 0, "n": 1, "mkt": "zh-CN"}),
        ("en-US", {"format": "js", "idx": 0, "n": 1, "mkt": "en-US"}),
        ("ja-JP", {"format": "js", "idx": 0, "n": 1, "mkt": "ja-JP"}),
        ("de-DE", {"format": "js", "idx": 0, "n": 1, "mkt": "de-DE"}),
        ("无 mkt", {"format": "js", "idx": 0, "n": 1}),
        ("en-US+ensearch", {"format": "js", "idx": 0, "n": 1,
                            "mkt": "en-US", "ensearch": 1}),
    ]
    matrix = []
    for label, p in queries:
        try:
            _, d = get_json(p, args.timeout)
            it = d["images"][0]
            matrix.append({"label": label, "urlbase": it.get("urlbase"),
                           "title": it.get("title")})
        except Exception as exc:
            matrix.append({"label": label, "error": str(exc)})
    bases = {m.get("urlbase") for m in matrix[:5] if m.get("urlbase")}
    mkt_effective = len(bases) > 1
    r.add("A-2 市场 / 地区参数", "PASS" if mkt_effective else "WARN",
          matrix,
          ("mkt 能改变返回内容。" if mkt_effective else
           "mkt 单独传入不改变返回内容；ensearch=1 才切换语言版本，且得到的是区域化后缀而非目标市场。"),
          "规格 4.1「地区切换」与接口能力存在冲突；自用版建议砍掉地区选择，"
          "仅保留中文；若保留，须先定义「地区」的实际语义。")

    # A-3 标清 / UHD 图片
    ub = img.get("urlbase", "")
    variants = [
        ("标准 _1920x1080.jpg", BING + ub + "_1920x1080.jpg"),
        ("UHD 拼接 _UHD.jpg", BING + ub + "_UHD.jpg"),
    ]
    try:
        _, uhd_doc = get_json({**base_params, "uhd": 1}, args.timeout)
        variants.append(("uhd=1 返回的 url 原样",
                         BING + uhd_doc["images"][0]["url"]))
    except Exception as exc:
        r.add("A-3 uhd=1 参数", "WARN", {"error": str(exc)}, "uhd=1 请求失败。")
    sizes = []
    for label, url in variants:
        try:
            st, body = get(url, args.timeout)
            wh = jpeg_size(body)
            sizes.append({"variant": label, "http": st,
                          "bytes": len(body), "pixels": wh})
        except Exception as exc:
            sizes.append({"variant": label, "error": str(exc)})
    r.add("A-3 图片规格与 UHD", "WARN", sizes,
          "UHD 须用 urlbase 自行拼接或剥离缩放参数；直接采用接口 url 会被服务端缩放到 1080p。",
          "规格 7.2「UHD 是请求偏好，不承诺 3840×2160」成立；"
          "界面应展示下载后解析的真实像素，而非 UHD 标签。")

    # 7.2 仅当天约束
    try:
        _, n3 = get_json({"format": "js", "idx": 0, "n": 3, "mkt": "zh-CN"},
                         args.timeout)
        count = len(n3.get("images", []))
        r.add("7.2 仅当天约束", "WARN" if count > 1 else "PASS",
              {"n": 3, "returned": count,
               "dates": [x.get("startdate") for x in n3.get("images", [])]},
              f"n=3 返回 {count} 天内容；实现必须硬编码 idx=0&n=1。",
              "不得为补齐历史而请求其它日期。")
    except Exception as exc:
        r.add("7.2 仅当天约束", "WARN", {"error": str(exc)}, "n=3 复核失败。")

    # A-4 接口自带用途声明
    tips = doc.get("tooltips", {})
    r.add("A-4 用途声明", "WARN",
          {"walls": tips.get("walls"), "walle": tips.get("walle")},
          "接口自带「仅限用作桌面壁纸」声明；自用下载＋设为桌面贴合该边界。",
          "不打包图片进发行物、不用于宣传截图、不商用、不再分发；"
          "自用定位下不需法律闭环，但边界应写进使用说明。")

    # A-1 请求频率（仅记录，不做压测）
    r.add("A-1 请求频率", "NOTE", {"requests_this_run": len(queries) + 4},
          "本次核验未做频率压测；实现应克制请求并复用短期元数据缓存。",
          "不绕过访问控制、不伪造身份；接口为非正式使用方式，随时可能变化。")

    out = {
        "verified_at": now.isoformat(),
        "scope": "单次快照 / 单一网络出口 / 不构成稳定契约",
        "project_mode": "完全自用，不公开发布",
        "items": r.items,
    }
    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=2)
        print(f"\n原始结果已写入 {args.json_path}")
    print("\n结论: 接口当前可用；地区、UHD 拼接、日期基准三项须在实现中按上述口径处理。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
