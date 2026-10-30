#!/usr/bin/env python3
"""The disk drive test of the simulation: a cartridge for slot 2 (cartridge B) that drives the WD1793
of the VY-0010 in slot 1 through its registers (7FF8-7FFF) without the disk ROM, and the disk images
it reads.

Every sector of a test image starts with its track, side, sector and A5, then (i + track + sector)
& FF. The program (sjasmplus) runs from page 2 with page 1 on slot 1: motor on, restore, then for
each entry of TESTS seek, side, read the sector and compare its first three bytes; then it writes a
sector with a pattern and reads it back. It prints one character per step and a result line:
    FDC 12345678WR OK
A digit: that read was right; "x": wrong data, "e": the status had an error bit (shown in hex after
FAIL). W / R: the write and its read back.

usage: mkfdd.py OUTDIR    (fdctest.rom, test720.dsk, test360.dsk)
"""
import os
import subprocess
import sys

SJASM = os.environ.get('SJASMPLUS', '/opt/sjasmplus/sjasmplus')

# (track, side, sector) to read on the 720 KB image; on 360 KB side 1 is left out
TESTS = [(0, 0, 1), (0, 0, 9), (0, 1, 1), (1, 0, 1), (2, 0, 5), (40, 1, 3), (79, 0, 9), (79, 1, 9)]
WRITE = (3, 0, 4)


def image(sides):
    out = bytearray()
    for t in range(80):
        for s in range(sides):
            for n in range(1, 10):
                sec = bytearray((i + t + n) & 0xFF for i in range(512))
                sec[0:4] = bytes((t, s, n, 0xA5))
                out += sec
    return out


def asm(tests):
    entries = '\n'.join('\tdb\t%d, %d, %d' % t for t in tests)
    return f"""
CHPUT	equ	0x00A2
FDC_CMD	equ	0x7FF8
FDC_TRK	equ	0x7FF9
FDC_SEC	equ	0x7FFA
FDC_DAT	equ	0x7FFB
FDC_SIDE equ	0x7FFC
FDC_DRV	equ	0x7FFD
FDC_IRQ	equ	0x7FFF		; bit 7: /DRQ, bit 6: /INTRQ
BUF	equ	0xC000
	org	0x4000
	db	"AB"
	dw	init
	ds	12, 0
init:	di
	ld	sp, 0xF380
	; page 2 to the slot of page 1, then on in page 2
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
	jp	main

	ds	0x8000 - $, 0xFF
main:	ld	hl, title
	call	print
	; page 1 to slot 1: the VY-0010
	in	a, (0xA8)
	and	0xF3
	or	0x04
	out	(0xA8), a
	ld	a, 0x80		; motor on, drive 0
	ld	(FDC_DRV), a
	ld	a, 0x00		; restore
	call	command
	ld	ix, tests
	ld	b, {len(tests)}
	ld	c, 0		; errors
next:	push	bc
	ld	a, (ix+0)
	ld	(FDC_DAT), a
	ld	a, 0x10		; seek
	call	command
	ld	a, (ix+1)
	ld	(FDC_SIDE), a
	ld	a, (ix+2)
	ld	(FDC_SEC), a
	call	readsec
	pop	bc
	jr	nz, bad
	ld	a, (BUF)
	cp	(ix+0)
	jr	nz, wrong
	ld	a, (BUF+1)
	cp	(ix+1)
	jr	nz, wrong
	ld	a, (BUF+2)
	cp	(ix+2)
	jr	nz, wrong
	ld	a, {len(tests)} + '1'
	sub	b
	jr	show
wrong:	inc	c
	ld	a, 'x'
	jr	show
bad:	inc	c
	ld	(status), a
	ld	a, 'e'
show:	push	bc
	call	CHPUT
	pop	bc
	inc	ix
	inc	ix
	inc	ix
	djnz	next

	; write a sector with 5A ^ i, read it back
	push	bc
	ld	a, {WRITE[0]}
	ld	(FDC_DAT), a
	ld	a, 0x10
	call	command
	ld	a, {WRITE[1]}
	ld	(FDC_SIDE), a
	ld	a, {WRITE[2]}
	ld	(FDC_SEC), a
	ld	a, 0xA0		; write sector
	ld	(FDC_CMD), a
	ld	e, 0
	ld	d, 2		; 512 bytes
wloop:	ld	a, (FDC_IRQ)
	bit	6, a
	jr	z, wdone
	bit	7, a
	jr	nz, wloop
	ld	a, e
	xor	0x5A
	ld	(FDC_DAT), a
	inc	e
	jr	nz, wloop
	dec	d
	jr	nz, wloop
wwait:	ld	a, (FDC_IRQ)
	bit	6, a
	jr	nz, wwait
wdone:	ld	a, (FDC_CMD)
	and	0x7C
	pop	bc
	jr	nz, wbad
	ld	a, 'W'
	push	bc
	call	CHPUT
	pop	bc
	push	bc
	call	readsec
	pop	bc
	jr	nz, wbad
	ld	hl, BUF
	ld	e, 0
	ld	d, 2
cmp:	ld	a, e
	xor	0x5A
	cp	(hl)
	jr	nz, rbad
	inc	hl
	inc	e
	jr	nz, cmp
	dec	d
	jr	nz, cmp
	ld	a, 'R'
	jr	wshow
wbad:	ld	(status), a
	ld	a, 'e'
	inc	c
	jr	wshow
rbad:	ld	a, 'x'
	inc	c
wshow:	push	bc
	call	CHPUT
	pop	bc
	ld	a, c
	or	a
	ld	hl, good
	jr	z, result
	ld	hl, fail
	call	print
	ld	a, (status)
	call	hex2
	jr	stop
result:	call	print
stop:	jr	stop

; a type I command (restore / seek), wait for INTRQ
command: ld	(FDC_CMD), a
cwait:	ld	a, (FDC_IRQ)
	bit	6, a
	jr	nz, cwait
	ld	a, (FDC_CMD)	; clear INTRQ
	ret

; read the sector of the registers into BUF; Z when the status has no error (A: the status)
readsec: ld	a, 0x80
	ld	(FDC_CMD), a
	ld	hl, BUF
rloop:	ld	a, (FDC_IRQ)
	bit	6, a
	jr	z, rdone
	bit	7, a
	jr	nz, rloop
	ld	a, (FDC_DAT)
	ld	(hl), a
	inc	hl
	jr	rloop
rdone:	ld	a, (FDC_CMD)
	and	0x1C		; not found, CRC, lost data
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

title:	db	"FDC ", 0
good:	db	" OK", 0
fail:	db	" FAIL ", 0
tests:
{entries}
status:	equ	0xF000
"""


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, sides in (('test720.dsk', 2), ('test360.dsk', 1)):
        open(os.path.join(out, name), 'wb').write(image(sides))
    for name, tests in (('fdctest.rom', TESTS), ('fdctest360.rom', [t for t in TESTS if t[1] == 0])):
        src = os.path.join(out, name + '.asm')
        raw = os.path.join(out, name + '.bin')
        open(src, 'w').write(asm(tests))
        subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True, stdout=subprocess.DEVNULL)
        code = open(raw, 'rb').read()
        assert len(code) <= 0x8000
        open(os.path.join(out, name), 'wb').write(code + b'\xFF' * (0x8000 - len(code)))


if __name__ == '__main__':
    main()
