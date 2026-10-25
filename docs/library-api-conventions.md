# Library API conventions

These conventions guide the standard and extended libraries. Existing modules
must migrate with their callers as each family is completed.

## Values and ownership

Ordinary scalar and record values copy. A record containing an allocation handle
does not acquire a second allocation when copied. The current language does not
enforce unique ownership or automatic destruction.

- An owned value has one active owner. `destroy` releases its allocation exactly
  once. A clone allocates independent storage; nested ownership must specify
  whether the clone is shallow or deep.
- A consuming operation returns the replacement owner. On success, use only
  that returned owner. On failure, the operation's contract states how the
  original owner is recovered or retained.
- Prefer a borrowed mutating receiver when the compiler supports its complete
  behavior. It lets a fallible operation return `Result` without transferring
  ownership merely to update a buffer.
- Views borrow storage. Their owner must remain alive, and operations that
  move or destroy the storage invalidate them. Read-only views must not expose
  writable storage that can break an invariant without an explicit contract.
- Do not describe manual ownership conventions as compiler-enforced safety.

## Errors

- `Option<T>` represents ordinary absence, such as a search without a match.
- `Result<T, E>` represents recoverable failure. Error values identify the
  cause and carry useful context such as an input byte offset.
- Qualify error variants when an application imports modules with overlapping
  names, for example `alloc::string::Error::AllocationFailed`.
- Operations that can fail allocation should return an explicit result.
  Do not require callers to compare lengths to discover failure in new APIs.
- Fallible edits validate input and reserve storage before changing contents.
  Allocation or validation failure leaves the original contents and owner
  valid. State exceptions explicitly for stream operations that may already
  have transferred bytes.
- Panics are for documented checked preconditions and explicit convenience
  operations. Missing host support must never look like successful execution.

## Bytes, text and indices

Bytes are arbitrary `u8` values. Text is valid UTF-8 and can contain NUL. String
length means bytes unless the API explicitly names scalars or graphemes.

Borrowed Text values carry their byte length and support subviews without
copying. ASCII whitespace helpers recognize HT, LF, VT, FF, CR and space;
format parsers must apply their own specified whitespace grammar.

Text edits and text slices require Unicode scalar boundaries. A negative index,
an index beyond the length, and a byte index inside a scalar have explicit
failure behavior. Empty text is valid. No normalization or locale-sensitive
comparison happens implicitly.

Use `core::slice::View<T>` to retain logical lengths across subviews and cursor
operations. Its initial constructor still needs a separate `i32` count because
the compiler cannot expose slice lengths; the caller must back the selected
range. Legacy free slice functions also require counts. Removing this physical
backing precondition needs compiler support. Raw pointers and lengths remain
explicit low-level interfaces.

Owned UTF-8 storage should use packed bytes. Encoding validation belongs at
construction and mutation boundaries; repeated queries should not revalidate
an unchanged owned string.

## Comparisons, hashing and iteration

Equality and hashing must agree. A hash collection requires equivalence
semantics, including a defined choice for floating-point NaNs and signed zero.
Partial ordering and total ordering are different contracts. Sorting, binary
search and ordered collections must state the relation they require.

Iteration exposes progress and exhaustion explicitly. Adapters preserve
documented ownership, error and cancellation behavior. Do not require closure
or associated-type features without first establishing compiler support.

## I/O and targets

Readers report bytes read, EOF and errors distinctly. Writers report partial
progress; `write_all` handles short writes. Buffering, flushing, closing and
cancellation have separate meanings. Host bindings preserve errors needed by
callers instead of converting every failure to a boolean.

Descriptor writes retain the process's signal policy. Programs that require a
closed pipe to return EPIPE and run manual cleanup explicitly select
[`std::signal` BrokenPipe Ignore](stdlib-signals.md) before writing. This changes
process-wide disposition; descriptor adapters do not select it implicitly.
Socket sends suppress SIGPIPE for that call through their documented
MSG_NOSIGNAL policy. Flush, close and signal disposition remain separate effects.

Module documentation names supported targets and required services. Portable
algorithms remain separate from allocation and operating-system bindings.

## Cryptography and TLS boundary

Cryptographic primitives, key derivation, signatures, certificate trust and TLS
must come from an established external library through a checked native binding.
Do not add in-house implementations to the standard or extended library. That
native integration remains a dependency; protocol declarations or raw syscalls
do not supply a working backend.

Checksums, noncryptographic hashes and protocol framing can remain Lanius code.
Secure entropy remains an operating-system service. DER/X.509 structure parsing
does not establish certificate trust, authenticated names or TLS support.

## Compatibility and evidence

There is no identified external compatibility commitment for the APIs being
developed here. Migrate repository consumers together rather than adding aliases
or permanent wrappers around old APIs. Record a real external requirement before
introducing compatibility support.

Examples must run. Tests cover normal values, boundaries, malformed input and
applicable resource failures. A declaration, source scan or successful type check
does not establish an executable API.
