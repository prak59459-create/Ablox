# .absc ガイド（AbloxScript でゲームを作る）

AbloxScript は Ablox のためのプログラミング言語で、ファイルの拡張子は **`.absc`** です。
ルール（ピッカーで作るイベント）ではできないことは、全部これで作れます。

- **画面GUI** — 文字・ボタン・パネル・アイコン・バー・入力欄を、好きな位置・大きさ・色で。メニュー画面やショップも作れる
- **カメラと画面** — 1人称／3人称／真上から／固定カメラ、視野角、揺れ、フェード、ジョイスティックや上のバーを隠す
- **キャラクター** — 色・大きさ・帽子・名前・表示/非表示、速さ・ジャンプ・重力、瞬間移動、吹き飛ばし、向き
- **NPC** — ゲームが動かすキャラ。歩かせる・追いかけさせる・撃たせる・しゃべらせる
- **マップ** — ブロックを作る・消す・コピー・動かす・回す・色や形を変える。空・重力・明るさも
- **戦闘** — 銃（自作も可）、当たり判定、体力、復活、チーム
- **計算** — 四則演算、三角関数、位置（ベクトル）の計算、リスト・文字の操作、並べ替え

> English version: [`scripting.md`](scripting.md)

## どこで書くの？

1. Ablox Studio でワールドを開く
2. 左のパネルで **スクリプト** タブ
3. **新しいファイル**（または下のサンプル）を押す
4. エディタで **チェック**（文法の間違い）と **テスト実行**（実際の動き）を確認
5. 遊ぶと、スクリプトは**ホストのiPad**の上で動きます

- 1つのワールドに `.absc` ファイルを**いくつでも**（32個まで）入れられます。全部いっしょに動き、ファイルごとに `on join` などを書けます
- ファイルの「…」メニューから **.absc を書き出す**（「ファイル」に保存・AirDrop）、**読み込む** でPCで書いた `.absc` を取り込めます
- GitHubのゲーム一覧（AbloxGames）では `index.json` に `"scripts": ["games/xxx/main.absc"]` と書けば、`.absc` ファイルをそのまま置いておけます
- **GitHubのリポジトリから直接取得**もできます（↓）

## GitHubから .absc を取得する

パソコンで書いた `.absc` をGitHubに置いて、そのままワールドに取り込めます。

1. 公開（Public）のGitHubリポジトリに `.absc` を置く（例: `scripts/main.absc`, `scripts/ui.absc`）
2. Studio の **スクリプト** タブで **GitHubから .absc を取得**
3. **リポジトリ**（`owner/repo`）・**ブランチ**（ふつうは `main`）・**フォルダ**（例: `scripts`、いちばん上なら空）を入れて **保存して取得**
4. 次からは **今すぐ最新を取得** を押すだけ

- 同じ名前のファイルは置き換わります。iPadにしかないファイルは**消えません**
- 取得は1回の「取り消し」で元に戻せます
- **遊ぶたびに最新を取得する** をオンにすると、ゲームを始める前にホストのiPadが毎回取りにいきます。GitHubで直せば、ワールドを公開し直さなくても全員に届きます（つながらないときは保存されているスクリプトで遊べます）
- GitHubは数分キャッシュするので、pushしてから反映まで少しかかることがあります
- 読むだけで、何もアップロードしません。1ファイル1MBまで、32ファイルまで

### 公開ゲームをStudioで開く

Studio の最初の画面の **公開ゲームを開く** で、ゲーム一覧（Ablox の「ゲーム」タブと同じもの）のゲームを、マップ・ルール・スクリプトごと新しいプロジェクトとして開けます。
一覧のリポジトリとブランチはそこで変えられ、Ablox の **設定 → ゲーム一覧** と共通です。

右側の **リファレンス** に、使える関数とイベントが全部のっています。

## 例: タイトル画面つきの1対1シューティング

```lua
on join(p)
  -- タイトル画面（ジョイスティックは隠す）
  p.controls = false
  p.ui_panel("title", {w: 420, h: 240})
  p.ui_text("name", "1v1 DUEL", {parent: "title", y: 0.3, size: 44, bold: true, color: "gold"})
  p.ui_button("play", "スタート", {parent: "title", y: 0.75, w: 200, h: 56, bg: "green"})
end

on button(p, id)
  if id == "play" then
    p.ui_remove("title")
    p.controls = true
    p.camera = "first"      -- 1人称
    p.give("rifle")         -- 銃を持たせる
    p.ui_text("kills", "キル: 0", {at: "top_left", size: 26, bold: true})
  end
end

on death(victim, killer)
  if killer == nil then return end
  killer.score = killer.score + 1
  killer.ui_text("kills", "キル: " + killer.score)   -- 同じ id で書き換え
  victim.shake(0.5, 0.5)
  if killer.score >= 5 then end_round(killer.name + " の勝ち！") end
end
```

## 言語の基本

```lua
let score = 0                 -- 変数を作る（2回目からは let なし）
score = score + 1

if score >= 10 then
  print("クリア！")
elif score >= 5 then
  print("あと少し")
else
  print("がんばれ")
end

for i in 1 to 3 do print(i) end          -- 1, 2, 3
for p in players() do print(p.name) end  -- リストを順に
while score < 3 do score = score + 1 end

func double(x)
  return x * 2
end

let list = [1, 2, 3]                     -- リストは1番から
let pos = {x: 0, y: 5, z: 0}             -- 位置
let up = pos + {x: 0, y: 1, z: 0} * 2    -- 位置は足し算・かけ算できる
```

- `--` か `#` から行の終わりまではコメント
- 文字と数を `+` でつなぐと文字になります（`"点数: " + score`）
- `nil` と `false` だけが「うそ」
- 変数名に日本語も使えます（`let 点数 = 0`）
- iPadのキーボードが「“ ”」に変えても、全角の「（ ）＝１」で打っても、そのまま読めます

## イベント

| イベント | いつ |
|---|---|
| `on start()` | ラウンド開始 |
| `on tick(dt)` | 1秒に10回（`dt` は前回からの秒数） |
| `on join(p)` / `on leave(p)` | プレイヤーが入った／抜けた |
| `on touch(p, block)` / `on tap(p, block)` | ブロックに触れた（NPCも）／タップした |
| `on fire(p)` / `on hit(victim, attacker, damage)` / `on hit_block(p, block)` | 撃った／当たった（数を return でダメージ変更）／ブロックに当たった |
| `on death(victim, killer)` / `on respawn(p)` | 倒された／復活した |
| `on button(p, id)` / `on input(p, id, text)` | 画面のボタン／テキストボックス |
| `on chat(p, text)` | チャット（`/fly` のようなコマンドにも） |

## 画面GUI

```lua
ui_text("score", "Score: 0", {at: "top_left", size: 24, color: "gold"})
ui_button("play", "Play", {x: 0.5, y: 0.7, w: 200, h: 56, bg: "green"})
ui_panel("menu", {w: 400, h: 300, bg: "#000000AA", radius: 20})
ui_text("title", "Shop", {parent: "menu", y: 0.1, size: 30})
ui_image("heart", "heart.fill", {at: "top_right", size: 40, color: "red"})
ui_bar("hp", 50, 100, {at: "bottom", w: 300})
ui_input("name", "名前を入れてね", {w: 240})

let t = ui_text("msg", "Hi")
t.text = "Hello"        -- 返ってきた項目を直接変えられる
t.visible = false
ui_remove("menu")       -- パネルを消すと中身も消える
```

- `x`, `y` は画面（またはパネル）の端から端まで **0〜1**。`at: "top_left"` などで端にぴったり
- 同じ `id` でもう一度呼ぶと**書き換え**（書かなかった設定はそのまま）
- 全員用は `ui_text(...)`、1人用は `p.ui_text(...)`
- 設定: `at x y pivot dx dy w h color bg size bold radius opacity visible layer parent text value max`

## カメラと画面

```lua
p.camera = "first"      -- "third"（後ろ） "top"（真上） "fixed"（固定）
p.camera_distance = 12
p.fov = 90
p.camera_look({x: 0, y: 20, z: -20}, block("Stage"))   -- 固定カメラ
p.camera_reset()
p.fade("black", 1)  p.fade(nil, 1)   -- 暗転と戻す
p.shake(0.5, 1)
p.controls = false      -- ジョイスティックとボタンを隠す
p.default_ui = false    -- 上のバーとチャットを隠す（退出ボタンだけは残ります）
```

## キャラクター（プレイヤー・NPC共通）

```lua
p.color = "red"   p.head_color = "#FFD60A"   p.leg_color = "blue"
p.size = 3        p.hat = "crown"            p.visible = false    p.name = "ボス"
p.speed = 2       p.jump = 1.5               p.gravity = 0.3      p.frozen = true
p.position = {x: 0, y: 10, z: 0}             -- 瞬間移動
p.launch(0, 20, 0)                           -- 吹き飛ばす
p.look_at(block("Goal"))                     -- 向かせる
p.health = 50   p.damage(10)   p.heal(10)   p.kill()   p.respawn()
p.give("rifle")   p.take()   p.reload()
p.message("やった！", 2)   p.chat("こんにちは")   p.sound("hit")
p.coins = 0                                  -- 自分の値を保存できる
```

## NPC

```lua
let z = create_npc({name: "Zombie", position: {x: 0, y: 2, z: 10},
                    color: "green", size: 1.2, health: 80, speed: 0.6})
z.follow(p)          -- 追いかける
z.move_to(block("Door"))
z.stop()   z.jump_now()   z.shoot(p)   z.say("グルル…")   z.destroy()
for n in npcs() do ... end
```

NPCは撃たれると倒れ、`on death` で復活させない限り消えます。

## マップとワールド

```lua
let b = create_block({shape: "sphere", position: {x: 0, y: 5, z: 0}, size: 2,
                      color: "red", material: "neon", tags: ["coin"]})
b.position = {x: 3, y: 5, z: 0}   b.size = {x: 2, y: 1, z: 2}   b.rotation = {x: 0, y: 45, z: 0}
b.move(0, 3, 0, 1)   b.rotate(0, 90, 0)   b.clone()   b.destroy()
b.visible = false    b.solid = false      b.opacity = 0.5
b.behavior = "trigger"   -- さわったら on touch が動く（すり抜ける）。hazard / bounce / checkpoint なども
world.sky = "#87CEEB"   world.gravity = -3   world.light = 0.2   world.fall_height = -20
```

- `on touch` が動くのは **behavior があるブロックだけ**。スクリプトで作ったコインなどは `behavior: "trigger"` をつけよう

`restart_round()` でやり直すと、スクリプトが変えたマップは元に戻ります。

## 武器

最初から: `blaster` `rifle` `shotgun` `pistol`。自分で作るとき:

```lua
weapon("railgun", {model: "rifle", damage: 500, rate: 0.5, range: 800, ammo: 1, reload: 3, spread: 0})
```

範囲: damage 0〜100万 / rate 0.1〜30 / range 1〜1000 / ammo 1〜1000 / reload 0〜60 / spread 0〜45

## 計算と便利な関数

`raycast(p, p.look, 50)`（線の先で最初に当たるもの）、`distance(a, b)`、`random(1, 6)`、
`vec normalize dot cross lerp magnitude`、`pow sqrt sin cos tan atan2 log round fixed`、
`sort map filter range slice reverse sum insert index_of`、`replace split join upper lower` など。
全部 Studio の **リファレンス** にあります。

## 制限（ほぼ無制限、でも安全装置つき）

1回のイベントで200万ステップまで、リスト10万個、文字100万字、タイマー1000個、画面の項目300個、NPC100体、ブロック2万個。
`while true do end` のような終わらないループだけは自動で止まり、エラーになります（ホストのiPadが固まらないように）。

## 困ったとき

- エラーは「main.absc の 12行目: …」の形で出ます。遊ぶ前に **チェック** で見つけられます
- `on joni(p)` のような打ち間違いは「`on join` のことですか？」と教えてくれます
- 遊んでいる最中のエラーは、ホストの画面左下に出ます
