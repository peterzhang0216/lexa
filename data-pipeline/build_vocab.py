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
        "SELECT word, phonetic, definition, translation, pos, tag, frq, exchange "
        "FROM stardict")
    n = 0
    for word, phonetic, definition, translation, pos, tag, frq, exchange in cur:
        n += 1
        w = clean_word(word or "")
        if not w:
            continue
        if w not in ec and (w in voa_set or w in awl_set):
            ec[w] = {"phonetic": phonetic or "", "definition": definition or "",
                     "translation": translation or "", "pos": pos or "",
                     "exchange": exchange or ""}
        if w not in exam_pool and w not in voa_set and w not in awl_set:
            tags = (tag or "").split()
            if any(t in ("toefl", "ielts", "gre") for t in tags):
                exam_pool[w] = {"phonetic": phonetic or "",
                                "definition": definition or "",
                                "translation": translation or "",
                                "pos": pos or "", "frq": frq or 0,
                                "exchange": exchange or ""}
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
            "forms": forms_from_exchange(rec.get("exchange", ""), word),
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

    # 7) 例句（Tatoeba；原始包缺失时跳过，词书照常生成）
    try:
        ex_map = build_examples({b["id"]: [w["word"] for w in b["words"]]
                                 for b in (book_voa, book_awl, book_exam)})
        for book in (book_voa, book_awl, book_exam):
            for w in book["words"]:
                w["examples"] = ex_map.get(w["word"], [])
    except SystemExit:
        raise
    except Exception as e:                      # 例句是增强项，不阻断生成
        log(f"[warn] 例句生成失败（{e}），examples 置空")
        for book in (book_voa, book_awl, book_exam):
            for w in book["words"]:
                w["examples"] = []

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
TATOEBA_TARBALL = os.path.join(HERE, "tatoeba_sentences.tar.bz2")   # sentences.csv 容器

# 词书文件清单（顺序 = app 内展示顺序）
BOOK_FILES = ("voa_core.json", "cet4_core.json", "cet6_core.json",
              "ky_core.json", "awl_academic.json", "exam_plus.json")

# 考试词书规格（ECDICT tag 整词匹配；顺序即去重优先级，每词只进最先命中的书）
EXAM_BOOK_SPECS = [
    ("cet4", "四级核心词汇",
     "ECDICT cet4 标签词表，去除已收录词后按词频排序，覆盖四级高频",
     ("cet4",)),
    ("cet6", "六级核心词汇",
     "ECDICT cet6 标签词表，去除四级及已收录词后按词频排序",
     ("cet6",)),
    ("ky", "考研核心词汇",
     "ECDICT 考研(ky)标签词表，去重后精选（多数考研词已在四六级/VOA 中）",
     ("ky",)),
]

# ---------------------------------------------------------------- 例句（Tatoeba）----
# 纯功能词配例句没有学习价值（"a / the / of" 的句子不说明任何用法），直接跳过。
SKIP_EXAMPLES = {
    "a", "an", "the", "of", "to", "and", "or", "is", "are", "was", "were", "be",
    "been", "being", "am", "it", "its", "this", "that", "as", "at", "by", "in",
    "into", "on", "with", "but", "not", "no", "so", "if", "than", "then", "there",
    "he", "she", "they", "we", "you", "i", "his", "her", "their", "our", "my",
    "me", "him", "them", "us", "up", "down", "out", "off", "over", "under",
    "again", "once", "who", "which", "what", "when", "where", "why", "how",
}
# 常用功能/高频词（词书集合之外补齐），用于"句子用词是否简单"打分
COMMON_EXTRA = {
    "the", "be", "to", "of", "and", "a", "in", "that", "have", "i", "it", "for",
    "not", "on", "with", "he", "as", "you", "do", "at", "this", "but", "his",
    "by", "from", "they", "we", "say", "her", "she", "or", "an", "will", "my",
    "one", "all", "would", "there", "their", "what", "so", "up", "out", "if",
    "about", "who", "get", "which", "go", "me", "when", "make", "can", "like",
    "time", "no", "just", "him", "know", "take", "people", "into", "year",
    "your", "good", "some", "could", "them", "see", "other", "than", "then",
    "now", "look", "only", "come", "its", "over", "think", "also", "back",
    "after", "use", "two", "how", "our", "work", "first", "well", "way", "even",
    "new", "want", "because", "any", "these", "give", "day", "most", "us",
    "man", "woman", "mr", "mrs", "said", "says", "told", "asked",
}

TOKEN_RE = re.compile(r"[a-z]+")
SENT_OK_RE = re.compile(r"^[A-Za-z][A-Za-z ,.!?'\";:-]*$")


def inflected_forms(word):
    """与 app 端 WordHighlight.inflectedForms 保持一致的基础屈折表。"""
    forms = {word, word + "s", word + "es", word + "d", word + "ed", word + "ing"}
    stem = word[:-1] if word.endswith("y") else word
    forms |= {stem + "ies", stem + "ied"}
    if word and word[-1] not in "aeiou":
        forms |= {word + word[-1] + "ing", word + word[-1] + "ed"}
    return forms


def build_examples(words_by_book, preserve=None):
    """流式扫描 Tatoeba sentences.csv，给每个词挑最多 2 条例句。

    挑选规则：6-14 词的纯文本短句；按"句中词汇被词书+常用词覆盖的比例"打分
    （越高越接近学习者水平），同分偏好 9 词左右；同一句子全库只配给一个词。
    preserve: word -> [sentence, ...] 已有例句的词跳过重配，其句子也不再
    分给别的词（增量填充，保证幂等）。返回 word -> [sentence, ...]。
    """
    import tarfile
    if not os.path.exists(TATOEBA_TARBALL):
        log("[error] 找不到 tatoeba_sentences.tar.bz2（抓取命令见 SOURCES.md）")
        sys.exit(1)

    preserve = preserve or {}
    all_words = sorted(({w for ws in words_by_book.values() for w in ws}
                        - SKIP_EXAMPLES) - set(preserve))
    form_index = {}                       # 屈折形式 -> 目标词
    for w in all_words:
        for f in inflected_forms(w):
            form_index.setdefault(f, w)
    common = (set(all_words)
              | {w for ws in words_by_book.values() for w in ws}
              | set(preserve)
              | COMMON_EXTRA)

    candidates = {w: [] for w in all_words}
    used_texts = {s for ss in preserve.values() for s in ss}
    scanned = 0
    with tarfile.open(TATOEBA_TARBALL, "r:bz2") as tar:
        member = next(m for m in tar.getmembers() if m.name.endswith(".csv"))
        import io
        with io.TextIOWrapper(tar.extractfile(member), encoding="utf-8") as f:
            for line in f:
                scanned += 1
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 3 or parts[1] != "eng":
                    continue
                sid, text = parts[0], parts[2]
                toks = text.split(" ")
                if not 6 <= len(toks) <= 14:
                    continue
                if not SENT_OK_RE.match(text) or any(c.isdigit() for c in text):
                    continue
                if text in used_texts:
                    continue
                lower = TOKEN_RE.findall(text.lower())
                if not lower:
                    continue
                hit = None
                for t in lower:
                    hit = form_index.get(t)
                    if hit:
                        break
                if not hit:
                    continue
                coverage = sum(1 for t in lower if t in common) / len(lower)
                # 累计超过上限后只在分数更好时替换，内存有界
                cands = candidates[hit]
                key = (-coverage, abs(len(lower) - 9), sid)
                if len(cands) < 50:
                    cands.append((key, sid, text))
                else:
                    worst = max(range(len(cands)), key=lambda i: cands[i][0])
                    if key < cands[worst][0]:
                        cands[worst] = (key, sid, text)
                if scanned % 2_000_000 == 0:
                    log(f"[tatoeba] 已扫描 {scanned} 行…")

    examples, used = dict(preserve), set()
    for w in sorted(all_words, key=lambda x: len(candidates[x])):
        picked = []
        for key, sid, text in sorted(candidates[w]):
            if sid in used:
                continue
            used.add(sid)
            picked.append(text)
            if len(picked) == 2:
                break
        if picked:
            examples[w] = picked
    fresh = len(examples) - len(preserve)
    log(f"[tatoeba] 扫描 {scanned} 行，目标 {len(all_words)} 词"
        + (f"（保留已有 {len(preserve)}）" if preserve else "")
        + f"，新配 {fresh} 个（配到率 {fresh*100//max(1,len(all_words))}%）")
    return examples


def apply_examples(examples):
    """把例句写进三个已提交词书 JSON（--add-examples 模式，不动其他字段）。"""
    for name in BOOK_FILES:
        path = os.path.join(RESOURCES_DIR, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            book = json.load(f)
        filled = sum(1 for w in book["words"] if (ex := examples.get(w["word"])))
        for w in book["words"]:
            w["examples"] = examples.get(w["word"], [])
        with open(path, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, indent=2)
            f.write("\n")
        log(f"[examples] {name}: {filled}/{len(book['words'])} 词配到例句")


# ---------------------------------------------------------------- 词形变化（ECDICT）----
# ECDICT exchange 字段：逗号分隔的 "code:form"，code 见 ECDICT README。
# 只保留对学习者有意义的屈折，按固定顺序输出，最多 6 项；与原形相同的丢弃。
EXCHANGE_LABELS = [                      # (code, 中文标签)，展示顺序
    ("s", "复数"),
    ("3", "三单"),
    ("p", "过去式"),
    ("d", "过去分词"),
    ("i", "现在分词"),
    ("r", "比较级"),
    ("t", "最高级"),
]


def forms_from_exchange(exchange, word):
    if not exchange:
        return []
    table = {}
    for part in exchange.split("/"):     # ECDICT exchange 用 "/" 分隔，如 "d:done/p:did"
        code, _, form = part.partition(":")
        code, form = code.strip(), form.strip().lower()
        if form and form != word:
            table.setdefault(code, form)
    out = []
    for code, label in EXCHANGE_LABELS:
        if code in table:
            out.append(f"{label} {table[code]}")
        if len(out) == 6:
            break
    return out


def build_forms(words_by_book):
    """单遍扫描 stardict.db 的 exchange 列，返回 word -> ["复数 studies", ...]。"""
    all_words = {w for ws in words_by_book.values() for w in ws}
    forms = {}
    con = open_ecdict()
    cur = con.execute("SELECT word, exchange FROM stardict")
    n = 0
    for word, exchange in cur:
        n += 1
        w = clean_word(word or "")
        if not w or w in forms or w not in all_words:
            continue
        fs = forms_from_exchange(exchange or "", w)
        if fs:
            forms[w] = fs
    con.close()
    log(f"[forms] 扫描 {n} 行，{len(forms)}/{len(all_words)} 个词配到词形变化")
    return forms


def apply_forms(forms):
    """把词形变化写进三个已提交词书 JSON（--add-forms 模式，不动其他字段）。"""
    for name in BOOK_FILES:
        path = os.path.join(RESOURCES_DIR, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            book = json.load(f)
        filled = sum(1 for w in book["words"] if (fs := forms.get(w["word"])))
        for w in book["words"]:
            w["forms"] = forms.get(w["word"], [])
        with open(path, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, indent=2)
            f.write("\n")
        log(f"[forms] {name}: {filled}/{len(book['words'])} 词有词形变化")


# ------------------------------------------------------- 四六级/考研词书构建 ----
def build_exam_like_books(existing_words):
    """从 stardict.db 生成 cet4/cet6/ky 三本词书（每词只进最先命中的书，
    排除 existing_words；frq 升序=最常用在前）。返回 {文件名: book_dict}。"""
    tag_sets = {bid: set(tags) for bid, _, _, tags in EXAM_BOOK_SPECS}
    pools = {bid: {} for bid in tag_sets}
    claimed = set(existing_words)
    con = open_ecdict()
    cur = con.execute(
        "SELECT word, phonetic, definition, translation, pos, tag, frq, exchange "
        "FROM stardict")
    n = 0
    for word, phonetic, definition, translation, pos, tag, frq, exchange in cur:
        n += 1
        w = clean_word(word or "")
        if not w or w in claimed:
            continue
        for bid, _, _, _ in EXAM_BOOK_SPECS:
            if any(t in tag_sets[bid] for t in (tag or "").split()):
                pools[bid][w] = {"phonetic": phonetic or "",
                                 "definition": definition or "",
                                 "translation": translation or "",
                                 "pos": pos or "", "frq": frq or 0,
                                 "exchange": exchange or ""}
                claimed.add(w)
                break
    con.close()

    books = {}
    for bid, title, subtitle, _ in EXAM_BOOK_SPECS:
        items = sorted(pools[bid].items(),
                       key=lambda kv: (0, kv[1]["frq"]) if kv[1]["frq"] > 0
                       else (1, 0))
        words = []
        for w, rec in items:
            if not split_translation(rec["translation"]):
                continue
            words.append({
                "id": f"{bid}-{len(words) + 1}",
                "word": w,
                "phonetic": rec["phonetic"] if rec["phonetic"] else None,
                "pos": clean_pos(w, rec["pos"]) or None,
                "defsEn": split_semicolon(rec["definition"]),
                "zh": clean_zh(split_translation(rec["translation"])),
                "forms": forms_from_exchange(rec["exchange"], w),
                "examples": [],
            })
        books[f"{bid}_core.json"] = {"id": bid, "title": title,
                                     "subtitle": subtitle, "words": words}
        log(f"[{bid}] 收词 {len(words)} 条")
    log(f"[exam-like] 扫描 {n} 行")
    return books


def clean_committed():
    """对已生成的三个词书 JSON 就地应用 clean_zh/clean_pos（不依赖原始材料）。
    只清洗字段内容，不增删词条、不改 id —— 用户学习进度按 word id 存，不能动。"""
    for name in BOOK_FILES:
        path = os.path.join(RESOURCES_DIR, name)
        if not os.path.exists(path):
            continue
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


def load_committed_books():
    """读取 Resources 下已存在的词书（容忍缺文件），返回 {文件名: book}。"""
    books = {}
    for name in BOOK_FILES:
        path = os.path.join(RESOURCES_DIR, name)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                books[name] = json.load(f)
    return books


def words_by_book_of(books):
    return {b["id"]: [w["word"] for w in b["words"]] for b in books.values()}


if __name__ == "__main__":
    if "--clean-committed" in sys.argv:
        clean_committed()
    elif "--build-exam-books" in sys.argv:
        existing = load_committed_books()
        existing_words = {w for b in existing.values() for w in
                          (x["word"] for x in b["words"])}
        new_books = build_exam_like_books(existing_words)
        for name, book in new_books.items():
            path = os.path.join(RESOURCES_DIR, name)
            with open(path, "w", encoding="utf-8") as f:
                json.dump(book, f, ensure_ascii=False, indent=2)
                f.write("\n")
            log(f"[out] {path} words={len(book['words'])}")
        # 例句增量填充：已有词的例句原样保留，只为新词匹配
        all_books = load_committed_books()
        preserve = {w["word"]: w["examples"] for b in all_books.values()
                    for w in b["words"] if w.get("examples")}
        apply_examples(build_examples(words_by_book_of(all_books),
                                      preserve=preserve))
    elif "--add-examples" in sys.argv:
        books = load_committed_books()
        preserve = {w["word"]: w["examples"] for b in books.values()
                    for w in b["words"] if w.get("examples")}
        apply_examples(build_examples(words_by_book_of(books),
                                      preserve=preserve))
    elif "--add-forms" in sys.argv:
        books = load_committed_books()
        apply_forms(build_forms(words_by_book_of(books)))
    else:
        main()
