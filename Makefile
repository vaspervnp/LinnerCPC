# Linner - Amstrad CPC build
#
#   make            build/linner.dsk (RUN"DISC) and build/linner.sna
#   make run        play the snapshot in Caprice32 (EMU=cpcemu for CPCEMU)
#   make run-dsk    boot the disk image instead
#   make debug      play the DEBUG build: border colours show the frame time
#   make shot       headless Caprice32 run of the scripted demo -> build/shot.png
#   make sim        same demo in tools/cpcsim.py, with frame timings
#   make clean

RASM   := rasm -amper -v2
B      := build
SRC    := $(wildcard src/*.asm)
GEN    := $(B)/tables.asm $(B)/level1.asm
EMU    ?= caprice32
DEFS   ?=
TEST_FRAMES ?= 300

all: $(B)/linner.dsk

$(B):
	mkdir -p $(B)

$(B)/tables.asm: tools/gen_tables.py | $(B)
	python3 tools/gen_tables.py $@

$(B)/level1.asm: levels/level1.txt tools/level2asm.py | $(B)
	python3 tools/level2asm.py $< level1 $@

# rasm writes linner.bin (SAVE directive), the snapshot and the symbols
$(B)/linner.sna: $(SRC) $(GEN)
	cd $(B) && $(RASM) -I../src -I. $(DEFS) ../src/main.asm -oi linner.sna -os linner.sym -s -sl \
	  2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi
	@grep -E "Write binary" $(B)/rasm.log || true

$(B)/loader.bin: src/loader.asm | $(B)
	rasm -amper src/loader.asm -ob $@ 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -iE "error|warning" && exit 1 || true

$(B)/linner.dsk: $(B)/linner.sna $(B)/loader.bin src/disc.bas
	rm -f $@
	sed "s/\r*$$/\r/" src/disc.bas > $(B)/DISC.BAS   # CPC BASIC wants CR LF
	cp $(B)/loader.bin $(B)/LOADER.BIN
	cp $(B)/linner.bin $(B)/LINNER.BIN
	cd $(B) && iDSK linner.dsk -n >/dev/null \
	  && iDSK linner.dsk -i DISC.BAS -t 0 >/dev/null \
	  && iDSK linner.dsk -i LOADER.BIN -t 1 -e 9000 -c 9000 >/dev/null \
	  && iDSK linner.dsk -i LINNER.BIN -t 1 -e 0040 -c 0040 >/dev/null
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
	cd $(B)/test && $(RASM) -I../../src -I.. -DTEST_FRAMES=$(TEST_FRAMES) -DDEBUG=1 ../../src/main.asm \
	  -oi linner.sna -os linner.sym -s -sl 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > rasm.log; \
	  if grep -qiE "error|warning" rasm.log; then cat rasm.log; rm -f linner.sna; exit 1; fi

shot: $(B)/test/linner.sna
	tools/cpcemu -timeout 90 -shot $(B)/shot.png $(B)/test/linner.sna

sim: $(B)/test/linner.sna
	python3 tools/cpcsim.py $(B)/test/linner.sna --sym $(B)/test/linner.sym --slow 1.25 \
	  --frames $$(( $(TEST_FRAMES) + 10 )) --timing --screen $(B)/sim.png --peek frame_drops:1 gear:1 hero_cy:1

clean:
	rm -rf $(B)

.PHONY: all run run-dsk debug shot sim clean
