# ATtiny85

## ラーメンタイマー

ATtiny85 で作る、カップラーメン用の3分タイマーです。
ボタンを押すとカウントが始まり、3分たつとブザーとLEDで知らせます。

### 進捗

- 基板とケースを発注しました。

### 動き

1. ボタンを押す → 「ピッ」と鳴ってスタート
2. カウント中は LED が1秒ごとに点滅
3. 途中でボタンを押すと「ピピッ」と鳴ってキャンセル
4. 3分たつと「ピピピッ」と鳴り続け、LED も光る
5. ボタンを押すと止まる

### 部品

| 部品 | 数量 |
|---|---|
| ATtiny85 | 1 |
| 圧電ブザー（パッシブ） | 1 |
| LED | 1 |
| 抵抗 330Ω（LED用） | 1 |
| タクトスイッチ | 1 |
| CR2032 電池＋ホルダー（3V） | 1 |

### 配線

```
            ATtiny85
          +----U----+
   RESET -|1       8|- VCC (+3V)
     PB3 -|2       7|- PB2 ---- スイッチ ---- GND
     PB4 -|3       6|- PB1 ---- ブザー ------ GND
     GND -|4       5|- PB0 ---- 330Ω -- LED - GND
          +---------+
```

スイッチは内部プルアップを使うので、抵抗はいりません。

### プログラム

Arduino IDE に **ATTinyCore** を入れて書き込みます。

- ボード：ATtiny25/45/85 (No bootloader)
- Chip：ATtiny85
- Clock：8 MHz (internal)　※最初に「ブートローダを書き込む」でクロックを設定

```cpp
// ATtiny85 ラーメンタイマー（3分）
const uint8_t LED = 0;  // PB0
const uint8_t BUZ = 1;  // PB1
const uint8_t BTN = 2;  // PB2

const unsigned long TIME_MS = 3UL * 60 * 1000;  // 3分

void setup() {
  pinMode(LED, OUTPUT);
  pinMode(BUZ, OUTPUT);
  pinMode(BTN, INPUT_PULLUP);
}

// ボタンが押されて離されたら true
bool pressed() {
  if (digitalRead(BTN) == LOW) {
    delay(20);
    while (digitalRead(BTN) == LOW) {}
    delay(20);
    return true;
  }
  return false;
}

void beep(int ms) {
  tone(BUZ, 2000);
  delay(ms);
  noTone(BUZ);
}

void loop() {
  if (!pressed()) return;

  // スタート
  beep(100);
  unsigned long start = millis();

  // カウント中
  while (millis() - start < TIME_MS) {
    digitalWrite(LED, (millis() - start) % 1000 < 100);  // 1秒ごとに点滅
    if (pressed()) {  // キャンセル
      digitalWrite(LED, LOW);
      beep(50); delay(100); beep(50);
      return;
    }
  }

  // 3分たった：ボタンを押すまで「ピピピッ」
  unsigned long t0 = millis();
  bool last = false;
  while (!pressed()) {
    unsigned long p = (millis() - t0) % 1000;
    bool on = (p < 600) && (p % 200 < 100);
    if (on != last) {
      if (on) tone(BUZ, 2000); else noTone(BUZ);
      digitalWrite(LED, on);
      last = on;
    }
  }
  noTone(BUZ);
  digitalWrite(LED, LOW);
}
```

### メモ

- 時間を変えるときは `TIME_MS` の `3UL` を変えます（5分なら `5UL`）。
- 内部クロックなので、数秒ずれることがあります。ラーメンには十分です。
