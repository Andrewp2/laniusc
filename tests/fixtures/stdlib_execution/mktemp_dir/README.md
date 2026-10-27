# Real temporary-directory application oracle

Status: all four tests pass 48 native process invocations across four groups
and two separate runtime commands. Counts include baselines/setup calls and
are not 48 distinct coverage properties. Production source is
`sample_programs/library/mktemp_dir.lani`; no test-only Lanius wrapper replaces
the command. The semantic guide is [Temporary-directory command](../../../../docs/stdlib-mktemp-dir.md).

Root runs the focused driver, serializing compilation/native work:

```sh
timeout --kill-after=2s 100s cargo test --test stdlib_mktemp_dir_execution mktemp_dir_creates_new_empty_private_directories_and_publishes_exact_names -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_mktemp_dir_execution mktemp_dir_argument_and_path_admission_has_no_creation_effects -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_mktemp_dir_execution mktemp_dir_all_reached_source_ooms_release_owners_before_exit -- --exact --nocapture
timeout --kill-after=2s 100s cargo test --test stdlib_mktemp_dir_execution mktemp_dir_reached_host_output_and_cleanup_failures_preserve_publication_truth -- --exact --nocapture
```

The same oracle can reuse an already compiled executable without recompilation:

```sh
timeout --kill-after=2s 70s python3 -B tests/fixtures/stdlib_execution/mktemp_dir/oracle.py normal /ABSOLUTE/COMPILED/ELF
```

Groups are `normal`, `arguments`, `allocations` and `faults`. Each native child
has a five-second deadline; each Rust oracle group has a 70-second deadline.
Normal cases use actual output to inspect type/mode/link count/empty
contents and repeat creation in the same parent. Admission cases include a real
closed-reader help pipe and the exact/over 4,095-byte argument cap. Allocation
positions come from the successful executable's verified source sites; no old
allocation floor or stage distribution is retained. Faults cover reached
signal/open/duplicate/stat/flags/entropy/mkdir/child-open sites, EINTR/EEXIST
recovery, entropy and write caps, all three closes, real EPIPE, and failed
empty removal with explicit recovery-name transfer. No unreached injection is
accepted as evidence.

The existing TempFile raw-ELF verifier is imported read-only. Source map/release
validation retains exact full-width addresses, allocator post-instruction
sites, flags and requested lengths. Local fd generations distinguish caller
parent, duplicate anchor and child. Injected failed closes are explicitly
tracked as logical retirement with skipped native close until process exit;
they never satisfy physical-close assertions. Source mappings must be freed by
the application, and all other logical descriptors must close before exit.
The oracle removes kept/recovery directories only inside its own temporary
work roots; evidence logs and namespace observations remain outside those work
subdirectories.

CPU-only preparation check:

```sh
timeout --kill-after=2s 100s python3 -B tests/fixtures/stdlib_execution/mktemp_dir/oracle.py controls
```

## Accepted finite receipts

Current profile: native Linux x86_64 emitted by the GPU compiler, kernel
`7.0.0-38-generic`, test-owned ext4 `/tmp` roots, explicit umask 0022. User GPU
kernels and other hosts are unverified. Logs are under `target/stdlib-work/`:

| Log | Result |
| --- | --- |
| `filesystem-mktemp-behavior-local-guard.log` | PASS two tests in 7.64s: arguments 13 and normal 5 process invocations. |
| `filesystem-mktemp-faults-first.log` | PASS two tests in 7.32s: allocations 4 (baseline plus all three reached source OOMs) and faults 26 process invocations. |
| `filesystem-mktemp-driver-first-build.log` | Driver `--no-run` admission in 1.14s; separate from native execution. |

Accepted source SHA-256 identities:

| Source | SHA-256 |
| --- | --- |
| `sample_programs/library/mktemp_dir.lani` | `118f9a78f53bdab02ad0ed014d226f2c4ba3560124da18eef5b25639160ab4b9` |
| `stdlib/std/temp_dir.lani` | `56898b00479c5051db959b5f05069b7435c337be0b96cfe47c997adaf2c994b6` |
| `stdlib/std/file_ops.lani` | `21269e340801c09396a133a43ea5f5391307a59de861476605a140f953530ab6` |
| `tests/stdlib_mktemp_dir_execution.rs` | `374da201a24031ee8764397baa47a73ae67403fa575d0b86f0172a534db86351` |
| `oracle.py` | `ca6a150271794d569ea9ab4d760fce40e8bac3fd345a68ac1b94aa9879b69786` |

Sixteen CPU controls separately pass injection reachability/result/site/request
binding, trace completeness, actual entropy/name derivation and source literal
lengths. Python source parses and the dedicated Rust file was formatted with
`skip_children=true`. Root ran the native gates; the fixture author made no
additional native/Cargo/GPU runs during documentation finalization.

The first selected two-test command failed before ELF/native admission in
2.56s (`filesystem-mktemp-behavior-first.log`). Its larger-import generic-bound
label did not locate the cause. The
[minimal cast/guard reproduction](../../stdlib_compiler_state/filesystem_imports/README.md)
isolates an ambiguous parser form in FileOps; an equivalent widened local
comparison admits the same behavior. App/TempDir sources stayed unchanged.
That failed command supplies no runtime acceptance, and the repair supplies no
general claim about all generic bounds/casts. The full library goal stays open.
