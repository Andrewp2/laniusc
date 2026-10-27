# Owned HTTP URL planning fixtures

All three programs have passed direct GPU-compiler compilation and native
execution. Rust integration registrations are authored and have not been run.
These fixtures exercise the actual public `ext::http_url` and `ext::host_name`;
DNS, socket adoption, HTTP, HTTPS, NSS and the URL-client program have separate
acceptance gates. The public API guide is [Owned HTTP URL planning](../../../../docs/extended-http-url.md).

## Accepted direct receipts

| Program | Actual receipt | Finite scope |
| --- | --- | --- |
| `contracts.lani` | `target/stdlib-work/http-url-contracts-compile-first.log`: compile exit 0; `http-url-contracts-native-first.{trace,log}`: native exit 0, empty stdout/stderr | Public imports, copied snapshots, actual negative and positive signed strides with nonzero starts/canaries, DNS and IP getters, exact authority/target/port spelling, rejected logical ranges/limits/policies, inactive getters and idempotent destroy |
| `model.lani` with `model.py` | `http-url-model-compile-first.log`: compile exit 0; `http-url-model-native-first.log`: exactly `http-url model cases=70 layouts=2` | 70 authored semantic records, each on two real backing layouts, in one batched native process |
| `ownership.lani` with `owners.py` | `http-url-ownership-argument-retry.log`: compile exit 0, empty log; `http-url-owners-first.log`: exactly `http-url owners cases=16 reached-oom=4`, after its evidence-path line | Two ordinary baselines, four individually reached constructor OOM denials, and ten preflight rejections with every mmap denied |

The contracts trace has 18 lines: successful launch, eight source allocations,
eight matching releases, and raw `exit(0)`. It contains no other host operation.
This is successful allocation/cleanup evidence, not reached OOM evidence. The
semantic model and owner probe deliberately use stdin/stdout test transport.
These direct receipts are not Rust libtest passes; the registrations need not
rerun these programs solely to change their receipt format. The 16 owner group
cases include baselines and failure contexts, rather than 16 independent
properties. Owner evidence is retained at
`/tmp/lanius-http-url-owners-n__fsohc`.

The model is a fixed component/error catalog, not a second URL parser. Expected
host, authority, target, scheme, port, numeric identity octets and complete
public diagnostic projections are supplied independently. Python `ipaddress`
packs an explicitly supplied expected IP identity and never parses the input
URL. Cases distinguish strict numeric IPs from legacy numeric spellings, DNS
label/total limits, explicit default/zero-padded ports, empty path/query,
fragments, literal escapes/dot segments/slashes, syntax-before-policy errors,
typed underlying URI errors, target limits, invalid limits and logical ranges.

The native probes overwrite caller URL bytes after parse, then read all result
components. Both actual layouts start at element three: native `u8` stride is
negative, packed byte stride is positive one. Canaries outside the selected
range remain intact. Returned views are used only while the URL owner is live.
Destroy is checked twice and all Option getters must return None afterward;
the probes never create a second cleanup authority by copying the owner.

Executed source and artifact identities:

```text
host_name.lani  d7fae97246446f28fe6091a8bba0944f89df5346c268aea55906965060fbdf71
http_url.lani   b73ff204043bcb2e752f41e51b46a7f0abf2c0dfb26cd6b362e106d24c9864f4
contracts.lani b7750c38ea6c54ac1ca68a885dbd9b0d506231176ec74f90e7809ff38b833289
contracts ELF  247a3a98ac23af177db45ce7b8cda82abca235a9acda69279f1370457952f4ca
model.lani     4d2eea5ccf32b7baef31ad824c6fff4546235b5f882bf4579b66c51a6aa19f11
model.py       49757de7bebc8e5d17c179752a2cfa852e7868ed333ede9a7363a5886b42643f
model ELF      bad5bffe175767d11489849538d5244ad38adee4f99e456442ec650c294918f8
ownership.lani 44d781b7c3f05148fdffc183737a1d3d2e30cfaa1715af6b5a11ea96bf6f4a25
owners.py      9a45dd25c28e96587a03f2129ad57efa81c4613fb1c646a453c9b7e95a97ce99
ownership ELF  ee4db1c479576f86c5e4134b3a626ff57fff0e9ce2f21939b5146edb09098f94
Rust driver    125ed5986d56968c8122496312db49cdb7e417b045bd6ace4f21ade79c8459b0
```

Current `http_url.lani` is
`244725429cf192de727c2d2af3805e5011ee08284948d59663cd3f3ffa65caca`.
Only its two leading comments changed to clarify allocator host effects;
algorithm/API are unchanged. The executed source identity remains `b73ff204…`.
Here, pure URL planning allows allocator backing and excludes host services.

Before the first compile, one fixture-only assumption was corrected: the shared
DNS helper returns successful `Ok(0)`, rather than a byte count. The plan did not
promise a byte count. All URL assertions stayed unchanged, and no failed native
or compile receipt preceded the accepted semantic runs.

## Accepted owner/OOM gate

The first ownership-only compilation stopped before native execution with
LNC0006 in `http-url-ownership-compile-first.log`: the fixture supplied
`View<i64>` to the public Linux call API, whose actual argument type is
`View<std::linux::Argument>`. The corrected fixture supplies a zero-length view
over one `Argument::Word(0)` slot. No production/compiler code or runtime
assertion changed. The accepted contracts/model programs are unchanged.

`ownership.lani` uses the same bounded test request layout, plus two live ACK
checkpoints. Frame one reports the real PID, backing stride, constructor
diagnostic or copied components. The process remains alive with a successful
URL owner, or after complete partial-construction cleanup on failure. After ACK
`A`, a successful owner is explicitly destroyed twice and every getter is
checked inactive. Frame two then blocks for another `A` before process exit.
The host checks source mappings and `/proc` ownership before each ACK; exit
cleanup cannot make a leaked owner pass.

`owners.py` reuses the current exact ELF source-allocation verifier through
`archive_source/ledger.py` and `stdlib_execution/temp_file/ledger.py`. It adds no
opcode scanner or allocation classifier. The shared verifier binds exact
post-instruction sites, per-site `0x22`/`0x62` profiles, full-width addresses,
original requested sizes and corresponding successful releases.

Two ordinary DNS/IPv6 baselines derive the actually reached source allocation
positions. Each position is denied separately. The injected failure must be
marked reached and match the baseline's exact preceding source allocation
prefix, instruction address, syscall ordinal and allocation arguments. No
fixed allocation-count floor is used. Failure must return AllocationFailed
with offset -1 and leave no source owner before the first ACK. The ten local
rejection profiles run with every mmap denied and must attempt none: this
checks preflight priority, not OOM recovery. Between the live and released
checkpoints, getters/destroy may free mappings but must allocate none.

The owner gate records all syscalls. Only the checked successful launch and
final raw exit are removed before shared accounting; any other operation
besides source mappings, stdin/stdout and test PID observation fails the pure
operation guard. It also checks exact pre-exit file descriptors and the physical
absence of explicitly released source ranges. The wrapper's group deadline is
65 seconds, each child sequence seven seconds, and Rust's outer deadline is
75 seconds. Failure keeps requests, commands, traces and output prefixes under
a printed evidence directory.

CPU-only controls have passed: ten fixed-catalog comparator/framing/name
controls, and 27 owner controls (17 reused live-ledger controls plus ten focused
full-trace/reached-prefix controls). These are not Lanius runtime acceptance.
The negative controls reject changed same-case output bytes, unexpected host
work, duplicate launch, wrong I/O descriptor, nonzero exit, changed allocation
IP/size/ordinal and a missing injection marker.

## Bounded commands and filters

Root serializes compiler/native commands. Reuse an already compiled artifact
where available; every command remains below two minutes.

```sh
python3 -B tests/fixtures/extended/http_url/model.py controls
python3 -B tests/fixtures/extended/http_url/owners.py controls
timeout --kill-after=2s 25s python3 -B tests/fixtures/extended/http_url/model.py /absolute/path/to/model
timeout --kill-after=2s 75s python3 -B tests/fixtures/extended/http_url/owners.py /absolute/path/to/ownership
```

Rust filters in `extended_http_url_execution`:

```text
http_url_public_snapshots_numeric_identities_strides_and_destroy_execute
http_url_components_and_diagnostics_match_fixed_semantic_catalog
http_url_reached_constructor_oom_and_preflight_release_before_exit
```

Supported evidence so far is GPU-compiler output executed on Linux x86_64 CPU.
There is no GPU-device execution, NSS/network/TLS acceptance, independent
fixture-review receipt or maximum-default-size performance claim here.
