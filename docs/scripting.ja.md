# AbloxScript ガイド（スクリプトでゲームを作る）

AbloxScript は Ablox Studio の中で書ける、ゲーム用の小さなプログラミング言語です。
ルール（ピッカーで作るイベント）ではできないゲーム——**1対1のシューティング、
チーム戦、1人称視点、銃、画面のGUI（文字・バー・ボタン）、タイマー**——を作れます。

> English version: [`scripting.md`](scripting.md)

## どこで書くの？

1. Ablox Studio でワールドを開く
2. 左のパネルで **スクリプト** タブを選ぶ
3. **スクリプトを書く**（またはサンプルを選ぶ）
4. エディタ右上の **チェック** で文法の間違いを、**テスト実行** で実際の動きを確認
5. 公開して Ablox で遊ぶと、スクリプトは**ホストのiPad**の上で動きます

右側の **リファレンス** に、使える関数とイベントが全部のっています。

## いちばん短い1対1シューティング

```lua
on join(p)
  p.camera = "first"   -- 1人称にする
  p.give("rifle")      -- ライフルを持たせる
end

on death(victim, killer)
  if killer then
    killer.score = killer.score + 1
    if killer.score >= 5 then
      end_round(killer.name + " の勝ち！")
    end
  end
end
```

これだけで、入ってきた全員が1人称になり、ライフルで撃ち合い、先に5回倒した人が勝ちます。
画面には照準・撃つボタン・弾数・体力バーが自動で出ます。

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

let list = [1, 2, 3]      -- リストは1番から
let pos = {x: 0, y: 5, z: 0}
```

- `--` か `#` から行の終わりまではコメント
- 文字と数を `+` でつなぐと文字になります（`"点数: " + score`）
- `nil` と `false` だけが「うそ」、ほかは全部「ほんとう」
- 変数名に日本語も使えます（`let 点数 = 0`）
- iPadのキーボードが「“ ”」に変えても、全角の「（ ）＝１」で打っても、そのまま読めます

## イベント

`on イベント名(引数)` ～ `end` の中に、そのときにしたいことを書きます。

| イベント | いつ |
|---|---|
| `on start()` | ラウンド開始 |
| `on tick(dt)` | 1秒に10回（`dt` は前回からの秒数） |
| `on join(p)` | プレイヤーが入った（武器・カメラはここで） |
| `on leave(p)` | プレイヤーが抜けた |
| `on touch(p, block)` | ブロックに触れた |
| `on tap(p, block)` | ブロックをタップした |
| `on fire(p)` | 撃った |
| `on hit(victim, attacker, damage)` | 弾が当たった。数を `return` するとダメージを変更（0で無効） |
| `on hit_block(p, block)` | 弾がブロックに当たった |
| `on death(victim, killer)` | 倒された（誰のせいでもなければ `killer` は nil） |
| `on respawn(p)` | 復活した |
| `on button(p, id)` | 画面のボタンが押された |

## プレイヤー（`p`）

| 書き方 | 意味 |
|---|---|
| `p.name` `p.score` `p.team` | 名前・点数・チーム（点数とチームは変更可） |
| `p.health` `p.max_health` `p.alive` | 体力。`p.health = 0` で倒れる |
| `p.camera = "first"` / `"third"` | 1人称 / 3人称 |
| `p.give("rifle")` `p.take()` `p.weapon` | 武器を渡す / 取り上げる / 今の武器 |
| `p.ammo` `p.reload()` | 弾数 / リロード |
| `p.damage(20)` `p.heal(20)` `p.kill()` `p.respawn()` | ダメージ・回復・倒す・復活 |
| `p.teleport(block("Spawn"))` | ブロック・プレイヤー・`{x, y, z}` へ移動 |
| `p.speed = 2` `p.jump = 1.5` | 速さ・ジャンプ（最大3倍） |
| `p.message("やった！", 2)` `p.sound("hit")` | その人だけにメッセージ・音 |
| `p.kills = 0` | 自分の値を保存できる |

## 武器

最初から使える武器: `blaster`（バランス）、`rifle`（遠くまで強い）、`shotgun`（近距離で強い）、`pistol`（速い）。

自分で作ることもできます。書かなかった値は `model` の武器と同じになります。

```lua
on start()
  weapon("sniper", {model: "rifle", damage: 90, rate: 0.8, ammo: 3, spread: 0})
end
on join(p) p.give("sniper") end
```

| 項目 | 意味 | 範囲 |
|---|---|---|
| `damage` | 1発のダメージ | 0–1000 |
| `rate` | 1秒に撃てる数 | 0.2–20 |
| `range` | 届く距離（m） | 1–200 |
| `ammo` | 弾倉の弾数 | 1–200 |
| `reload` | リロード秒数 | 0–10 |
| `spread` | ばらつき（度） | 0–30 |

当たり判定はホストのiPadが決めます（壁の向こうには当たりません）。

## 画面のGUI

```lua
hud_text("title", "キャプチャー・ザ・フラッグ", {at: "top", color: "red", size: "large"})
hud_bar("time", 30, 60, {at: "top", color: "yellow"})
p.hud_button("shop", "ショップ", {color: "green"})   -- その人の画面だけ
hud_remove("title")
```

- 同じ `id` でもう一度呼ぶと書き換わります
- `at`: `top_left` `top` `top_right` `left` `center` `right` `bottom_left` `bottom` `bottom_right`
- `size`: `small` `medium` `large`
- `color`: `red` `blue` `赤` `青` … または `"#FF8800"`
- ボタンが押されると `on button(p, id)` が呼ばれます
- 1人の画面に出せるのは24個まで

## みんなに・時間

| 書き方 | 意味 |
|---|---|
| `players()` | 全員のリスト |
| `block("Door")` `blocks("coin")` | 名前でブロックを探す / タグで全部 |
| `b.visible = false` `b.solid = false` `b.color = "red"` `b.move(0, 3, 0, 1)` | ブロックを変える |
| `announce("スタート！", 3)` `sound("goal")` `end_round("赤の勝ち！")` | 全員へ |
| `after(2, func() … end)` | 2秒後に1回 |
| `let t = every(1, func() … end)` / `cancel(t)` | 1秒ごとに / 止める |
| `time()` `distance(a, b)` `random(1, 6)` | 経過秒数・距離・サイコロ |
| `game.respawn_time = 3` | 復活までの秒数（`-1` で自動復活しない） |
| `game.friendly_fire = true` | 味方にも当たるようにする |

## 困ったとき

- エラーは「〇行目: …」の形で出ます。**チェック** ボタンで遊ぶ前に見つけられます
- 終わらないループは自動で止まり、エラーになります（ゲームは止まりません）
- `on joni(p)` のような打ち間違いは「`on join` のことですか？」と教えてくれます
- 遊んでいる最中のエラーは、ホストの画面左下に出ます

## サンプル

Studio の **サンプル** メニューから、そのまま遊べるゲームを入れられます:

- **1対1シューティング** — 1人称・ライフル・先に5回倒した方の勝ち
- **チーム戦** — 赤と青に分かれて、先に10回倒したチームの勝ち
- **タイマーとボタン** — 減っていくバーと、画面のボタン
- **コインラッシュ** — 「coin」タグのブロックを90秒で集める
