# 單字延伸推薦通用性抽樣驗證（2026-11-07）

本次事先指定 117 個字詞，涵蓋九類，刻意不包含原本 15 個教學字目、windmill 或 nonsignificant。
其中 107 個存在於實際 26 個字庫分片並執行推薦，54 個有相關字候選、53 個只有例句；另有 10 個未收錄。
自訂字與無資料字另有測試。這是代表性案例檢查，並非隨機抽樣；不能將候選覆蓋數當作正確率，或外推到整份字庫。

## 驗證方法

- 使用正式 `BuiltinWordBankRepository` 與 `WordExtensionService`，同一服務共用索引。
- 九組指定的正例檢查具體目標（例如 bookcase → book、unfair → fair、written → write），而非只檢查非空。
- 每項候選檢查真實字庫來源、例句來源、非自身、不重複、數量上限與推薦理由。
- 額外 26 項獨立測試關閉人工關係表，涵蓋七種否定前綴、複合字、變化形、自訂字、多義與反例。
- 沒有可靠線索時允許空結果；不為提高覆蓋數填入無關字。

## 這次發現並修正的問題

1. 變化形義項與詞性混用：saw 在鋸子／鋸切義項下會錯推 see；wrote 的名詞卡或字庫誤標名詞的 kept 也會推薦動詞原形。現在每條變化形關係綁定來源詞性與具體定義子句，並檢查目前義項。
2. 說明句被切成獨立釋義：protogyny 的說明提到蘋果，solicitor 的說明提到城市，原本分別被 apple、city 當成同釋義字。現在不把長解釋中的逗號碎片當成釋義。
3. 列舉釋義缺乏語境佐證：quickly 曾推薦 elegantly。現在只有短而明確的釋義列舉可拆分，且候選例句須出現拆出的義項。
4. 查證提示充當詞義：took 與 eaver 的「疑似非標準／應再查證」曾被當成相同釋義。這些提示不再作推薦依據。
上述八項誤推先以失敗測試重現，再修正通用規則；沒有加入這些單字的特例表，也沒有修改字庫 shard。

## 分類結果

| 類型 | 查核字詞 | 有候選 | 僅例句 | 未收錄 |
|---|---:|---:|---:|---:|
| 日常名詞 | 20 | 7 | 13 | 0 |
| 形容詞 | 12 | 9 | 3 | 0 |
| 複合字 | 19 | 11 | 5 | 3 |
| 前綴字 | 12 | 9 | 3 | 0 |
| 變化形 | 24 | 7 | 15 | 2 |
| 多義字 | 12 | 4 | 8 | 0 |
| 副詞 | 4 | 1 | 2 | 1 |
| 拼字陷阱 | 10 | 6 | 4 | 0 |
| 多字詞條 | 4 | 0 | 0 | 4 |

## 仍存在的限制

- **目前只能確認規則可跨類型運作，不能宣稱推薦品質已完整通用。** 約一半已收錄樣本仍僅有例句。
- 常用字如 dog、cat、book 缺乏足夠明確關係。children、feet 等字庫沒有明載原形的定義，也無法僅靠目前規則建立關係。
- 字庫有缺字或釋義／詞性品質問題，例如 snowman、schoolbag、women、slowly 與這次抽樣的四個多字詞條未收錄。
- 候選可能生僻或可疑：beautiful 的候選包含 lindo（其定義提到西班牙語）；quick 的候選 rapic 仍需字庫內容審核。這些結果不能因通過機械檢查就視為已人工確認。
- 演算法無法獨立驗證字庫的每項語義；詞性／翻譯錯誤仍可能污染結果。長定義與無例句佐證的列舉被排除後，也可能漏掉正確關係。
- 後續優先事項應是補充經審核的常用字關係與字庫品質、改善候選的學習價值排序，而非放寬規則硬湊結果。

## 全部查核結果

以下是修正後實際輸出。列出候選不代表已逐項完成詞典學審核。

| 類型 | 字詞 | 目前字庫釋義 | 結果 | 相關字／易混淆字 |
|---|---|---|---|---|
| 日常名詞 | dog | 狗 | 僅例句 | — |
| 日常名詞 | cat | 貓 | 僅例句 | — |
| 日常名詞 | house | 房子 | 僅例句 | — |
| 日常名詞 | garden | 花園 | 有候選 | garten, phulwara |
| 日常名詞 | book | 書 | 僅例句 | — |
| 日常名詞 | water | 水 | 僅例句 | — |
| 日常名詞 | music | 音樂 | 僅例句 | — |
| 日常名詞 | apple | 蘋果 | 僅例句 | — |
| 日常名詞 | table | 桌子 | 有候選 | desk, tables |
| 日常名詞 | river | 河 | 僅例句 | — |
| 日常名詞 | city | 城市 | 僅例句 | — |
| 日常名詞 | food | 食物 | 有候選 | food chain, victuals, vivers |
| 日常名詞 | school | 學校 | 有候選 | boarding school, driving school, public school |
| 日常名詞 | train | 火車 | 僅例句 | — |
| 日常名詞 | friend | 朋友 | 有候選 | fair-weather friend, school friend, pal |
| 日常名詞 | family | 家庭 | 有候選 | household |
| 日常名詞 | money | 錢 | 僅例句 | — |
| 日常名詞 | time | 時間 | 有候選 | dinner time, openning time |
| 日常名詞 | idea | 主意 | 僅例句 | — |
| 日常名詞 | road | 路 | 僅例句 | — |
| 形容詞 | beautiful | 美麗的 | 有候選 | lindo, beauteous, fairlike |
| 形容詞 | tiny | 很小的；微小的 | 有候選 | dinky, diminutal, diminute |
| 形容詞 | large | 大的 | 有候選 | big |
| 形容詞 | clever | 聰明的 | 有候選 | intelligent, smart, witful |
| 形容詞 | smart | 聰明的 | 有候選 | clever, intelligent, witful |
| 形容詞 | silent | 沉默的 | 有候選 | nonvocal, mumming, tongueless |
| 形容詞 | quiet | 安靜的 | 有候選 | indisturbable, lown, hushing |
| 形容詞 | ordinary | 普通的 | 有候選 | normal, vulgare, commonplace |
| 形容詞 | rare | 稀有的 | 僅例句 | — |
| 形容詞 | careful | 小心 | 僅例句 | — |
| 形容詞 | careless | 粗心的 | 僅例句 | — |
| 形容詞 | quick | 快的 | 有候選 | rapic |
| 複合字 | snowman | — | 未收錄 | — |
| 複合字 | bookcase | 書櫃 | 有候選 | book |
| 複合字 | raincoat | 雨衣 | 有候選 | rain, caban, Mac |
| 複合字 | bookshelf | 用於存放書籍以便於視覺參考的一個或多個架子。 | 僅例句 | — |
| 複合字 | teapot | 茶壺 | 有候選 | tea |
| 複合字 | toothbrush | 牙刷 | 有候選 | teethbrush |
| 複合字 | football | 足球 | 有候選 | football field, ball, soccer |
| 複合字 | sunflower | 向日葵 | 僅例句 | — |
| 複合字 | bedroom | 臥室 | 有候選 | cubiculum |
| 複合字 | keyboard | 鍵盤 | 有候選 | claviature, clavier |
| 複合字 | railway | 鐵路 | 有候選 | rail, railroad, railroad/railway |
| 複合字 | moonlight | 月光 | 有候選 | light, moonbeam, moonglow |
| 複合字 | schoolbag | — | 未收錄 | — |
| 複合字 | waterfall | 瀑布 | 有候選 | vanfoss |
| 複合字 | sunrise | 一天中太陽出現在東部地平線上方的時間。 | 僅例句 | — |
| 複合字 | sunset | 人或物生命的最後階段。 | 僅例句 | — |
| 複合字 | seashore | — | 未收錄 | — |
| 複合字 | homework | 家庭作業 | 有候選 | home, prep |
| 複合字 | snowball | 一種小蛋糕，通常是奶油餡的，上面覆蓋著巧克力糖霜和椰絲。 | 僅例句 | — |
| 前綴字 | unhappy | 不高興的，不幸福的 | 有候選 | annoyed, blissless, mislike |
| 前綴字 | unfair | 不公平的 | 有候選 | fair, discriminatory, inequitable |
| 前綴字 | unhealthy | 不健康的 | 有候選 | healthy, diseased, indisposed |
| 前綴字 | unclear | 不清楚的；模糊的 | 有候選 | clear, ambiguous, bleared |
| 前綴字 | uncertain | 不確定的；沒有把握的 | 有候選 | chancy, graspless, indeterminate |
| 前綴字 | unable | 不能的，無法的 | 僅例句 | — |
| 前綴字 | impossible | 不可能的 | 有候選 | possible, infeasible, insupposable |
| 前綴字 | irregular | 不遵循給定語言中常規或預期的變形模式。 | 僅例句 | — |
| 前綴字 | illegal | 非法的 | 有候選 | illicit |
| 前綴字 | dishonest | 不誠實 | 有候選 | honest, inveracious, doublehearted |
| 前綴字 | nonverbal | 非語言的；不使用言語表達的。 | 僅例句 | — |
| 前綴字 | harmless | 無法造成傷害或危險；安全的。 | 有候選 | nonhazardous, riskless, safe |
| 變化形 | children | 孩子們（複數） | 僅例句 | — |
| 變化形 | mice | 分心或註意力不集中（可能指貓被老鼠分心）。 | 僅例句 | — |
| 變化形 | went | 去；走（go 的過去式）；古語中的道路 | 有候選 | go |
| 變化形 | gone | 離去的；消失的 | 有候選 | evanish |
| 變化形 | took | 疑似非標準或極罕見拼寫；正式使用前應再查證 | 僅例句 | — |
| 變化形 | taken | 癡情；喜歡或被吸引。 | 僅例句 | — |
| 變化形 | gave | 給 (give 的過去式) | 有候選 | give |
| 變化形 | given | 給定的；特定的 | 僅例句 | — |
| 變化形 | seen | 見過 | 僅例句 | — |
| 變化形 | saw | 鋸 | 僅例句 | — |
| 變化形 | wrote | 寫的過去式 | 僅例句 | — |
| 變化形 | written | 寫下的（write 的過去分詞） | 有候選 | write |
| 變化形 | feet | 腳；英尺的複數 | 僅例句 | — |
| 變化形 | teeth | 牙齒 (Tooth 之複數) | 僅例句 | — |
| 變化形 | men | 男人 | 僅例句 | — |
| 變化形 | women | — | 未收錄 | — |
| 變化形 | ran | 跑；奔跑，為 run 的過去式 | 有候選 | run |
| 變化形 | kept | keep的過去式和過去分詞 | 僅例句 | — |
| 變化形 | ate | 吃（eat的過去式），阿忒（希臘神話的罪惡女神） | 僅例句 | — |
| 變化形 | eaten | 已經被吃的消耗掉了。 | 僅例句 | — |
| 變化形 | slept | — | 未收錄 | — |
| 變化形 | spoke | 說話；speak 的過去式；輪輻 | 有候選 | speak, talk |
| 變化形 | spoken | 說話,講話 | 有候選 | speak, spoke, talk |
| 變化形 | sung | 歌唱的簡單過去式 | 僅例句 | — |
| 多義字 | bank | 銀行 | 有候選 | bank draft, bank rate, obey bank balance |
| 多義字 | spring | 春天 | 有候選 | foreyear, springtime |
| 多義字 | bat | 蝙蝠 | 有候選 | chiropter, flitterbat, flittermouse |
| 多義字 | light | 光 | 僅例句 | — |
| 多義字 | kind | 種類 | 僅例句 | — |
| 多義字 | right | 正確的 | 僅例句 | — |
| 多義字 | match | 相配、相同或使兩者接合；火柴。 | 僅例句 | — |
| 多義字 | present | 展示 | 僅例句 | — |
| 多義字 | lead | 帶領 | 僅例句 | — |
| 多義字 | wind | 風 | 僅例句 | — |
| 多義字 | read | 讀 | 僅例句 | — |
| 多義字 | milk | 牛奶 | 有候選 | milch |
| 副詞 | quickly | 迅速 | 僅例句 | — |
| 副詞 | slowly | — | 未收錄 | — |
| 副詞 | happily | 快樂地；高興地；幸好。 | 有候選 | blithefully, blithely, gaily |
| 副詞 | easily | 比平常或預期更快或可能。 | 僅例句 | — |
| 拼字陷阱 | carpet | 地毯 | 有候選 | tapete, tapis |
| 拼字陷阱 | butterfly | 蝴蝶 | 僅例句 | — |
| 拼字陷阱 | pineapple | 鳳梨。 | 有候選 | ananas |
| 拼字陷阱 | hamburger | 漢堡；夾有肉排的麵包。 | 有候選 | hamburger/burger |
| 拼字陷阱 | understand | 理解 | 有候選 | comprehend, construe |
| 拼字陷阱 | uncle | 叔叔 | 僅例句 | — |
| 拼字陷阱 | inflammable | 易燃的；可燃的 | 有候選 | noninflammable, accendible, combustible |
| 拼字陷阱 | invaluable | 非常寶貴的 | 僅例句 | — |
| 拼字陷阱 | nonplus | 一種困惑或困惑的狀態。 | 僅例句 | — |
| 拼字陷阱 | union | 聯盟 | 有候選 | alliance, league, coalition |
| 多字詞條 | in front of | — | 未收錄 | — |
| 多字詞條 | look after | — | 未收錄 | — |
| 多字詞條 | give up | — | 未收錄 | — |
| 多字詞條 | take care of | — | 未收錄 | — |

## 重跑

```sh
flutter test --no-pub test/word_extension_generalization_test.dart test/word_extension_coverage_test.dart
# 選擇性輸出機器可讀的完整理由與結果（平常測試不寫入檔案）：
flutter test --no-pub --dart-define=WORD_EXTENSION_AUDIT_PATH=/tmp/word-extension-audit.json test/word_extension_coverage_test.dart
```
