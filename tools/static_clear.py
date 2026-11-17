#!/usr/bin/env python3
"""Remove the constant bake backdrop, retaining a fixed transparent Clear overlay.
Pure stdlib PNG/RGBA8; no screenshots, images or live wallpaper are inputs.
The original shader is baked over encoded neutral 102/255. This decomposes its
result into the minimum-opacity foreground reproducing that neutral composite.
Wallpaper can show through normally; no adaptive material or refraction remains.
"""
import struct
import zlib
from pathlib import Path

SIGNATURE = b'\x89PNG\r\n\x1a\n'
MARKER = b'NGStaticClear\x00neutral102-matte-v1'

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

def read_rgba(data):
    if not data.startswith(SIGNATURE):
        raise ValueError('Not PNG')
    offset, compressed, size = 8, bytearray(), None
    while offset < len(data):
        length = struct.unpack('>I', data[offset:offset+4])[0]
        kind = data[offset+4:offset+8]
        value = data[offset+8:offset+8+length]
        if len(value) != length:
            raise ValueError('Truncated PNG')
        if kind == b'IHDR':
            width, height, depth, color, method, filtering, interlace = struct.unpack('>IIBBBBB', value)
            if (depth,color,method,filtering,interlace) != (8,6,0,0,0) or not (0 < width <= 4096 and 0 < height <= 4096):
                raise ValueError('Expected bounded RGBA8 noninterlaced PNG')
            size = width,height
        elif kind == b'IDAT':
            compressed.extend(value)
        offset += 12 + length
    if size is None:
        raise ValueError('No IHDR')
    width,height = size
    raw = zlib.decompress(compressed)
    stride = width*4
    if len(raw) != height*(stride+1):
        raise ValueError('Unexpected PNG data size')
    pixels = bytearray()
    previous = bytearray(stride)
    for y in range(height):
        start = y*(stride+1)
        filtering = raw[start]
        row = bytearray(raw[start+1:start+1+stride])
        for x in range(stride):
            left = row[x-4] if x >= 4 else 0
            above = previous[x]
            upper = previous[x-4] if x >= 4 else 0
            if filtering == 0: predictor = 0
            elif filtering == 1: predictor = left
            elif filtering == 2: predictor = above
            elif filtering == 3: predictor = (left+above)//2
            elif filtering == 4:
                p = left+above-upper
                a,b,c = abs(p-left),abs(p-above),abs(p-upper)
                predictor = left if a <= b and a <= c else above if b <= c else upper
            else: raise ValueError('Invalid PNG filter')
            row[x] = (row[x]+predictor)&255
        pixels.extend(row)
        previous = row
    return width,height,pixels

def matte(data):
    if MARKER in data:
        return data
    width,height,pixels = read_rgba(data)
    for i in range(0,len(pixels),4):
        rgb = pixels[i:i+3]
        coverage = pixels[i+3]/255
        effect = max(max((c-102)/153, (102-c)/102, 0) for c in rgb)
        if effect < 1/255 or not coverage:
            pixels[i:i+4] = b'\x00\x00\x00\x00'
            continue
        foreground = [round(max(0,min(255,(c-(1-effect)*102)/effect))) for c in rgb]
        pixels[i:i+4] = bytes(foreground+[round(255*coverage*effect)])
    stride = width*4
    raw = b''.join(b'\x00'+pixels[y*stride:(y+1)*stride] for y in range(height))
    return (SIGNATURE + chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))
            + chunk(b'sRGB',b'\x00') + chunk(b'tEXt',MARKER)
            + chunk(b'IDAT',zlib.compress(raw,9)) + chunk(b'IEND',b''))

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(matte(args.source.read_bytes()))
    print('Fixed transparent Clear resource:',args.output)
