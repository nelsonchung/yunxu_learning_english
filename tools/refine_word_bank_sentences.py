#!/usr/bin/env python3
"""Refine weak word-bank example sentences with guarded, varied templates.

This tool is intentionally deterministic. It is not a dictionary; it uses the
existing word/meaning/POS data to replace polluted or template-like sentences
with safer bilingual examples. When the source meaning is too weak, it blocks
the entry for review instead of inventing a generic example.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "assets" / "word_bank" / "word_bank_main-d.json"


FORBIDDEN_RE = re.compile(
    r"作者|作家|Writers use|Older manuals use|如何在句子中使用|如何用|如何使用|"
    r"How to use|這個概念|這種狀態|這樣的方式|較舊的書|造句|vocabulary|word list|"
    r"flashcard|one that|的同義詞|的同義字|同義詞|同義字|罕見的或專門的英語術語|"
    r"罕見或專門的英語術語|英語術語",
    re.IGNORECASE,
)

AWKWARD_RE = re.compile(
    r"少見用語|冷門名詞|冷門形容詞|冷門副詞|冷門動作|韋氏|"
    r"比賽的最大活力|比賽或終點|保齡球比賽中球|詩人比賽|"
    r"選美比賽中的演員|選美比賽的或與之相關|這個問題|時細節|"
    r"一株一種|一個一種|一位一|很[A-Za-z]|以[A-Za-z]+的方式|"
    r"處理[A-Za-z]+這件事|處理[A-Za-z]+的細節|說話很[A-Za-z]|"
    r"以[^，。]{2,14}式|以[^，。]{2,30}方式|：.*地|或[^，。]{1,12}地|"
    r"通常以|通常用|－通常|一種[^，。]{2,20}的課堂例子|這份文件|這個計畫|"
    r"屬於、|關於、|與之相關|具有.*特徵|發生或分佈|用於保護|用於固定|"
    r"例如博物館|（例如|冒充或|错误|一个罕见|英语术语|通常作為|提供或實現|"
    r"透過雙眼|性發展的心理|她在會議中.+地回答|請在句子裡.+地使用這個字|"
    r"used .+ in a natural sentence|explained .+ with a clear example|"
    r"報告把.+和地方傳統連在一起|導覽員說明.+會出現在日常生活|"
    r"文章把.+描述為舊習俗|導覽資料用紅色標出|展示選了一個|"
    r"手作書示範|週末工作坊|在河邊指給大家看",
)

TEMPLATE_RE = re.compile(
    r"The teacher introduced .+ during class\.|She wrote a short note about .+ after class\.|"
    r"The article used .+ to describe a small detail\.|She noticed a .+ mark in the old photo\.|"
    r"He copied the note .+ so he would not miss anything\.|The plan changed .+ after the review\.|"
    r"If someone acts .+, they do so in a way|博物館標籤|舊展品|褪色地圖|舊地圖|"
    r"老照片裡注意到.*標記|The class learned about .+ during the lesson\.|"
    r"She added .+ to her notebook after class\.|The teacher wrote .+ on the board during class\.|"
    r"The teacher used .+ to describe the example\.",
)

WEIRD_TRANSLITERATION_RE = re.compile(
    r"伊伊|德德|克克|阿阿|爾伊|恩格爾|奇伊|阿恩|勒科克|夫伊伊|帕阿爾|"
    r"爾爾|斯斯|尤斯爾伊|卡爾爾伊|阿爾伊|歐恩|伊恩|亞阿|安恩|"
    r"阿布爾|克提奧恩|提奧恩|比伊|巴阿|布爾伊|布爾爾|西伊|卡阿|科歐|科伊|查阿"
)

OLD_TEMPLATE_RES = [
    re.compile(pattern)
    for pattern in (
        r"^The device used a .+ part to improve performance\.",
        r"^A .+ signal appeared on the screen\.",
        r"^She used .+ to solve a small problem at work\.",
        r"^The new plan depended on .+\.",
        r"^The team noticed .+ during the morning check\.",
        r"^.+ became important after the first test\.",
        r"^The doctor noted a .+ change in the report\.",
        r"^A .+ pattern appeared after treatment\.",
        r"^The .+ material reacted during the test\.",
        r"^The sample looked .+ under the microscope\.",
        r"^The researcher studied .+ in the lab\.",
        r"^.+ affected the test results\.",
        r"^The cells showed .+ under the microscope\.",
        r"^.+ affected the animal's growth\.",
    )
]

QUALITY_RE = re.compile(
    "|".join(
        [
            FORBIDDEN_RE.pattern,
            AWKWARD_RE.pattern,
            TEMPLATE_RE.pattern,
            WEIRD_TRANSLITERATION_RE.pattern,
        ]
    ),
    re.IGNORECASE,
)

NOISY_MEANING_RE = re.compile(
    r"英語術語|英语术语|英文術語|韋氏|字典|"
    r"記錄為|记录为|包含在|同義詞|同義字|How to use|Learn definitions|"
    r"Synonym Discussion|Merriam-Webster",
    re.IGNORECASE,
)

PLACEHOLDER_MEANING_RE = re.compile(
    r"罕見(?:的)?(?:或專門的|或专门的)?(?:英語|英语|英文)?術語|"
    r"罕见(?:的)?(?:或专门的)?(?:英语|英文)?术语|"
    r"(?:記錄為|记录为)\s*[A-Za-z][A-Za-z .'-]+|"
    r"^[A-Za-z][A-Za-z .'-]+$",
    re.IGNORECASE,
)

META_OUTPUT_RE = re.compile(
    r"這個詞|這個副詞|這個形容詞|這個動詞|意思|詞彙表|例句|"
    r"meaning of|glossary|natural sentence|clear example|"
    r"teacher wrote|teacher used|teacher gave|teacher explained",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Context:
    word: str
    meaning: str
    pos: str
    label: str | None
    domain: str
    confidence: str


SPECIFIC_ADVERB_KEYS = {
    "dabbl",
    "dactyl",
    "calm",
    "clear",
    "correct",
    "comfort",
    "commercial",
    "collect",
    "conscious",
    "constant",
    "creative",
    "critical",
    "cruel",
    "danger",
    "deliberate",
    "different",
    "directly",
    "dense",
    "diligent",
    "dishonest",
    "dismiss",
    "digestib",
    "digital",
    "explicit",
}

SAFE_SPECIAL_WORDS = {
    "earner",
    "endocarp",
    "enquirer",
    "enthusiasm for english",
    "entrant",
    "entree",
    "esko flower arranging",
    "esparto",
    "esquire",
    "estoppel",
    "etiology",
    "evader",
    "exon",
    "fifteener",
    "fableist",
    "fablemonger",
    "fairgoer",
    "feedbox",
    "fatalness",
    "fearlessness",
    "feeding bottle",
    "fellow feeling",
    "fender",
    "ferry boat",
    "ferryman",
    "floor lamp",
    "floppy disk",
    "flower arranging",
    "flower bed",
    "flower nursery",
    "flowerpot",
    "flowers",
    "flu virus",
    "fluorescent lamp",
    "fog light",
    "food chain",
    "food preservation",
    "food processing",
    "foodie",
    "footstool",
    "forefinger",
    "forsythia",
    "fortescue",
    "foxhound",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refine weak bilingual example sentences in a word-bank shard."
    )
    parser.add_argument("--path", default=str(DEFAULT_PATH), help="Shard path to refine.")
    parser.add_argument("--apply", action="store_true", help="Write changes to --path.")
    parser.add_argument("--limit", type=int, help="Maximum entries to refine.")
    parser.add_argument("--offset", type=int, default=0, help="Offset in candidate order.")
    parser.add_argument("--report", help="Optional JSON report path.")
    parser.add_argument(
        "--include-clean",
        action="store_true",
        help="Also refine entries that are not currently flagged. Useful for upgrading fallback-heavy shards.",
    )
    parser.add_argument(
        "--allow-low-confidence",
        action="store_true",
        help="Allow low-confidence generic output. Off by default so weak entries are reported as blocked.",
    )
    parser.add_argument(
        "--allow-general",
        action="store_true",
        help="Allow generic-domain fallback sentences. Off by default to avoid fixed, artificial examples.",
    )
    parser.add_argument(
        "--report-limit",
        type=int,
        default=200,
        help="Maximum changes/blocked items to include in the report. Use 0 for all.",
    )
    return parser.parse_args()


def repo_path(raw_path: str) -> Path:
    path = Path(raw_path)
    return path if path.is_absolute() else ROOT / path


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    with temp_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")
    os.replace(temp_path, path)


def split_bilingual_sentence(sentence: str) -> tuple[str, str]:
    for index, char in enumerate(sentence):
        if "\u4e00" <= char <= "\u9fff":
            start = index
            while start > 0 and sentence[start - 1].isspace():
                start -= 1
            return sentence[:start].strip(), sentence[start:].strip()
    return sentence.strip(), ""


def zh_half(sentence: str) -> str:
    return split_bilingual_sentence(sentence)[1]


def raw_word_in_zh(word: str, sentence: str) -> bool:
    if len(word) < 3:
        return False
    return bool(re.search(rf"(?<![A-Za-z]){re.escape(word)}(?![A-Za-z])", zh_half(sentence), re.IGNORECASE))


def entry_reasons(entry: dict[str, Any]) -> list[str]:
    word = str(entry.get("word", ""))
    meaning = str(entry.get("meaning", ""))
    sentences = [str(sentence) for sentence in entry.get("sentences") or []]
    reasons: list[str] = []
    if NOISY_MEANING_RE.search(meaning) or PLACEHOLDER_MEANING_RE.search(meaning):
        reasons.append("weak_or_noisy_meaning")
    if re.search(r"字首|字尾|前綴|後綴|prefix|suffix", meaning, re.IGNORECASE):
        reasons.append("affix_meaning_needs_review")
    if any(raw_word_in_zh(word, sentence) for sentence in sentences):
        reasons.append("raw_word_in_zh")
    if any(FORBIDDEN_RE.search(sentence) for sentence in sentences):
        reasons.append("forbidden_text")
    if any(AWKWARD_RE.search(sentence) for sentence in sentences):
        reasons.append("awkward_text")
    if any(TEMPLATE_RE.search(sentence) for sentence in sentences):
        reasons.append("template_sentence")
    if any(WEIRD_TRANSLITERATION_RE.search(sentence) for sentence in sentences):
        reasons.append("weird_transliteration")
    if any(any(pattern.search(sentence) for pattern in OLD_TEMPLATE_RES) for sentence in sentences):
        reasons.append("old_template_sentence")
    if len(sentences) != 2:
        reasons.append("invalid_sentence_count")
    return reasons


SENTENCE_REASON_KEYS = {
    "raw_word_in_zh",
    "forbidden_text",
    "awkward_text",
    "template_sentence",
    "weird_transliteration",
    "old_template_sentence",
    "invalid_sentence_count",
}


def needs_sentence_refine(reasons: Iterable[str]) -> bool:
    return any(reason in SENTENCE_REASON_KEYS for reason in reasons)


def normalize_pos(pos: str, word: str) -> str:
    raw = pos.lower().strip()
    if "adv" in raw or word.lower().endswith("ly") or word.lower().endswith("wise"):
        return "adverb"
    if "adj" in raw:
        return "adjective"
    if "verb" in raw or raw in {"v", "v."}:
        return "verb"
    if "prep" in raw:
        return "preposition"
    if "conj" in raw:
        return "conjunction"
    if "interj" in raw or "exclamation" in raw:
        return "exclamation"
    return "noun"


def sanitize_label(label: str | None) -> str | None:
    if not label:
        return None
    cleaned = str(label)
    replacements = {
        "可人饮用": "可飲用",
        "可人飲用": "可飲用",
        "可饮用": "可飲用",
        "可口的食物": "精緻點心",
        "可口食物": "精緻點心",
        "是標準瓶體積的一半": "半瓶容量",
        "標準瓶體積的一半": "半瓶容量",
        "相當於女騎士 的頭銜": "女騎士頭銜",
        "相當於女騎士的頭銜": "女騎士頭銜",
        "喘可鄙": "可鄙",
        "加 诊断": "診斷",
        "加 診斷": "診斷",
        "董事会": "董事會",
        "数字圖書館": "數位圖書館",
        "数字图书馆": "數位圖書館",
        "数位技术": "數位技術",
        "数字技术": "數位技術",
        "電話的) 撥號聲": "撥號聲",
        "电话的) 撥號聲": "撥號聲",
        "電話的) 区号": "區號",
        "电话的) 区号": "區號",
        "美国) 小學": "小學",
        "美國) 小學": "小學",
        "区号": "區號",
        "电话的": "撥號聲",
        "上四饮食学": "飲食學",
        "上四飲食學": "飲食學",
        "吕隔膜": "隔膜",
        "工作者": "從業人員",
        "製作者": "製作的人",
        "創作者": "創作的人",
        "作者": "撰寫者",
        "作家": "寫手",
        "同義詞": "相近用語",
        "同義字": "相近用字",
        "如何": "",
    }
    for old, new in replacements.items():
        cleaned = cleaned.replace(old, new)
    cleaned = re.sub(r"^以(.+?)(?:的)?(?:方式|形式)$", r"\1", cleaned)
    cleaned = re.sub(r"屬的一種植物$", "", cleaned)
    cleaned = re.sub(r"屬$", "", cleaned)
    cleaned = re.sub(r"的一種$", "", cleaned)
    cleaned = re.sub(r"^[一二三四五六七八九十]張(?=.+(?:沙發|桌|椅|床))", "", cleaned)
    cleaned = re.sub(r"(?:的)?名稱$", "", cleaned)
    if cleaned.startswith("血") and not re.match(r"血(?:液|管|壓|糖|紅素|小板|球|清|漿|尿|症|栓|友病)", cleaned):
        cleaned = cleaned[1:]
    cleaned = re.sub(r"^[一二三四五六七八九十]+\s*(?=(?:可口|美味|好吃|精緻|精致|有害|有用))", "", cleaned)
    cleaned = re.sub(r"^四\s*", "", cleaned)
    cleaned = re.sub(r"^(?:加|上四|吕|國)\s*", "", cleaned)
    cleaned = cleaned.strip(" 。，；;:：、")
    if (
        not cleaned
        or FORBIDDEN_RE.search(cleaned)
        or TEMPLATE_RE.search(cleaned)
        or WEIRD_TRANSLITERATION_RE.search(cleaned)
        or re.search(r"相近用語|相近用字|記錄為|记录为|被記錄為|被记录为|學習定義|学习定义", cleaned)
    ):
        return None
    if META_OUTPUT_RE.search(cleaned):
        return None
    return cleaned[:18]


def short_label(meaning: str, word: str) -> tuple[str | None, str]:
    if not meaning or PLACEHOLDER_MEANING_RE.search(meaning):
        return None, "low"
    cleaned = re.sub(r"[A-Za-z][A-Za-z\-. ]*", "", meaning)
    cleaned = re.sub(r"[“”\"'`]", "", cleaned)
    cleaned = re.sub(r"^【[^】]+】", "", cleaned)
    cleaned = re.sub(r"^\[[^\]]+\]", "", cleaned)
    cleaned = re.sub(r"^(?:電話|电话)的[)）]\s*", "", cleaned)
    cleaned = re.sub(r"[（(][^）)]*[）)]", "", cleaned)
    cleaned = re.sub(r"^(?:一種|一种|某種|某种)", "", cleaned)
    cleaned = re.sub(r"^(?:罕見的?|罕见的?|較少見的?|较少见的?|古語|古语|罕用的?)", "", cleaned)
    cleaned = re.sub(r"^(?:的|之)", "", cleaned)
    cleaned = cleaned.strip()
    pieces = re.split(r"[。；;，,:：/()]|、", cleaned)
    generic_labels = {
        "邏輯學",
        "逻辑学",
        "威爾斯法律",
        "威尔斯法律",
        "術語",
        "术语",
        "名詞",
        "名词",
        "植物",
        "動物",
        "动物",
        "物質",
        "物质",
        "礦物",
        "矿物",
        "方礦物",
        "方矿物",
        "東西",
        "东西",
        "和",
        "或",
        "寫作",
        "写作",
    }
    for piece in pieces:
        candidate = sanitize_label(piece.strip())
        if not candidate:
            continue
        if candidate in generic_labels:
            continue
        if re.search(r"屬於|關於|通常|一種|用於|包括|相關|等同於|變體|拼寫", candidate):
            continue
        if len(candidate) <= 10:
            return candidate, "high"
    for piece in pieces:
        candidate = sanitize_label(piece.strip())
        if candidate:
            if candidate in generic_labels:
                continue
            return candidate, "medium"
    return None, "low"


def infer_domain(word: str, meaning: str, label: str | None) -> str:
    text = f"{word} {meaning} {label or ''}".lower()
    text = re.sub(r"血(?=謾罵|谩骂|損害|损害|賠償|赔偿|擠奶|挤奶)", "", text)
    if re.search(r"酒後駕車|酒后驾车|drunk driving", text):
        return "safety"
    if re.search(r"可飲用|可饮用|飲用|drinkable|potable", text):
        return "drink"
    if re.search(r"飲品|飲料|茶|湯|咖啡|drink|beverage|soup", text):
        return "drink"
    if re.search(r"主菜|餐點|菜餚|菜肴|食物|food|dish|entree", text):
        return "food"
    if re.search(r"電腦|电脑|伺服器|進程|进程|程式|程序|server|process|computer", text):
        return "technology"
    if re.search(r"數位|数字|數字|磁碟|訊號|信号|圖書館|图书馆|時鐘|钟|撥號|拨号|電話|区号|區號|digital|disk|signal|library|clock|phone", text):
        return "technology"
    if re.search(r"騎手|骑手|driver|rider|cyclist", text):
        return "person"
    if re.search(r"馬車|小艇|小船|航班|車|船|公車|飛機|flight|boat|carriage|vehicle", text):
        return "transport"
    if re.search(r"精神分裂|精神疾病|心理疾病|mental illness|schizophrenia", text):
        return "medical"
    if re.search(r"腹瀉|白喉|診斷|诊断|難產|难产|飲食學|饮食学|利尿|消化|diarrhea|diphtheria|diagnostic|dietetic|digestion", text):
        return "medical"
    if re.search(r"黏性物質|粘性物质|黏著物|粘着物|用於防治害蟲|sticky substance|adhesive", text):
        return "material"
    if re.search(r"沙發|桌|椅|床|家具|sofa|couch|table|chair|furniture", text):
        return "furniture"
    if re.search(r"食物|可口|點心|点心|堅果|坚果|辣椒|酪梨|蛋糕|food|soup|cake|nut", text):
        return "food"
    if re.search(r"手指|足趾|手部|腳趾|身体|身體|finger|toe", text):
        return "body"
    if re.search(r"女工|工人|的人|人員|人员|者|師|商|族|成員|成员|maid|worker|people|person|singer|member", text):
        return "person"
    if re.search(r"十個|十个|一組十|一组十|半瓶|瓶體積|瓶体积|dozen|ten items|group of ten", text):
        return "quantity"
    if re.search(r"10的|十進位|十进位|第十|符號|符号|行列式|半音|漸弱|渐弱|數量|数量|delta|decimal|determinant|semitone|decrescendo", text):
        return "math"
    if re.search(r"頭銜|头衔|騎士|爵士|貴族|贵族|title|knight|dame", text):
        return "title"
    if re.search(r"法律|權利|罰金|賠償|法院|law|legal|court", text):
        return "law"
    if re.search(r"醫|病|症|細胞|神經|血|骨|肌|皮膚|治療|doctor|patient|cell|medical", text):
        return "medical"
    if re.search(r"水合物|矽化物|硅化物|糖苷|元素|蒸餾|蒸馏|化物|酸|compound|hydrate|distil", text):
        return "science"
    if re.search(r"科名|亞科|亚科|綱|纲|目名|分類|分类|classification|taxonom", text):
        return "taxonomy"
    if re.search(r"植物|樹|花|草|果|種子|葉|木|藻|龍膽|菊|杉|松|麻|作物|綠肥|botan|plant|tree|flower|seed", text):
        return "plant"
    if re.search(r"魚|鳥|犬|狗|貓|動物|昆蟲|蟲|魟|夜鶯|犰狳|袋鼬|金龜|animal|fish|bird|dog|insect", text):
        return "animal"
    if re.search(r"化學|酸|鹽|礦|晶|金屬|酵素|反應|綠柱石|鈣霞石|compound|mineral|chemical|enzyme", text):
        return "science"
    if re.search(r"山谷|丘陵|河谷|valley|dale|hill", text):
        return "geography"
    if re.search(r"德拉瓦州|地區|地区|坑|豎井|竖井|堤|州|area|state|pit|shaft|dike", text):
        return "place"
    if re.search(r"損害|损害|傷害|伤害|有害|damage|harmful", text):
        return "damage"
    if re.search(r"絕望|绝望|沮喪|沮丧|厭惡|厌恶|嘲弄|恐怖|不屑|貧窮|贫穷|莊重|庄重|可鄙|不誠實|不诚实|devotion|despair|disgust|mock|fear|poor|dignified", text):
        return "emotion"
    if re.search(r"存款|董事|市場|市场|電話費|电话费|貶值|贬值|商業|商业|bank|deposit|director|market|fee|devaluation", text):
        return "business"
    if re.search(r"檯燈|台灯|燈|灯|偵測器|侦测器|盤子|盘子|郵袋|邮袋|裝置|装置|工具|lamp|detector|bag|device|tool", text):
        return "object"
    if re.search(r"神話|神话|希臘|希腊|達那|达那|myth", text):
        return "mythology"
    if re.search(r"雕刻|寶石|宝石|藝術|艺术|建築|建筑|風格|风格|\bjewel\b|\bgem\b|carv|style", text):
        return "art"
    if re.search(r"邏輯|逻辑|三段論|三段论|論證|论证|logic|syllogism|argument", text):
        return "logic"
    if re.search(r"語|文法|發音|拼寫|音節|詩|格律|language|grammar|poem|verse", text):
        return "language"
    if re.search(r"宗教|教義|神話|神明|神祇|儀式|祈禱|church|ritual|theology", text):
        return "religion"
    if re.search(r"單位|英吋|加侖|重量|長度|容量|unit|measure", text):
        return "unit"
    if re.search(r"插花|flower arranging", text):
        return "art"
    return "general"


def choose(word: str, options: list[tuple[str, str]]) -> tuple[str, str]:
    digest = hashlib.sha256(word.encode("utf-8")).digest()
    return options[digest[0] % len(options)]


def context_for(entry: dict[str, Any]) -> Context:
    word = str(entry.get("word", "")).strip()
    meaning = str(entry.get("meaning", "")).strip()
    pos = normalize_pos(str(entry.get("partOfSpeech", "")), word)
    if pos == "verb" and re.search(r"的|有害|有用|損害的|损害的", meaning) and re.search(r"(ed|ing)$", word.lower()):
        pos = "adjective"
    label, confidence = short_label(meaning, word)
    domain = infer_domain(word, meaning, label)
    if domain == "technology" and re.search(r"守護進程|守护进程", meaning):
        label = "守護進程"
        confidence = "high"
    return Context(word=word, meaning=meaning, pos=pos, label=label, domain=domain, confidence=confidence)


def article(word: str) -> str:
    return "an" if word[:1].lower() in {"a", "e", "i", "o", "u"} else "a"


def noun_sentences(ctx: Context) -> list[str]:
    word = ctx.word
    if not ctx.label:
        return []
    label = ctx.label
    if ctx.domain == "animal" and re.search(r"狗|犬", label):
        templates = [
            (f"The family adopted a {word} from the shelter.", f"這家人從收容所領養了一隻{label}。"),
            (f"A {word} slept beside the sofa all afternoon.", f"一隻{label}整個下午睡在沙發旁。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    if ctx.domain == "plant" and re.search(r"作物|綠肥|农|農|土壤|soil|crop", ctx.meaning, re.IGNORECASE):
        templates = [
            (f"Farmers planted {word} before the rice season.", f"農民在稻作季前種下{label}。"),
            (f"The field used {word} to improve the soil.", f"這塊田用{label}改善土壤。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    if ctx.word.lower() == "earner":
        return [
            combine("Her father was the main earner in the family.", "她父親是家裡主要賺錢的人。"),
            combine("A steady earner can help support the household.", "收入穩定的人可以幫忙支撐家計。"),
        ]
    if ctx.word.lower() == "fableist":
        return [
            combine("The fableist told a short story to the children.", "寓言作家給孩子們講了一個短故事。"),
            combine("A good fableist can teach a lesson through animals.", "好的寓言作家能透過動物故事傳達道理。"),
        ]
    if ctx.word.lower() == "fablemonger":
        return [
            combine("The fablemonger entertained the crowd with old stories.", "說寓言的人用老故事逗大家開心。"),
            combine("Children gathered around the fablemonger after dinner.", "晚餐後孩子們圍在說寓言的人身邊。"),
        ]
    if ctx.word.lower() == "fairgoer":
        return [
            combine("The fairgoer bought snacks near the entrance.", "逛博覽會的人在入口附近買了點心。"),
            combine("Many fairgoers waited in line for the new ride.", "許多逛博覽會的人排隊等新的遊樂設施。"),
        ]
    if ctx.word.lower() == "feedbox":
        return [
            combine("The farmer filled the feedbox before sunrise.", "農夫在日出前把飼料箱裝滿。"),
            combine("The horse ate quietly from the feedbox.", "馬安靜地從飼料箱裡吃東西。"),
        ]
    if ctx.word.lower() == "fifteener":
        return [
            combine("The poet counted the syllables in the fifteener.", "詩人數了那行十五音節詩句的音節。"),
            combine("The class practiced reading a fifteener aloud.", "課堂練習朗讀一行十五音節的詩句。"),
        ]
    if ctx.word.lower() == "fatalness":
        return [
            combine("The report warned about the fatalness of the mistake.", "報告提醒大家這個錯誤可能致命。"),
            combine("The doctor explained the fatalness of the injury.", "醫生說明這種傷勢的致命性。"),
        ]
    if ctx.word.lower() == "fearlessness":
        return [
            combine("Her fearlessness helped the team stay calm.", "她的無畏讓團隊保持冷靜。"),
            combine("The coach praised his fearlessness during the game.", "教練稱讚他在比賽中的無畏。"),
        ]
    if ctx.word.lower() == "feeding bottle":
        return [
            combine("She warmed the feeding bottle before bedtime.", "她睡前把奶瓶溫熱。"),
            combine("The baby held the feeding bottle with both hands.", "寶寶用雙手抱著奶瓶。"),
        ]
    if ctx.word.lower() == "fellow feeling":
        return [
            combine("Her fellow feeling made him feel less alone.", "她的同理心讓他覺得不那麼孤單。"),
            combine("The story created fellow feeling among the neighbors.", "這個故事讓鄰居之間產生同病相憐的感覺。"),
        ]
    if ctx.word.lower() == "fender":
        return [
            combine("The mechanic replaced the dented fender.", "技師換掉凹陷的車側板。"),
            combine("Mud splashed onto the bicycle fender.", "泥巴濺到自行車擋泥板上。"),
        ]
    if ctx.word.lower() == "ferry boat":
        return [
            combine("The ferry boat carried cars across the river.", "渡船把汽車載過河。"),
            combine("We waited for the ferry boat at the pier.", "我們在碼頭等渡船。"),
        ]
    if ctx.word.lower() == "ferryman":
        return [
            combine("The ferryman helped passengers onto the boat.", "渡船夫協助乘客上船。"),
            combine("The old ferryman knew the river well.", "老渡船夫很熟悉這條河。"),
        ]
    if ctx.word.lower() == "floor lamp":
        return [
            combine("She turned on the floor lamp beside the sofa.", "她打開沙發旁的落地燈。"),
            combine("The floor lamp made the room feel warmer.", "落地燈讓房間感覺更溫暖。"),
        ]
    if ctx.word.lower() == "floppy disk":
        return [
            combine("He found an old floppy disk in the drawer.", "他在抽屜裡找到一片舊軟碟。"),
            combine("The computer could no longer read the floppy disk.", "那台電腦已經讀不到那片軟碟。"),
        ]
    if ctx.word.lower() == "flower arranging":
        return [
            combine("She practices flower arranging every Saturday.", "她每週六練習插花。"),
            combine("Flower arranging made the room feel fresh.", "插花讓房間感覺更清新。"),
        ]
    if ctx.word.lower() == "flower bed":
        return [
            combine("Grandma planted roses in the flower bed.", "奶奶在花壇裡種玫瑰。"),
            combine("The children watered the flower bed after school.", "孩子們放學後幫花壇澆水。"),
        ]
    if ctx.word.lower() == "flower nursery":
        return [
            combine("She bought seedlings from the flower nursery.", "她從花圃買了幼苗。"),
            combine("The flower nursery opens early in spring.", "那座花圃春天很早就開門。"),
        ]
    if ctx.word.lower() == "flowerpot":
        return [
            combine("He put the basil in a small flowerpot.", "他把羅勒種在小花盆裡。"),
            combine("The flowerpot cracked during the move.", "花盆在搬家時裂開了。"),
        ]
    if ctx.word.lower() == "flowers":
        return [
            combine("She put fresh flowers on the table.", "她把新鮮的花放在桌上。"),
            combine("The flowers smelled sweet after the rain.", "雨後的花聞起來很香。"),
        ]
    if ctx.word.lower() == "flu virus":
        return [
            combine("The flu virus spread quickly through the school.", "流感病毒很快在學校裡傳開。"),
            combine("Doctors watched for changes in the flu virus.", "醫生觀察流感病毒的變化。"),
        ]
    if ctx.word.lower() == "fluorescent lamp":
        return [
            combine("The fluorescent lamp buzzed above the desk.", "書桌上方的螢光燈嗡嗡作響。"),
            combine("They replaced the old fluorescent lamp in the kitchen.", "他們換掉廚房裡的舊螢光燈。"),
        ]
    if ctx.word.lower() == "fog light":
        return [
            combine("He turned on the fog light during the storm.", "暴風雨中他打開霧燈。"),
            combine("The mechanic checked the fog light before the trip.", "技師在出發前檢查霧燈。"),
        ]
    if ctx.word.lower() == "food chain":
        return [
            combine("The teacher drew a simple food chain on the board.", "老師在白板上畫了一條簡單的食物鏈。"),
            combine("Small fish are part of the ocean food chain.", "小魚是海洋食物鏈的一部分。"),
        ]
    if ctx.word.lower() == "food preservation":
        return [
            combine("Freezing is a common method of food preservation.", "冷凍是一種常見的食品保存方法。"),
            combine("Grandma taught us food preservation in summer.", "奶奶夏天教我們保存食物。"),
        ]
    if ctx.word.lower() == "food processing":
        return [
            combine("The factory improved its food processing line.", "工廠改善了食品加工產線。"),
            combine("Food processing can make ingredients easier to store.", "食品加工能讓食材更容易保存。"),
        ]
    if ctx.word.lower() == "foodie":
        return [
            combine("My sister is a foodie who loves night markets.", "我妹妹是個熱愛夜市的美食家。"),
            combine("The foodie took photos before tasting the noodles.", "那位美食家吃麵前先拍了照片。"),
        ]
    if ctx.word.lower() == "footstool":
        return [
            combine("She rested her feet on the footstool.", "她把腳放在腳凳上休息。"),
            combine("The child used the footstool to reach the sink.", "孩子踩著腳凳才碰得到洗手台。"),
        ]
    if ctx.word.lower() == "forefinger":
        return [
            combine("He pointed at the map with his forefinger.", "他用食指指著地圖。"),
            combine("She cut her forefinger while cooking.", "她做飯時割傷了食指。"),
        ]
    if ctx.word.lower() == "forsythia":
        return [
            combine("The forsythia bloomed bright yellow in spring.", "連翹在春天開出鮮黃的花。"),
            combine("She planted forsythia along the fence.", "她沿著籬笆種下連翹。"),
        ]
    if ctx.word.lower() == "fortescue":
        return [
            combine("The aquarium kept a fortescue in a quiet tank.", "水族館把澳洲蠍子魚養在安靜的水槽裡。"),
            combine("The diver avoided the fortescue near the rocks.", "潛水員避開岩石旁的澳洲蠍子魚。"),
        ]
    if ctx.word.lower() == "foxhound":
        return [
            combine("The foxhound followed the scent through the field.", "獵狐犬循著氣味穿過田野。"),
            combine("A tired foxhound slept beside the door.", "一隻疲倦的獵狐犬睡在門邊。"),
        ]
    if ctx.word.lower() == "endocarp":
        return [
            combine("She removed the hard endocarp from the fruit.", "她把水果裡堅硬的內果皮取出來。"),
            combine("The peach endocarp protects the seed inside.", "桃子的內果皮保護裡面的種子。"),
        ]
    if ctx.word.lower() == "enquirer":
        return [
            combine("The enquirer asked for more details at the desk.", "詢問者在櫃台要求更多細節。"),
            combine("A careful enquirer checked the price twice.", "細心的詢問者把價格確認了兩次。"),
        ]
    if ctx.word.lower() == "entrant":
        return [
            combine("Each entrant filled out a form before the contest.", "每位參賽者在比賽前都填了表格。"),
            combine("The youngest entrant waited near the stage.", "最年輕的參賽者在舞台旁等待。"),
        ]
    if ctx.word.lower() == "entree":
        return [
            combine("She ordered an entree with vegetables.", "她點了一份附蔬菜的主菜。"),
            combine("The restaurant served the entree after the soup.", "餐廳在湯之後送上主菜。"),
        ]
    if ctx.word.lower() == "enthusiasm for english":
        return [
            combine("Her enthusiasm for English helped her study every day.", "她對英語的熱情讓她每天都願意讀書。"),
            combine("The teacher praised his enthusiasm for English.", "老師稱讚他對英語很有熱情。"),
        ]
    if ctx.word.lower() == "esparto":
        return [
            combine("The factory used esparto to make paper.", "工廠用針茅草製作紙張。"),
            combine("She bought a basket woven from esparto.", "她買了一個用針茅草編成的籃子。"),
        ]
    if ctx.word.lower() == "esko flower arranging":
        return [
            combine("She learned esko flower arranging at a weekend class.", "她在週末課程學習插花。"),
            combine("The shop displayed esko flower arranging near the entrance.", "店家在入口附近展示插花作品。"),
        ]
    if ctx.word.lower() == "esquire":
        return [
            combine("The letter used esquire after his name.", "信上在他的名字後加上鄉紳稱號。"),
            combine("People addressed him as esquire in formal letters.", "人們在正式書信中稱他為鄉紳。"),
        ]
    if ctx.word.lower() == "estoppel":
        return [
            combine("The lawyer explained estoppel before the hearing.", "律師在聽證前解釋禁止反言。"),
            combine("The contract dispute involved estoppel.", "這場合約爭議涉及禁止反言。"),
        ]
    if ctx.word.lower() == "etiology":
        return [
            combine("The doctor studied the etiology of the illness.", "醫生研究這種疾病的病因學。"),
            combine("The report discussed etiology in simple terms.", "報告用簡單方式討論病因學。"),
        ]
    if ctx.word.lower() == "evader":
        return [
            combine("The evader ignored the notice for weeks.", "逃避者好幾週都不理會通知。"),
            combine("The police finally found the evader.", "警方最後找到了逃避者。"),
        ]
    if ctx.word.lower() == "exon":
        return [
            combine("The biology class learned how an exon works.", "生物課學到外顯子的作用。"),
            combine("The chart marked the exon in blue.", "圖表用藍色標出外顯子。"),
        ]
    if ctx.domain == "transport" and re.search(r"航班|flight", label, re.IGNORECASE):
        templates = [
            (f"The family booked a {word} for the trip.", f"這家人為旅行預訂了{label}。"),
            (f"The {word} arrived on time.", f"{label}準時抵達。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    if ctx.domain == "business" and re.search(r"董事", label):
        templates = [
            (f"The {word} met on Monday morning.", f"{label}週一早上開會。"),
            (f"The company formed a new {word}.", f"公司成立了新的{label}。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    if ctx.domain == "business" and label == "市場":
        templates = [
            (f"The shop studied the {word} before opening.", f"店家開幕前研究市場。"),
            (f"The company entered a new {word} this year.", f"公司今年進入新市場。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    if ctx.domain == "person" and re.search(r"騎手|骑手", label):
        templates = [
            (f"The {word} fixed a flat tire before the race.", f"{label}在比賽前修好破掉的輪胎。"),
            (f"A young {word} practiced in the park.", f"一位年輕的{label}在公園練習。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    if ctx.domain == "person" and re.search(r"女工|工人|農夫|農婦|worker|maid", label, re.IGNORECASE):
        templates = [
            (f"The {word} carried two buckets of milk.", f"{label}提著兩桶牛奶。"),
            (f"The farm hired a {word} for the busy season.", f"農場在忙季雇用了一位{label}。"),
        ]
        first = choose(word, templates)
        second = choose(word + ":2", [item for item in templates if item != first])
        return [combine(*first), combine(*second)]
    domain_templates: dict[str, list[tuple[str, str]]] = {
        "animal": [
            (f"The nature book described the {word}.", f"自然書介紹了{label}。"),
            (f"The photo showed a {word} in its habitat.", f"照片拍到{label}在棲地中活動。"),
        ],
        "plant": [
            (f"The farmer planted {word} beside the field.", f"農民在田邊種下{label}。"),
            (f"The {word} grew quickly after the rain.", f"{label}在雨後長得很快。"),
        ],
        "science": [
            (f"The lab stored the {word} sample in a labeled jar.", f"實驗室把{label}樣本放進貼好標籤的罐子。"),
            (f"The report described {word} after the test.", f"報告在測試後描述了{label}。"),
        ],
        "transport": [
            (f"They rode in a {word} through the village.", f"他們搭著{label}穿過村子。"),
            (f"The {word} arrived before sunset.", f"{label}在日落前抵達。"),
        ],
        "math": [
            (f"The teacher wrote {word} on the board.", f"老師把{label}寫在白板上。"),
            (f"She checked {word} while doing homework.", f"她寫作業時檢查{label}。"),
        ],
        "emotion": [
            (f"His voice showed {word} after the bad news.", f"壞消息後，他的聲音透出{label}。"),
            (f"She wrote about {word} in her diary.", f"她在日記裡寫下自己的{label}。"),
        ],
        "business": [
            (f"The bank processed the {word} in the morning.", f"銀行早上處理了{label}。"),
            (f"The manager reviewed the {word} before lunch.", f"經理午餐前查看了{label}。"),
        ],
        "safety": [
            (f"The campaign warned people about {word}.", f"宣導活動提醒大家不要{label}。"),
            (f"The police stopped {word} near the bridge.", f"警方在橋邊取締{label}。"),
        ],
        "object": [
            (f"She put the {word} on the table.", f"她把{label}放在桌上。"),
            (f"He checked the {word} before leaving.", f"他離開前檢查了{label}。"),
        ],
        "place": [
            (f"The map marked the {word} clearly.", f"地圖清楚標出{label}的位置。"),
            (f"The class talked about the {word} in geography.", f"地理課提到{label}。"),
        ],
        "material": [
            (f"The farmer spread {word} on the sticky trap.", f"農民把{label}塗在黏蟲板上。"),
            (f"The label said {word} helped catch small pests.", f"標籤寫著{label}可以幫忙捕捉小害蟲。"),
        ],
        "drink": [
            (f"She bought a cup of {word} at the market.", f"她在市場買了一杯{label}。"),
            (f"The cold {word} tasted sweet.", f"冰的{label}喝起來很甜。"),
        ],
        "taxonomy": [
            (f"The science class compared {word} with a related group.", f"自然課把{label}和相關類群做比較。"),
            (f"The chart placed {word} under a larger group.", f"圖表把{label}放在較大的分類下。"),
        ],
        "furniture": [
            (f"She moved the {word} closer to the window.", f"她把{label}搬到窗邊。"),
            (f"The old {word} fit well in the living room.", f"那張舊{label}很適合客廳。"),
        ],
        "medical": [
            (f"The doctor explained {word} to the patient.", f"醫生向病人解釋{label}。"),
            (f"The nurse wrote down {word} during the checkup.", f"護理師在檢查時記下{label}。"),
        ],
        "body": [
            (f"The child hurt one {word} during practice.", f"孩子練習時傷到一根{label}。"),
            (f"The diagram labeled each {word} clearly.", f"圖解清楚標出每根{label}。"),
        ],
        "technology": [
            (f"She checked the {word} before leaving.", f"她離開前查看了{label}。"),
            (f"The {word} worked properly after lunch.", f"{label}午餐後運作正常。"),
        ],
        "food": [
            (f"Grandma served a {word} after dinner.", f"奶奶晚餐後端上一份{label}。"),
            (f"She packed a small {word} for the picnic.", f"她替野餐準備了一份小小的{label}。"),
        ],
        "law": [
            (f"The lawyer explained {word} during the inheritance meeting.", f"律師在繼承會議中解釋{label}。"),
            (f"The family discussed {word} before going to court.", f"這家人在上法院前討論{label}。"),
        ],
        "geography": [
            (f"The road ran through the {word}.", f"這條路穿過{label}。"),
            (f"Small farms lined the {word}.", f"小農場沿著{label}分布。"),
        ],
        "damage": [
            (f"The storm caused {word} to the roof.", f"暴風雨造成屋頂{label}。"),
            (f"The report listed the {word} after the accident.", f"報告列出事故後的{label}。"),
        ],
        "art": [
            (f"The jeweler practiced {word} on a small stone.", f"珠寶師在小石頭上練習{label}。"),
            (f"The museum displayed an example of {word}.", f"博物館展示了一件{label}作品。"),
        ],
        "logic": [
            (f"The student diagrammed a {word} argument.", f"學生畫出{label}論證的結構。"),
            (f"The class compared {word} with a simpler argument form.", f"課堂把{label}和較簡單的論證形式做比較。"),
        ],
        "unit": [
            (f"The old record measured the cloth in {word}.", f"舊紀錄用{label}測量布料。"),
            (f"The merchant counted the grain by {word}.", f"商人用{label}計算穀物。"),
        ],
        "quantity": [
            (f"The shop ordered a {word} of towels.", f"店家訂了一組十條毛巾。"),
            (f"She packed a {word} of small candles.", f"她裝好一組十支小蠟燭。"),
        ],
        "title": [
            (f"The queen gave her the title of {word}.", f"女王授予她{label}。"),
            (f"The invitation used {word} before her name.", f"邀請函在她名字前使用{label}。"),
        ],
        "person": [
            (f"The {word} joined the meeting after lunch.", f"這位{label}午餐後參加會議。"),
            (f"The article described the daily work of a {word}.", f"文章描述了一位{label}的日常工作。"),
        ],
        "mythology": [
            (f"The story mentioned {word} during the family feast.", f"故事在家族宴會中提到{label}。"),
            (f"The class read a short myth about {word}.", f"課堂讀了一則關於{label}的短神話。"),
        ],
        "language": [
            (f"The student marked the {word} in the Hebrew word.", f"學生在希伯來文字裡標出{label}。"),
            (f"The teacher pointed to the {word} before reading aloud.", f"老師朗讀前指著{label}。"),
        ],
        "religion": [
            (f"The ceremony included {word} before sunset.", f"儀式在日落前包含{label}。"),
            (f"The old church record mentioned {word}.", f"老教會紀錄提到{label}。"),
        ],
    }
    templates = domain_templates.get(
        ctx.domain,
        [
            (f"The article described {word} as part of an old custom.", f"文章把{label}描述為舊習俗的一部分。"),
            (f"The guide explained where {word} appeared in daily life.", f"導覽員說明{label}會出現在日常生活的哪裡。"),
            (f"The report connected {word} with a local tradition.", f"報告把{label}和地方傳統連在一起。"),
        ],
    )
    first = choose(word, templates)
    second = choose(word + ":2", [item for item in templates if item != first] or templates)
    return [combine(*first), combine(*second)]


def verb_sentences(ctx: Context) -> list[str]:
    word = ctx.word
    label = ctx.label or "這個動作"
    templates = [
        (f"Please {word} the fabric before it dries.", f"請在布料變乾前先{label}。"),
        (f"The worker had to {word} the rough edge carefully.", f"工人必須小心地{label}粗糙邊緣。"),
        (f"She learned to {word} the material during training.", f"她在訓練時學會{label}材料。"),
        (f"The old recipe says to {word} the mixture slowly.", f"老食譜說要慢慢{label}混合物。"),
    ]
    first = choose(word, templates)
    second = choose(word + ":2", [item for item in templates if item != first])
    return [combine(*first), combine(*second)]


def adjective_sentences(ctx: Context) -> list[str]:
    word = ctx.word
    label = (ctx.label or "這類").rstrip("的")
    if ctx.domain == "drink":
        drink_label = label[1:] if label.startswith("可") else label
        return [
            combine(f"The water was {word} after boiling.", f"水煮沸後可以{drink_label}。"),
            combine(f"The hikers checked whether the stream was {word}.", f"登山客確認溪水是否可以{drink_label}。"),
        ]
    if ctx.domain == "emotion":
        return [
            combine(f"His answer sounded {word}.", f"他的回答聽起來很{label}。"),
            combine(f"She gave him a {word} look.", f"她用很{label}的表情看著他。"),
        ]
    if ctx.domain == "medical":
        return [
            combine(f"The doctor gave a {word} report.", f"醫生給了一份{label}報告。"),
            combine(f"The nurse checked the {word} note.", f"護理師查看了{label}紀錄。"),
        ]
    if ctx.domain == "business":
        return [
            combine(f"The manager reviewed the {word} plan.", f"經理查看了{label}計畫。"),
            combine(f"The team discussed the {word} issue.", f"團隊討論了{label}問題。"),
        ]
    if ctx.domain == "technology":
        return [
            combine(f"The team checked the {word} file.", f"團隊檢查了{label}檔案。"),
            combine(f"She saved the {word} copy on her laptop.", f"她把{label}副本存在筆電裡。"),
        ]
    if ctx.domain == "damage":
        return [
            combine(f"The leak was {word} to the wooden floor.", f"漏水對木地板很{label}。"),
            combine(f"Too much sun can be {word} to the skin.", f"太多陽光可能對皮膚很{label}。"),
        ]
    if ctx.domain == "mythology":
        return [
            combine(f"The play used a {word} theme.", f"這齣戲使用了{label}相關的主題。"),
            combine(f"Her notes described a {word} story.", f"她的筆記描述了一則{label}相關的故事。"),
        ]
    if ctx.domain == "animal":
        return [
            combine(f"The photo showed a {word} animal resting in the shade.", f"照片裡有一隻{label}動物在陰影下休息。"),
            combine(f"The guide compared the {word} animal with a similar species.", f"導覽員把{label}動物和相近物種做比較。"),
        ]
    if ctx.domain == "plant":
        return [
            combine(f"The yard had several {word} plants.", f"院子裡有幾株{label}植物。"),
            combine(f"The gardener trimmed the {word} leaves.", f"園丁修剪{label}植物的葉子。"),
        ]
    if ctx.domain == "taxonomy":
        return [
            combine(f"The chart showed a {word} group.", f"圖表列出一個{label}類群。"),
            combine(f"The science class compared the {word} group with a related one.", f"自然課把{label}類群和相關類群做比較。"),
        ]
    if ctx.domain == "language":
        return [
            combine(f"She read a {word} phrase aloud.", f"她朗讀了一個{label}片語。"),
            combine(f"The note included a {word} spelling.", f"筆記裡有一個{label}拼法。"),
        ]
    noun_by_domain = {
        "animal": "animal",
        "plant": "plant",
        "medical": "symptom",
        "science": "sample",
        "language": "phrase",
        "religion": "ritual",
        "law": "rule",
        "art": "design",
        "mythology": "story",
        "title": "form of address",
    }
    noun = noun_by_domain.get(ctx.domain, "detail")
    templates = [
        (f"The report described a {word} {noun}.", f"報告描述了一個{label}的細節。"),
        (f"She noticed a {word} pattern in the photo.", f"她在照片裡注意到{label}的樣子。"),
        (f"The article mentioned a {word} feature.", f"文章提到一個{label}的特徵。"),
    ]
    first = choose(word, templates)
    second = choose(word + ":2", [item for item in templates if item != first])
    return [combine(*first), combine(*second)]


def adverb_sentences(ctx: Context) -> list[str]:
    word = ctx.word
    label = (ctx.label or "").rstrip("地")
    if not label:
        return []
    specific: dict[str, list[tuple[str, str]]] = {
        "dabbl": [
            (f"He studied the topic {word} over the weekend.", "他週末只是淺嚐式地研究這個主題。"),
            (f"She played the guitar {word} at first.", "她一開始只是半玩票地彈吉他。"),
        ],
        "dactyl": [
            (f"He read the verse {word} in class.", f"他在課堂上用{label}朗讀詩句。"),
            (f"The poet arranged the line {word}.", f"詩人用{label}安排詩行。"),
        ],
        "calm": [
            ("She answered calmly during the meeting.", "她在會議中冷靜地回答。"),
            ("He calmly closed the door before speaking.", "他先冷靜地關上門再開口。"),
        ],
        "clear": [
            ("Please speak clearly into the microphone.", "請對著麥克風清楚說話。"),
            ("She clearly wrote the address on the box.", "她把地址清楚地寫在盒子上。"),
        ],
        "correct": [
            ("She answered the question correctly.", "她正確地回答問題。"),
            ("He correctly filled in the date.", "他正確地填上日期。"),
        ],
        "comfort": [
            ("She sat comfortably by the window.", "她舒服地坐在窗邊。"),
            ("The child slept comfortably on the sofa.", "孩子舒服地睡在沙發上。"),
        ],
        "commercial": [
            ("The product was commercially successful.", "這項產品在商業上很成功。"),
            ("The film did commercially well overseas.", "這部電影在海外商業表現不錯。"),
        ],
        "collect": [
            ("The team solved the issue collectively.", "團隊共同解決了這件事。"),
            ("They collectively agreed to change the date.", "他們共同同意改期。"),
        ],
        "conscious": [
            ("She consciously slowed her breathing.", "她有意識地放慢呼吸。"),
            ("He consciously avoided checking his phone.", "他有意識地避免查看手機。"),
        ],
        "constant": [
            ("The phone rang constantly all morning.", "電話整個上午一直響。"),
            ("She constantly checked the oven while baking.", "她烘焙時一直查看烤箱。"),
        ],
        "creative": [
            ("She solved the problem creatively.", "她有創意地解決問題。"),
            ("He creatively reused the old boxes.", "他有創意地重複利用舊盒子。"),
        ],
        "critical": [
            ("She read the report critically.", "她批判性地閱讀報告。"),
            ("He critically compared the two plans.", "他批判性地比較兩個方案。"),
        ],
        "cruel": [
            ("He treated the dog cruelly.", "他殘忍地對待那隻狗。"),
            ("The guard cruelly ignored their request.", "警衛殘忍地忽視他們的請求。"),
        ],
        "danger": [
            ("He drove dangerously on the wet road.", "他在濕滑道路上危險駕駛。"),
            ("The ladder leaned dangerously to one side.", "梯子危險地歪向一邊。"),
        ],
        "deliberate": [
            ("She deliberately left the note on his desk.", "她故意把紙條留在他桌上。"),
            ("He deliberately spoke more slowly.", "他故意放慢說話速度。"),
        ],
        "different": [
            ("She arranged the chairs differently this time.", "她這次用不同方式排列椅子。"),
            ("He answered the question differently after thinking.", "他想過後用不同方式回答問題。"),
        ],
        "directly": [
            ("She spoke directly to the manager.", "她直接和經理說話。"),
            ("The bus goes directly to the station.", "公車直接到車站。"),
        ],
        "dense": [
            ("The houses were densely packed on the hill.", "山坡上的房子排列得很密集。"),
            ("The trees grew densely beside the path.", "小路旁的樹長得很密集。"),
        ],
        "diligent": [
            ("He studied diligently every evening.", "他每天晚上都勤奮讀書。"),
            ("She worked diligently to finish the form.", "她勤奮地完成表格。"),
        ],
        "dishonest": [
            ("He answered dishonestly during the interview.", "他在面試中不誠實地回答。"),
            ("The seller acted dishonestly about the price.", "賣家在價格上表現得不誠實。"),
        ],
        "dismiss": [
            ("She waved dismissingly at the complaint.", "她不屑地揮手回應抱怨。"),
            ("He answered dismissingly and left the room.", "他不屑地回答後離開房間。"),
        ],
        "digestib": [
            ("The soup was digestibly light.", "這碗湯清淡又容易消化。"),
            ("She cooked the vegetables digestibly for her child.", "她把蔬菜煮得容易消化，給孩子吃。"),
        ],
        "digital": [
            ("The form was signed digitally.", "這份表格以數位方式簽署。"),
            ("The photos were stored digitally.", "照片以數位方式保存。"),
        ],
        "explicit": [
            ("She explicitly said the meeting was canceled.", "她明確表示會議取消了。"),
            ("The sign explicitly asks visitors to stay quiet.", "告示明確要求訪客保持安靜。"),
        ],
    }
    for key, bilingual_options in specific.items():
        if key in word.lower():
            return [combine(*pair) for pair in bilingual_options[:2]]
    if ctx.domain in {"science", "medical"}:
        first = (
            f"The sample changed {word} during the test.",
            f"樣本在測試中出現{label}變化。",
        )
        second = (
            f"The process worked {word} under pressure.",
            f"這個過程在壓力下呈現{label}反應。",
        )
        return [combine(*first), combine(*second)]
    if ctx.domain in {"language", "logic", "religion", "law"}:
        first = (f"He read the passage {word}.", f"他用{label}讀那段文字。")
        second = (f"She explained the rule {word}.", f"她用{label}解釋規則。")
        return [combine(*first), combine(*second)]
    templates = [
        (f"She answered the customer {word}.", f"她{label}地回應顧客。"),
        (f"He checked the form {word}.", f"他{label}地檢查表格。"),
        (f"The team changed the schedule {word}.", f"團隊{label}地調整時程。"),
    ]
    first = choose(word, templates)
    second = choose(word + ":2", [item for item in templates if item != first])
    return [combine(*first), combine(*second)]


def combine(english: str, zh: str) -> str:
    return f"{english.strip()} {zh.strip()}"


def build_sentences(ctx: Context) -> list[str]:
    if ctx.pos == "verb":
        return verb_sentences(ctx)
    if ctx.pos == "adjective":
        return adjective_sentences(ctx)
    if ctx.pos == "adverb":
        return adverb_sentences(ctx)
    return noun_sentences(ctx)


def validate_sentences(ctx: Context, sentences: Iterable[str]) -> list[str]:
    errors: list[str] = []
    sentence_list = list(sentences)
    if len(sentence_list) != 2:
        errors.append("invalid_sentence_count")
    for index, sentence in enumerate(sentence_list, start=1):
        english, translation = split_bilingual_sentence(sentence)
        if not english or not translation:
            errors.append(f"missing_bilingual_half:s{index}")
        if raw_word_in_zh(ctx.word, sentence):
            errors.append(f"raw_word_in_zh:s{index}")
        if QUALITY_RE.search(sentence):
            errors.append(f"quality_pattern:s{index}")
        if META_OUTPUT_RE.search(sentence):
            errors.append(f"meta_pattern:s{index}")
    return errors


def safe_general_adverb(ctx: Context) -> bool:
    label = (ctx.label or "").strip()
    if not label:
        return False
    lowered = ctx.word.lower()
    if any(key in lowered for key in SPECIFIC_ADVERB_KEYS):
        return True
    if re.search(r"形式|方式|法令|自然神論|一種|處於|狀態|與格|十進位|陳述|宣告", label):
        return False
    if re.search(r"^(危險|明確|精緻|破壞|快樂|不同|勤奮|直接|公正|冷靜|快速|緩慢|小心|溫柔|安靜)$", label):
        return True
    return False


def refine_entry(
    entry: dict[str, Any],
    allow_low_confidence: bool = False,
    allow_general: bool = False,
) -> tuple[list[str], list[str], Context]:
    ctx = context_for(entry)
    if ctx.confidence == "low" and not allow_low_confidence:
        return [], ["low_confidence_meaning"], ctx
    if not ctx.label and not allow_low_confidence:
        return [], ["missing_usable_label"], ctx
    if ctx.confidence == "medium" and not allow_low_confidence:
        return [], ["medium_confidence_needs_review"], ctx
    if ctx.label and ctx.word.lower() not in SAFE_SPECIAL_WORDS and re.search(
        r"學習.*定義|学习.*定义|記錄為|记录为|特別是|特别是|廣義|广义|或$|總目|总目|"
        r"用法和片語|用法和短語|土地產出|產品|據稱|据称|含有|呈現|礦物|矿物|"
        r"存在於|存在于|提供|涉及$|分佈|分布|文化.*植物|植物知識|植物知识|"
        r"享有|權利|权利|內層|内层|隔膜|產生者|产生者|在句子中使用|用作|"
        r"立體異構|立体异构|具有|鞋子和紙張|鞋子和纸张|除水|基於|基于|可能發生|核酸中的|"
        r"在某些|哺乳動物|哺乳动物|行為|行为|参加|參加|成員|成员|"
        r"容器|蕨類植物學|蕨类植物学|幼年動物|幼年动物|終結語|终结语|"
        r"狀態|状态|狀況|状况|等於|等于|佈置|布置|集合|像或|類似|类似|分支|"
        r"美國|美国|神話般|神话般|虛構|虚构|^與|^和|^由|^對|^关于|^關於|"
        r"^[一二三四五六七八九十]?[a-zA-Z0-9 ]+$|^[^，。；;]{18,}$|源自|\\d{2,}",
        ctx.label,
    ):
        return [], ["label_needs_review"], ctx
    if re.search(r"字首|字尾|前綴|後綴|prefix|suffix", ctx.meaning, re.IGNORECASE):
        return [], ["affix_meaning_needs_review"], ctx
    if ctx.pos == "noun" and ctx.label in {"開車", "駕駛", "喝酒", "進餐"}:
        return [], ["noun_label_looks_verbal"], ctx
    if ctx.domain == "general" and not allow_general and not (ctx.pos == "adverb" and safe_general_adverb(ctx)):
        return [], ["general_domain_needs_review"], ctx
    if ctx.domain == "person" and ctx.label and re.search(r"使.+的人|讓.+的人|令.+的人", ctx.label):
        return [], ["person_role_needs_review"], ctx
    if ctx.domain == "person" and ctx.word.lower() not in SAFE_SPECIAL_WORDS:
        return [], ["person_domain_needs_review"], ctx
    if ctx.pos == "adjective" and ctx.word.lower() not in SAFE_SPECIAL_WORDS and not safe_general_adverb(ctx):
        return [], ["adjective_needs_review"], ctx
    if ctx.domain == "plant" and ctx.label and re.search(r"用的|法蘭|葉子的|植物學|學$", ctx.label):
        return [], ["plant_label_needs_review"], ctx
    if ctx.domain == "transport" and ctx.label and re.search(r"快速|穿過|^[^車船艇航班]{1,4}$", ctx.label):
        return [], ["transport_label_needs_review"], ctx
    if ctx.domain == "language" and ctx.label and not re.search(r"語|文法|發音|拼寫|拼法|音節|片語|字母|重音|格|詞|字|Hebrew|希伯來", ctx.label, re.IGNORECASE):
        return [], ["language_label_needs_review"], ctx
    if ctx.pos == "adjective" and ctx.domain in {"math", "science", "technology"}:
        return [], ["technical_adjective_needs_review"], ctx
    if ctx.pos == "adjective" and ctx.confidence == "medium":
        return [], ["medium_confidence_adjective_needs_review"], ctx
    if ctx.pos == "adverb" and not safe_general_adverb(ctx):
        return [], ["adverb_needs_review"], ctx
    if ctx.pos == "verb" and not allow_general:
        return [], ["verb_needs_review"], ctx
    if ctx.pos == "verb" and ctx.label and re.search(r"的$", ctx.label):
        return [], ["verb_label_looks_adjectival"], ctx
    sentences = build_sentences(ctx)
    errors = validate_sentences(ctx, sentences)
    return sentences, errors, ctx


def main() -> int:
    args = parse_args()
    path = repo_path(args.path)
    data = load_json(path)
    if not isinstance(data, list):
        raise SystemExit(f"Expected a JSON list: {path}")

    candidates: list[tuple[int, dict[str, Any], list[str]]] = []
    for index, entry in enumerate(data):
        reasons = entry_reasons(entry)
        if (reasons and needs_sentence_refine(reasons)) or args.include_clean:
            candidates.append((index, entry, reasons or ["include_clean"]))

    selected = candidates[args.offset :]
    if args.limit is not None:
        selected = selected[: args.limit]

    changes: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []
    for index, entry, reasons in selected:
        word = str(entry.get("word", "")).strip().lower()
        # A template marker in an example sentence is precisely the case this
        # refiner can repair when the meaning is still usable.  Keep blocking
        # entries whose meaning is itself noisy, because generating examples
        # from an unreliable gloss would only hide the data problem.
        if (
            "forbidden_text" in reasons
            and "weak_or_noisy_meaning" in reasons
            and word not in SAFE_SPECIAL_WORDS
        ):
            blocked.append(
                {
                    "index": index,
                    "word": str(entry.get("word", "")),
                    "reasons": reasons,
                    "errors": ["forbidden_text_needs_review"],
                    "proposedSentences": [],
                }
            )
            continue
        if "raw_word_in_zh" in reasons and word not in SAFE_SPECIAL_WORDS:
            blocked.append(
                {
                    "index": index,
                    "word": str(entry.get("word", "")),
                    "reasons": reasons,
                    "errors": ["raw_word_needs_review"],
                    "proposedSentences": [],
                }
            )
            continue
        new_sentences, errors, ctx = refine_entry(
            entry,
            allow_low_confidence=args.allow_low_confidence,
            allow_general=args.allow_general,
        )
        if errors:
            blocked.append(
                {
                    "index": index,
                    "word": ctx.word,
                    "reasons": reasons,
                    "errors": errors,
                    "proposedSentences": new_sentences,
                }
            )
            continue
        old_sentences = entry.get("sentences") or []
        if old_sentences == new_sentences:
            continue
        changes.append(
            {
                "index": index,
                "word": ctx.word,
                "partOfSpeech": ctx.pos,
                "domain": ctx.domain,
                "confidence": ctx.confidence,
                "reasons": reasons,
                "oldSentences": old_sentences,
                "newSentences": new_sentences,
            }
        )
        if args.apply:
            entry["sentences"] = new_sentences

    change_report = changes if args.report_limit == 0 else changes[: args.report_limit]
    blocked_report = blocked if args.report_limit == 0 else blocked[: args.report_limit]
    report = {
        "path": str(path),
        "entryCount": len(data),
        "candidateCount": len(candidates),
        "selectedCount": len(selected),
        "changeCount": len(changes),
        "blockedCount": len(blocked),
        "applied": bool(args.apply),
        "changes": change_report,
        "blocked": blocked_report,
    }

    if args.apply and changes:
        write_json(path, data)
    if args.report:
        write_json(repo_path(args.report), report)

    print(json.dumps({key: report[key] for key in ("candidateCount", "selectedCount", "changeCount", "blockedCount", "applied")}, ensure_ascii=False, indent=2))
    return 1 if blocked else 0


if __name__ == "__main__":
    raise SystemExit(main())
