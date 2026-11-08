# 常用字關係補強與候選品質改善（2026-11-07）

這次延續 [117 字詞通用性抽樣](word-extension-generality-audit-2026-11-07.md)，沿用同一組樣本與實際字庫。沒有修改字庫 shard 或新增依賴。

## 結果

- 新增 33 組經整理核對的關係，原先 53 個只有例句的字中，32 個現在有明確延伸，21 個暫不補。
- 每組關係包含雙端義項、詞性、關係說明及義項相符的字庫例句；驗證 66 個正反向查詢。
- house/home 與 invaluable/valuable 是差異比較；其他關係明示為字族、分類、動作情境、相反概念等，不宣稱可以互換。
- 撤掉其他 26 個樣本原本僅靠弱依據或生僻候選形成的結果；因此整體候選數沒有增加 32 個，這是品質篩選的預期取捨。

| 原 117 字詞抽樣 | 改善前 | 改善後 |
|---|---:|---:|
| 有相關／易混淆字候選 | 54 | 60 |
| 只有例句 | 53 | 47 |
| 字庫未收錄 | 10 | 10 |

這些是候選覆蓋數，不是全字庫準確率。改善後的 47 個只有例句，包含原先保留的 21 個及品質篩選後撤下候選的 26 個。

## 候選品質規則

1. 人工整理的關係仍必須符合目前義項、雙端詞性、可用雙語例句及字目品質。未標程度的 kitten、reader 等字可由這些明確關係進入推薦。
2. 自動候選必須同時有 `twCeec` 或 `pdfExamBook` 來源，且有國小／國中學級或難度 1–4 的訊號。一般 audience 或 college/toeic signals 標籤、未標程度、單獨的低學級標籤都不足以放行。
3. 古語、罕用、生僻、方言、非標準拼寫、明示為外語用法、含斜線／數字等不合字目格式的候選會排除。這不是頻率統計，也無法代替完整詞典審核。
4. 明載的變化形可以繼承常用原形的依據，例如 fly → flown；仍須通過義項、詞性及品質檢查。
5. 同等關係證據下，先考慮有基礎教材依據的字，再比較程度距離。無合格候選時保留例句，不用其他字補滿。
6. 新增關係各選一個義項相符的實際字庫例句；正反向分別取用對應端。避免 light → bright 時顯示「聰明的學生」、read → book 時顯示「預訂機票」、common → rare 時顯示牛排熟度。例句若不再存在於字庫或不是雙語內容，就略過該整理關係。

## 原先 53 個只有例句的字

| 字詞 | 改善後 | 延伸 |
|---|---|---|
| dog | 有明確延伸 | puppy |
| cat | 有明確延伸 | kitten |
| house | 有明確延伸 | 差異比較：home |
| book | 有明確延伸 | read |
| water | 有明確延伸 | drink |
| music | 有明確延伸 | song |
| apple | 有明確延伸 | fruit |
| river | 有明確延伸 | stream |
| city | 有明確延伸 | town |
| train | 有明確延伸 | station |
| money | 有明確延伸 | price |
| idea | 有明確延伸 | thought |
| road | 有明確延伸 | street |
| rare | 有明確延伸 | common |
| careful | 有明確延伸 | careless |
| careless | 有明確延伸 | careful |
| bookshelf | 有明確延伸 | shelf |
| sunflower | 有明確延伸 | flower |
| sunrise | 保留只有例句 | — |
| sunset | 保留只有例句 | — |
| snowball | 保留只有例句 | — |
| unable | 有明確延伸 | able |
| irregular | 保留只有例句 | — |
| nonverbal | 保留只有例句 | — |
| children | 有明確延伸 | child |
| mice | 保留只有例句 | — |
| took | 保留只有例句 | — |
| taken | 保留只有例句 | — |
| given | 有明確延伸 | give |
| seen | 有明確延伸 | see |
| saw | 保留只有例句 | — |
| wrote | 有明確延伸 | write |
| feet | 有明確延伸 | foot |
| teeth | 保留只有例句 | — |
| men | 保留只有例句 | — |
| kept | 保留只有例句 | — |
| ate | 保留只有例句 | — |
| eaten | 保留只有例句 | — |
| sung | 保留只有例句 | — |
| light | 有明確延伸 | bright |
| kind | 保留只有例句 | — |
| right | 保留只有例句 | — |
| match | 保留只有例句 | — |
| present | 保留只有例句 | — |
| lead | 有明確延伸 | leader |
| wind | 有明確延伸 | breeze |
| read | 有明確延伸 | book, reader |
| quickly | 有明確延伸 | quick |
| easily | 保留只有例句 | — |
| butterfly | 有明確延伸 | insect |
| uncle | 有明確延伸 | aunt |
| invaluable | 有明確延伸 | 差異比較：valuable |
| nonplus | 保留只有例句 | — |

## 保留的缺口

暫不補的 21 個字：sunrise, sunset, snowball, irregular, nonverbal, mice, took, taken, saw, teeth, men, kept, ate, eaten, sung, kind, right, match, present, easily, nonplus。

部分是多義／抽象定義或例句需要進一步核對，部分有明顯詞性或釋義問題，例如 mice、took、men、kept。未為了增加覆蓋而把已知的另一個意思硬接進目前錯誤詞義。這不代表它們沒有可教的關係，而是現有資料尚未安全對應。

新增關係的選詞已逐項核對，但既有字庫仍有品質限制：例如部分 wrote 例句是詞形說明，並非自然情境句；其他未整理關係的泛用例句仍可能混合義項。metadata 也不是完美的常用度證明。

## 撤下候選的樣本

garden, food, school, beautiful, tiny, silent, quiet, toothbrush, bedroom, keyboard, railway, waterfall, unhappy, uncertain, illegal, bank, spring, bat, milk, happily, carpet, pineapple, hamburger, understand, inflammable, union。

例如 beautiful → lindo、quick → rapic、food → victuals、time → openning time、bank → obey bank balance 已排除。quick 另由明確字族關係取得 quickly，其餘若沒有安全替代就留空。

## 驗證

- `test/word_extension_coverage_test.dart`：同一 117 字詞抽樣、33 組新增關係正反向與實際不良候選反例。
- `test/word_extension_candidate_quality_test.dart`：常用度訊號、雙端詞性、未標程度的整理關係、變化形繼承、排除反例與義項例句。
- 全專案 330 項測試通過；新增的 20 項候選品質測試與 66 個新關係正反向查詢／對應例句檢查皆通過。
- 靜態分析僅有原先 18 項主題與共用元件提示，本次修改無新增分析問題。

```sh
flutter test --no-pub test/word_extension_candidate_quality_test.dart test/word_extension_coverage_test.dart
flutter test --no-pub --dart-define=WORD_EXTENSION_AUDIT_PATH=/tmp/word-extension-common-audit.json test/word_extension_coverage_test.dart
```
