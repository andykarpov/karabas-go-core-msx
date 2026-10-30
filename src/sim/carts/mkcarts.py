#!/usr/bin/env python3
"""Test cartridges for the mappers of the MSX1 core (rtl/msx/cart): 128 KB ROMs, assembled with
sjasmplus. Each bank of the mapper (8 KB, ASCII 16: 16 KB) has its number at offset BANK-16 (the
last 16 bytes of the bank). The program (in bank 0, at 4000) maps page 2 to its slot (port A8), writes the bank registers the way
games of that mapper do (so the mapper detection of rom_detect.v sees it), then maps every bank
into the window at 8000, reads its number there and prints it with CHPUT of the BIOS:
    KONAMI 0123456789ABCDEF OK
A wrong mapper gives other digits; "OK" only when all of them match.

usage: mkcarts.py OUTDIR      (writes konami.rom, konami_scc.rom, ascii8.rom, ascii16.rom)
"""
import os
import subprocess
import sys

SJASM = os.environ.get('SJASMPLUS', '/opt/sjasmplus/sjasmplus')

# name, bank size, the init writes (address, value) the games do, the register of the window 8000
MAPPERS = [
    ('KONAMI', 0x2000, [(0x6000, 1), (0x8000, 2), (0xA000, 3)], 0x8000),
    ('KONAMI_SCC', 0x2000, [(0x5000, 0), (0x7000, 1), (0x9000, 2), (0xB000, 3)], 0x9000),
    ('ASCII8', 0x2000, [(0x6000, 0), (0x6800, 1), (0x7000, 2), (0x7800, 3)], 0x7000),
    ('ASCII16', 0x4000, [(0x6000, 0), (0x7000, 1)], 0x7000),
]
SIZE = 0x20000


def asm(name, bank, init, reg):
    n = SIZE // bank
    marker = 0x8000 + bank - 16
    inits = '\n'.join('\tld a,%d\n\tld (0x%04X),a' % (v, a) for a, v in init)
    return f"""
CHPUT	equ	0x00A2
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
start:
	di
	ld	sp, 0xF380
	; page 2 to the slot of page 1 (the BIOS starts a cartridge with page 1 only), as games do
	in	a, (0xA8)
	ld	b, a
	and	0x0C
	add	a, a
	add	a, a
	ld	c, a
	ld	a, b
	and	0xCF
	or	c
	out	(0xA8), a
{inits}
	ld	hl, title
	call	print
	ld	c, 0		; errors
	ld	b, 0
loop:
	ld	a, b
	ld	(0x{reg:04X}), a
	ld	a, (0x{marker:04X})
	cp	b
	jr	z, same
	inc	c
same:
	call	hex
	inc	b
	ld	a, b
	cp	{n}
	jr	nz, loop
	ld	hl, bad
	ld	a, c
	or	a
	jr	nz, result
	ld	hl, good
result:
	call	print
stop:	jr	stop

hex:	push	bc
	and	0x0F
	add	a, '0'
	cp	'9' + 1
	jr	c, digit
	add	a, 7
digit:	call	CHPUT
	pop	bc
	ret

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

title:	db	"{name} ", 0
good:	db	" OK", 0
bad:	db	" FAIL", 0
"""


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, bank, init, reg in MAPPERS:
        src = os.path.join(out, name.lower() + '.asm')
        raw = os.path.join(out, name.lower() + '.bin')
        open(src, 'w').write(asm(name, bank, init, reg))
        subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True)
        code = open(raw, 'rb').read()
        rom = bytearray(b'\xFF' * SIZE)
        rom[:len(code)] = code
        for k in range(SIZE // bank):
            rom[k * bank + bank - 16] = k
        assert len(code) < bank - 16
        open(os.path.join(out, name.lower() + '.rom'), 'wb').write(rom)
        print(name.lower() + '.rom', len(code), 'bytes of code')


if __name__ == '__main__':
    main()
