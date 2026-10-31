#!/usr/bin/env python3
"""The Nextor SD interface test of the simulation: a cartridge for slot 2 (cartridge B) that talks to
the SD card of nextor_sd.v in slot 1 as the Nextor driver of MSX1FPGA does (bank 7 at 6000, the SPI
data port 7B00, the card select 7FF0), without the Nextor ROM, and the hard disk image it uses.

Sector n of the image starts with n (4 bytes, little endian) and 5A, then (i + n) & FF. The program
(sjasmplus) runs from page 2 with page 1 on slot 1 and prints one character per step:
    SD P08AOC13WRM OK
P the card is present (status), 0 CMD0 (idle), 8 CMD8 (R7 echo), A ACMD41 (ready), O CMD58 (CCS),
C CMD9 (C_SIZE of the 1 MB image: 1), 1 CMD17 of sector 5, 3 CMD18 of sectors 10-12 and CMD12,
W CMD24 of sector 7 (pattern i ^ 3C), R its read back, M CMD25 of sectors 20-21 (pattern i ^ n)
and a read back of 21. A step that fails prints "x" and the program stops with FAIL. The image saved
after the run (sim_sys --save-hdd) has the written sectors (checked by run_hdd.sh).

usage: mkhdd.py OUTDIR    (sdtest.rom, test.img)
"""
import os
import subprocess
import sys

SJASM = os.environ.get('SJASMPLUS', '/opt/sjasmplus/sjasmplus')
SECTORS = 2048   # 1 MB


def sector(n):
    sec = bytearray((i + n) & 0xFF for i in range(512))
    sec[0:5] = bytes((n & 0xFF, (n >> 8) & 0xFF, 0, 0, 0x5A))
    return sec


def image():
    out = bytearray()
    for n in range(SECTORS):
        out += sector(n)
    return out


ASM = """
CHPUT	equ	0x00A2
BANK	equ	0x6000
SPI	equ	0x7B00
CTL	equ	0x7FF0
BUF	equ	0xC000
	org	0x4000
	db	"AB"
	dw	init
	ds	12, 0
init:	di
	ld	sp, 0xF380
	; page 2 to the slot of page 1 (slot 2), then on in page 2
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
	; page 1 to slot 1: the SD interface
	in	a, (0xA8)
	and	0xF3
	or	0x04
	out	(0xA8), a
	ld	a, 7
	ld	(BANK), a
	; deselected, 10 dummy bytes
	ld	a, 0xFF
	ld	(CTL), a
	ld	b, 10
dummy:	ld	a, (SPI)
	djnz	dummy
	; P: the card is there
	ld	a, (CTL)
	and	2
	jp	nz, fail
	ld	a, 'P'
	call	CHPUT
	ld	a, 0xFE
	ld	(CTL), a
	; 0: CMD0, R1 = 01
	ld	hl, cmd0
	call	command
	cp	1
	jp	nz, fail
	ld	a, '0'
	call	CHPUT
	; 8: CMD8, R1 01, R7 00 00 01 AA
	ld	hl, cmd8
	call	command
	cp	1
	jp	nz, fail
	call	spi
	call	spi
	call	spi
	cp	1
	jp	nz, fail
	call	spi
	cp	0xAA
	jp	nz, fail
	ld	a, '8'
	call	CHPUT
	; A: CMD55 + ACMD41 until R1 = 00
	ld	b, 20
acmd:	push	bc
	ld	hl, cmd55
	call	command
	ld	hl, acmd41
	call	command
	pop	bc
	or	a
	jr	z, acmd_ok
	djnz	acmd
	jp	fail
acmd_ok: ld	a, 'A'
	call	CHPUT
	; O: CMD58, OCR bit 30 (CCS)
	ld	hl, cmd58
	call	command
	or	a
	jp	nz, fail
	call	spi
	and	0x40
	jp	z, fail
	call	spi
	call	spi
	call	spi
	ld	a, 'O'
	call	CHPUT
	; C: CMD9, the CSD, C_SIZE = 1
	ld	hl, cmd9
	call	command
	or	a
	jp	nz, fail
	call	token
	jp	nz, fail
	ld	hl, BUF
	ld	b, 18
csd:	call	spi
	ld	(hl), a
	inc	hl
	djnz	csd
	ld	a, (BUF)
	cp	0x40
	jp	nz, fail
	ld	a, (BUF+7)
	ld	b, a
	ld	a, (BUF+8)
	or	b
	jp	nz, fail
	ld	a, (BUF+9)
	cp	1
	jp	nz, fail
	ld	a, 'C'
	call	CHPUT
	; 1: CMD17 of sector 5
	ld	hl, cmd17_5
	call	command
	or	a
	jp	nz, fail
	call	block
	jp	nz, fail
	ld	e, 5
	call	check
	jp	nz, fail
	ld	a, '1'
	call	CHPUT
	; 3: CMD18 of 10, 11, 12, then CMD12
	ld	hl, cmd18_10
	call	command
	or	a
	jp	nz, fail
	ld	e, 10
multi:	push	de
	call	block
	pop	de
	jp	nz, fail
	call	check
	jp	nz, fail
	inc	e
	ld	a, e
	cp	13
	jr	nz, multi
	ld	hl, cmd12
	call	command
	or	a
	jp	nz, fail
	ld	a, '3'
	call	CHPUT
	; W: CMD24 of sector 7, the pattern i ^ 3C
	ld	hl, cmd24_7
	call	command
	or	a
	jp	nz, fail
	ld	a, 0xFE
	ld	c, 0x3C
	call	wblock
	jp	nz, fail
	ld	a, 'W'
	call	CHPUT
	; R: read 7 back
	ld	hl, cmd17_7
	call	command
	or	a
	jp	nz, fail
	call	block
	jp	nz, fail
	ld	c, 0x3C
	call	wcheck
	jp	nz, fail
	ld	a, 'R'
	call	CHPUT
	; M: CMD25 of 20 and 21 (i ^ 20, i ^ 21), FD, then read 21 back
	ld	hl, cmd25_20
	call	command
	or	a
	jp	nz, fail
	ld	a, 0xFC
	ld	c, 20
	call	wblock
	jp	nz, fail
	ld	a, 0xFC
	ld	c, 21
	call	wblock
	jp	nz, fail
	ld	a, 0xFD
	ld	(SPI), a
	call	spi
	call	notbusy
	jp	nz, fail
	ld	hl, cmd17_21
	call	command
	or	a
	jp	nz, fail
	call	block
	jp	nz, fail
	ld	c, 21
	call	wcheck
	jp	nz, fail
	ld	a, 'M'
	call	CHPUT
	ld	a, 0xFF
	ld	(CTL), a
	ld	hl, good
	call	print
stop:	jr	stop

fail:	ld	a, 0xFF
	ld	(CTL), a
	ld	a, 'x'
	call	CHPUT
	ld	hl, bad
	call	print
	jr	stop

; a byte exchange: A = the byte of the exchange before (a read of the port sends FF)
spi:	ld	a, (SPI)
	ret

; the 6 bytes of a command at HL, then R1 in A (the first byte that is not FF, 16 tries)
command: ld	b, 6
cmdb:	ld	a, (hl)
	ld	(SPI), a
	inc	hl
	djnz	cmdb
	ld	b, 16
r1:	call	spi
	cp	0xFF
	ret	nz
	djnz	r1
	ret

; wait for the data token FE: Z when it came (up to 65536 x 8 bytes)
token:	ld	d, 8
tok2:	ld	bc, 0
tok:	call	spi
	cp	0xFF
	jr	nz, tok_end
	dec	c
	jr	nz, tok
	djnz	tok
	dec	d
	jr	nz, tok2
	or	a		; A = FF: NZ
	ret
tok_end: cp	0xFE
	ret

; wait while the card answers 00 (busy): Z when it ended
notbusy: ld	d, 8
nb2:	ld	bc, 0
nb:	call	spi
	or	a
	jr	nz, nb_end
	dec	c
	jr	nz, nb
	djnz	nb
	dec	d
	jr	nz, nb2
	inc	a		; NZ
	ret
nb_end:	xor	a
	ret

; a data block into BUF: the token, 512 bytes, the CRC; Z when it came
block:	call	token
	ret	nz
	ld	hl, SPI
	ld	de, BUF
	ld	bc, 512
	ldir
	call	spi
	call	spi
	xor	a
	ret

; BUF is sector E of the image (its first bytes and byte 100): Z when it is
check:	ld	a, (BUF)
	cp	e
	ret	nz
	ld	a, (BUF+4)
	cp	0x5A
	ret	nz
	ld	a, e
	add	a, 100
	ld	b, a
	ld	a, (BUF+100)
	cp	b
	ret

; write a block: token A, 512 bytes i ^ C, the CRC, then the data response (05) and the busy
wblock:	ld	(SPI), a
	ld	de, 0
wb:	ld	a, e
	xor	c
	ld	(SPI), a
	inc	de
	ld	a, d
	cp	2
	jr	nz, wb
	ld	a, 0xFF
	ld	(SPI), a
	ld	(SPI), a
	ld	b, 16
wr1:	call	spi
	cp	0xFF
	jr	nz, wr_resp
	djnz	wr1
	ret
wr_resp: and	0x1F
	cp	5
	ret	nz
	jp	notbusy

; BUF is the pattern i ^ C (bytes 0, 1, 255, 256, 511): Z when it is
wcheck:	ld	a, (BUF)
	cp	c
	ret	nz
	ld	a, (BUF+1)
	xor	1
	cp	c
	ret	nz
	ld	a, (BUF+255)
	xor	255
	cp	c
	ret	nz
	ld	a, (BUF+256)
	cp	c
	ret	nz
	ld	a, (BUF+511)
	xor	255
	cp	c
	ret

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

cmd0:	db	0x40, 0, 0, 0, 0, 0x95
cmd8:	db	0x48, 0, 0, 0x01, 0xAA, 0x87
cmd55:	db	0x77, 0, 0, 0, 0, 0xFF
acmd41:	db	0x69, 0x40, 0, 0, 0, 0xFF
cmd58:	db	0x7A, 0, 0, 0, 0, 0xFF
cmd9:	db	0x49, 0, 0, 0, 0, 0xFF
cmd12:	db	0x4C, 0, 0, 0, 0, 0xFF
cmd17_5: db	0x51, 0, 0, 0, 5, 0xFF
cmd17_7: db	0x51, 0, 0, 0, 7, 0xFF
cmd17_21: db	0x51, 0, 0, 0, 21, 0xFF
cmd18_10: db	0x52, 0, 0, 0, 10, 0xFF
cmd24_7: db	0x58, 0, 0, 0, 7, 0xFF
cmd25_20: db	0x59, 0, 0, 0, 20, 0xFF
title:	db	"SD ", 0
good:	db	" OK", 0
bad:	db	" FAIL", 0
"""


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, 'test.img'), 'wb').write(image())
    src = os.path.join(out, 'sdtest.asm')
    raw = os.path.join(out, 'sdtest.bin')
    open(src, 'w').write(ASM)
    subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True, stdout=subprocess.DEVNULL)
    code = open(raw, 'rb').read()
    assert len(code) <= 0x8000
    open(os.path.join(out, 'sdtest.rom'), 'wb').write(code + b'\xFF' * (0x8000 - len(code)))


if __name__ == '__main__':
    main()
