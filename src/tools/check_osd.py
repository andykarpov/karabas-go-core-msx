#!/usr/bin/env python3
"""Checks the osd of a core*.json before make_core packs it: the F and FL items need different
slot numbers. The firmware keeps both kinds in one array of file slots (file_slots[slot]): two
items with one slot share the extensions, the dir and the file name of the last one (Cart A
showed only .dsk files when it was FL 0 next to the disk F 0).

usage: check_osd.py core.json
"""
import json
import sys

osd = json.load(open(sys.argv[1]))['osd']
seen = {}
err = 0
for i, item in enumerate(osd):
    if item['type'] not in ('F', 'FL'):
        continue
    s = item['slot']
    if s in seen:
        print('%s: item %d "%s" has slot %d of item %d "%s"' % (sys.argv[1], i, item['name'], s, seen[s][0], seen[s][1]))
        err += 1
    seen[s] = (i, item['name'])
sys.exit(1 if err else 0)
