import '../models/word_card.dart';
import '../models/word_extension.dart';

/// Reviewed links for common words. Meanings and grammatical roles are scoped
/// to the existing dictionary entries; topical links are explained explicitly.
const commonWordRelations = <WordRelation>[
  WordRelation(
    sourceWord: 'unable',
    targetWord: 'able',
    sourceSense: '不能的，無法的',
    targetSense: '有能力的',
    sourcePartsOfSpeech: [PartOfSpeech.adjective],
    sourceExample:
        "I was unable to attend the meeting due to a prior commitment. 由於事先已有約定，我無法參加會議。",
    targetPartsOfSpeech: [PartOfSpeech.adjective],
    targetExample:
        "Will you be able to attend the meeting tomorrow morning? 你明天早上能參加會議嗎？",
    kind: WordRelationKind.related,
    explanation:
        '相反概念：be able to 表示能夠做某事；be unable to 表示無法做某事。unable 與 able 都是形容詞。',
  ),
  WordRelation(
    sourceWord: 'bookshelf',
    targetWord: 'shelf',
    sourceSense: '用於存放書籍以便於視覺參考的一個或多個架子。',
    targetSense: '架子',
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample: "He built a narrow bookshelf for the hallway. 他為走廊做了一個窄書架。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "He placed the new book on the top shelf of the bookcase. 他把新書放在書架的最頂層。",
    kind: WordRelationKind.related,
    explanation: '用途關係：bookshelf 是用來放書的 shelf；shelf 泛指放置物品的架子或層板。',
  ),
  WordRelation(
    sourceWord: "dog",
    targetWord: "puppy",
    sourceSense: "狗",
    targetSense: "小狗",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "The dog barked loudly when someone rang the door bell. 當有人按門鈴時，狗大聲地叫了起來。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "The little puppy was wagging its tail and jumping with joy. 小狗正搖著尾巴，高興地跳著。",
    kind: WordRelationKind.related,
    explanation: "dog 泛指狗；puppy 特指幼年的狗。這是動物與其幼年個體的關係。",
  ),
  WordRelation(
    sourceWord: "cat",
    targetWord: "kitten",
    sourceSense: "貓",
    targetSense: "小貓",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "My cat loves to curl up and sleep on my lap. 我的貓喜歡蜷縮在我腿上睡覺。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "The children were playing with a cute little kitten. 孩子們正在和一隻可愛的小貓玩。",
    kind: WordRelationKind.related,
    explanation: "cat 泛指貓；kitten 特指幼年的貓。這是動物與其幼年個體的關係。",
  ),
  WordRelation(
    sourceWord: "house",
    targetWord: "home",
    sourceSense: "房子",
    targetSense: "家",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "They live in a beautiful house with a large garden. 他們住在有一座大花園的漂亮房子裡。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample: "Taiwan is my home, and I love living here. 台灣是我的家，我喜歡住在這。",
    kind: WordRelationKind.confused,
    explanation: "house 著重住宅建築本身；home 著重居住的家或歸屬感。",
    comparisonExample: "That house is our home.\n那棟房子是我們的家。",
  ),
  WordRelation(
    sourceWord: "book",
    targetWord: "read",
    sourceSense: "書",
    targetSense: "讀",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "I'm reading a very interesting book about space exploration. 我正在讀一本關於太空探索的有趣書籍。",
    targetPartsOfSpeech: [PartOfSpeech.verb],
    targetExample:
        "She likes to read the morning newspaper while drinking coffee. 她喜歡在喝咖啡時讀早報。",
    kind: WordRelationKind.related,
    explanation: "情境搭配：read a book 表示讀一本書；book 是閱讀的對象，read 是閱讀的動作。",
  ),
  WordRelation(
    sourceWord: "water",
    targetWord: "drink",
    sourceSense: "水",
    targetSense: "喝",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "It's important to drink plenty of water every day for your health. 每天喝充足的水對健康很重要。",
    targetPartsOfSpeech: [PartOfSpeech.verb],
    targetExample:
        "It's important to drink plenty of water every day. 每天喝充足的水很重要。",
    kind: WordRelationKind.related,
    explanation: "情境搭配：drink water 表示喝水；water 是飲用的對象，drink 是飲用的動作。",
  ),
  WordRelation(
    sourceWord: "music",
    targetWord: "song",
    sourceSense: "音樂",
    targetSense: "歌曲",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "I love listening to classical music while I'm studying or working. 我喜歡在唸書或工作時聽古典音樂。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "She sang a beautiful traditional song at the talent show. 她在才藝表演中唱了一首優美的傳統歌曲。",
    kind: WordRelationKind.related,
    explanation: "song 通常指可以演唱的歌曲，是音樂作品的一種；music 可泛指音樂。",
  ),
  WordRelation(
    sourceWord: "apple",
    targetWord: "fruit",
    sourceSense: "蘋果",
    targetSense: "水果",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample: "An apple a day keeps the doctor away. 一天一蘋果，醫生遠離我。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "Fresh fruit is a healthy and delicious snack. 新鮮水果是健康又美味的零食。",
    kind: WordRelationKind.related,
    explanation: "分類關係：apple 是 fruit 的一種，fruit 是水果的總稱。",
  ),
  WordRelation(
    sourceWord: "river",
    targetWord: "stream",
    sourceSense: "河",
    targetSense: "溪流",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "The Thames River flows through the heart of London. 泰晤士河橫貫倫敦市中心。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "The mountain stream was crystal clear and cold as ice. 山間溪流的水清澈見底且冰冷如冰。",
    kind: WordRelationKind.related,
    explanation: "river 與 stream 都指流動的水道；stream 通常是較小的溪流，river 通常是較大的河流。",
  ),
  WordRelation(
    sourceWord: "city",
    targetWord: "town",
    sourceSense: "城市",
    targetSense: "鎮",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "Tokyo is a huge and vibrant city with a lot to explore. 東京是一座巨大且充滿活力的城市，有很多值得探索的地方。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "They live in a small town in the south of France. 他們住在法國南部的一個小鎮。",
    kind: WordRelationKind.related,
    explanation: "city 與 town 都可描述聚居地；city 常指城市，town 常指鎮，實際劃分依地區而異。",
  ),
  WordRelation(
    sourceWord: "train",
    targetWord: "station",
    sourceSense: "火車",
    targetSense: "車站",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "What time does the next train to Taipei leave the station? 下一班去台北的火車幾點開？",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "I'll meet you at the train station at 10:00 a.m. tomorrow. 我明天早上十點在火車站等妳。",
    kind: WordRelationKind.related,
    explanation: "交通情境：train station 是火車站；train 是交通工具，station 是乘客上下車的場所。",
  ),
  WordRelation(
    sourceWord: "money",
    targetWord: "price",
    sourceSense: "錢",
    targetSense: "價格",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "Success is not always measured by how much money you earn. 成功並不總是以你賺了多少錢來衡量的。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "The price of gold has reached an all-time high this year. 金價今年達到了歷史新高。",
    kind: WordRelationKind.related,
    explanation: "購物情境：price 表示商品或服務的價格，也就是購買時需要付多少 money。",
  ),
  WordRelation(
    sourceWord: "time",
    targetWord: "minute",
    sourceSense: "時間",
    targetSense: "分鐘",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "I have spent a lot of time learning how to speak English. 我花了大量的時間學習如何說英文。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample: "Please wait for a minute; I'll be right back. 請等一分鐘，我馬上回來。",
    kind: WordRelationKind.related,
    explanation: "計量關係：minute 是衡量 time 的單位，一分鐘等於六十秒。",
  ),
  WordRelation(
    sourceWord: "idea",
    targetWord: "thought",
    sourceSense: "主意",
    targetSense: "想法；思考；念頭",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample: "That's a great idea! Let's do it. 那是個好主意！我們就這麼辦吧。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "Thought can change the way we see a problem. 思考能改變我們看待問題的方式。",
    kind: WordRelationKind.related,
    explanation: "idea 常指點子或主意；thought 也可指思考的活動或腦中的念頭。兩字在部分情境相近，仍須依句意選用。",
  ),
  WordRelation(
    sourceWord: "road",
    targetWord: "street",
    sourceSense: "路",
    targetSense: "街道",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "Follow this main road for two miles and you will find the house. 沿著這條主路走兩英里，你就會找到那間房子。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "Living on a busy street can be very noisy and stressful. 住在繁忙的街道上可能會非常吵鬧且充滿壓力。",
    kind: WordRelationKind.related,
    explanation: "road 泛指道路；street 通常指城鎮中兩側有建築物的街道，兩字的使用範圍不同。",
  ),
  WordRelation(
    sourceWord: "rare",
    targetWord: "common",
    sourceSense: "稀有的",
    targetSense: "常見的",
    sourcePartsOfSpeech: [PartOfSpeech.adjective],
    sourceExample:
        "The bird is a very rare species that is only found on this island. 這種鳥是僅在該島上發現的非常罕見物種。",
    targetPartsOfSpeech: [PartOfSpeech.adjective],
    targetExample:
        "It is very common for students to feel nervous before an exam. 學生在考試前感到緊張是非常普遍的。",
    kind: WordRelationKind.related,
    explanation: "相反概念：rare 表示稀有、不常見；common 表示常見。此處比較的是出現頻率，不是牛排熟度。",
  ),
  WordRelation(
    sourceWord: "careful",
    targetWord: "careless",
    sourceSense: "小心",
    targetSense: "粗心的",
    sourcePartsOfSpeech: [PartOfSpeech.adjective],
    sourceExample:
        "Please be careful when you cross the busy street. 過繁忙的街道時要小心。",
    targetPartsOfSpeech: [PartOfSpeech.adjective],
    targetExample:
        "It was a careless mistake that could have been avoided. 那是一個本可以避免的粗心錯誤。",
    kind: WordRelationKind.related,
    explanation: "相反概念：careful 表示小心、仔細；careless 表示粗心、不夠留意。",
  ),
  WordRelation(
    sourceWord: "light",
    targetWord: "bright",
    sourceSense: "光",
    targetSense: "明亮的",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "The morning light shone through the window and woke me up. 早晨的光線穿過窗戶把我喚醒。",
    targetPartsOfSpeech: [PartOfSpeech.adjective],
    targetExample:
        "The sun was so bright that I had to wear sunglasses. 陽光太刺眼了，我不得不戴上太陽眼鏡。",
    kind: WordRelationKind.related,
    explanation: "描述情境：bright light 表示明亮的光；light 是光，bright 用來形容光線明亮。",
  ),
  WordRelation(
    sourceWord: "wind",
    targetWord: "breeze",
    sourceSense: "風",
    targetSense: "微風",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample: "The strong wind blew my hat off. 強風吹掉了我的帽子。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "There was a gentle breeze blowing from the ocean this evening. 今晚從大海吹來一陣微風。",
    kind: WordRelationKind.related,
    explanation: "分類關係：breeze 指輕柔的 wind，也就是微風。wind 是較廣泛的風的總稱。",
  ),
  WordRelation(
    sourceWord: "read",
    targetWord: "reader",
    sourceSense: "讀",
    targetSense: "讀者",
    sourcePartsOfSpeech: [PartOfSpeech.verb],
    sourceExample:
        "She likes to read the morning newspaper while drinking coffee. 她喜歡在喝咖啡時讀早報。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "That young reader finishes a novel every weekend. 那個小讀者每個週末都看完一本小說。",
    kind: WordRelationKind.related,
    explanation: "字族關係：reader 指閱讀的人；read 是閱讀的動作，reader 是進行這個動作的人。",
  ),
  WordRelation(
    sourceWord: "butterfly",
    targetWord: "insect",
    sourceSense: "蝴蝶",
    targetSense: "昆蟲",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "A colorful butterfly landed on a flower in the garden. 一隻彩色的蝴蝶停在花園裡的一朵花上。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "Ants and butterflies are common types of insects. 螞蟻和蝴蝶是常見的昆蟲種類。",
    kind: WordRelationKind.related,
    explanation:
        "分類關係：butterfly 是 insect 的一種。這是動物分類關係，不是把 butterfly 拆成 butter 與 fly。",
  ),
  WordRelation(
    sourceWord: "uncle",
    targetWord: "aunt",
    sourceSense: "叔叔",
    targetSense: "阿姨",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "My uncle lives in Canada and visits us once a year. 我的叔叔住在加拿大，每年來探望我們一次。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "My aunt lives in New York and visits us every Christmas. 我的阿姨住在紐約，每年聖誕節都會來探望我們。",
    kind: WordRelationKind.related,
    explanation: "親屬稱呼：uncle 與 aunt 分別可指父母輩的男性與女性親屬；實際中文稱呼依親屬關係而定。",
  ),
  WordRelation(
    sourceWord: "invaluable",
    targetWord: "valuable",
    sourceSense: "非常寶貴的",
    targetSense: "有價值的",
    sourcePartsOfSpeech: [PartOfSpeech.adjective],
    sourceExample:
        "The mentor provided invaluable guidance and support to the young researchers. 導師為年輕研究人員提供了非常寶貴的指導和支持。",
    targetPartsOfSpeech: [PartOfSpeech.adjective],
    targetExample:
        "He gave me some valuable advice on how to improve my skills. 他給了我一些關於如何提升技能的寶貴建議。",
    kind: WordRelationKind.confused,
    explanation: "valuable 表示有價值；invaluable 表示非常寶貴、難以估價，並不是 valuable 的反義字。",
    comparisonExample:
        "Your advice is valuable, and your support is invaluable.\n你的建議很有價值，而你的支持更是寶貴無比。",
  ),
  WordRelation(
    sourceWord: "sunflower",
    targetWord: "flower",
    sourceSense: "向日葵",
    targetSense: "花",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample: "A tall sunflower grew beside the fence. 籬笆旁長了一株高高的向日葵。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "The garden is full of beautiful colorful flowers in spring. 春天時花園裡開滿了美麗繽紛的花朵。",
    kind: WordRelationKind.related,
    explanation: "分類關係：sunflower 是向日葵，flower 是花的總稱；向日葵是開花植物的一種。",
  ),
  WordRelation(
    sourceWord: "children",
    targetWord: "child",
    sourceSense: "孩子們（複數）",
    targetSense: "孩子",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "The park was filled with the sounds of children laughing and playing. 公園裡充滿了孩子們笑鬧玩耍的聲音。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "The child was playing happily with his toys in the garden. 孩子正在花園裡開心地玩玩具。",
    kind: WordRelationKind.related,
    explanation: "不規則複數：children 是 child 的複數形式；一個孩子用 child，多個孩子用 children。",
  ),
  WordRelation(
    sourceWord: "feet",
    targetWord: "foot",
    sourceSense: "腳",
    targetSense: "腳",
    sourcePartsOfSpeech: [PartOfSpeech.noun],
    sourceExample:
        "After the long hike, her feet felt warm and tired. 長途健行後，她的雙腳又暖又累。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "He hurt his foot while playing football yesterday. 他昨天踢足球時弄傷了腳。",
    kind: WordRelationKind.related,
    explanation: "不規則複數：描述身體部位時，feet 是 foot 的複數形式；一隻腳用 foot，雙腳用 feet。",
  ),
  WordRelation(
    sourceWord: "wrote",
    targetWord: "write",
    sourceSense: "寫的過去式",
    targetSense: "寫",
    sourcePartsOfSpeech: [PartOfSpeech.verb],
    sourceExample:
        "Wrote, not writed, was the answer on his worksheet. 他的練習單答案是這個正確過去式，不是錯誤拼法。",
    targetPartsOfSpeech: [PartOfSpeech.verb],
    targetExample:
        "Please write your name and address on the application form. 請在申請表上寫下你的姓名和地址。",
    kind: WordRelationKind.related,
    explanation: "動詞變化：wrote 是 write 的過去式，用來描述過去寫作或書寫的動作。",
  ),
  WordRelation(
    sourceWord: "seen",
    targetWord: "see",
    sourceSense: "見過",
    targetSense: "看",
    sourcePartsOfSpeech: [PartOfSpeech.verb],
    sourceExample: "I have seen this movie twice. 這部電影我已經看過兩次。",
    targetPartsOfSpeech: [PartOfSpeech.verb],
    targetExample:
        "It was so dark that I could hardly see anything in front of me. 天太黑了，我幾乎看不見面前的任何東西。",
    kind: WordRelationKind.related,
    explanation: "動詞變化：seen 是 see 的過去分詞，常與 have、has 或 had 搭配，例如 have seen。",
  ),
  WordRelation(
    sourceWord: "gone",
    targetWord: "go",
    sourceSense: "離去的；消失的",
    targetSense: "去",
    sourcePartsOfSpeech: [PartOfSpeech.adjective],
    sourceExample: "Summer is gone. 夏天已經過去了。",
    targetPartsOfSpeech: [PartOfSpeech.verb],
    targetExample: "I have to go now. 我得走了。",
    kind: WordRelationKind.related,
    explanation: "字族關係：gone 是 go 的過去分詞，也可作形容詞表示已離去或消失的狀態。",
  ),
  WordRelation(
    sourceWord: "given",
    targetWord: "give",
    sourceSense: "給定的；特定的",
    targetSense: "給予；提供",
    sourcePartsOfSpeech: [PartOfSpeech.adjective],
    sourceExample: "The answer depends on a given condition. 答案取決於一項給定條件。",
    targetPartsOfSpeech: [PartOfSpeech.verb],
    targetExample: "Give the dog a little water after the walk. 散步後給狗喝一點水。",
    kind: WordRelationKind.related,
    explanation: "字族關係：given 是 give 的過去分詞，也可作形容詞表示給定的或特定的。",
  ),
  WordRelation(
    sourceWord: "quickly",
    targetWord: "quick",
    sourceSense: "迅速",
    targetSense: "快的",
    sourcePartsOfSpeech: [PartOfSpeech.adverb],
    sourceExample: "She looked quickly at the note on the door. 她快速地看了看門上的紙條。",
    targetPartsOfSpeech: [PartOfSpeech.adjective],
    targetExample:
        "I need to have a quick shower before we go out. 出門前我需要快速洗個澡。",
    kind: WordRelationKind.related,
    explanation: "字族關係：quickly 是 quick 對應的副詞，常用來描述動作發生得很快；quick 是形容詞。",
  ),
  WordRelation(
    sourceWord: "lead",
    targetWord: "leader",
    sourceSense: "帶領",
    targetSense: "領導者",
    sourcePartsOfSpeech: [PartOfSpeech.verb],
    sourceExample:
        "The experienced guide will lead us through the forest. 經驗豐富的導遊將帶領我們穿過森林。",
    targetPartsOfSpeech: [PartOfSpeech.noun],
    targetExample:
        "He is a natural leader who knows how to motivate his team. 他是一位天生的領導者，知道如何激勵他的團隊。",
    kind: WordRelationKind.related,
    explanation: "字族關係：leader 指帶領或領導他人的人；lead 是帶領的動作。此處不是金屬「鉛」的義項。",
  ),
];
