from ctypes import cdll, POINTER, c_int, c_void_p, Structure, c_char_p, byref
import sys

print("Loading NDI dylib directly...")
try:
    libndi = cdll.LoadLibrary("/usr/local/lib/libndi.dylib")
    print("Found NDI in /usr/local/lib")
except OSError:
    try:
        libndi = cdll.LoadLibrary("/Library/NDI SDK for Apple/lib/macOS/libndi.dylib")
        print("Found NDI in SDK path")
    except OSError as e:
        print("NDI NOT FOUND:", e)
        sys.exit(1)

# Make sure basic initialization works
libndi.NDIlib_initialize.restype = c_int
result = libndi.NDIlib_initialize()
print(f"NDIlib_initialize returned: {result}")
if result:
    print("NDI initialized perfectly via ctypes bindings!")
