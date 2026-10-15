#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_vocab.py — 为 iOS 背单词 App (lexa) 生成 3 个词书 JSON。

运行前提（本目录下已有原始材料，抓取命令见下）：
  voa_wordbook.pdf   VOA Learning English Word Book 官方 PDF（14.6MB）
  awl_raw.json       AWL 570 词族 machine-readable 镜像
  stardict.db        ECDICT 1.0.28 SQLite 词典（约 340 万词条）

原始材料抓取命令（2026-10-14 执行）：
  # 1) VOA 官方词书 PDF（USAGM 旗下 VOA Learning English 官网下载链接；
  #    官网页面 https://learningenglish.voanews.com/a/voa-word-book/6607229.html）
  curl -L -A "Mozilla/5.0" \
    "https://docs.voanews.eu/en-us-learn/2022/06/07/c4dbd6af-5f63-4f28-bc42-0bd175f4e4b4.pdf" \
    -o voa_wordbook.pdf
  # 2) AWL 570 词头（Coxhead Academic Word List 的 machine-readable 镜像，
  #    按官方 10 个 sublist 组织；无释义，释义由 ECDICT 提供）
  curl -L "https://raw.githubusercontent.com/lpmi-13/machine_readable_wordlists/master/Academic/AWL/AWL.json" \
    -o awl_raw.json
  # 3) ECDICT（MIT 协议开源词典）。注：任务原计划用 ecdict.csv.zip，但该资产已从
  #    GitHub releases 移除（现仅有 1.0.28 的 stardict/sqlite 等 8 个包），故改用字段
  #    完全相同的官方 sqlite 版（python3 标准库 sqlite3 读取）。
  curl -L -C - "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip" \
    -o ecdict-sqlite-28.zip && unzip -o ecdict-sqlite-28.zip   # 得到 stardict.db

处理逻辑摘要：
  1. VOA：用 pdftotext 按左右两栏裁剪提取 PDF 第 12-88 页（词表正文），逐栏合并后
     用正则 "词 – 词性. 释义" 切出 1541 个词条；处理 PDF 换行连字符（respon- sible →
     responsible）、行尾标点伪影（"material,." / "a. decision"）、以及一处官方排版
     错误（walk 的释义与 wall 词条排在同一行，见 KNOWN_FIXES）。VOA 官方释义按
     "; " 拆成 defsEn；词形、音标、词性、中文释义均以 ECDICT 为准（去括号变体、
     小写、去重）；zh 为空的词条丢弃；含空格的多词词条（air force 等 6 个）按清洗
     规则丢弃。产出 voa_words.txt / voa_defs.tsv / voa_core.json。
  2. AWL：读 awl_raw.json 的 10 个 sublist 共 570 个词头（U+2011 连字符归一化），
     释义/音标/词性/中文全部来自 ECDICT。产出 awl_words.txt / awl_academic.json。
  3. exam：单遍扫描 stardict.db，收集 tag 含 toefl/ielts/gre 的词，排除已在 VOA/AWL
     集合中的词，按 frq 降序（0/缺失靠后，稳定排序）取前 1200 个。产出 exam_plus.json。
  清洗规则（全词书通用）：word 小写、按首次出现去重；丢弃含空格或以非字母开头的
  word；丢弃 zh 为空的词条；phonetic/pos 空串转 null；examples 一律 []。
  中文释义降噪（2026-10-15 加，详见 clean_zh/POS_OVERRIDES）：ECDICT translation 混有
  专业词典的领域义项（"[计] 累加器, 加法器…"），整行丢弃；行内短标签（[口] [棒球]）
  剥掉标签保留释义；若某词条全部释义都是领域行则退化为仅剥标签（不丢词、不动 id，
  以免打乱既有学习进度的 word id 映射）。

用法：
  python3 build_vocab.py                  # 完整重建（需要 stardict.db 等原始材料）
  python3 build_vocab.py --clean-committed  # 只对已生成的三个 JSON 就地做降噪清洗
                                           # （不依赖原始材料，规则与完整重建一致）

输出：voa_core.json / awl_academic.json / exam_plus.json（UTF-8，结构一致）。
"""

import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from collections import OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
VOA_PDF = os.path.join(HERE, "voa_wordbook.pdf")
VOA_PAGES_DIR = os.path.join(HERE, "voa_cols")          # pdftotext 裁剪输出
AWL_JSON = os.path.join(HERE, "awl_raw.json")
ECDB = os.path.join(HERE, "stardict.db")
VOA_FALLBACK_JSON = os.path.join(HERE, "voa_brandon.json")  # 备用镜像（无官方 PDF 时）

# 词表正文在 PDF 的第 12-88 页（页面尺寸 419.5x595.3pt，左栏 x:0-205，右栏 x:205-420）
VOA_PAGE_FIRST, VOA_PAGE_LAST = 12, 88

ENTRY_RE = re.compile(r"^(?P<word>.+?)\s*–\s*(?P<pos>ad|adj|n|v|pro|prep|conj|int)\.\s*(?P<def>.*)$")
WORD_CLEAN_RE = re.compile(r"\s*\([^)]*\)")   # 去掉 "a (an)" / "seek(ing)" 里的括号变体
WORD_OK_RE = re.compile(r"^[a-z][a-z'\-]*$")  # 小写字母开头，只含字母/撇号/连字符

# 官方 PDF 的已知排版缺陷：
#   1) p84 左栏中 "walk" 的释义换行 "in front of the other" 与下一条 "wall – n."
#      被排在同一行，按原文切回两条，避免 wall 丢失；
#   2) 同页左栏末尾 pdftotext 多吐出一个孤立的 "wall" token（PDF 文本层重复），
#      直接丢弃，否则会被当成 wall 释义的续行。
KNOWN_LINE_FIXES = {
    "in front of the other wall – n. the": [
        "in front of the other",
        "wall – n. the",
    ],
    "wall": [],
}


def log(*a):
    print(*a, flush=True)


# ---------------------------------------------------------------- VOA 解析 ----
def extract_voa_columns():
    """用 pdftotext 把官方 PDF 词表页按左右两栏裁剪提取到 voa_cols/。"""
    if not os.path.exists(VOA_PDF):
        return False
    if shutil.which("pdftotext") is None:
        log("[warn] pdftotext 不可用，VOA 将降级为镜像数据")
        return False
    os.makedirs(VOA_PAGES_DIR, exist_ok=True)
    for p in range(VOA_PAGE_FIRST, VOA_PAGE_LAST + 1):
        for side, x, w in (("L", 0, 205), ("R", 205, 215)):
            out = os.path.join(VOA_PAGES_DIR, f"p{p}_{side}.txt")
            cmd = ["pdftotext", "-layout", "-f", str(p), "-l", str(p),
                   "-x", str(x), "-y", "50", "-W", str(w), "-H", "525",
                   VOA_PDF, out]
            subprocess.run(cmd, check=True,
                           stderr=subprocess.DEVNULL)
    return True


def parse_voa_entries():
    """按页序（每页先左栏后右栏）解析出 [(word_raw, pos, definition), ...]。"""
    lines = []
    for p in range(VOA_PAGE_FIRST, VOA_PAGE_LAST + 1):
        for side in ("L", "R"):
            fn = os.path.join(VOA_PAGES_DIR, f"p{p}_{side}.txt")
            with open(fn, encoding="utf-8") as f:
                for raw in f:
                    line = raw.rstrip()
                    fixed = KNOWN_LINE_FIXES.get(line.strip())
                    if fixed is not None:   # 注意: 修复项可能为空列表(仅丢弃该行)
                        lines.extend(fixed)
                        continue
                    lines.append(line)

    entries = []   # [word_raw, definition_so_far]
    for line in lines:
        s = line.strip()
        if not s or re.fullmatch(r"[A-Z]{1,3}", s):   # 空行 / 字母分节头(A, XYZ)
            continue
        m = ENTRY_RE.match(s)
        if m and entries is not None:
            if m.group("word").strip():
                entries.append([m.group("word").strip(), m.group("def").strip()])
                continue
        # 否则为当前词条释义的续行
        if not entries:
            continue
        cur = entries[-1]
        prev = cur[1]
        nxt_first = s[:1]
        if prev.endswith("-"):                 # PDF 换行连字符: respon- sible
            cur[1] = prev[:-1] + s
        elif prev.endswith(",."):              # 行尾 ",." 伪影 → ","
            cur[1] = prev[:-1] + " " + s
        elif prev.endswith(".") and nxt_first.islower():  # 行尾 "." 伪影
            cur[1] = prev[:-1] + " " + s
        else:
            cur[1] = (prev + " " + s).strip()
    out = []
    for w, d in entries:
        d = re.sub(r"\s+", " ", d).strip()
        out.append((w, d))
    return out


def parse_voa_fallback():
    """降级：GitHub 镜像的 VOA Special English Word Book（含官方英文释义）。"""
    with open(VOA_FALLBACK_JSON, encoding="utf-8") as f:
        data = json.load(f)
    out = []
    for it in data:
        w = it.get("Value", "").strip()
        d = re.sub(r"\s+", " ", it.get("Definition", "")).strip()
        if w and d:
            out.append((w, d))
    return out


# ---------------------------------------------------------------- ECDICT -----
def open_ecdict():
    if not os.path.exists(ECDB):
        log("[error] 找不到 ECDICT 数据库 stardict.db")
        sys.exit(1)
    con = sqlite3.connect(ECDB)
    return con


def split_semicolon(text):
    """ECDICT definition 按分号/换行拆成释义数组，去空并压缩空白。
    ECDICT 用 '--' 占位表示“无英文释义”，视同空 → 空数组。"""
    if not text or text.strip() in ("--", "-"):
        return []
    parts = re.split(r"[;\n]", text)
    out = []
    for p in parts:
        p = re.sub(r"\s+", " ", p).strip()
        if p and p not in out:   # ECDICT 个别词条分号拆分后有完全重复的释义项
            out.append(p)
    return out


def split_translation(text):
    """ECDICT translation 按换行拆成中文释义数组，去空行和首尾空白。"""
    if not text:
        return []
    parts = re.sub(r"\r\n?", "\n", text).split("\n")
    return [p.strip() for p in parts if p.strip()]


# 专业词典领域义项：行首（可带词性前缀）的短方括号标签，如 "art. [计] 累加器…"、
# "[医] 胸廓"。这类行是 ECDICT 合并的专业词典内容，对学习者全是噪声。
ZH_HEAD_TAG_RE = re.compile(r"^\s*(?:[a-z]{1,6}\.\s*)?\[[^\]]{1,6}\]")
# 行内短标签（[口] [棒球] [航空]…）：前一个字符不是中文（避免误伤"面积[2]"之类），
# 方括号内不超过 4 字符（避免误伤真正的括号补充说明）。
ZH_INLINE_TAG_RE = re.compile(r"(?<![\u4e00-\u9fff])\[[^\]]{1,4}\]")
# ECDICT 个别功能词的 pos 明显错位（全库仅这几个），显示在卡片上会误导 learners。
POS_OVERRIDES = {"a": "art.", "the": "art.", "our": "pron."}


def strip_inline_tags(line):
    return re.sub(r"\s+", " ", ZH_INLINE_TAG_RE.sub("", line)).strip(" ;；")


def clean_zh(lines):
    """中文释义降噪：丢领域行、剥行内标签；全丢光时退化为剥标签保留。"""
    kept = [l for l in lines if not ZH_HEAD_TAG_RE.match(l)]
    kept = [c for l in kept if (c := strip_inline_tags(l))]
    if not kept:
        kept = [c for l in lines if (c := strip_inline_tags(l))]
    return kept


def clean_pos(word, pos):
    return POS_OVERRIDES.get(word, pos)


def clean_word(word):
    """统一小写；括号变体归一；含空格或非字母开头判为异常返回 None。"""
    w = WORD_CLEAN_RE.sub("", word.strip()).strip().lower()
    if not w or " " in w or not WORD_OK_RE.match(w):
        return None
    return w


# ---------------------------------------------------------------- 主流程 -----
def main():
    # 1) VOA 词条（官方 PDF 优先，镜像降级）
    if extract_voa_columns():
        voa_entries = parse_voa_entries()
        voa_src = "official PDF"
    else:
        voa_entries = parse_voa_fallback()
        voa_src = "github mirror (Brandon689)"
    log(f"[voa] 解析到 {len(voa_entries)} 条官方词条（来源: {voa_src}）")

    # 2) AWL 570 词头（保持官方 sublist 顺序）
    with open(AWL_JSON, encoding="utf-8") as f:
        awl_data = json.load(f)
    awl_heads, seen = [], set()
    for sublist in sorted(awl_data.keys()):
        for head in awl_data[sublist]:
            w = head.replace("\u2011", "-").strip().lower()  # so‑called 连字符归一
            if w and w not in seen:
                seen.add(w)
                awl_heads.append(w)
    log(f"[awl] {len(awl_heads)} 个词头")

    with open(os.path.join(HERE, "awl_words.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(awl_heads) + "\n")

    # 3) VOA 词形清洗 + 落盘 words.txt / defs.tsv
    voa_defs = OrderedDict()      # clean_word -> VOA 官方英文释义
    for w_raw, d in voa_entries:
        w = clean_word(w_raw)
        if not w or d == "":
            continue
        if w not in voa_defs:     # 以第一次出现为准
            voa_defs[w] = d
    log(f"[voa] 清洗后 {len(voa_defs)} 个词")

    with open(os.path.join(HERE, "voa_words.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(voa_defs.keys()) + "\n")
    with open(os.path.join(HERE, "voa_defs.tsv"), "w", encoding="utf-8") as f:
        for w, d in voa_defs.items():
            f.write(f"{w}\t{d}\n")

    # 4) 单遍扫描 ECDICT：为 voa/awl 匹配词条 + 收集 exam 候选
    awl_set = set(awl_heads)
    voa_set = set(voa_defs.keys())
    ec = {}                       # word -> dict(phonetic, definition, translation, pos)
    exam_pool = OrderedDict()     # word -> row（保持扫描顺序，排序时稳定）
    con = open_ecdict()
    cur = con.execute(
        "SELECT word, phonetic, definition, translation, pos, tag, frq "
        "FROM stardict")
    n = 0
    for word, phonetic, definition, translation, pos, tag, frq in cur:
        n += 1
        w = clean_word(word or "")
        if not w:
            continue
        if w not in ec and (w in voa_set or w in awl_set):
            ec[w] = {"phonetic": phonetic or "", "definition": definition or "",
                     "translation": translation or "", "pos": pos or ""}
        if w not in exam_pool and w not in voa_set and w not in awl_set:
            tags = (tag or "").split()
            if any(t in ("toefl", "ielts", "gre") for t in tags):
                exam_pool[w] = {"phonetic": phonetic or "",
                                "definition": definition or "",
                                "translation": translation or "",
                                "pos": pos or "", "frq": frq or 0}
    con.close()
    log(f"[ecdict] 扫描 {n} 行，匹配 voa/awl 词条 {len(ec)} 个，exam 候选 {len(exam_pool)} 个")

    # 5) exam 排序：ECDICT 的 frq 是“当代语料库(COCA)词频顺序”即排名，数值越小
    #    越高频（见 ECDICT README 字段表）。为达成“按词频精选”的目的，这里按 frq
    #    升序（最常用优先）取前 1200；frq 为 0/缺失的视为无排名排在最后（稳定排序）。
    exam_sorted = sorted(exam_pool.items(),
                         key=lambda kv: (0, kv[1]["frq"]) if kv[1]["frq"] > 0
                         else (1, 0))
    exam_selected = [w for w, _ in exam_sorted[:1200]]

    # 6) 组装词书
    def make_word(prefix, idx, word, rec, defs_en):
        return {
            "id": f"{prefix}-{idx}",
            "word": word,
            "phonetic": rec["phonetic"] if rec["phonetic"] else None,
            "pos": clean_pos(word, rec["pos"]) or None,
            "defsEn": defs_en,
            "zh": clean_zh(split_translation(rec["translation"])),
            "examples": [],
        }

    def build_book(book_id, title, subtitle, prefix, items):
        words, dropped = [], 0
        for i, (word, rec, defs_en) in enumerate(items, 1):
            if not split_translation(rec["translation"]):
                dropped += 1
                continue
            entry = make_word(prefix, len(words) + 1, word, rec, defs_en)
            words.append(entry)
        log(f"[{book_id}] 收词 {len(words)} 条，丢弃 zh 为空 {dropped} 条")
        return {"id": book_id, "title": title, "subtitle": subtitle,
                "words": words}

    # voa：优先 VOA 官方释义；ECDICT 没有的词直接丢弃（无 zh）
    voa_items = []
    for w, d in voa_defs.items():
        rec = ec.get(w)
        if not rec:
            continue
        voa_items.append((w, rec, split_semicolon(d)))
    book_voa = build_book(
        "voa", "VOA 核心词汇",
        "源自 VOA Learning English 官方 Word Book（美国国际媒体署），约 1500 核心词",
        "voa", voa_items)

    awl_items = []
    for w in awl_heads:
        rec = ec.get(w)
        if not rec:
            continue
        awl_items.append((w, rec, split_semicolon(rec["definition"])))
    book_awl = build_book(
        "awl", "AWL 学术词汇",
        "源自 Academic Word List（Averil Coxhead），北美大学英语教学广泛使用的 570 学术词族",
        "awl", awl_items)

    exam_items = []
    for w in exam_selected:
        rec = exam_pool.get(w)
        if not rec:   # 理论上不会发生：候选记录本身来自扫描
            continue
        exam_items.append((w, rec, split_semicolon(rec["definition"])))
    book_exam = build_book(
        "exam", "托福雅思进阶词汇",
        "按 ECDICT 考试标签(toefl/ielts/gre)与词频精选，适合四六级以上进阶",
        "exam", exam_items)

    for name, book in (("voa_core.json", book_voa),
                       ("awl_academic.json", book_awl),
                       ("exam_plus.json", book_exam)):
        path = os.path.join(HERE, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, indent=2)
            f.write("\n")
        log(f"[out] {path}  words={len(book['words'])}")


# ------------------------------------------------------- 就地清洗已提交 JSON ----
RESOURCES_DIR = os.path.join(HERE, "..", "Sources", "Resources")


def clean_committed():
    """对已生成的三个词书 JSON 就地应用 clean_zh/clean_pos（不依赖原始材料）。
    只清洗字段内容，不增删词条、不改 id —— 用户学习进度按 word id 存，不能动。"""
    for name in ("voa_core.json", "awl_academic.json", "exam_plus.json"):
        path = os.path.join(RESOURCES_DIR, name)
        with open(path, encoding="utf-8") as f:
            book = json.load(f)
        changed = 0
        for w in book["words"]:
            new_zh = clean_zh(w["zh"])
            new_pos = clean_pos(w["word"], w["pos"] or "") or None
            if new_zh != w["zh"] or new_pos != w["pos"]:
                changed += 1
            w["zh"], w["pos"] = new_zh, new_pos
        with open(path, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, indent=2)
            f.write("\n")
        log(f"[clean] {path}: {len(book['words'])} 词，清洗 {changed} 条")


if __name__ == "__main__":
    if "--clean-committed" in sys.argv:
        clean_committed()
    else:
        main()
