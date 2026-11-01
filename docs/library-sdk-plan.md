# Relocatable development SDK plan

This increment addresses the roadmap's binary SDK distribution gap. It does not
complete the standard-library goal or establish a stable release channel.

## Contract

Build a Linux x86_64 alpha development snapshot from an explicitly supplied,
quiescent compiler build and this source tree. The SDK must work after relocation
with the original checkout, build and initial SDK paths hidden. Programs produced
by the compiler execute as native x86_64 Linux programs; this does not establish
device execution of library programs or compatibility with arbitrary Linux hosts.

The compiler launcher derives its prefix through PATH and symlinks, selects the
bundled shaders and forwards every argument unchanged with `exec`. Library roots
are explicit compiler arguments. Do not duplicate the compiler's mode parser or
inject roots into package, lock, daemon or other compiler commands.

Reuse `tools/pin_laniusc.py` through a fresh temporary pin directory, the existing
`tools/lanius-test` driver and `tools/vendor_lanius.py` package resolver integration.
The suite launcher supplies the existing environment defaults; explicit caller
overrides remain effective. The vendor launcher supplies the compiler default.

## Layout and implementation boundaries

```
SDK/
  bin/{laniusc,lanius-test,lanius-vendor,lanius-sdk-verify}
  libexec/laniusc
  shaders/                         # all SPIR-V, reflection and metadata files
  share/lanius/
    stdlib/ extended/ docs/
    examples/{calculator,hash,suite}/
    calculator.package.json        # roots confined beneath share/lanius
    tools/                         # existing drivers and SDK helpers
    LICENSE-MIT LICENSE-APACHE
    data/unicode/17.0.0/LICENSE.txt
    third_party/rust-dec2flt/{LICENSE-MIT,LICENSE-APACHE,NOTICE.md}
  notices/                         # dependency and toolchain notices/metadata
  SDK.json
  SDK.txt
  SHA256SUMS
```

Keeping the existing vendor helper under `share/lanius/tools` preserves its
notice lookup convention. Package manifests must not contain absolute or `..`
roots; the compiler already rejects those. The calculator manifest lives above
its example and library roots. Examples reuse the existing calculator and
OpenSSL EVP hash implementation, plus a small two-case explicit source suite.

Root owns this plan, Cargo registration if required, integration, native runs and
release receipts. Agent ownership:

1. Builder: `tools/build_lanius_sdk.py`; CLI `--target-dir DIR --profile PROFILE
   --out NEWDIR --cargo-metadata FILE --rust-sysroot DIR`, and read-only
   `--verify SDK`. Import the two helper modules below.
2. Launchers: `tools/lanius_sdk_launchers.py`; `install_launchers(stage: Path)`.
3. Examples: `sample_programs/library/sdk_suite.lani` and SDK example manifests
   if needed; coordinate the exact suite names/output with native tests.
4. Host tests: `tools/test_build_lanius_sdk.py`.
5. Isolation: `tests/support/library_sdk_isolation.rs`.
6. Native tests: `tests/library_sdk_execution.rs`.
7. Payload/docs: `tools/lanius_sdk_payload.py`, `docs/library-sdk.md`, and concise
   overview/roadmap integration. Interface
   `populate_payload(source_root, stage, cargo_metadata, rust_sysroot) -> dict`
   copies libraries, selected documentation, example sources/manifests, six
   existing source notices, and compiler/toolchain dependency notices. Its
   returned metadata describes the source and notice inventory. Builder copies
   helper tools separately. Coordinate interface changes before using them.
8. Independent review: plan, changed sources, acceptance evidence; no owned edits.

## Integrity, identity and failure

Do not equate the compiler's shader metadata digest with binary build provenance.
Record the supplied binary SHA-256, every shader/reflection file hash and the
verbatim successful compiler version output. Validate shader/reflection pairs
and declared counts. Separately record source revision/dirty state and payload
hashes. The source revision is not a claim about which commit built the binary.

The supplied Cargo metadata and Rust sysroot describe notice inputs, not proven
binary provenance. Copy conservative locked dependency notices and report their
origin and any gaps explicitly; do not silently omit required inputs. No registry
or cryptographic authentication is introduced: SHA-256 inventories detect changes.

Refuse an existing output (including symlinks), reject symlink/nonregular input
payloads, bound file counts and sizes (8,192 files, 512 MiB payload, 8 MiB manifest),
detect source/build changes during snapshot, and clean up only newly created
staging paths after ordinary failure. A killed build may leave incomplete staging;
it must not be accepted as a finished SDK. Verification is read-only, never runs
payload executables, and rejects missing, extra, changed, unsafe or duplicate files
and changed executable modes. It must work with only the installed helper files.

SDK documentation keeps bundled links local and converts omitted committed source
references to immutable revision links. Uncommitted/build-artifact references must
not be represented as published evidence. Historical checkout commands remain
clearly identified as such. Root human documents are not edited or regenerated.

## Acceptance

Host tests cover transparent argument forwarding and relocated PATH/symlink
launches; exact payload/integrity behavior; malformed/missing assets; existing
destination preservation; and ordinary failure cleanup. These are packaging
tests, not Python implementations of library algorithms.

Four focused native gates cover (1) calculator compilation/execution, (2) native
OpenSSL SHA-256 execution, (3) installed suite listing/filtering/pass/missing-filter
exit status, and (4) selective vendoring, relocating the bundle, regenerating its
lock and compiling/executing it. Each gate uses fresh external work/cache paths,
hides original checkout/build/staging locations with bwrap, requires positive
installed compiler/source/tool/shader trace evidence as applicable, validates ELF
output and checks exact runtime output. Start with a small cold compilation to
check the command-time bound before larger examples.

Root alone executes Cargo/compiler/native commands, serially under
`target/stdlib-work/library-gpu.lock`. Every outer command is capped at 100 seconds.
No broad GPU/performance reruns, compiler changes, root README edits, formal-proof
changes or changes to protected vec/mem/common test support belong to this slice.
Record exact results and limitations before committing and pushing the reviewed
manifest to `origin/codex/stdlib`.

## Implementation adjustments

- The two exact Rust copyright inventory inputs may be up to 32 MiB each; the
  supplied toolchain's `COPYRIGHT.html` is about 14 MiB. Other input documents and
  SDK manifests retain the 8 MiB limit, and the total stays at 512 MiB. The first
  real build rejected the legitimate larger notice and cleaned up its staging.
- Notice coverage follows the complete supplied Linux Cargo resolution: 148
  packages. Its package/node/edge identities must agree with the source lockfile;
  92 locked packages outside this target/feature selection are listed separately.
  No selected-package notice gap remains in the candidate.
- Registered native SDK gates are explicitly ignored until selected with
  `--ignored` and `LANIUS_SDK_TEST_ROOT`. A missing SDK is then a hard failure.
  The standalone trace-parser control runs without an SDK.
- Build the test harness with `CARGO_PROFILE_DEV_DEBUG=0` and
  `CARGO_PROFILE_TEST_DEBUG=0`, and keep the chosen compiler snapshot separate
  from a Cargo target directory that subsequent builds can replace. The first
  harness build selected a different profile; no compiler-source change was
  made. Compiler identity is always recorded by hash.
- The observer uses `strace --seccomp-bpf -ff -yy -e trace=%file`. Filtering
  unselected syscall stops preserves the same file evidence with lower overhead.
  Two earlier calculator attempts timed out during initialization under ordinary
  ptrace tracing. The corrected observer passed on the same pinned candidate
  with fresh caches and the unchanged 80-second compile cap. These observations
  are acceptance history, not a compiler performance benchmark.

The [SDK guide](library-sdk.md) records the final focused receipts and remaining
distribution/target dependencies. Documentation can be rebuilt after acceptance
when every executable, source, shader and tool payload hash is compared with the
tested candidate; that does not extend the executed target matrix.
