# macOS: uxplay installed in /usr/local/bin loads two GLib/GObject copies and segfaults on first HTTPS (HLS) playback

## Environment

| | |
|---|---|
| UxPlay | 1.74, master `48f5ce4` |
| OS | macOS 13.7.8 (22H730), Intel x86_64 (iMac18,3) |
| GStreamer | official macOS framework 1.28.9 (`/Library/Frameworks/GStreamer.framework`) |
| libplist | 2.8.1 static (`/usr/local/lib/libplist-2.0.a`) |
| Binary location | `/usr/local/bin/uxplay` (Homebrew prefix on Intel) |

Built exactly as the README's macOS section says (framework pkg-config + Brew `openssl@3`).

## Symptom

`uxplay -hls` + "AirPlay" icon in the iOS YouTube app. Video starts, then the process dies:

```
GStreamer error (video): hlsdemux2 Invalid manifest
(<unknown>:72257): GLib-GObject-CRITICAL **: parameter 1 of type 'GstMemory'
    for signal "GstSoupHTTPSrc::accept-certificate" is not a value type
(<unknown>:72257): GLib-GObject-CRITICAL **: can't peek value table for type 'buffers'
    which is not currently referenced
Segmentation fault: 11
```

Crash thread: `souphttpsrc` → `_soup_session_new_with_options` → `g_object_new_valist`.
Mirroring (no `-hls`) is unaffected because it never pulls in `souphttpsrc`.

## Cause

The framework's dylibs resolve `@rpath/libgio-2.0.0.dylib` (and `libglib`, `libgobject`)
through `LC_RPATH @executable_path/../lib` **before** `@loader_path/../lib`.
With the executable in `/usr/local/bin`, `@executable_path/../lib` is `/usr/local/lib`,
which on a machine with Homebrew glib contains

```
/usr/local/lib/libgio-2.0.0.dylib -> ../Cellar/glib/2.88.3/lib/libgio-2.0.0.dylib
```

so Homebrew's glib is loaded in addition to the framework copy. Second GObject type
system → the `accept-certificate` signal's parameter types cannot be resolved → SIGSEGV.

`DYLD_PRINT_LIBRARIES=1 uxplay -n test` shows both copies:

```
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libglib-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgobject-2.0.0.dylib
/usr/local/Cellar/glib/2.88.3/lib/libgio-2.0.0.dylib
/usr/local/Cellar/glib/2.88.3/lib/libglib-2.0.0.dylib
/usr/local/Cellar/glib/2.88.3/lib/libgobject-2.0.0.dylib
```

Which image pulls it in: `libgstsdp-1.0.0.dylib` requires `@rpath/libgio-2.0.0.dylib`,
and its first `LC_RPATH` is `@executable_path/../lib` → `/usr/local/lib`.

## Workarounds

- Run the binary from any directory whose `../lib` does not contain Homebrew glib
  (e.g. run it from the build directory instead of installing to `/usr/local/bin`), or
- `DYLD_LIBRARY_PATH=/Library/Frameworks/GStreamer.framework/Versions/1.0/lib uxplay ...`

## Suggestion

Document this in the macOS build section of the README: after `make install`, do not
keep the binary in a directory that has a Homebrew/port `lib` sibling (`/usr/local/bin`
on Intel Homebrew is the common case), or export `DYLD_LIBRARY_PATH` to the framework
lib dir. `-vsync no` is documented for a different GStreamer problem, this one is
silent until the first HTTPS/HLS playback.
