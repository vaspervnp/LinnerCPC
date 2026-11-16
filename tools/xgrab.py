#!/usr/bin/env python3
"""xgrab.py WINDOW_ID out.png: save an X window's pixels (XGetImage via ctypes).
Used by tools/cpcemu25: CPCEMU's own screenshot (PrintScreen) is unusable."""
import ctypes, sys
from PIL import Image
X = ctypes.cdll.LoadLibrary('libX11.so.6')
X.XOpenDisplay.restype = ctypes.c_void_p
X.XGetImage.restype = ctypes.c_void_p
X.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                        ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int]
class Attr(ctypes.Structure):
    _fields_ = [('x', ctypes.c_int), ('y', ctypes.c_int), ('width', ctypes.c_int),
                ('height', ctypes.c_int), ('pad', ctypes.c_byte * 256)]
class XImage(ctypes.Structure):
    _fields_ = [('width', ctypes.c_int), ('height', ctypes.c_int), ('xoffset', ctypes.c_int),
                ('format', ctypes.c_int), ('data', ctypes.c_void_p), ('byte_order', ctypes.c_int),
                ('bitmap_unit', ctypes.c_int), ('bitmap_bit_order', ctypes.c_int),
                ('bitmap_pad', ctypes.c_int), ('depth', ctypes.c_int),
                ('bytes_per_line', ctypes.c_int), ('bits_per_pixel', ctypes.c_int)]
d = X.XOpenDisplay(None)
w = int(sys.argv[1], 0)
a = Attr()
X.XGetWindowAttributes(ctypes.c_void_p(d), ctypes.c_ulong(w), ctypes.byref(a))
img = X.XGetImage(d, w, 0, 0, a.width, a.height, 0xFFFFFFFF, 2)
if not img:
    sys.exit('XGetImage failed')
xi = XImage.from_address(img)
buf = ctypes.string_at(xi.data, xi.bytes_per_line * xi.height)
im = Image.frombuffer('RGBX', (xi.width, xi.height), buf, 'raw', 'BGRX', xi.bytes_per_line, 1)
im.convert('RGB').save(sys.argv[2])
print(xi.width, xi.height, xi.bits_per_pixel)
