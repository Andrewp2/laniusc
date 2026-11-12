# Game of Life on GPU textures

[`gpu_life.lani`](../sample_programs/library/gpu_life.lani) is an interactive
Game of Life using `ext::gpu` and `ext::window`. It keeps a 256×160 board in two
RGBA8 textures. The CPU creates the initial seed; compute shaders evolve every
subsequent generation, and a fragment shader displays the latest texture.
There is no per-generation CPU simulation or readback in the application.

## Run

The executable built in this workspace is `target/stdlib-work/gpu-life`:

```sh
./target/stdlib-work/gpu-life
```

Controls are shown in the window title:

- **Space:** pause/resume.
- **Right arrow:** pause and advance one generation.
- **R:** restore the same initial seed, keeping the pause state.
- **Escape** or window close: exit.

The simulation targets 20 generations per second. It waits for outstanding
frame/work tickets before advancing again, and does not accumulate a catch-up
backlog if the driver or window is slow. Rendering continues while paused, so
resize and expose events still produce frames. The board stays 256×160 and
scales to the window; resizing does not change the simulation. Edges wrap in
both directions.

`--frames N` presents N frames and exits, for N from 1 through 600. Frames are
not generations: paused and repeated frames count too. Malformed arguments
exit with status 2 before opening a display. Runtime failure exits with status
3; normal close/frame-limit exits with status 0.

Rebuild from the repository root:

```sh
timeout --kill-after=2s 100s target/release/laniusc \
  --native-link --native-library X11 \
  --native-object /lib/x86_64-linux-gnu/libvulkan.so.1 \
  --stdlib-root stdlib --source-root extended \
  --source-root sample_programs/library \
  sample_programs/library/gpu_life.lani -o target/stdlib-work/gpu-life

timeout --kill-after=2s 25s target/stdlib-work/gpu-life --frames 60
```

It uses the existing [Linux x86_64 Vulkan/X11 profile](extended-gpu.md), including
swapchain-maintenance support and trusted shaders. This is a Lanius application
using precompiled GLSL compute/graphics shaders; it does not add a Lanius shader
compiler. No compiler or GPU-library changes were needed for the example.

## Generation and synchronization

The [compute shader](../sample_programs/library/shaders/life.comp) uses Conway's
B3/S23 rule: dead cells are born with three live neighbors; live cells survive
with two or three. All changes use the previous generation, as specified in
[Gardner's original account of Conway's game](https://www.ibiblio.org/lifepatterns/october1970.html).
The finite wrapping board is a deliberate variation on its infinite plane.

Each invocation owns one output cell. It reads eight neighbors from one
storage texture and writes the next state into the other. Two immutable bind
groups represent A→B and B→A. After successful submission, the application
switches which texture it displays. It never binds the same texture as input
and output for a generation. Workgroups are 8×8, with a bounds check for
partial edge groups. Red stores alive/dead as 255/0; green/blue are zero and
alpha is 255 after evolution. Display colors are applied separately.

Texture uploads occur at initialization and reset only. A fixed xorshift seed
produces a reproducible starting board at approximately 30% occupancy. Reset
uploads the retained seed buffer into A and clears B. A new simulation/reset
is admitted only after the previous compute and frame tickets retire.

Compute and graphics submit to the same queue. The library's barriers make
the new texture visible to sampling without a CPU wait between those two
submissions. The event loop polls tickets and processes window events while
work is pending. Scene owners retain partially created resources and pending
encoders/submissions so cleanup can respect the library's lifetime rules.

The [vertex](../sample_programs/library/shaders/life.vert) and
[fragment](../sample_programs/library/shaders/life.frag) shaders scale the board
across the window. Cells have a green-to-blue display gradient and a small gap
when each cell has enough screen pixels. These colors do not affect Life state.

Regenerate the checked-in SPIR-V word arrays with
`python3 tools/generate_gpu_life.py`; `--check` checks reproducibility. The tool
uses glslang targeting Vulkan 1.1 and `spirv-val`, like the other GPU examples.

## Executable checks

Two focused tests pass on RTX 3090 with driver 615.71.09, XWayland, and required
Khronos validation/synchronization validation (layer 1.4.313):

- **Shader oracle:** 120 GPU generations across ten cases, including seeded
  37×23 boards, a stable block, a period-two blinker, a glider crossing wrapped
  edges, full/empty/single-cell boards, and 1×1 and 2×3 tori. Both one-step and
  three-step command buffers are exercised. A test-only C reference scatters
  neighbor counts from live cells, independently of the shader's gather loop.
  It compares exact RGBA output and checks known periods/glider translation.
  Initialization is submitted without waiting before the first compute work.
- **Actual application:** bounded exit, invalid arguments, and injected native
  key events. Dispatch counts establish that pause stops evolution, Right
  advances exactly once, reset performs another upload without a generation,
  and resume restarts compute. Native resize and close complete the trace.

On very small tori, each of the eight neighbor offsets is counted, even when
wrapping maps several offsets to the same cell. The small-board tests make
that convention explicit; the interactive board has distinct neighbors.

The first paired run passed in 6.35 seconds (`target/stdlib-work/gpu-life-tests.log`).
The later control-specific test passed in 3.94 seconds
(`gpu-life-controls-tests.log`). The standalone executable also ran 300 frames
without the C observer and with zero validation diagnostics. The rendered
window was inspected: the board fills the client area, cell colors and gaps
are visible, and the title's controls are readable. The capture is
`target/stdlib-work/gpu-life.png`.

Run the focused tests, using the dependency environment from the GPU guide:

```sh
LANIUS_GPU_REQUIRE_HARDWARE=1 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=85000 \
  timeout --kill-after=2s 100s cargo test --release \
  --test extended extended_gpu_execution::game_of_life \
  -- --include-ignored --test-threads=1
```

The tests are ignored by default because they require Vulkan development
headers, a driver/validation layer, and X11 for the application test. The
reference simulation and native event injection are test-only code.
