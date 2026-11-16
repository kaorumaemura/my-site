; =====================================================================
;  ラーメンタイマー  ATtiny85 @ 1MHz (内蔵8MHz / CKDIV8)
;
;  PB0〜PB2 : LED (3分 / 4分 / 5分)
;  PB3      : スイッチ (内部プルアップ、押すと0)
;  PB4      : ブザー (Timer1割り込みで反転)
;
;  通常: 1回押す=スタート/キャンセル、2回押す(ダブルクリック)=設定へ
;  設定: 押すごとに3→4→5→3分、3秒操作なしで確定 (EEPROMに保存)
; =====================================================================
.include "tn85def.inc"

; ---- レジスタ ----
.def hist   = r2        ; スイッチ履歴 (10msごとに左へずらす、bit0=最新、1=押している)
.def kak    = r3        ; 確定値 (1=押している)
.def clicks = r4        ; 通常: クリック回数 / 設定: 1=確定済み
.def sdur   = r5        ; 音の残り時間 (10ms単位)
.def scnt   = r6        ; ピッピッピッの残り区間数 / メロディの残り演奏回数
.def tsel   = r7        ; 設定時間 0=3分 1=4分 2=5分
.def tmp    = r16
.def tmp2   = r17
.def flg    = r18       ; 1ループだけ有効なイベント (下のF_xxx)
.def ledt   = r19       ; 設定時間のLEDを見せる残り秒数
.def state  = r20       ; ST_xxx
.def t10    = r21       ; 10ms分周カウンタ
.def pend   = r22       ; 設定中の選択 (NONE=未選択、ALMSTOP=アラーム停止の印)
.def snd    = r23       ; SND_xxx
; r25:r24 = 1秒カウンタ (msで1000から減らす)
; X = 残り秒数   Y = クリック待ち・設定タイムアウト (ms)   Z = メロディ位置

; ---- 定数 ----
.equ CLICKWIN  = 400    ; ダブルクリック判定 (ms)
.equ SETTO     = 3000   ; 設定の無操作タイムアウト (ms)

.equ TICK      = 0      ; GPIOR0のbit: 1ms経過

.equ F_SWDN    = 0      ; flg: スイッチが押された
.equ F_10MS    = 1      ; flg: 10ms経過
.equ F_SEC     = 2      ; flg: 1秒経過

.equ ST_IDLE   = 0
.equ ST_RUN    = 1
.equ ST_SET    = 2

.equ NONE      = 3
.equ ALMSTOP   = 4

.equ SND_OFF   = 0
.equ SND_BEEP  = 1
.equ SND_MEL   = 2
.equ SND_BEEP3 = 3

; Timer1 = 1MHz/2 = 500kHz、一致ごとに反転 → 周波数 = 250kHz / (OCR+1)
;   249:約1000Hz  184:約1350Hz  165:約1500Hz  142:約1750Hz  124:約2000Hz
.equ TONE_BEEP = 249    ; 操作音 約1000Hz
.equ TONE_HI   = 124    ; ピッピッピッ 約2000Hz
.equ REST      = 255    ; メロディの休符

.equ PRR_OFF   = (1<<PRTIM1)|(1<<PRUSI)|(1<<PRADC)   ; Timer1も停止
.equ PRR_SND   = (1<<PRUSI)|(1<<PRADC)               ; Timer1は動かす

; ---- 割り込みベクタ (使う割り込みは本体を直接置く) ----
.org 0x0000
    rjmp RESET              ; 0  RESET
    reti                    ; 1  INT0
    reti                    ; 2  PCINT0 : パワーダウンから起こすだけ
    sbi  PINB, PINB4        ; 3  TIM1_COMPA : ブザー反転 (SREG不変)
    reti                    ; 4  TIM1_OVF (未使用、3の続き)
    reti                    ; 5  TIM0_OVF
    reti                    ; 6  EE_RDY
    reti                    ; 7  ANA_COMP
    reti                    ; 8  ADC
    reti                    ; 9  TIM1_COMPB
    sbi  GPIOR0, TICK       ; 10 TIM0_COMPA : 1ms (SREG不変)
    reti                    ; 11 TIM0_COMPB (未使用、10の続き)
    reti                    ; 12 WDT
    reti                    ; 13 USI_START
    reti                    ; 14 USI_OVF

RESET:                      ; SPはハードでRAMENDに初期化済み
    clr  ZH                 ; r0〜r29 をまとめて0にする
    ldi  ZL, 30
CLR_LP:
    st   -Z, ZH
    cpse ZL, ZH
    rjmp CLR_LP

    ldi  tmp, 0x17          ; PB0〜PB2・PB4 出力
    out  DDRB, tmp
    ldi  tmp, (1<<PORTB3)   ; PB3 プルアップ
    out  PORTB, tmp

    ldi  tmp, (1<<ACD)      ; アナログコンパレータ停止
    out  ACSR, tmp
    ldi  tmp, PRR_OFF       ; ADC・USI・Timer1のクロック停止
    out  PRR, tmp

    ldi  tmp, (1<<PCINT3)   ; PB3のピン変化で復帰
    out  PCMSK, tmp
    ldi  tmp, (1<<PCIE)
    out  GIMSK, tmp

    ldi  tmp, (1<<SE)       ; 普段のスリープはアイドル
    out  MCUCR, tmp

    ldi  tmp, (1<<WGM01)    ; Timer0 CTC、1MHz/8=125kHz、125カウント=1ms
    out  TCCR0A, tmp
    ldi  tmp, (1<<CS01)
    out  TCCR0B, tmp
    ldi  tmp, 124
    out  OCR0A, tmp
    ldi  tmp, (1<<OCIE0A)|(1<<OCIE1A)   ; Timer1はPRRで止めるので許可したままでよい
    out  TIMSK, tmp

    out  EEARH, ZH          ; EEPROMアドレスは0固定 (EEARHの初期値は不定)
    out  EEARL, ZH

    ldi  pend, NONE
    rcall SEC_RST
    rcall EE_READ           ; 保存してある時間
    mov  tsel, tmp
    sei

; ---- メインループ: 1msごとに1周、それ以外はスリープ ----
MAIN:
    cli
    sbic GPIOR0, TICK
    rjmp GO
    sei
    sleep                   ; sei直後のsleepは割り込みを取りこぼさない
    rjmp MAIN
GO:
    cbi  GPIOR0, TICK
    sei
    clr  flg
    rcall TASK_SW
    rcall TASK_TIME
    rcall TASK_UI
    rcall TASK_SOUND
    rcall TASK_LED
    rcall TRY_PDOWN
    rjmp MAIN

; ---- スイッチ: 10msごとに読み、3回続けて同じなら確定 ----
TASK_SW:
    inc  t10
    cpi  t10, 10
    brlo SW_END
    clr  t10
    sbr  flg, (1<<F_10MS)

    lsl  hist
    sbis PINB, PINB3
    inc  hist               ; 押している → bit0=1
    mov  tmp, hist
    andi tmp, 0x07
    breq SW_REL             ; 000 → 離した
    cpi  tmp, 0x07
    brne SW_END             ; 混在 → そのまま
    tst  kak                ; 111 → 押した
    brne SW_END
    inc  kak
    sbr  flg, (1<<F_SWDN)   ; 押した瞬間
    ret
SW_REL:
    clr  kak
SW_END:
    ret

; ---- 1秒カウンタ ----
TASK_TIME:
    sbiw r24, 1
    brne TT_END
    sbr  flg, (1<<F_SEC)
    ldi  r24, low(1000)
    ldi  r25, high(1000)
TT_END:
    ret

; ---- ステート処理 ----
TASK_UI:
    cpi  state, ST_SET
    brne UI_NORMAL

; 設定: 押すごとに3→4→5→3分、3秒操作なしで確定
UI_SETTING:
    tst  clicks             ; 確定済み → ピッピッピッが終わるまで待つ
    breq US_ACT
    tst  snd
    brne US_END
    clr  clicks
    clr  state
    rjmp SHOW3              ; 確定した時間のLEDを3秒見せる
US_ACT:
    sbrs flg, F_SWDN
    rjmp US_TO
    rcall BEEP
    inc  pend               ; NONE(3)→0、0→1→2→0
    cpi  pend, 3
    brlo US_RL
    clr  pend
US_RL:
    ldi  YL, low(SETTO)
    ldi  YH, high(SETTO)
    rjmp SEC_RST            ; 点滅を押した瞬間からやり直す
US_TO:
    sbiw YL, 1
    brne US_END
    cpi  pend, NONE
    breq US_NOSEL           ; 未選択なら変更なし・音なし
    mov  tsel, pend
    mov  tmp, pend
    rcall EE_WRITE
    inc  clicks             ; 確定済みの印
    rjmp BEEP3
US_NOSEL:
    clr  state
    rjmp SHOW3
US_END:
    ret

; 通常: 1回=スタート/キャンセル (アラーム中は停止のみ)、2回=設定へ
UI_NORMAL:
    sbrs flg, F_SWDN
    rjmp UN_WAIT
    tst  clicks
    breq UN_FIRST
    clr  clicks             ; 2回目 → 設定へ
    rcall BEEP
    rjmp ENTER_SET
UN_FIRST:
    cpi  snd, SND_MEL       ; アラーム中の1回目は「止めるだけ」の印
    brne UN_F2
    ldi  pend, ALMSTOP
UN_F2:
    inc  clicks
    ldi  YL, low(CLICKWIN)
    ldi  YH, high(CLICKWIN)
    rcall BEEP              ; 操作音 (アラームも止まる)
    rjmp UN_SEC
UN_WAIT:
    tst  clicks
    breq UN_SEC
    sbiw YL, 1
    brne UN_SEC
    clr  clicks             ; 待ち時間切れ → 1回クリック確定
    cpi  pend, ALMSTOP
    brne UN_TOGGLE
    ldi  pend, NONE
    rjmp UN_SEC
UN_TOGGLE:
    tst  state
    brne UN_STOP
    rcall START_TIMER
    rjmp UN_SEC
UN_STOP:
    clr  state              ; キャンセル (残り時間は捨てる)
    clr  ledt
UN_SEC:
    sbrs flg, F_SEC
    ret
    tst  ledt
    breq UN_S2
    dec  ledt
UN_S2:
    cpi  state, ST_RUN
    brne UN_END
    sbiw XL, 1
    brne UN_END
    clr  state              ; 時間切れ → チャルメラ
    clr  ledt
    rjmp MELODY_START
UN_END:
    ret

ENTER_SET:
    ldi  state, ST_SET
    ldi  pend, NONE
    ldi  YL, low(SETTO)
    ldi  YH, high(SETTO)
    rjmp SEC_RST

START_TIMER:                ; X = 180 + 60*tsel 秒
    ldi  XL, low(180)
    clr  XH
    sbrc tsel, 0
    adiw XL, 60
    sbrc tsel, 1
    adiw XL, 60
    sbrc tsel, 1
    adiw XL, 60
    ldi  state, ST_RUN
SHOW3:                      ; 設定時間のLEDを3秒見せる
    ldi  ledt, 3
SEC_RST:                    ; 1秒の区切りをここから数え直す
    ldi  r24, low(1000)
    ldi  r25, high(1000)
    cbr  flg, (1<<F_SEC)
    ret

; ---- LED ----
; 待機: 消灯 (操作後3秒だけ設定時間のLED)
; 動作: 最初の3秒は点灯、以後1秒ごとに0.1秒点灯
; 設定: 全LEDを0.1秒点灯/0.9秒消灯、選択中のLEDは点灯したまま
TASK_LED:
    clr  tmp
    clt                     ; T=1: 1秒のうち最初の0.1秒
    cpi  r24, low(901)
    ldi  tmp2, high(901)
    cpc  r25, tmp2
    brlo LD_PH
    set
LD_PH:
    cpi  state, ST_SET
    brne LD_NRM
    brtc LD_SEL
    ldi  tmp, 0x07
LD_SEL:
    mov  tmp2, pend
    cpi  tmp2, NONE
    brne LD_MASK
    rjmp LD_OUT
LD_NRM:
    mov  tmp2, tsel
    tst  ledt
    brne LD_MASK
    cpi  state, ST_RUN
    brne LD_OUT
    brtc LD_OUT
LD_MASK:                    ; 0,1,2 → 1,2,4
    inc  tmp2
    cpi  tmp2, 3
    brne LD_OR
    ldi  tmp2, 4
LD_OR:
    or   tmp, tmp2
LD_OUT:                     ; PB0〜PB2だけ書き換える (PB4の反転と競合しないよう割り込み禁止)
    cli
    in   tmp2, PORTB
    andi tmp2, 0xF8
    or   tmp2, tmp
    out  PORTB, tmp2
    sei
    ret

; ---- 何もない待機中はパワーダウン (ボタンで復帰) ----
TRY_PDOWN:
    tst  state
    brne TP_END
    mov  tmp, clicks
    or   tmp, snd
    or   tmp, ledt
    brne TP_END
    mov  tmp, hist          ; 離して安定しているときだけ
    andi tmp, 0x07
    brne TP_END
    cli
    ldi  tmp, (1<<PCIF)     ; 保留中のピン変化フラグを消す
    out  GIFR, tmp
    sbis PINB, PINB3        ; 押されていたら眠らない
    rjmp TP_ABORT
    ldi  tmp, (1<<SE)|(1<<SM1)
    out  MCUCR, tmp
    sei
    sleep                   ; パワーダウン
    ldi  tmp, (1<<SE)       ; アイドルに戻す
    out  MCUCR, tmp
    ret
TP_ABORT:
    sei
TP_END:
    ret

; ---- 音 (10msごとに長さを数える) ----
TASK_SOUND:
    sbrs flg, F_10MS
    ret
    tst  snd
    breq TS_END
    dec  sdur
    brne TS_END
    cpi  snd, SND_MEL
    breq TS_MEL
    cpi  snd, SND_BEEP3
    breq TS_TRI
TS_STOP:                    ; ピッ終了 / 全体の終了
    clr  snd
    rjmp TONE_OFF
TS_TRI:                     ; ピッピッピッ: 音・休み・音・休み・音 (各60ms)
    ldi  tmp, 6
    mov  sdur, tmp
    dec  scnt
    breq TS_STOP
    sbrs scnt, 0
    rjmp TONE_OFF           ; 偶数 → 休み
    ldi  tmp, TONE_HI
    rjmp TONE_ON            ; 奇数 → 音
TS_MEL:
    lpm  tmp, Z+            ; 音 (OCR値)
    lpm  tmp2, Z+           ; 長さ (10ms単位)
    mov  sdur, tmp2
    tst  tmp
    breq TS_FIN             ; 0 = 曲の終わり
    cpi  tmp, REST
    brne TONE_ON
    rjmp TONE_OFF
TS_FIN:
    dec  scnt               ; 残り演奏回数
    breq TS_STOP
    ldi  ZL, low(CHARU*2)
    ldi  ZH, high(CHARU*2)
    ldi  tmp, 100           ; 曲間 1秒
    mov  sdur, tmp
    rjmp TONE_OFF
TS_END:
    ret

MELODY_START:               ; チャルメラ3回
    ldi  ZL, low(CHARU*2)
    ldi  ZH, high(CHARU*2)
    ldi  tmp, 3
    mov  scnt, tmp
    ldi  snd, SND_MEL
    ldi  tmp, 1             ; 次の10msで1音目
    mov  sdur, tmp
    ret

BEEP:                       ; ピッ 約1000Hz 80ms
    ldi  tmp, TONE_BEEP
    ldi  tmp2, 8
    ldi  snd, SND_BEEP
    rjmp SND_START
BEEP3:                      ; ピッピッピッ 約2000Hz
    ldi  tmp, 5
    mov  scnt, tmp
    ldi  tmp, TONE_HI
    ldi  tmp2, 6
    ldi  snd, SND_BEEP3
SND_START:
    mov  sdur, tmp2
TONE_ON:                    ; tmp = OCR値
    ldi  tmp2, PRR_SND      ; Timer1にクロックを入れてから設定する
    out  PRR, tmp2
    out  OCR1C, tmp
    out  OCR1A, tmp
    clr  tmp2
    out  TCNT1, tmp2
    ldi  tmp2, (1<<OCF1A)
    out  TIFR, tmp2
    ldi  tmp2, (1<<CTC1)|(1<<CS11)   ; CTC、1MHz/2
    out  TCCR1, tmp2
    ret

TONE_OFF:
    clr  tmp2
    out  TCCR1, tmp2
    ldi  tmp2, (1<<OCF1A)
    out  TIFR, tmp2
    cbi  PORTB, PORTB4
    ldi  tmp2, PRR_OFF      ; Timer1のクロックも止める
    out  PRR, tmp2
    ret

; ---- EEPROM (アドレス0、EEARはRESETで0に設定済み) ----
EE_READ:                    ; tmp ← 保存値 (0〜2以外なら0=3分)
    sbic EECR, EEPE
    rjmp EE_READ
    sbi  EECR, EERE
    in   tmp, EEDR
    cpi  tmp, 3
    brlo ER_END
    clr  tmp
ER_END:
    ret

EE_WRITE:                   ; tmp = 書く値 (同じ値なら書かない)
    sbic EECR, EEPE
    rjmp EE_WRITE
    sbi  EECR, EERE
    in   tmp2, EEDR
    cp   tmp2, tmp
    breq EW_END
    out  EEDR, tmp
    clr  tmp2
    out  EECR, tmp2         ; 消去+書き込みモード
    cli
    sbi  EECR, EEMPE
    sbi  EECR, EEPE
    sei
EW_END:
    ret

; ---- チャルメラ: (音, 長さ) の組。長さは10ms単位、1拍=25 (250ms) ----
; ソ=157(約1582Hz) ラ=140(約1773Hz) シ=124(約2000Hz)、255=休符、0,0=終わり
; そらしーらそ 休 そらしらそら〜〜〜
CHARU:
    .db 157,25, 140,25, 124,50, 140,25, 157,25, REST,100
    .db 157,25, 140,25, 124,25, 140,25, 157,25, 140,100
    .db 0,0
