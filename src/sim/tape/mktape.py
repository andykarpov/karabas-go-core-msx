#!/usr/bin/env python3
"""The cassette test: a cartridge (tapetest.rom, for slot 2 = cartridge B) that reads the tape of a
.cas file (test.cas) through the cassette input (bit 7 of port A of the PSG) with its own decoder, and
the .cas file. C-BIOS has no tape routines (no BASIC), so the cartridge does what TAPION / TAPIN of
a real BIOS do, in short:
- motor on (PPI port C bit 4 = 0), interrupts off;
- a cycle of the signal is timed from a rising edge to the next: short (2400 Hz, half a "1" bit) or
  long (1200 Hz, a "0" bit), at 2400 baud the player of the core (rtl/msx/tape.v) gives
  748 / 1496 T-states;
- a block starts after 256 short cycles in a row (the header), then a byte is a start bit (long),
  8 bits LSB first, the stop bits (short) are skipped while waiting for the next start bit.
The test.cas has two blocks of BLOCKS bytes; byte i of the whole stream is (3 + 7 i) & FF. The
screen shows one character per block ('1', '2' or 'x') and the result:
    TAPE 12 OK
The 8 KB of FILL after the blocks are not played: they make the load longer than one burst (the
fifo and the pause of the disk fill in msx_tape), sim_sys checks them in the SRAM (--cas).

bad.cas is test.cas with one byte of block 2 changed: "TAPE 1x FAIL ...".

usage: mktape.py OUTDIR    (tapetest.rom, test.cas, bad.cas)
"""
import os
import subprocess
import sys

SJASM = os.environ.get('SJASMPLUS', '/opt/sjasmplus/sjasmplus')
SIG = bytes.fromhex('1FA6DEBACC137D74')
BLOCKS = (16, 64)
FILL = 8192
TH = 32       # cycle counts of the decoder loop (35 T-states): short about 21, long 43


def stream():
    n = sum(BLOCKS)
    return bytes((3 + 7 * i) & 0xFF for i in range(n))


def cas():
    data = stream()
    out = bytearray()
    p = 0
    for n in BLOCKS:
        while len(out) % 8:
            out.append(0)
        out += SIG + data[p:p + n]
        p += n
    while len(out) % 8:
        out.append(0)
    out += bytes((i * 13 + 5) & 0xFF for i in range(FILL))
    return bytes(out)


def asm():
    n1, n2 = BLOCKS
    return f"""
CHPUT	equ	0x00A2
BUF	equ	0xC000
left	equ	0xF000
	org	0x4000
	db	"AB"
	dw	init
	ds	12, 0
init:	di
	ld	sp, 0xF380
	ld	hl, title
	call	print
	di
	in	a, (0xAA)
	and	0xEF		; motor on
	out	(0xAA), a
	ld	a, 14		; PSG port A: bit 7 the cassette input
	out	(0xA0), a
	ld	hl, BUF
	ld	de, {n1}
	call	block
	ld	hl, BUF + {n1}
	ld	de, {n2}
	call	block
	in	a, (0xAA)
	or	0x10		; motor off
	out	(0xAA), a

	; check the blocks: byte i = 3 + 7 i
	ld	hl, BUF
	ld	d, 3
	ld	bc, {n1}
	call	check
	ld	a, '1'
	jr	z, show1
	ld	a, 'x'
show1:	ld	(r1), a
	ld	bc, {n2}
	call	check
	ld	a, '2'
	jr	z, show2
	ld	a, 'x'
show2:	ld	(r2), a
	ld	a, (r1)
	call	CHPUT
	ld	a, (r2)
	call	CHPUT
	ld	a, (r1)
	cp	'1'
	jr	nz, bad
	ld	a, (r2)
	cp	'2'
	jr	nz, bad
	ld	hl, good
	call	print
	jr	stop
bad:	ld	hl, fail
	call	print
	ld	a, (BUF)
	call	hex2
	ld	a, (BUF + 1)
	call	hex2
	ld	a, (BUF + {n1})
	call	hex2
stop:	jr	stop

; compare BC bytes at HL with D, D + 7, ...: Z when all match (HL, D go on)
check:	ld	e, 0		; errors
chk:	ld	a, (hl)
	cp	d
	jr	z, chk1
	inc	e
chk1:	inc	hl
	ld	a, d
	add	a, 7
	ld	d, a
	dec	bc
	ld	a, b
	or	c
	jr	nz, chk
	ld	a, e
	or	a
	ret

; read a block of DE bytes to HL: the header first, then the bytes
block:	ld	(left), de
hdr0:	ld	b, 0		; 256 short cycles in a row
hdr:	call	cycle
	ld	a, c
	cp	{TH}
	jr	nc, hdr0
	djnz	hdr
byte:	call	cycle		; the start bit: a long cycle
	ld	a, c
	cp	{TH}
	jr	c, byte
	ld	b, 8
bit:	call	cycle
	ld	a, c
	cp	{TH}		; NC: long, a 0 (carry clear)
	jr	nc, shift
	call	cycle		; the second short cycle of a 1
	scf
shift:	rr	d
	djnz	bit
	ld	(hl), d
	inc	hl
	ld	de, (left)
	dec	de
	ld	(left), de
	ld	a, d
	or	e
	jr	nz, byte
	ret

; C = the loop count from now (a rising edge) to the next rising edge
cycle:	ld	c, 0
cw0:	inc	c
	in	a, (0xA2)
	rla
	jr	c, cw0
cw1:	inc	c
	in	a, (0xA2)
	rla
	jr	nc, cw1
	ret

hex2:	push	af
	rrca
	rrca
	rrca
	rrca
	call	hex1
	pop	af
hex1:	and	0x0F
	add	a, '0'
	cp	'9' + 1
	jr	c, h1
	add	a, 7
h1:	jp	CHPUT

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

title:	db	"TAPE ", 0
good:	db	" OK", 0
fail:	db	" FAIL ", 0
r1	equ	0xF002
r2	equ	0xF003
"""


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    c = cas()
    open(os.path.join(out, 'test.cas'), 'wb').write(c)
    bad = bytearray(c)
    p = c.index(SIG, 8) + 8 + 10
    bad[p] ^= 0x40
    open(os.path.join(out, 'bad.cas'), 'wb').write(bad)
    src = os.path.join(out, 'tapetest.rom.asm')
    raw = os.path.join(out, 'tapetest.rom.bin')
    open(src, 'w').write(asm())
    subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True, stdout=subprocess.DEVNULL)
    code = open(raw, 'rb').read()
    assert len(code) <= 0x4000
    open(os.path.join(out, 'tapetest.rom'), 'wb').write(code + b'\xFF' * (0x4000 - len(code)))


if __name__ == '__main__':
    main()
