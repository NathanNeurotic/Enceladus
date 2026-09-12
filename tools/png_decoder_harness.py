#!/usr/bin/env python3
"""Execute the real PNG decoder with host libpng; GS upload alone is mocked.

Requires Python 3, g++, pkg-config and libpng development headers (Debian/Ubuntu:
apt-get install g++ pkg-config libpng-dev). Run: python3 tools/png_decoder_harness.py
Optional --source selects a baseline graphics.cpp to demonstrate a regression.
This checks decoded texture bytes, not GS rendering or device I/O on a PS2.
"""

import argparse
import os
from pathlib import Path
import shlex
import struct
import subprocess
import tempfile
import zlib


STUBS = r"""
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <malloc.h>
#include <vector>
#include <png.h>
using u8 = uint8_t;
using u32 = uint32_t;
enum { GS_PSM_CT32=0, GS_PSM_CT24=1, GS_PSM_T8=19, GS_PSM_T4=20,
       GS_CLUT_STORAGE_CSM1=0, GS_FILTER_NEAREST=0, GSKIT_ALLOC_USERBUFFER=0 };
const u32 GSKIT_ALLOC_ERROR = ~0u;
struct GSTEXTURE {
    int Width, Height, PSM, ClutPSM, ClutStorageMode, Filter;
    u32 *Mem, *Clut, Vram, VramClut;
    bool Delayed;
};
void *gsGlobal = nullptr;
#define DPRINTF(...) ((void)0)
// Pinned gsKit reserves four EE bytes/pixel for BOTH CT24 and CT32.
int gsKit_texture_size_ee(int w, int h, int psm) {
    return psm == GS_PSM_T4 ? w*h/2 : psm == GS_PSM_T8 ? w*h : w*h*4;
}
int gsKit_texture_size(int w, int h, int psm) { return gsKit_texture_size_ee(w,h,psm); }
u32 gsKit_vram_alloc(void *, int, int) { return 256; }
void gsKit_setup_tbw(GSTEXTURE *) {}
std::vector<u8> uploaded, uploaded_clut;
void gsKit_texture_upload(void *, GSTEXTURE *t) {
    auto p = reinterpret_cast<u8 *>(t->Mem);
    uploaded.assign(p, p + gsKit_texture_size_ee(t->Width,t->Height,t->PSM));
    if (t->Clut) {
        p = reinterpret_cast<u8 *>(t->Clut);
        uploaded_clut.assign(p, p + (t->PSM == GS_PSM_T4 ? 64 : 1024));
    }
}
"""

DRIVER = r"""
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    bool delayed = atoi(argv[2]);
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 3;
    GSTEXTURE *t;
    if (atoi(argv[3])) {
        fseek(f, 0, SEEK_END);
        long n = ftell(f);
        rewind(f);
        std::vector<u8> bytes(n);
        if (fread(bytes.data(),1,n,f) != static_cast<size_t>(n)) return 4;
        fclose(f);
        t = DecodePngFromMemory(bytes.data(),bytes.size(),delayed);
    } else {
        t = loadpng(f,delayed);
    }
    if (!t) { puts("rejected"); return 0; }
    size_t size = gsKit_texture_size_ee(t->Width,t->Height,t->PSM);
    size_t clut_size = (t->Clut || !uploaded_clut.empty()) ? (t->PSM == GS_PSM_T4 ? 64 : 1024) : 0;
    printf("%d %d %d %zu %zu\n",t->PSM,t->Width,t->Height,size,clut_size);
    fwrite(delayed ? reinterpret_cast<u8 *>(t->Mem) : uploaded.data(),1,size,stdout);
    if (clut_size) fwrite(delayed ? reinterpret_cast<u8 *>(t->Clut) : uploaded_clut.data(),1,clut_size,stdout);
    free(t->Mem); free(t->Clut); free(t);
}
"""


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


def png(w, h, depth, color, pixel, *, interlace=False, extra=b''):
    """Generate deterministic PNGs, including genuine Adam7 and packed palettes."""
    passes = [(0, 0, 1, 1)] if not interlace else [
        (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
        (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    rows = bytearray()
    for x0, y0, dx, dy in passes:
        if x0 >= w or y0 >= h:
            continue
        for y in range(y0, h, dy):
            row = b''.join(pixel(x, y) for x in range(x0, w, dx))
            if depth == 4:
                row = bytes((row[i] << 4) | (row[i+1] if i+1 < len(row) else 0)
                            for i in range(0, len(row), 2))
            rows.extend(b'\0' + row)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w,h,depth,color,0,0,interlace))
            + extra + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1] / 'src/graphics.cpp')
    args = parser.parse_args()
    source = args.source.read_text()
    # Compile production functions verbatim. No copied decoder implementation.
    decoder = source[source.index('//2D drawing functions'):source.index('GSTEXTURE* loadbmp(')]
    rgb = lambda x, y: bytes((x % 256, y % 256, (x*3+y*5) % 256))
    cases = []

    def truecolor(name, depth, color, pixel, expected, **options):
        w, h = 200, 200
        cases.append((name, png(w,h,depth,color,pixel,**options), 0, w,h,
                      b''.join(expected(x,y) for y in range(h) for x in range(w)), b''))

    opaque = lambda x,y: rgb(x,y) + b'\x7f'
    truecolor('RGB',8,2,rgb,opaque)
    truecolor('RGBA opaque',8,6,lambda x,y: rgb(x,y)+b'\xff',opaque)
    truecolor('RGB Adam7',8,2,rgb,opaque,interlace=True)
    truecolor('RGBA varying alpha',8,6,lambda x,y: rgb(x,y)+bytes(((x+y)%256,)),
              lambda x,y: rgb(x,y)+bytes((((x+y)%256)>>1,)))
    truecolor('RGB 16 bit',16,2,lambda x,y: b''.join(bytes((v,37)) for v in rgb(x,y)),opaque)
    truecolor('gray',8,0,lambda x,y: bytes((x,)),lambda x,y: bytes((x,x,x,127)))
    truecolor('gray alpha',8,4,lambda x,y: bytes((x,y)),lambda x,y: bytes((x,x,x,y>>1)))
    transparent = chunk(b'tRNS', struct.pack('>HHH',0,0,0))
    truecolor('RGB tRNS',8,2,rgb,lambda x,y: rgb(x,y)+bytes((0 if rgb(x,y)==b'\0\0\0' else 127,)),extra=transparent)
    for depth in (4,8):
        for alpha in (False,True):
            w,h = 200,200
            extra = chunk(b'PLTE', b'\xff\0\0\0\xff\0')
            if alpha:
                extra += chunk(b'tRNS', b'\0\xff')
            data = png(w,h,depth,3,lambda x,y: bytes(((x+y)%2,)),extra=extra)
            if alpha:
                # Existing tRNS transform expands indexed transparency to RGBA.
                pixels = b''.join(b'\0\xff\0\x7f' if (x+y)%2 else b'\xff\0\0\0'
                                  for y in range(h) for x in range(w))
                cases.append((f'palette {depth} tRNS',data,0,w,h,pixels,b''))
                continue
            pixels = bytes((x+y)%2 for y in range(h) for x in range(w))
            if depth == 4:
                pixels = bytes(pixels[i] | pixels[i+1]<<4 for i in range(0,len(pixels),2))
            clut = bytes((255,0,0,128,0,255,0,128))
            clut += bytes((64 if depth==4 else 1024)-len(clut))
            cases.append((f'palette {depth} alpha={alpha}',data,20 if depth==4 else 19,w,h,pixels,clut))
    # Existing size limits and libpng error handling remain active.
    for name,w,h in [('dimension limit',1025,1),('byte budget',608,608)]:
        cases.append((name,png(w,h,8,2,rgb),None,0,0,b'',b''))
    cases.append(('truncated PNG',cases[0][1][:50],None,0,0,b'',b''))

    with tempfile.TemporaryDirectory(prefix='popsloader-png-') as tmp:
        tmp = Path(tmp)
        cpp, exe, fixture = tmp/'decoder.cpp', tmp/'decoder', tmp/'fixture.png'
        cpp.write_text(STUBS + decoder + DRIVER)
        flags = shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','libpng'],text=True))
        subprocess.run([os.environ.get('CXX','g++'),'-std=c++11','-O1','-g',
                        '-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-pie','-no-pie',
                        str(cpp),'-o',str(exe),*flags],check=True)
        count = 0
        for name,data,psm,w,h,pixels,clut in cases:
            fixture.write_bytes(data)
            for delayed in (0,1):
                for memory in (0,1):
                    run = subprocess.run([str(exe),str(fixture),str(delayed),str(memory)],capture_output=True,check=True)
                    context = f'{name}, delayed={delayed}, memory={memory}'
                    if psm is None:
                        assert run.stdout == b'rejected\n', context
                    else:
                        header,payload = run.stdout.split(b'\n',1)
                        assert list(map(int,header.split())) == [psm,w,h,len(pixels),len(clut)], context + ': texture format/size'
                        assert payload == pixels+clut, context + ': pixel/alpha/CLUT mismatch'
                    count += 1
            print('PASS',name)
        print(f'PASS: {count} decoder cases (file/memory, delayed/immediate), ASan + UBSan')


if __name__ == '__main__':
    main()
