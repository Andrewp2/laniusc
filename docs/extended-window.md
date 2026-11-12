# Native windows and RGB canvases

`ext::window` creates desktop windows, receives events and presents an RGB
canvas. Window ownership, validation, event translation and pixel scaling are
implemented in Lanius. The first backend calls the operating system's `libX11`
interface directly. There is no SDL, GLFW or production C shim.

The separate [`ext::gpu`](extended-gpu.md) backend now attaches Vulkan GPU
surfaces to these windows. This module's `present` remains software rendered.
A GPU attachment prevents software presentation and window closure until its
surface is closed.

The supported profile is native-linked **Linux x86_64/glibc with X11 or
XWayland**, a depth-24 TrueColor default visual, ordinary RGB masks and
little-endian 32-bit image storage. `init` and image creation reject other
layouts explicitly. Programs execute on the CPU; the GPU compiler builds
them. User GPU kernels cannot create these windows.

## Run the canvas example

From the repository root, with a current compiler and the libX11 development
package installed:

```sh
timeout --kill-after=2s 100s target/release/laniusc \
  --native-link --native-library X11 \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/window_demo.lani -o /tmp/window-demo

timeout --kill-after=2s 100s /tmp/window-demo
```

The example opens a resizable animated canvas. Space pauses it, a pointer
button changes its colors, and Escape or the window manager's close button
exits. `--frames 3` presents three frames and exits. `--frames N` accepts
1 through 600; malformed arguments return exit status 2 before connecting to
a display. Window failures return 3 and canvas allocation failures return 4.
All normal and recoverable error exits release the vector, window and context.

`DISPLAY` and the usual X11 authorization determine the connection. On a
Wayland desktop this uses XWayland. Native Wayland is not implemented.

## API and ownership

```text
init() -> Result<Context, Failure>
rgb(red: u8, green: u8, blue: u8) -> u32

Context.borrow() -> &Context
Context.is_open() -> bool
Context.create(title: Text, width: i32, height: i32, resizable: bool)
    -> Result<Window, Failure>
Context.poll() -> Result<Option<Event>, Failure>
Context.wait(milliseconds: i32) -> Result<Option<Event>, Failure>
Context.close() -> Result<bool, Failure>

Window.borrow() -> &Window
Window.acquire_gpu() -> Result<NativeWindow, Failure>
Window.release_gpu() -> Result<bool, Failure>
Window.is_open() -> bool
Window.id() -> u64
Window.canvas_size() -> Size
Window.size() -> Result<Size, Failure>
Window.present(pixels: View<u32>) -> Result<i32, Failure>
Window.close() -> Result<bool, Failure>

Size { width: i32, height: i32 }
Failure { cause: Cause, stage: Stage }
```

A context owns one X connection; each window owns its native window, graphics
context and image. Independent contexts can coexist. Use each context and its
windows only on the thread that created the context. Operations that access
native resources reject a different thread with `WrongThread`. The simple
field queries (`is_open`, `id`, `canvas_size`) do not provide synchronization.

Close every window before its context. `Context.close` returns `Busy` while
any window remains. A successful close returns `true`, clears that owner's
handle and releases its resources. Closing the same cleared owner again
returns `false`. Further resource operations return `Closed`; a closed
window's `id` is zero and `canvas_size` retains its original dimensions.
`is_open` reports local ownership, not server liveness.

Ownership is manual. Do not copy, forge or mutate owner fields, retain a
window after its context is released, or use an old alias after the real owner
closes. Copies do not create another cleanup authority. Borrow owners for
helper calls. Do not destroy or mutate their native resources through another
API. Slice descriptors must describe live backing for the duration of a call.
Descriptor length checks cannot validate forged pointers or lifetimes. There
is no automatic destructor, borrow checker or formal lifetime proof here.

The `NativeWindow { display: ptr, window: u64 }` record and GPU lease methods
are raw backend integration hooks. Keep the real window owner alive and do not
release a lease until its native GPU surface and swapchains are destroyed.
`ext::gpu` manages this protocol; application code should use its Surface API.

## Creation and pixels

Dimensions must be in `1..=16384`. Titles may contain at most 4095 UTF-8 bytes;
embedded NUL, invalid UTF-8 and invalid ranges are rejected before native
window creation. Empty titles are allowed. The backend sets the UTF-8 window
title, installs `WM_DELETE_WINDOW`, and supplies min/max size hints. A fixed
window requests equal min/max dimensions. Window-manager size hints are
advisory, and mapping is asynchronous: a successful `create` does not promise
that the compositor has made the window visible yet.

Pixels are opaque `0x00RRGGBB`, row-major from the upper-left. The high byte is
ignored. `present` requires exactly the original canvas's `width * height`
elements and validates the range against the slice descriptor before reading.
Nonzero offsets and ordinary Lanius strided views work. No caller pixel pointer
is retained after the call.

`size` queries the current native client size. Resizing leaves `canvas_size`
unchanged; `present` scales the original canvas to the current window size with
nearest-neighbor sampling. A replacement image is allocated before the old
one is destroyed. If allocation fails, the window and previous image remain
owned and presentation can be retried. An image needs four native bytes per
output pixel; the maximum dimension pair can require 1 GiB. Input canvas
storage is separate. There is no hidden frame queue.

Presentation returns the input pixel count after `XPutImage` and an `XSync`
round trip. This establishes server processing; it does not establish scanout,
vsync or compositor presentation. Redraw after exposure. This is software
presentation without alpha compositing, color management, GPU rendering or
hardware acceleration guarantees.

## Events and waiting

`poll` removes at most one queued event. `wait` checks the queue first, then
makes at most one native `poll` call for the requested nonnegative number of
milliseconds. Zero means no waiting. Timeout and spurious readiness return
`None`; interrupted system calls return `System(errno)` without an unbounded
retry. The timeout applies to readiness waiting. Xlib connection traffic and
round trips do not have a hard elapsed-time deadline.

| Event | Meaning |
| --- | --- |
| `Close(window)` | A matching `WM_PROTOCOLS` / `WM_DELETE_WINDOW` request. The application still owns the window and decides when to close it. |
| `Exposed(window)` | Contents need repainting; the application may redraw the whole canvas. |
| `Resized { window, width, height }` | A native configure notification. Notifications may also report an unchanged size. |
| `Key { window, key, scan, modifiers, down }` | Press/release, base-level keysym and native X11 keycode/modifier bits. Common navigation keys have named variants; others retain `Key::Other(keysym)`. |
| `Motion { window, x, y, buttons }` | Pointer coordinates in window pixels and the native X11 state mask, which includes modifier bits. |
| `Button { window, button, down, x, y }` | Native button press/release. Scroll wheels arrive as button events, conventionally buttons 4–7. |
| `Focus { window, gained }` | Native keyboard focus notification. |
| `Other(type)` | An unhandled native event type. Malformed or unrelated client messages are not close requests. |

The record variants carry the public `ResizeEvent`, `KeyEvent`, `MotionEvent`,
`ButtonEvent` and `FocusEvent` structs. Events retain the target window ID for
multi-window routing. IDs belong to a context; they are not globally persistent
identities. Native autorepeat may produce repeated press/release events.
`Key` is not text input: composition, IME, layout-aware text and clipboard
support remain future work. Handle native events as notifications, not as an
authenticated source of input; X11 clients can send synthetic events.

## Failures and the native boundary

`Cause` distinguishes invalid sizes, titles, pixels and timeouts; allocation
failure; absent/unusable display connections; unsupported display layouts;
closed or busy owners; wrong-thread calls; native status failure; a system
errno; and observed poll disconnection. `Stage` identifies `Init`, `Create`,
`Image`, `Poll`, `Size`, `Present` or `Close`. A nested operation retains its
own stage, for example an image allocation failure during presentation.
Partial constructor failure releases every resource acquired by that call.
Input rejection performs no presentation.

**Xlib protocol errors and connection I/O failures are not generally recoverable
through this Result API.** This backend leaves Xlib's process-wide error
handlers unchanged. With the default handlers, a protocol error or lost
connection can terminate the process, including during `present` or `close`.
The typed `Disconnected` case covers poll error/hangup flags when they are
observed before Xlib handles the connection. It is not a general disconnect
recovery guarantee. Applications that replace Xlib's global handlers must
understand that asynchronous errors are not converted into `Failure` by this
module. No successful return promises recovery from such a handler's ignored
protocol error.

This boundary follows the [Xlib manual](https://xorg.freedesktop.org/archive/current/doc/libX11/libX11/libX11.html):
X requests can fail asynchronously, and `XDestroyImage` frees both the image
record and its data. Image data therefore comes from libc `calloc`, while
Lanius owns and frees the context state through its own allocator. The two
allocation domains are never mixed.

## Executable evidence

`tests/extended_window_execution.rs` compiles Lanius through the current GPU
compiler, links native x86_64 executables and runs them. The first Linux
XWayland receipt has all four tests passing (three library tests, followed by
the corrected demo test). It covers:

- A real window opening, presenting and closing without the observer linked.
- An invalid `DISPLAY` returning `NoDisplay` in a separate process.
- Window titles, resize hints and WM protocols queried through libX11;
  exact native pixel readback for a nonzero-offset canvas at 8×8 and 13×11.
- Native event records for exposure, resize, keys, motion, buttons, focus and
  unknown events; malformed close rejection and actual `XSendEvent` close
  delivery through the server. The deterministic record tests use Xlib's
  native event queue, not simulated public Lanius events.
- Wrong-thread rejection through an actual pthread callback, busy/idempotent
  close, multiple contexts/windows, invalid input and physical slice bounds.
- Twelve reached injected failures: connection, unsupported depth, atom,
  initial/replacement image, image layout, window, GC, WM protocols, geometry,
  poll errno and poll hangup. The observer checks balanced native owners and
  both explicit pixel-payload frees on failed image construction. This is not
  exhaustive allocation-failure coverage.
- The real demo exiting after three frames and after a server-delivered close
  request, plus four invalid CLI cases rejected before display access.

The C fixture is a test-only native oracle and fault injector. Header-based
static assertions check the LP64 record layouts used by Lanius. It contains no
production window implementation. Display tests are marked ignored by default
so headless test runs do not pretend to exercise a window. Run them explicitly
against an X server, or under a separately installed depth-24 Xvfb:

```sh
LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=85000 timeout --kill-after=2s 100s \
  cargo test --release --test extended extended_window_execution:: -- \
  --include-ignored --test-threads=1
```

Initial logs are `target/stdlib-work/window-x11-tests.log` (three library tests
pass; initial demo source error) and `window-x11-demo-tests.log` (corrected demo
passes). Test source errors were in the example, not compiler changes.
After GPU lease integration, all four tests pass again in 4.79 seconds;
`target/stdlib-work/gpu-window-regressions.log` records that run. The GPU tests
separately exercise busy window closure/software presentation and lease release
after failed constructors.

Xvfb, native Xorg, other visual layouts and other operating systems were not
used for this receipt. Native Wayland, Windows/macOS backends, richer input,
additional GPU backends and formal verification remain open. No compiler or runtime
changes were needed for this increment.
