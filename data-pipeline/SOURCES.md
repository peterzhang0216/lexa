# lexa-data 词库数据来源与处理说明

获取日期：2026-10-14
生成工具：本目录下 `build_vocab.py`（python3 标准库，无第三方依赖；VOA 解析另需系统 `pdftotext`）

## 1. voa_core.json — VOA 核心词汇（1533 词）

- **来源（官方）**：VOA Learning English 官网 Word Book 页面
  <https://learningenglish.voanews.com/a/voa-word-book/6607229.html>
  页面内下载的官方 PDF（14.6MB，2022-06 版）：
  <https://docs.voanews.eu/en-us-learn/2022/06/07/c4dbd6af-5f63-4f28-bc42-0bd175f4e4b4.pdf>
  本地文件：`voa_wordbook.pdf`（词表正文为 PDF 第 12-88 页，双栏排版）
- **获取方式**：`pdftotext -layout` 按左右栏裁剪提取（`build_vocab.py` 自动完成，输出在 `voa_cols/`），正则解析出 1541 条官方词条（词 + 词性 + 英文释义），另存 `voa_words.txt` 与 `voa_defs.tsv`。
- **备用镜像**（本次未使用，仅当官方 PDF 解析不可用时降级）：
  <https://raw.githubusercontent.com/Brandon689/VOA-Special-English-Word-Book/master/VOA%20Special%20English%20Word%20Book.json>（1516 条，本地 `voa_brandon.json`）
- **授权**：VOA 为美国国际媒体署（USAGM）旗下机构，其 Word Book 属美国政府作品，**公有领域**（public domain），可自由使用与再分发。
- **英文释义**：全部来自 VOA 官方 PDF，按 `; ` 拆分为 `defsEn` 数组。
- **注意**：官方词书的数字、星期、月份等列入"Special Words"附录而非主词表，故 `one`、`Monday` 等不在本词书，与官方保持一致。

## 2. awl_academic.json — AWL 学术词汇（570 词）

- **来源（镜像）**：Academic Word List（Averil Coxhead, 2000）的 machine-readable 镜像
  <https://raw.githubusercontent.com/lpmi-13/machine_readable_wordlists/master/Academic/AWL/AWL.json>
  该镜像按 AWL 官方 10 个 sublist 组织，共 570 个词族词头（headword），与 Coxhead 原表一致（如 sublist 1 以 analyse, approach, area, assess, assume, authority… 开头）。
- **获取方式**：curl 下载后按 sublist 顺序读取词头，U+2011 连字符归一为普通连字符（`so‑called` → `so-called`），存 `awl_words.txt`。
- **授权**：AWL 版权归 Averil Coxhead 所有，作者**允许自由用于教学与研究目的（free for teaching and research purposes），需署名来源**：Coxhead, A. (2000). A New Academic Word List. *TESOL Quarterly*, 34(2), 213-238。本词书仅取 570 个词头，释义与中文释义来自下述 ECDICT。
- **英文释义/中文/音标/词性**：均来自 ECDICT（AWL 原表不含释义）。

## 3. exam_plus.json — 托福雅思进阶词汇（1200 词）

- **来源**：ECDICT 1.0.28（同上）。筛选 `tag` 含 `toefl` / `ielts` / `gre` 的词条，排除已入选 voa/awl 词书的词，按词频取前 1200 个。
- **排序说明（重要）**：ECDICT 的 `frq` 字段是"当代语料库（COCA）词频**顺序**"即排名，**数值越小越常用**（见 ECDICT README 字段表）。为达成"按词频精选、常用优先"的目的，实现按 `frq` **升序**（最常用在前）取前 1200；`frq` 为 0/缺失（无排名）的排在最后。这与任务稿面写法"frq 降序"不同——按字面降序会把最生僻的词排最前（如 brindled、polyandry），与"进阶词汇精选"的意图相悖，故按语义实现并在此如实说明。

## 3b. cet4_core / cet6_core / ky_core — 四级/六级/考研核心词汇（2026-10-16 加入）

- **来源**：ECDICT 1.0.28 的 `tag` 字段（整词匹配 `cet4` / `cet6` / `ky` 考研标签）。
- **构建**：`build_vocab.py --build-exam-books`（一条命令完成建书 + 增量配例句）。
  去重规则：每词只进最先命中的书（优先级 cet4 → cet6 → ky），且排除已收录在
  voa/awl/exam 词书中的词；按 `frq` 升序（最常用在前）。收词：cet4 1809、
  cet6 1672、ky 307（考研词大多已在四六级/VOA 中）。
- **已知历史问题**：voa↔awl 两本初代词书本身有 113 个重叠词（初版管线只对
  exam 词书做了去重），各自独立 id、独立进度，不合并不重排——重排会破坏
  存量用户的 word id 进度映射。
- **授权**：同 ECDICT（MIT）；例句同 4b（Tatoeba CC BY 2.0 FR）。

## 4. ECDICT（三个词书共用的中文释义/音标/词性来源）

- **来源**：<https://github.com/skywind3000/ECDICT/releases>（tag 1.0.28）
- **获取方式**：
  ```
  curl -L -C - "https://github.com/skywind3000/ECDICT/releases/download/1.0.28/ecdict-sqlite-28.zip" -o ecdict-sqlite-28.zip
  unzip -o ecdict-sqlite-28.zip   # 得到 stardict.db（约 340 万词条）
  ```
  **注意**：任务原计划下载 `ecdict.csv.zip`，但该资产已从 GitHub releases 移除（1.0.28 现仅有 eudic/mdx/mobi/sqlite/stardict 共 8 个包）。改用官方 **sqlite 版** `stardict.db`，字段与 csv 完全一致（word, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq），用 python3 标准库 `sqlite3` 读取。
- **授权**：MIT 协议，可自由商用与再分发。

## 4b. Tatoeba（例句来源，2026-10-15 加入）

- **来源**：<https://tatoeba.org> 开放句库官方导出
- **获取方式**：
  ```
  curl -L -C - "https://downloads.tatoeba.org/exports/sentences.tar.bz2" -o tatoeba_sentences.tar.bz2
  # 219MB（全语言 sentences.csv）；本地文件已列入 .gitignore，不入库
  ```
- **授权**：句库整体以 **CC BY 2.0 FR** 发布，可自由使用/修改/再分发，需署名 tatoeba.org（app 内署名在 设置 → 词库来源）。
- **处理**（`build_vocab.py --add-examples`，或完整重建时自动执行）：流式扫描 sentences.csv 的英语句（eng），选 6-14 词、纯常规标点的短句；按"句中词汇被三本词书+常用功能词覆盖的比例"打分（越接近学习者词汇量越好），同分偏好 9 词左右；目标词匹配含基础屈折形式（+s/+es/+ed/+ing/y→ies 等，与 app 端 `WordHighlight.inflectedForms` 一致）；**同一句子全库只配给一个词**；每个词最多 2 条；a/the/of 等纯功能词不配例句。
- **兜底**：语料包缺失或处理失败时 `examples` 置空，词书生成/清洗不受影响。

## 5. build_vocab.py 处理逻辑摘要

1. **VOA 解析**：pdftotext 按栏裁剪提取 PDF 第 12-88 页（左栏 x:0-205pt、右栏 x:205-420pt，跳过页眉页脚），按页序（先左栏后右栏）合并后用正则 `词 – 词性. 释义` 切分词条（1541 条）；处理 PDF 换行连字符（`respon- sible` → `responsible`）、行尾标点伪影（`material,.` → `material,`；换行处多余的句点），并修复官方 PDF 两处排版缺陷（p84：walk 释义续行与 wall 词条同排；同页文本层重复的孤立 "wall" token，见脚本 `KNOWN_LINE_FIXES`）。VOA 官方释义按 `;` 拆为 `defsEn`。
2. **AWL**：读 `awl_raw.json` 10 个 sublist 共 570 词头，保持官方顺序。
3. **ECDICT 匹配**：单遍扫描 `stardict.db`（3,402,564 行），为 voa/awl 词取音标/词性/中文释义；同时收集 exam 候选（tag 含 toefl/ielts/gre 且不在 voa/awl 集合，11,405 个），按 frq 升序取前 1200。
4. **清洗规则（全词书通用）**：
   - word 统一小写，去括号变体（`a (an)` → `a`，`seek(ing)` → `seek`），按首次出现去重；
   - 丢弃含空格（`air force`、`civil rights`、`genetic engineering`、`nucleic acid`、`swear in`、`Web site` 等）或以非字母字符开头的异常词条；
   - 丢弃中文释义（translation 按换行拆分后）为空的词条；
   - `phonetic` / `pos` 空串转 `null`；ECDICT definition 的 `--` 占位符视同为空（→ 空 `defsEn` 数组）；
   - `forms`：词形变化表，来自 ECDICT `exchange` 字段（`/` 分隔的 `code:form`），映射为「复数/三单/过去式/过去分词/现在分词/比较级/最高级」标签，最多 6 项、与原形相同的丢弃（2026-10-15 加入，`build_vocab.py --add-forms` 可单独补填）；
   - `examples`：来自 Tatoeba 例句（见 4b；功能词不配，其余每词最多 2 条）。
   - 中文释义降噪（2026-10-15）：ECDICT translation 行首带领域标签（"[计] …"、"[医] …"）的专业义项整行丢弃，行内短标签剥掉保留；`a/the/our` 等功能词词性按 override 表修正。
5. **产出**：`voa_core.json` / `awl_academic.json` / `exam_plus.json`（UTF-8，结构一致：id/title/subtitle/words[]，词条含 id、word、phonetic、pos、defsEn、zh、examples）。

## 6. 各文件清单

| 文件 | 说明 |
|---|---|
| `voa_core.json` | 词书：VOA 核心词汇，1533 词（释义来自官方 PDF） |
| `awl_academic.json` | 词书：AWL 学术词汇，570 词 |
| `exam_plus.json` | 词书：托福雅思进阶词汇，1200 词 |
| `voa_words.txt` / `voa_defs.tsv` | VOA 清洗后词表 / word↔官方释义 TSV |
| `awl_words.txt` | AWL 570 词头 |
| `build_vocab.py` | 处理脚本（头部注释含全部 curl 抓取命令） |
| `voa_wordbook.pdf` / `awl_raw.json` / `stardict.db` | 原始材料（抓取命令见脚本头部） |
| `voa_cols/` | pdftotext 分栏中间产物（脚本可重建） |
| `voa_brandon.json` | VOA 备用镜像（仅降级时使用） |
| `ecdict-sqlite-28.zip` | ECDICT 原始下载包（已解压出 stardict.db，可删除） |
