# Native GPU rendering and compute

`ext::gpu` owns Vulkan devices, buffers, textures, resource bindings, graphics
and compute pipelines, command encoders, submissions, and window surfaces.
Resource management, command recording, synchronization and error handling
are implemented in Lanius. Applications call the system Vulkan loader and GPU
driver directly. There is no wgpu, SDL or production C shim in this library.
The compiler's existing Rust/wgpu implementation is separate and unchanged.

This is an executable first profile, not a WebGPU compatibility or shader
safety layer. The [generated API inventory](api/ext/gpu.md) lists declarations;
this guide defines their behavior and limits.

## Supported profile

Linux x86_64/glibc, Vulkan 1.1 or later, with X11/XWayland presentation:

- Instance extensions: `VK_KHR_surface`, `VK_KHR_xlib_surface`,
  `VK_KHR_get_surface_capabilities2`, `VK_EXT_surface_maintenance1`.
- Device extensions: `VK_KHR_swapchain`, `VK_EXT_swapchain_maintenance1`,
  with the `swapchainMaintenance1` feature enabled.
- One queue family supporting **both graphics and compute**, and presentation
  to any attached window. All commands use its first queue.
- Buffers need host-visible, host-coherent memory. Textures need device-local
  memory and optimal-tiling RGBA8 UNORM support for the requested image usages.
- Surfaces need FIFO presentation, BGRA8 or RGBA8 UNORM in the sRGB-nonlinear
  surface color space, and color-attachment plus transfer-source usage.

Unsupported configurations return errors. Buffer/texture/compute operations
do not open a display, although this backend still links libX11 and enables
window extensions. Other operating systems and native Wayland are unimplemented.

`open(adapter)` selects a Vulkan enumeration index, 0 through 31, not a promise
of hardware acceleration. Discovery is bounded to 32 adapters, 64 queue
families and 64 surface formats; incomplete enumeration reports a Vulkan error.

## Examples

The computed-texture example uses a uniform buffer, a storage buffer, a storage
image, a sampled image, compute dispatch, and asynchronous window submissions.
The GPU generates the image; the CPU polls completion and handles events.

```sh
timeout --kill-after=2s 100s target/release/laniusc \
  --native-link --native-library X11 \
  --native-object /lib/x86_64-linux-gnu/libvulkan.so.1 \
  --stdlib-root stdlib --source-root extended \
  --source-root sample_programs/library \
  sample_programs/library/gpu_compute.lani -o /tmp/gpu-compute

timeout --kill-after=2s 100s /tmp/gpu-compute --frames 3
```

Omit `--frames` for an interactive window; Escape or window close exits.
Both `gpu_compute.lani` and the simpler `gpu_triangle.lani` accept frame limits
1 through 600. The triangle uses synchronous rendering conveniences.
`--native-library vulkan` also works if a loader development symlink exists.

Checked-in SPIR-V arrays avoid a shader compiler dependency for ordinary
builds. `tools/generate_gpu_work.py` and `tools/generate_gpu_triangle.py`
compile their GLSL sources with glslang for Vulkan 1.1, run `spirv-val`, and
embed native words. Both accept `--check`. Recorded generators use glslang
15.3.0 and SPIRV-Tools v2025.1; these are sample-data tools, not runtime code
or a Lanius-to-SPIR-V compiler.

The [Game of Life example](extended-gpu-life.md) evolves a 256×160 wrapping
board in two textures, samples the latest generation, and supports pause,
single-step and reset. Its dedicated shader and interactive-control tests
extend the foundation tests recorded below.

## Buffers and textures

Buffers have lengths 1 through 64 MiB. Each owns a Vulkan buffer, allocation,
and persistent coherent host mapping, and is initially zeroed. `read` and
`write` validate the full slice and buffer ranges before copying; ordinary
Lanius strides and nonzero view starts work. Empty host copies at the end are
valid. A malformed view or out-of-range request returns `Bounds`.

Every buffer supports transfer, uniform and storage use. Uniform bindings
cover the whole buffer and are limited to 16 KiB; storage bindings cover the
whole buffer up to 64 MiB. The profile does not expose offset bindings,
dynamic offsets or device-only buffers.

`Device.copy_buffer` waits for completion. `CommandEncoder.copy_buffer`
records the same operation for later submission. Source and target must be
distinct buffers on the same device. Offsets and byte count must be multiples
of four; both full ranges must fit. A zero count is admitted and copies no
bytes. The encoder retains admitted resources even for an empty copy.

Textures are 2D **RGBA8 UNORM**, 1 through 4096 pixels per dimension, with one
mip, layer and sample. They own an optimal-tiling image, device-local allocation,
view, and a nearest/clamp-to-edge sampler. Their supported usages are transfer,
sampling, storage, and color attachment; this increment does not expose
rendering directly into a texture.

A new texture has **undefined contents**. Initialize it with an encoder's
`clear_texture` (transparent black) or `upload_texture`. Sampling, compute
binding use and download reject an uninitialized texture with `Uninitialized`.
Storage images also require initialization before dispatch, even if the shader
is expected to overwrite all pixels.

Upload/download copy the entire texture as tightly packed, row-major RGBA8
bytes, at a four-byte-aligned buffer offset. The full `width * height * 4`
range must fit. Transfers return the byte count when recorded; successful
recording is not completion. There are no partial rectangles or row pitches
in this profile. Textures use `GENERAL` layout after their first transition.

Initialization belongs to the encoder that records it. Another encoder cannot
use that texture until the initializer is submitted; it receives `Busy` or
`Uninitialized` as appropriate. Discarding or failing that encoder rolls back
its initialization claim. Successful submission allows a subsequent submission
on the same queue to use the texture without waiting on the CPU.

## Resource bindings and pipelines

`create_binding_layout(View<BindingKind>)` defines one descriptor set with
1 through 4 dense bindings, numbered from zero. Kinds are `UniformBuffer`,
`StorageBuffer`, `SampledTexture` (combined image/sampler) and `StorageTexture`.
`create_bind_group(layout, View<Binding>)` must supply exactly those kinds,
in order, using live resources on the same device. Groups are immutable.

Groups retain their layout and resources. Pipelines retain their layout.
Closing a retained owner returns `Busy`. Two separately created layouts are
not interchangeable, even if their declarations match: a group must use the
same layout owner used to construct the pipeline, or get `BindingMismatch`.
Groups can be created before texture initialization; execution admission
checks that their textures have been initialized.

- `create_pipeline(vertex, fragment, format)` creates descriptor-free graphics.
- `create_bound_pipeline(vertex, fragment, format, layout)` uses descriptor set 0.
- `create_compute_pipeline(code, layout)` uses a compute shader and descriptor set 0.

Graphics uses triangle-list topology, vertex-index-generated positions, no
vertex attributes, culling, blending or depth/stencil, one sample, and a
viewport/scissor covering the surface. The clear color is `(0.02,0.03,0.06,1)`.
Vertices must be 1 through 1048576 **and** valid for the particular shader.
The supplied examples require exactly three. Pipelines own compatible render
passes independently of a surface; closing a surface does not destroy them.

`CommandEncoder.dispatch(pipeline, group, x, y, z)` admits 1 through 65535 groups
on each axis, with at most 1048576 groups total. Workgroup size comes from the
shader, not these arguments. Dispatch records actual GPU work.

### Trusted shader contract

All shaders must be independently validated SPIR-V for Vulkan 1.1, with entry
point `main`, matching stages and interfaces. The library checks slice bounds,
5–262144 words, and SPIR-V magic, then stages aligned native words. These checks
are **not** a SPIR-V validator, reflection engine, sandbox or bounds checker.

Shader descriptor declarations must match the layout and resource types;
buffer accesses must remain in range. Fragment color output is location zero.
There are no push constants or specialization constants. Compute workgroup
size, memory requirements and capabilities must fit the selected device.
For a conservative profile, use at most 128 total local invocations, local
sizes no larger than 128×128×64, and at most 16 KiB shared memory. Optional
shader features are not enabled: in particular, storage writes are supported
in compute, not vertex or fragment stages. Storage image shaders declare
`rgba8`; there is no formatless storage-image feature enablement. Shader
validation remains the caller's responsibility, including shader-specific
bounds and data races. This API does not claim WebGPU's safety guarantees.

## Command encoders and asynchronous submissions

```text
encoder = device.create_encoder()?
encoder.copy_buffer(source, 0, target, 0, length)?
submission = encoder.submit()?        // transfers the encoder's ownership
submission.poll()?                    // true only when complete
submission.wait(timeout_ns)?          // false on timeout; still owns the work
submission.close()?                  // Busy while pending
```

Each encoder owns a separate command pool, command buffer and fence. It can
record copies, texture initialization/transfers and dispatches. At most 64
unique buffer, texture, pipeline and group references may occur in one encoder.
Groups and pipelines retain their layouts transitively. Admission validates the whole operation and capacity
before recording it. Closing an unsubmitted encoder discards its commands
and releases its resource references.

Recorded resources are locked against CPU `read`/`write` and destruction from
recording until observed completion or encoder discard. A bind group alone
prevents resource destruction but does not block host access. Several encoders
or pending submissions may share initialized resources; each owns a separate
reference. Polling a later ticket does not retire an earlier one. CPU access
remains `Busy` until every referencing encoder/ticket releases its lock.

`submit` performs no fence wait. On success it empties the encoder and returns
its ownership as a `Submission`. A failure leaves the encoder owned and
closeable, but no longer recordable or resubmittable. `poll` never waits;
`wait` uses one nanosecond timeout across all of that submission's fences.
Timeouts and ordinary query errors retain ownership for retry. A completed
ticket must still be closed to release its pool/fence and device-child slot.

Operations run on one queue and use conservative all-command memory barriers
between GPU operations, plus a GPU-to-host barrier before submission completion.
This supports dependent compute/transfer/graphics submissions in queue order,
including shader-write-to-sampling and texture-transfer-to-host visibility.
It prioritizes correctness; suballocation, command pooling, precise hazard
tracking and multiple queues are future performance work.

## Window presentation

A surface borrows the actual window owner and holds its GPU lease. Window
close, software presentation and a second attachment return `Busy` while the
lease exists. Close the surface before the window/context. Raw window lease
hooks must not be used to release a surface's lease externally.

Synchronous methods are `render`, `render_readback`, `render_bound`, and
`render_bound_readback`. The corresponding asynchronous methods are `submit`,
`submit_readback`, `submit_bound`, and `submit_bound_readback`.

Asynchronous surface methods return:

- `Submitted(Submission)`: rendering was accepted. Keep and retire this ticket.
- `Retry`: no submission; try again after processing events.
- `Suspended`: zero drawable extent; process events before retrying.

Only one frame may be outstanding per surface. Another frame or surface close
returns `Busy` until its ticket observes completion. Independent command
submissions and other surfaces can remain outstanding. A frame ticket covers
acquisition, rendering **and presentation** fences. It keeps pipelines,
bindings, buffers, textures and the surface alive. The rendering semaphore
is not reused until the presentation fence completes, following Khronos'
[presentation lifetime contract](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).

After completion, `ticket.frame()` returns `Presented(Size)`, `Retry`, or an
error. An out-of-date presentation returns `Retry`, not `Presented`. Crucially,
a presentation error **after accepted rendering still returns the ticket**;
it does not discard an in-flight owner. A command-only ticket's `frame()`
returns `Unsupported`. `Presented` establishes safe resource retirement, not
that the monitor has scanned out the frame.

Asynchronous acquisition uses timeout zero and a semaphore; there is no CPU
fence wait in steady-state submission. Synchronous acquisition has a one-second
timeout. Creating/rebuilding a swapchain and native driver calls can block;
[Vulkan permits presentation calls to block](https://docs.vulkan.org/refpages/latest/refpages/source/vkQueuePresentKHR.html).
This is asynchronous GPU completion, not a hard wall-clock guarantee for every
API call. Resize/close drain native work explicitly.

Every frame checks the extent. Dimensions are 1 through 4096, with at most
16 swapchain images. Resize destroys the old chain after draining it and then
builds a replacement; allocation failure leaves an owned, retryable surface,
not an atomic rollback. A surface's format stays fixed throughout its life.
Readback copies native BGRA8/RGBA8 rows into a same-device buffer of at least
`width * height * 4` bytes. Read after completion. A later presentation error
or `Retry` may follow completed readback; errors do not roll back pixels.

## Failure and ownership rules

All resource operations run on the creating thread. Device close returns
`Busy` while child owners remain. Successful close clears the actual owner and
returns `true`; closing it again returns `false`. Copies are inactive aliases,
not independent destruction authorities. Transfer ownership explicitly and
retire only one authority. Do not forge/mutate owner fields, use stale aliases,
free borrowed windows early, or call these objects concurrently. Local field
queries such as `len` and `is_open` do not establish driver health. This
increment has no automatic destructors, borrow-checker guarantee or ownership
proof.

`Failure` carries a `Cause` and `Stage`. Causes include `Closed`, `Busy`,
`WrongThread`, `Bounds`, `Unsupported`, `AllocationFailed`, `InvalidShader`,
`DifferentDevice`, `BindingMismatch`, `Uninitialized`, `Poisoned`, a window
failure, a native `Vulkan(status)`, and `DeviceLost`.

Vulkan out-of-memory submission failures leave resources unaffected, as
[specified by Vulkan](https://docs.vulkan.org/refpages/latest/refpages/source/vkQueueSubmit.html).
An unexpected submission status with uncertain acceptance poisons the device
and retains the encoder until idle can be established. If that happens in a
surface submission and immediate cleanup also fails, the surface keeps the
abandoned encoder for a later close. Unknown query errors never unlock work.
The older synchronous conveniences poison the device on uncertain fence waits.
Post-acquisition surface failures preserve pending acquisition/presentation
fences for cleanup. A failed close retains its owner for retry.

Device loss rejects subsequent work and permits terminal cleanup. Actual
hardware loss has not been forced. X11 protocol/I/O errors retain the separate
process-fatal boundary documented in the [window guide](extended-window.md).

## Native ABI and remaining dependencies

`ext::gpu_native` is unsafe backend support. Its LP64 offsets and native
signatures are generated from Khronos Vulkan headers by
`tools/generate_gpu_native.py`; `--check --include PATH` verifies them.
The small C measurement program is not linked into applications. Generation
used headers 1.4.313. Production runtime logic remains Lanius.

The subset directly links loader exports. Lanius cannot yet call arbitrary
native function pointers returned by a loader, which limits broader extension
dispatch. Export names around 70 characters also fail interface generation
with `LNC0057`; `tests/fixtures/extended/gpu/compiler_limits/` preserves a
minimal reproduction. Generated constants use shorter names. Neither issue
requires a compiler change for this implemented subset.

Remaining work includes shader validation/reflection, richer pipeline state,
vertex/index buffers, render-to-texture, mipmaps/arrays/additional formats,
configurable samplers, multiple descriptor sets/queues, allocation/pipeline
caches, other platforms, performance characterization, and formal verification.

## Executable evidence

The eight-test native GPU suite passes on NVIDIA GeForce RTX 3090, driver
615.71.09, XWayland, with Khronos validation layer 1.4.313. The clean full run
exited successfully in 17.21 seconds (`target/stdlib-work/gpu-features-final.log`).
A later focused run also verifies the added fragment-input/readback alias
barrier in 3.52 seconds (`gpu-alias-tests.log`). The encoder-capacity boundary
then passes in 3.36 seconds (`gpu-capacity-tests.log`), checking that rejecting
reference 65 preserves all admitted copies and leaves the rejected destination
untouched. Tests explicitly require the
validation layer, enable synchronization validation, and reject all diagnostics
from generated executables. They cover:

- GPU buffer transfers, zero initialization, bounds/alignment and offset cases.
- Dependent asynchronous submissions, reverse completion observation, a
  deterministic pending fence, timed wait, query failure, retained-resource
  `Busy`, discard, and no fence waits inside submission.
- Texture upload/download at nonzero offsets, untouched surrounding bytes,
  transparent clearing, uninitialized rejection and initialization rollback.
- Uniform/storage-buffer and storage-image compute writes, checked byte for
  byte on a 13×9 image using partial edge workgroups.
- Compute-to-texture sampling without a CPU wait, exact native BGRA/RGBA frame
  readback, resize, and a fragment-read/readback-write buffer alias.
- Asynchronous presentation ownership, presentation out-of-date and failure
  after rendering was accepted, plus retained cleanup after uncertain queue
  acceptance and an injected idle failure.
- Pipeline/layout/group lifetimes, malformed bindings, wrong-device requests,
  creating-thread requirements, and idempotent close.
- Both interactive examples, frame-limited exit, native resize and close events.
- **47 reached injected failures** across the fixtures, with balanced native
  buffer/image/memory/view/sampler/descriptor/pipeline/command/synchronization/
  device/surface/instance counters after cleanup. This is finite coverage,
  not exhaustive allocation/driver-failure verification.

The observer is test-only C; production GPU logic is Lanius. The standalone
computed-texture example also builds and runs without that observer. The older
four software-window tests passed after the GPU lease addition; the new
increment does not modify `ext::window`.

These tests are ignored by default because they require native dependencies:

```sh
LANIUS_GPU_REQUIRE_HARDWARE=1 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=85000 \
  timeout --kill-after=2s 100s cargo test --release \
  --test extended extended_gpu_execution:: -- --include-ignored --test-threads=1
```

`LANIUS_VULKAN_INCLUDE` can name an alternate header directory;
`LANIUS_VULKAN_LOADER` can name the loader file. `VK_LAYER_PATH` and
`LD_LIBRARY_PATH` can locate a separately unpacked validation layer. For these
receipts, headers/layers are under `target/stdlib-work/vulkan-sdk`; no system
packages were changed. Each command is bounded below two minutes.

### Separate compiler-harness observation

An intermediate seven-test invocation reported all generated executables
passing, then the **parent Rust compiler/test process** aborted with
`corrupted double-linked list` (`target/stdlib-work/gpu-features-tests.log`).
Another earlier run printed `NVVM compilation failed: 3` after test completion.
The later full eight-test invocation above exited cleanly. Neither observation
is attributed to a particular compiler/driver defect without further evidence;
the aborted invocation is not counted as a passing suite receipt. The command
above, with the recorded dependency environment, is the available aggregate
reproduction attempt. A deterministic minimal reproducer remains open. No
compiler, IR, extractor, proof or x86 ABI changes were made in this increment.
Other GPUs/software drivers/platforms and hardware device loss remain unverified.
