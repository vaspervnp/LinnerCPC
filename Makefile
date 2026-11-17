# Linner - Amstrad CPC build
#
#   make            build/linner.dsk (RUN"DISC) and build/linner.sna
#   make run        play the snapshot in Caprice32 (EMU=cpcemu for CPCEMU)
#   make run-dsk    boot the disk image instead
#   make debug      play the DEBUG build: border colours show the frame time
#   make shot       headless Caprice32 run of the scripted demo -> build/shot.png
#   make sim        same demo in tools/cpcsim.py, with frame timings
#   make hitest     high score save/load round trip on a disk in Caprice32
#   make video      build/linner_video.mp4: 4 minutes of the demo, with sound
#   make release    build/release/linner-$(VERSION).zip
#   make screens    docs/screenshots/*.png (README and manuals)
#   make manuals    docs/manual_en.pdf + docs/manual_el.pdf
#   make clean

RASM   := rasm -amper -v2
B      := build
SRC    := $(wildcard src/*.asm)
LEVELS := $(sort $(wildcard levels/level*.txt))
GEN    := $(B)/tables.asm $(B)/levels.asm $(B)/music.asm
EMU    ?= caprice32
DEFS   ?=
TEST_FRAMES ?= 300

all: $(B)/linner.dsk

$(B):
	mkdir -p $(B)

$(B)/tables.asm: tools/gen_tables.py | $(B)
	python3 tools/gen_tables.py $@

$(B)/music.asm: tools/gen_music.py | $(B)
	python3 tools/gen_music.py $@

$(B)/levels.asm: $(LEVELS) tools/level2asm.py | $(B)
	python3 tools/level2asm.py $@ $(LEVELS)

# rasm writes linner.bin (SAVE directive), the snapshot and the symbols
$(B)/linner.sna: $(SRC) $(GEN)
	cd $(B) && $(RASM) -I../src -I. $(DEFS) ../src/main.asm -oi linner.sna -os linner.sym -s -sl \
	  2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi
	@grep -E "Write binary" $(B)/rasm.log || true

$(B)/loader.bin: src/loader.asm | $(B)
	rasm -amper src/loader.asm -ob $@ 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -iE "error|warning" && exit 1 || true

# $(call make_dsk,dir): a boot disk from dir/linner.bin
define make_dsk
	rm -f $(1)/linner.dsk
	sed "s/\r*$$/\r/" src/disc.bas > $(1)/DISC.BAS   # CPC BASIC wants CR LF
	cp $(B)/loader.bin $(1)/LOADER.BIN
	cp $(1)/linner.bin $(1)/LINNER.BIN
	head -c 512 /dev/zero > $(1)/HISCORE.DAT   # zeros: the built-in table
	cd $(1) && iDSK linner.dsk -n >/dev/null \
	  && iDSK linner.dsk -i DISC.BAS -t 0 >/dev/null \
	  && iDSK linner.dsk -i LOADER.BIN -t 1 -e 9000 -c 9000 >/dev/null \
	  && iDSK linner.dsk -i LINNER.BIN -t 1 -e 0040 -c 0040 >/dev/null \
	  && iDSK linner.dsk -i HISCORE.DAT -t 0 >/dev/null
	python3 tools/dsk2edsk.py $(1)/linner.dsk   # Extended DSK: emulators write it back whole
	python3 tools/hiscore.py --where $(1)/linner.dsk | head -1
endef

$(B)/linner.dsk: $(B)/linner.sna $(B)/loader.bin src/disc.bas tools/hiscore.py tools/dsk2edsk.py
	$(call make_dsk,$(B))
	@echo "build: $(B)/linner.dsk + $(B)/linner.sna"

run: all
	tools/play $(EMU) $(B)/linner.sna

run-dsk: all
	tools/play $(EMU) $(B)/linner.dsk

$(B)/debug/linner.sna: $(SRC) $(GEN)
	mkdir -p $(B)/debug
	cd $(B)/debug && $(RASM) -I../../src -I.. -DDEBUG=1 ../../src/main.asm \
	  -oi linner.sna -os linner.sym -s -sl 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi

debug: $(B)/debug/linner.sna
	tools/play $(EMU) $(B)/debug/linner.sna

# scripted demo build (stops itself at &0000 after TEST_FRAMES frames)
$(B)/test/linner.sna: $(SRC) $(GEN)
	mkdir -p $(B)/test
	cd $(B)/test && $(RASM) -I../../src -I.. -DTEST_FRAMES=$(TEST_FRAMES) -DDEBUG=1 $(TESTDEFS) ../../src/main.asm \
	  -oi linner.sna -os linner.sym -s -sl 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi

shot: $(B)/test/linner.sna
	tools/cpcemu -timeout 90 -shot $(B)/shot.png $(B)/test/linner.sna

sim: $(B)/test/linner.sna
	python3 tools/cpcsim.py $(B)/test/linner.sna --sym $(B)/test/linner.sym --slow 1.25 \
	  --frames $$(( $(TEST_FRAMES) + 60 )) --timing --screen $(B)/sim.png --peek frame_drops:1 gear:1 hero_cy:1

# High score round trip on the disk: one life, sink, enter "CPC64" (pad and
# typed keys), save HISCORE.DAT with the FDC, read it back; the title then
# shows what the disk holds -> build/hitest.png.
HITEST_FRAMES ?= 2000
$(B)/hitest/linner.dsk: $(SRC) $(GEN) $(B)/loader.bin src/disc.bas tools/hiscore.py
	mkdir -p $(B)/hitest
	cd $(B)/hitest && $(RASM) -I../../src -I.. -DTEST_FRAMES=$(HITEST_FRAMES) -DDEBUG=1 \
	  -DTEST_HISCORE=1 -DTEST_SOAK=2 ../../src/main.asm \
	  -oi linner.sna -os linner.sym -s -sl 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi
	$(call make_dsk,$(B)/hitest)

hitest: $(B)/hitest/linner.dsk
	tools/cpcemu -timeout 120 -shot $(B)/hitest.png $(B)/hitest/linner.sna $(B)/hitest/linner.dsk

# The video (tools/video.py): the demo autopilot (TEST_VIDEO: second jumps,
# no gear 5) from the title through levels 1-3, the Bureau's game over, the
# name entry and back; cpcsim frames and the AY's sound, synthesised.
VIDEO_FRAMES ?= 12300
$(B)/video/linner.sna: $(SRC) $(GEN)
	mkdir -p $(B)/video
	cd $(B)/video && $(RASM) -I../../src -I.. -DTEST_FRAMES=30000 -DTEST_TITLE_WAIT=500 -DTEST_VIDEO=1 \
	  -DDIFF_DEFAULT=1 ../../src/main.asm -oi linner.sna -os linner.sym -s -sl 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi

video: $(B)/video/linner.sna
	python3 tools/video.py $(B)/video/linner.sna --sym $(B)/video/linner.sym \
	  --frames $(VIDEO_FRAMES) --out $(B)/linner_video.mp4

# The release: the disc, the snapshot, the README, the disc label and the manuals.
VERSION ?= 1.0
release: all manuals
	rm -rf $(B)/release && mkdir -p $(B)/release/linner
	cp $(B)/linner.dsk $(B)/linner.sna release/README.txt release/label.svg \
	   docs/manual_en.pdf docs/manual_el.pdf $(B)/release/linner/
	cd $(B)/release && zip -qr linner-$(VERSION).zip linner
	@echo "release: $(B)/release/linner-$(VERSION).zip"

# Screenshots for the README and the manuals (scripted demos in cpcsim, the
# loading screen from a disc boot in Caprice32).
screens: all
	tools/screens.sh docs/screenshots

# The manuals as PDF (tools/manual2pdf.py: Markdown -> HTML -> headless Chrome).
docs/manual_%.pdf: docs/manual_%.md tools/manual2pdf.py $(wildcard docs/screenshots/*.png)
	python3 tools/manual2pdf.py $< $@

manuals: docs/manual_en.pdf docs/manual_el.pdf

clean:
	rm -rf $(B)

.PHONY: all run run-dsk debug shot sim hitest video release screens manuals clean
