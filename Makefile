# ソースファイル名は書かなくてよい: ディレクトリ内の .asm を自動検出する
# (.asm が複数ある場合は `make TARGET=xxx` で指定)
SRCS   := $(wildcard *.asm)
TARGET ?= $(basename $(firstword $(filter main.asm,$(SRCS)) $(SRCS)))
INCS   := $(wildcard *.inc)
EDITOR ?= vi

PROG    = stk500v1
PORT    = /dev/ttyUSB0
BAUD    = 19200

ifeq ($(TARGET),)
$(error .asm ファイルが見つかりません)
endif
ifneq ($(words $(SRCS)),1)
ifeq ($(origin TARGET),file)
$(warning .asm が複数あります ($(SRCS))。$(TARGET).asm を使います。別のものは make TARGET=xxx)
endif
endif

.PHONY: all edit write clean

all: $(TARGET).hex

# 自作の .inc を変更したときも再ビルドされるよう依存に入れる
$(TARGET).hex: $(TARGET).asm $(INCS)
	avra -l $(TARGET).lst -m $(TARGET).map -o $@ $<

edit:
	$(EDITOR) $(TARGET).asm

write: $(TARGET).hex
	avrdude -c $(PROG) -p t85 -P $(PORT) -b $(BAUD) -U flash:w:$(TARGET).hex:i

clean:
	rm -f $(TARGET).hex $(TARGET).eep.hex $(TARGET).obj $(TARGET).lst $(TARGET).map
