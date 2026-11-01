# Relocatable development SDK

The SDK packages a supplied Linux x86_64 compiler build with its shaders,
Lanius library sources, contract guides, examples and distribution tools. It is
an **alpha development snapshot**, not a stable release or a promise that every
library API works on every target. The compiler's own `--version` output retains
its source-worktree/development status.

Packaging controls and all four relocated calculator, OpenSSL, explicit-suite
and selective-bundle workflows pass on the documented host. The
[plan](library-sdk-plan.md) defines the focused acceptance scope. Existing
[source-distribution receipts](library-distribution.md) retain their original
scope; current SDK evidence is listed below.

## Requirements

Compilation requires a compatible Linux x86_64 host, Vulkan loader and GPU/driver
supported by the supplied compiler. Its bundled shaders run compiler work;
these examples produce ordinary native Linux x86_64 programs. They do not run
the library application on a GPU.

The supplied debug binary's symbol versions require glibc 2.39 and libgcc symbols
through `GCC_4.2.0`. A compatible dynamic loader, libc and libgcc are required;
glibc 2.39 alone does not certify a distribution. The current development host is
Ubuntu 24.04.5 LTS. Other distributions and drivers need their own validation.

Launchers require Bash and GNU `readlink`. The bounded commands below and the suite driver require GNU
`timeout`; vendoring and inventory verification require Python 3.11 or newer. Native C
linking needs a working system C linker/toolchain. The hash example additionally
needs OpenSSL 3 development/link files and its runtime `libcrypto`. The SDK does
not bundle system Vulkan, libc or OpenSSL. A generated program needs only its
own selected host dependencies; the calculator and small suite do not require a
GPU to execute.

## Install and verify

Move or copy the whole completed directory, then set `SDK` to its new absolute
path. No registration or root privileges are required. Keep generated binaries,
locks and application edits outside the SDK so the original inventory remains
valid.

```sh
SDK=/absolute/path/to/lanius-sdk
timeout --kill-after=2s 100s "$SDK/bin/lanius-sdk-verify"
"$SDK/bin/laniusc" --version
```

`lanius-sdk-verify` accepts no arguments and verifies its own resolved prefix.
Verification reads files without executing payload programs. It rejects changed,
missing, extra, symlinked or unsafe files and changed executable modes. SHA-256
records detect changes; they are not signatures or authentication of a publisher.

The compiler launcher works through PATH and external symlinks. It selects the
bundled shader directory and forwards arguments unchanged. Library roots are
explicit in compiler arguments or a package manifest. The suite launcher uses
`LANIUSC`, `LANIUS_STDLIB_ROOT` and `LANIUS_SOURCE_ROOT` when supplied, otherwise
its installed defaults. The vendor launcher defaults `LANIUSC` to the installed
compiler; its `--compiler` option still wins. Overrides can intentionally select
external inputs and therefore change the relocation guarantees.

## Compile a calculator

The included manifest uses confined relative paths beneath `share/lanius`:

```json
{
  "package": "sdk.calculator",
  "roots": ["extended", "examples/calculator"],
  "stdlib_root": "stdlib",
  "entry": "examples/calculator/app/main.lani"
}
```

Neither absolute paths nor `..` roots are permitted. The entry declares
`app::main`. Build from any working directory:

```sh
timeout --kill-after=2s 100s "$SDK/bin/laniusc" --emit x86_64 \
  --package-manifest "$SDK/share/lanius/calculator.package.json" -o ./calculator
printf '1+2*3\n-(5+6)\n' | timeout --kill-after=2s 10s ./calculator
```

Expected stdout is `7` and `-11`, each followed by LF. The
[calculator guide](extended-expr-calc.md) describes its grammar and errors.

## Hash bytes through OpenSSL

```sh
timeout --kill-after=2s 100s "$SDK/bin/laniusc" \
  --native-link --native-library crypto \
  --package-manifest "$SDK/share/lanius/hash.package.json" -o ./openssl-hash
printf abc | timeout --kill-after=2s 10s ./openssl-hash sha256
```

Expected stdout is
`ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`
followed by LF. [OpenSSL EVP](extended-openssl-hash.md) supplies the sensitive
implementation; the SDK sample only uses the existing native binding.

## Run an explicit source suite

```sh
timeout --kill-after=2s 100s "$SDK/bin/lanius-test" \
  "$SDK/share/lanius/examples/suite/app/main.lani" --list
timeout --kill-after=2s 100s "$SDK/bin/lanius-test" \
  "$SDK/share/lanius/examples/suite/app/main.lani" --filter 'checked arithmetic'
```

The suite names are `checked arithmetic` and `UTF-8 text`. An unfiltered run
executes both; a filter selecting neither returns status 3. This reuses the
[explicit source-suite driver](stdlib-development.md), not automatic discovery or
runtime registration. Its existing compile/run time limits and caller overrides
remain in effect.

## Make a selective source bundle

```sh
timeout --kill-after=2s 100s "$SDK/bin/lanius-vendor" \
  --manifest "$SDK/share/lanius/calculator.package.json" --out ./calculator-bundle
mv ./calculator-bundle ./calculator-relocated
timeout --kill-after=2s 100s "$SDK/bin/lanius-vendor" --verify ./calculator-relocated
timeout --kill-after=2s 100s "$SDK/bin/laniusc" package lock \
  --manifest ./calculator-relocated/lanius.package.json -o ./calculator.lock.json
timeout --kill-after=2s 100s "$SDK/bin/laniusc" \
  --package-lockfile ./calculator.lock.json -o ./calculator-locked
printf '1+2*3\n-(5+6)\n' | timeout --kill-after=2s 10s ./calculator-locked
```

The destination must be new. [Vendoring](library-distribution.md) copies only
reachable Lanius sources and notices, then verifies the relocated package.
Locks contain absolute paths: create them after relocation and outside the
immutable bundle. This provides no registry or external dependency resolver.

## Package contents and identity

| Location | Contents |
| --- | --- |
| `bin/` | Compiler, source-suite, vendor and verifier launchers |
| `libexec/laniusc`, `shaders/` | Supplied compiler and inventoried shader/reflection assets |
| `share/lanius/stdlib`, `extended` | Lanius standard and extended sources |
| `share/lanius/docs` | Contract guides, declaration reference and linked guide closure |
| `share/lanius/examples` | Calculator, OpenSSL hash and explicit source suite |
| `share/lanius/*.package.json` | Confined manifests for those examples |
| `share/lanius/tools` | Existing tools and SDK helpers |
| `notices/` | Cargo dependency and Rust compiler/runtime notice inputs |
| `SDK.json`, `SDK.txt`, `SHA256SUMS` | Identity, requirements and complete integrity inventory |

`SDK.json` distinguishes the supplied executable hash, shader hashes and
verbatim compiler version from the library/document source revision and dirty
state. A source revision does not prove which revision built an executable.
Changed working-tree content is recorded as a development snapshot.

The notice inventory covers the supplied Cargo resolution, checked against the
source lockfile. Generate the metadata with `--filter-platform
x86_64-unknown-linux-gnu`; every selected graph node, dependency and workspace
identity must have matching package metadata. Every selected name, version and
source must occur in the lockfile. The current selection contains 148 packages;
the other 92 locked target/feature packages are listed separately as outside
that supplied resolution, with no claim their notices are included. It includes package manifests, available dependency notices,
and Rust compiler/runtime copyright and license texts. Seven upstream overlays
supply missing packaged notices; their provenance distinguishes original upstream
files from unchanged standard license texts accompanying upstream declarations.
Any missing package notice is listed explicitly. These inputs describe the
notice collection, not verified binary dependency provenance or legal
certification. Existing repository MIT/Apache, Unicode and float-conversion
notices keep their paths so selective vendoring can carry them forward.

## Documentation boundaries

The SDK includes the generated API reference, its registered contract guides,
entry guides and their linked Markdown guide closure. Bundled library-source
and guide links remain local. Links to omitted unchanged committed tests, examples,
compiler or proof files become immutable links to the recorded repository
revision. Those require internet access. Modified tracked files, untracked files, local build outputs
and other unpublished references link here instead; the generated
`share/lanius/docs/sdk-unbundled-references.json` records their original targets.
They are not published runtime evidence.

Each shipped Markdown file identifies itself as an SDK snapshot. Historical
checkout commands, test paths and build receipts retain their historical scope;
use this page's commands for installed workflows. The SDK does not copy the
whole repository, test corpus, build outputs or Git history. Human root README
and policy files are not rewritten or used as generated inventories.

## Build a snapshot

From a quiescent source tree with an already built compiler and shader set:

```sh
timeout --kill-after=2s 100s python3 tools/build_lanius_sdk.py \
  --target-dir target/stdlib-build --profile debug \
  --out /absolute/new/sdk-directory \
  --cargo-metadata /absolute/path/to/cargo-metadata.json \
  --rust-sysroot /absolute/path/to/rust-sysroot
```

The Cargo metadata JSON and Rust sysroot must already exist. Packaging invokes
the existing pin helper and compiler version query; it does not rebuild the
compiler or download dependencies. It refuses an existing output, symlink or
nonregular inputs, missing required files, inconsistent shader/reflection
metadata and inputs changed during the snapshot. Limits are 8,192 files,
512 MiB total payload and 8 MiB per manifest or ordinary input document.
The two Rust copyright inventories have a separate 32 MiB limit each. Source and build
inputs must stay quiescent until publication. Ordinary failures remove only
new staging paths. A forcibly killed build may leave incomplete staging, which
must not be treated as a verified SDK.

## Acceptance and remaining work

The accepted candidate has content ID
`2307c633d48e1b3fdf79398b0a922a6f84f75a7d5223313cffe4dc6a875e2c4e`,
compiler SHA-256
`1c2718d4c17b7da613f999412bff037eef3770cb755a74e35e7eebd2cfc202f6`
and 923 shader pairs with reported digest `3dbb4ecf759bf00c`. Its manifest has
4,205 payload records totaling 169,631,649 bytes: 276 library sources and three
Lanius examples, one Bash support file, 675 Markdown files, 148 selected Cargo
packages, seven notice
overlays and 14 Rust notice files. No selected-package notice gap is reported;
92 other locked packages remain explicitly outside the supplied resolution.
These counts describe this candidate, not a fixed SDK format requirement.

Thirty focused host controls pass in 5.136 seconds, including malformed assets,
metadata truncation, exact manifests, relocated launchers, restored-mtime content
changes, FIFO/symlink rejection, size limits and ordinary failure cleanup. These
use controlled compiler probes and do not substitute for native compilation.
The trace-observer parser control passes separately.

| Native gate | Accepted scope | Test time |
| --- | --- | --- |
| Calculator | Core/extended compilation and one exact-output execution | 68.12 s |
| OpenSSL | Native-linked SHA-256 of `abc`, one execution and actual `libcrypto` open | 66.93 s |
| Source suite | Three executions: pass, list and missing filter; exact output/status 0/0/3 | 74.96 s |
| Selective bundle | Vendor, relocate, regenerate lock and execute one exact-output calculator | 71.93 s |

Each gate copies and renames the SDK outside the checkout, hides original
checkout/build/SDK paths with bubblewrap, starts a fresh unseeded driver cache,
and requires successful installed source/tool/shader opens and executable-path
witnesses. Later commands within one gate may reuse that gate's cache. The
observer uses `strace --seccomp-bpf` with the same file/process evidence checks;
this is finite relocation evidence, not a claim that every host syscall or
library behavior was tested. Retained calculator/hash/vendor ELF boundaries and exact application outputs
are checked; the suite driver removes its ELF, so that gate instead witnesses
successful generated-suite execution and its exact reports. Native times include setup and compilation and are not
application throughput measurements. Successful gates retire their private SDK
and cache copies while preserving logs and inventory evidence.

Two earlier calculator attempts each reached the 80-second compiler deadline
before application execution. The first used candidate `8e68052d…` with supplied
binary `f7cc18f7…` after a Cargo harness build replaced the earlier debug
artifact. The second used the final pinned compiler/candidate and also timed
out. The successful run retained the 80-second deadline and fresh cache while
using seccomp-filtered tracing; no compiler defect or unique timeout cause is
established. The original SDK build also rejected a legitimate 14 MiB Rust
copyright inventory under the old 8 MiB input cap; the explicit 32 MiB exception
for the two Rust copyright files corrected that packaging bound.

Receipts are `target/stdlib-work/sdk-host-tests.log`, `sdk-isolation-host.log`,
`sdk-native-calculator-final.log`, `sdk-native-openssl.log` and
`sdk-native-suite.log` and `sdk-native-vendor.log`. Earlier calculator attempts remain in
`sdk-native-calculator.log` and `sdk-native-calculator-pinned.log`. These are
local build receipts, not shipped log files.

### Reproduce one native gate

The four SDK tests are ignored in ordinary Cargo runs because they require an
assembled SDK. An explicit run fails if `LANIUS_SDK_TEST_ROOT` is missing. They
also require bubblewrap, strace with seccomp filtering, a compatible Vulkan
host and the selected native link dependencies. Build the harness separately,
keeping its debug settings consistent so it does not replace the supplied
compiler with a different profile:

```sh
export CARGO_TARGET_DIR="$PWD/target/stdlib-build"
export CARGO_PROFILE_DEV_DEBUG=0
export CARGO_PROFILE_TEST_DEBUG=0
timeout --kill-after=2s 100s cargo test --test library_sdk_execution --no-run
SELECTOR=relocated_sdk_compiles_core_and_extended_calculator
timeout --kill-after=2s 100s env LANIUS_SDK_TEST_ROOT="$SDK" \
  cargo test --test library_sdk_execution "$SELECTOR" -- \
  --ignored --exact --nocapture --test-threads=1
```

Run one selector per bounded command:

- `relocated_sdk_compiles_core_and_extended_calculator`
- `relocated_sdk_links_and_executes_openssl_service`
- `relocated_sdk_source_suite_driver_lists_filters_and_propagates_status`
- `relocated_sdk_vendors_and_executes_selective_package`

The four gates total six application process executions, separate from the
30 host controls and one parser control. The parser control is default-enabled;
host packaging controls are in `tools/test_build_lanius_sdk.py`. Current
acceptance is limited to the supplied debug compiler and the tested Linux
x86_64 host/driver; release/embedded shader builds and other hosts need separate
evidence.

A documentation-only distribution rebuild has its own content ID. These native
receipts apply to its runtime/tool payload only after every non-document
payload path, byte hash and mode is compared with the tested candidate. Such a
comparison is packaging evidence, not an additional native execution or proof
that a different compiler is equivalent. The rebuilt inventory still records
its own source revision, dirty state and documentation bytes.

A stable signed release channel, broader host/target validation, registry
resolution, automatic test discovery, complete semantic guide coverage and
formal verification remain separate work. See the
[whole library roadmap](library-roadmap.md).
