#!/usr/bin/env python3
"""Convierte imagenes IMD (ImageDisk) del Osborne 1 a imagen raw ordenada
pista/sector (sectores 1..N) para el core Osborne de MiSTer.
SD: 40 x 10 x 256 = 102400 bytes.  DD: 40 x 5 x 1024 = 204800 bytes."""
import sys, os

def parse_imd(data):
    p = data.index(0x1a) + 1
    comment = data[:p-1].decode('latin1', 'replace')
    tracks = []
    while p < len(data):
        mode, cyl, head, nsec, ssz = data[p:p+5]; p += 5
        smap = list(data[p:p+nsec]); p += nsec
        if head & 0x80: p += nsec      # cylinder map
        if head & 0x40: p += nsec      # head map
        size = 128 << ssz
        secs = {}
        for s in smap:
            t = data[p]; p += 1
            if t == 0:
                secs[s] = None
            elif t in (1, 3, 5, 7):
                secs[s] = bytes(data[p:p+size]); p += size
            else:
                secs[s] = bytes([data[p]]) * size; p += 1
        tracks.append(dict(mode=mode, cyl=cyl, head=head & 1, size=size, secs=secs))
    return comment, tracks

def convert(src, dst=None, verbose=True):
    comment, tracks = parse_imd(open(src, 'rb').read())
    sizes = sorted({t['size'] for t in tracks})
    cyls = max(t['cyl'] for t in tracks) + 1
    heads = max(t['head'] for t in tracks) + 1
    if verbose:
        modes = sorted({t['mode'] for t in tracks})
        nsec = sorted({len(t['secs']) for t in tracks})
        ids = sorted({s for t in tracks for s in t['secs']})
        print(f"{os.path.basename(src)}: cyls={cyls} heads={heads} sizes={sizes} spt={nsec} modes={modes} ids={ids[0]}..{ids[-1]}")
    if heads != 1 or len(sizes) != 1 or sizes[0] not in (256, 1024):
        print("  ** formato no soportado (solo Osborne SD 10x256 o DD 5x1024 de una cara)")
        return False
    size = sizes[0]; spt = 10 if size == 256 else 5
    img = bytearray([0xe5]) * (40 * spt * size)
    missing = 0
    for t in tracks:
        if t['cyl'] >= 40: continue
        for s, d in t['secs'].items():
            if 1 <= s <= spt and d is not None:
                o = (t['cyl'] * spt + s - 1) * size
                img[o:o+size] = d
            else:
                missing += 1
    if missing and verbose: print(f"  aviso: {missing} sectores ausentes/ilegibles o fuera de rango")
    dst = dst or os.path.splitext(src)[0] + '.IMG'
    open(dst, 'wb').write(img)
    return True

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("uso: imd2img.py fichero.imd [salida.img]"); sys.exit(1)
    sys.exit(0 if convert(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None) else 1)
