#!/usr/bin/env python3
"""Converts an Altera .mif (HEX radix, as srec_cat --mif writes it) into a $readmemh file:
one word per line, every address from 0 to DEPTH-1 (missing ones are 0).

usage: mif2hex.py in.mif out.hex
Lines: "addr: w0 w1 ...;" (consecutive words from addr) and "[a..b]: w;" (a range of one word).
"""
import re
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    text = open(src).read()
    text = re.sub(r'--[^\n]*', '', text)
    depth = int(re.search(r'DEPTH\s*=\s*(\d+)', text).group(1))
    width = int(re.search(r'WIDTH\s*=\s*(\d+)', text).group(1))
    for radix in ('ADDRESS_RADIX', 'DATA_RADIX'):
        m = re.search(radix + r'\s*=\s*(\w+)', text)
        if m and m.group(1).upper() != 'HEX':
            sys.exit('%s: %s %s, only HEX is supported' % (src, radix, m.group(1)))
    body = re.search(r'CONTENT\s+BEGIN(.*)END\s*;', text, re.S).group(1)
    mem = [0] * depth
    for stmt in body.split(';'):
        stmt = stmt.strip()
        if not stmt:
            continue
        addr, data = stmt.split(':', 1)
        words = [int(w, 16) for w in data.split()]
        addr = addr.strip()
        m = re.match(r'\[(\w+)\.\.(\w+)\]', addr)
        if m:
            for a in range(int(m.group(1), 16), int(m.group(2), 16) + 1):
                mem[a] = words[0]
        else:
            a = int(addr, 16)
            for i, w in enumerate(words):
                mem[a + i] = w
    digits = (width + 3) // 4
    with open(dst, 'w') as f:
        for w in mem:
            f.write('%0*x\n' % (digits, w))


if __name__ == '__main__':
    main()
