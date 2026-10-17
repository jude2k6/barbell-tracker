import struct, sys
d = open(sys.argv[1], 'rb').read()
def pool(off):
    typ, hsz, size, cnt, scnt, flags, sstart, _ = struct.unpack_from('<HHIIIIII', d, off)
    utf8 = flags & 0x100
    offs = struct.unpack_from('<%dI' % cnt, d, off + hsz)
    out = []
    for o in offs:
        p = off + sstart + o
        if utf8:
            n = d[p]; p += 2 if n & 0x80 else 1
            n = d[p]; 
            if n & 0x80: n = ((n & 0x7f) << 8) | d[p+1]; p += 2
            else: p += 1
            out.append(d[p:p+n].decode('utf8', 'replace'))
        else:
            n, = struct.unpack_from('<H', d, p); p += 2
            if n & 0x8000: n = ((n & 0x7fff) << 16) | struct.unpack_from('<H', d, p)[0]; p += 2
            out.append(d[p:p+2*n].decode('utf16', 'replace'))
    return out, size
# table header 12 bytes, then global string pool
gs, _ = pool(12)
# find package chunk, key pool, and string entries in default config
_, _, tsize = struct.unpack_from('<HHI', d, 0)
p = 12 + struct.unpack_from('<I', d, 16)[0]
typ, hsz, size = struct.unpack_from('<HHI', d, p)
pkg = p
typeStrOff, lastPublicType, keyStrOff = struct.unpack_from('<III', d, pkg + 8 + 4 + 256)
types, _ = pool(pkg + typeStrOff)
keys, _ = pool(pkg + keyStrOff)
q = pkg + hsz
res = {}
while q < pkg + size:
    ct, ch, cs = struct.unpack_from('<HHI', d, q)
    if ct == 0x0201:  # type chunk
        tid = d[q+8]; ecount, estart = struct.unpack_from('<II', d, q+12)
        cfg = d[q+20:q+20+struct.unpack_from('<I', d, q+20)[0]]
        default = all(b == 0 for b in cfg[4:])
        if types[tid-1] == 'string' and default:
            eo = struct.unpack_from('<%dI' % ecount, d, q + ch)
            for e in eo:
                if e == 0xFFFFFFFF: continue
                ep = q + estart + e
                esz, eflags, kidx = struct.unpack_from('<HHI', d, ep)
                if eflags & 1: continue
                vsz, _, vtype, vdata = struct.unpack_from('<HBBI', d, ep + esz)
                if vtype == 3: res[keys[kidx]] = gs[vdata]
    q += cs
for k, v in res.items():
    print(k, '=', v.replace('\n', '\\n'))
