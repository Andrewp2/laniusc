# Response files

Status: contract frozen; implementation and focused executable gates accepted
on the native Linux x86_64 profile below.
The complete standard and extended library goal remains open.

## Purpose and source context

Add an opt-in preprocessing step that produces stable owned byte arguments for
both existing CLI parsers. Keep option recognition, command routing, required
values and `--` semantics in the canonical option parser.

[GCC documents](https://gcc.gnu.org/onlinedocs/gcc/Overall-Options.html) in-place
response-file expansion, whitespace/quotes/backslash and recursive references.
The [LLVM GNU tokenizer](https://llvm.org/doxygen/CommandLine_8cpp_source.html)
provides a concrete byte grouping/concatenation reference. This implementation
chooses strict malformed-input errors and explicit load failures rather than
GCC's unreadable-file fallback or LLVM's permissive unfinished strings.
[Java argument files](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html#java-command-line-argument-files)
provide precedents for literal `@@` and fixed-directory interpretation; their
other syntax and recursion policies are not adopted. This is a documented
Lanius format, not a drop-in compatibility promise.

## Three module boundaries

1. `ext::response`: pure byte tokenization and raw-offset mapping, with caller
   buffers, complete preflight and no allocation or host services.
2. `ext::cli_response`: owned expansion over a generic Lanius provider. It uses
   only core/alloc plus the pure tokenizer and canonical CLI Location type.
3. `ext::cli_response_files`: native Linux file provider, borrowing a directory
   descriptor and using existing FileOps, File and Read. No compiler/runtime,
   extraction, proof or ABI changes belong to this increment.

## Byte grammar

- ASCII space, tab, CR and LF separate tokens. Other bytes are literal.
- Matching single/double quotes group bytes, with adjacent bare and quoted
  pieces concatenated. Empty quoted tokens are retained.
- Backslash removes itself and quotes the next byte inside/outside either
  quote. Escaped newline is a literal newline, not line continuation.
- Reject NUL, a trailing backslash and an unterminated quote at their raw byte
  offsets. A final backslash takes precedence over an unclosed surrounding quote.
- No comments, variable/glob expansion, Unicode decoding or BOM conversion.
  Preserve non-UTF-8 bytes and literal `#`, `$`, `*` and `~`.
- Host argv entries are already tokens; they are copied without quote parsing.

## Pure API

```lani
pub struct Shape { tokens:i32, bytes:i32 }
pub struct Span { raw_start:i32, raw_length:i32, start:i32, length:i32 }
pub enum Error {
    Bounds, Nul(i32), TrailingEscape(i32), UnclosedQuote(i32),
    BytesTooSmall(i32), TokensTooSmall(i32), NotSingleToken, DecodedBounds
}
measure(input:View<u8>) -> Result<Shape,Error>
tokenize_into(input:View<u8>, bytes:View<u8>, spans:View<Span>) -> Result<Shape,Error>
raw_offset(token:View<u8>, decoded_byte:i32) -> Result<i32,Error>
```

`tokenize_into` checks the entire syntax, both output logical bounds and both
capacities before any write. It writes decoded bytes and spans only in the
required prefixes, preserves all other storage and adds no NUL. One traversal
implementation serves measuring and writing. Spans index the logical input and
decoded output, independently of their physical starts or signed strides.
Inputs and output stores must be live and mutually disjoint.

`raw_offset` requires exactly one token, with no leading/trailing separators;
it admits offsets 0 through decoded length. Real bytes map to their raw source
byte, skipping quote/escape syntax. The endpoint and empty token map to the raw
token end. Logical ranges are checked; physical backing remains a precondition.

## Expansion API and ownership

```lani
pub trait Provider<H> {
    pub fn load(&self, path:View<u8>, maximum_bytes:i32) -> Result<Vec<u8>,H>;
}
pub struct Origin { source:i32, argument:i32, start:i32, length:i32 }
pub struct SourceInfo { path:View<u8>, included_at:Origin, loaded:bool }
pub struct Limits {
    max_arguments:i32, max_tokens:i32, max_argument_bytes:i32,
    max_output_bytes:i32, max_file_bytes:i32, max_source_bytes:i32,
    max_files:i32, max_depth:i32, max_path_bytes:i32, max_work:u64
}
pub enum Cause<H> {
    InvalidState, Bounds, SourceLimit, TokenLimit, ArgumentLimit,
    ArgumentBytes, OutputLimit, FileLimit, DepthLimit, PathLimit,
    WorkLimit, AllocationFailed, ProviderContract,
    Syntax(ext::response::Error), Provider(H)
}
pub struct Failure<H> { cause:Cause<H>, at:Origin }
pub enum LocateError { NotReady, Bounds, WorkLimit, Syntax(ext::response::Error) }
empty() -> Expansion
default_limits() -> Limits
Expansion.borrow() -> &Expansion
Expansion.prepare<P,H>(arguments:View<View<u8>>, provider:&P, limits:Limits)
    -> Result<i32,Failure<H>> where P:Provider<H>
Expansion.is_ready() -> bool
Expansion.arguments() -> Option<View<View<u8>>>
Expansion.origin(index:i32) -> Option<Origin>
Expansion.original(index:i32) -> Option<View<u8>>
Expansion.source(index:i32) -> Option<SourceInfo>
Expansion.raw_source(index:i32) -> Option<View<u8>>
Expansion.locate(location:ext::cli::Location, maximum_work:u64) -> Result<Origin,LocateError>
Expansion.destroy()
```

An Expansion is one manual owner. Copies alias that authority. Preparation is
one-shot until destroy resets it; a second preparation returns InvalidState
without changing existing state. Initial limits, argv descriptors, aggregate
input bytes and NULs are checked before any provider call. Copy initial argv
before expansion; retain original snapshots, source paths/raw bytes/decoded
tokens and inclusion origins on success or failure. Partial output is never
published. After allocation failure only successfully captured storage is
retained; there is no promise to finish capturing argv after OOM. Returned
provider errors transfer their own ownership to the caller;
Expansion.destroy releases only expansion-owned storage.

Source IDs are zero-based response-file request indices. Source -1 denotes
original argv and `argument` selects its original index; file origins use
argument -1. `start/length` are raw token spans relative to that source or argv
entry. A sentinel (-1,-1,0,0) denotes failures without an identifiable input
location, such as invalid limits or initial work/token admission. Known argv
bounds/argument-byte failures identify that entry, and aggregate source-byte
admission identifies the first entry crossing the cap. A requested source
record and its path are retained before invoking the provider. A load error can
therefore identify that source even though loaded is false; failures while
creating a record identify the including token instead. On successful load the
provider transfers an independent Vec owner; it must not alias expansion/input
storage. Oversized successful provider output is destroyed and rejected.
The provider must not retain the borrowed request path. Content and returned
error-owned data must remain independent of expansion backing when they
outlive the call; no deep copy or error destructor is synthesized for H.

Store offsets while buffers grow; create final argument views only after all
backing is stable. `arguments` and `origin` return None before complete success.
`original`, source and raw-source views remain usable for captured diagnostics
after failure. Destroy invalidates every borrowed view and resets the owner.

`locate` translates the canonical parser's expanded argument index and decoded
byte offset by replaying the same tokenizer over the retained raw span. It
accounts for removed `@@` prefixes, validates endpoints and reserves raw span
length plus one work unit before replay. It never assumes decoded and raw
offsets are equal and allocates nothing.
The returned Origin has length one for a real mapped byte and zero for the
endpoint, including an empty argument.

## Expansion, paths and limits

Decoded `@path` splices a file depth first, in place. `@` alone is literal;
`@@text` removes one @ and emits literally without another expansion. Quoting
does not suppress expansion. `@-` names a file called `-`. Preprocessing applies
everywhere, including required-value positions and after `--`.

The provider interprets path bytes. The native provider uses one caller-supplied
base directory for all relative references, including nested ones; absolute
paths use normal host semantics. Ordinary operand/value paths are unchanged.
No path identity/canonicalization or cycle detector is supplied: active cycles
terminate with DepthLimit, FileLimit or a prior work/source limit. Completed
files can be read again and count again. Use an explicit frame stack rather
than recursive native calls. Load and close a whole file before opening a child.

Every signed limit must be nonnegative. Zero permits no resource in that
category; it is not an unlimited sentinel. Defaults are arguments4096,
tokens8192, argument bytes65536, output bytes1048576, file bytes1048576,
aggregate source bytes4194304, files64, depth16, path bytes4095 and work33554432.
Aggregate source bytes include initial argv and each loaded file occurrence.
All argv entries count against max_tokens before effects, and file tokens count
even when they are directives or empty. Output count and byte caps are separate.
max_argument_bytes applies to every decoded token, including directives, and
every original argv entry. All initial entries are checked before effects.
The file/path/depth/work grants are checked before invoking a provider.

Before a provider call, charge the file's one work unit and compute its byte
grant as the minimum of max_file_bytes, remaining aggregate source bytes and
remaining work divided by four. Zero grants still permit an empty file.
After a successful load, charge four times its actual raw length; the grant
already guarantees that fits. A successful Vec exceeding the grant is a
ProviderContract failure and is destroyed. A provider error is propagated
unchanged: a native ByteLimit can therefore reflect a smaller aggregate or
work grant. FileLimit describes the file-request count, not this byte grant.

Work units reserve initial argv bytes, four units per raw response byte plus
one per file, two units per decoded token byte plus one per token, and one per
final descriptor. Charges precede the corresponding engine work; provider
bodies, allocator internals and machine instructions are not literal work
units. Check arithmetic in u64. Metadata/count capacities also obey checked
Vec allocation limits. Retained storage is bounded by aggregate raw bytes,
decoded bytes, path/file/token/argument limits and allocator capacity growth;
there is no exact heap/RSS cap or automatic lifetime enforcement.

Reserve all initial argv token work along with its raw-byte charge before
copying. After a loaded file's raw charge and syntax measurement, admit its
complete token count and reserve all decoded-token work before allocating or
decoding. Check every decoded token's individual byte cap before visiting any
child reference. These bulk charges do not repeat on later token visits.

## Native provider

```lani
pub enum Phase { Admission, Open, Metadata, Read, Close }
pub enum Cause { Bounds, CallLimit, NotRegular, ByteLimit, AllocationFailed, Io(core::io::Error) }
pub struct Error { phase:Phase, cause:Cause, cleanup:Option<core::io::Error> }
files(directory_fd:i32, maximum_calls:u64, follow_symlinks:bool) -> Result<Files,Error>
Files.borrow() -> &Files
Files.calls() -> u64
impl Provider<Error> for Files
```

Directory fd must be live, borrowed and stable; AT_FDCWD is allowed only while
the caller keeps cwd stable throughout expansion. The provider never owns or
closes that base descriptor. Paths must be nonempty, NUL-free and at most4095
bytes. Open read-only with CLOEXEC, NONBLOCK and NOCTTY; use NOFOLLOW when the
caller disables symlink following. Validate regular-file type using descriptor
metadata before reading. Normal lookup is not a confinement boundary.

Count every actual open/metadata/read/close attempt, including EINTR. Before
opening, admit at least four credits and reserve one exclusively for close.
Open and metadata do not retry; interrupted reads retry only after another
credit. Read chunks of at most4096 bytes, establish actual EOF and consume at
most one byte beyond the byte cap. Metadata size is not EOF. All failure paths
close once after acquisition; first cause wins and simultaneous close error is
reported separately. Close is retired even on error and never retried. A close
failure after otherwise successful reading is primary. Returned failure keeps
no file/content owner. Calls are finite; filesystem wall time is not bounded.

## Executable acceptance

- Pure syntax goldens, raw bytes, exact malformed offsets, full preflight,
  buffer canaries, logical bounds and actual signed strides; exact raw mapping.
- Independent expansion/provenance sequences and limit boundaries, nested and
  repeated includes, cycles, @@ and immutable snapshots after input mutation.
- Both actual parsers consume one expanded argv, including required values and
  terminators; diagnostics map to real source bytes after quotes/escapes.
- Native files, fixed-base nesting, exact caps/EOF probe, symlink policy,
  missing/nonregular inputs, budget boundaries, short/EINTR/error reads and
  primary/close errors. All reached source allocation failures and explicit
  ownership are checked separately from CPU oracle controls.
- Migrate kv_tool with bounded opt-in preprocessing before database effects;
  preserve ordinary argv behavior and its existing store/publication workflow.
  Verify ordinary no-file-access errors, response-file reads followed by invalid
  CLI without database effects, and response-backed successful operations.
- Document source/target scope and dependencies; regenerate references after
  acceptance. No successful type check alone establishes working behavior.

Every command remains below two minutes. Root serializes all compiler/native
gates with the shared lock. Supported targets are claimed only after execution.

## Accepted evidence

The three actual public smokes compile and execute. Both registered portable
tests pass together in 8.93s after a separate 3.37s build, including 96 model
records and caller-buffer/stride contracts. The retained pure contract and
tokenizer smoke also execute under full syscall observation with mmap denial;
only launch and final exit occur, without any reached allocation attempt.

Two direct native groups pass 70 overlapping group cases: provider39 and
resources31. The latter includes two baselines and all 29 individually reached
OOM positions, with live acknowledged source/native owners and independently
held provider-error storage. The real KV response group passes 55 direct cases,
including all 18 allocation denials from its response-help baseline and
post-database failure/visibility checks. These three direct oracle groups are
not three passing Rust libtests. Their registered drivers have a separate
combined 2.09s `--no-run` build receipt.

Production sources remain pure tokenizer `a997585c...`, expansion `35b6ee83...`,
native provider `461037b8...` and application `789143f6...`. Early fixture
qualification, grammar, read-count and artifact-path errors did not change
production. Two independent resource-oracle gaps were corrected before native
acceptance: unexpected phase effects now reject and OOM accessors explicitly
check nonpublication. A full-context compiler-name-resolution capture and
successful smaller controls remain separate, without a general pattern claim.

The [module guide](extended-cli-response.md#current-executable-evidence),
[portable fixture guide](../tests/fixtures/extended/cli_response/README.md),
[native resource guide](../tests/fixtures/extended/cli_response/files_README.md)
and [application guide](extended-kv.md#current-application-receipts) record exact
receipts and failure/target limits. This selected increment is accepted;
shell completion and the full library goal remain open.
