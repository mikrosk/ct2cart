AS      = m68k-atari-mintelf-as
LD      = m68k-atari-mintelf-ld
ASFLAGS = -m68030
# fastload only, no TT-RAM: runs with the MMU off, needs identity mapped ST-RAM
LDFLAGS = -s --mprg-flags=1

ct2cart.prg: ct2cart.o
	$(LD) $(LDFLAGS) -o $@ $<

ct2cart.o: ct2cart.s
	$(AS) $(ASFLAGS) -o $@ $<

clean:
	rm -f ct2cart.o ct2cart.prg

.PHONY: clean
