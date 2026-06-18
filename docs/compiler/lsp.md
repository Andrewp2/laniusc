# LSP Surface Internals

This chapter documents the `laniusc lsp` surface: the no-run capability
metadata command and the minimal stdio JSON-RPC server used by editor
experiments.

The LSP server is a tooling boundary, not a second compiler driver. It should
advertise exactly what it supports, reject unsupported protocol shapes with
machine-readable failure-boundary data, and avoid source-root loading, target
codegen, workspace traversal, or performance claims unless those features are
actually implemented and measured.

## What This Chapter Owns

This chapter covers:

- `laniusc lsp capabilities`
- `laniusc lsp serve --stdio`
- Content-Length framing and JSON-RPC response shape
- initialization, shutdown, and unsupported-method lifecycle rules
- open-document state and full-document synchronization
- full-document formatting requests
- pull diagnostics for opened documents
- LSP error-data metadata and no-run guards
- capability metadata and claim boundaries
- LSP-specific test evidence

It does not cover:

- general CLI parsing and diagnostic-format selection; see
  [CLI and tooling surface](cli.md)
- diagnostic object rendering and LSP diagnostic payloads; see
  [Diagnostics and status](diagnostics.md)
- formatter policy outside LSP; see [Formatter internals](formatter.md)
- type-checker internals; see [Resident type checker](type-checker.md)
- source-root, package, or workspace loading; see
  [Module and source-root resolution](module-resolution.md)

## Source Map

| Source | Responsibility |
| --- | --- |
| `cli/lsp/mod.rs` | Top-level `laniusc lsp` command routing, subcommand validation, capability printing, and server startup. |
| `cli/lsp/capabilities.rs` | No-run capability document and JSON-RPC `initialize` response. |
| `cli/lsp/protocol.rs` | Content-Length framing, response writing, transport metadata, error-data metadata, invalid-message responses, not-initialized responses, and unsupported-method responses. |
| `cli/lsp/session.rs` | Stdio server loop, lifecycle state, method dispatch, open-document map, and request error routing. |
| `cli/lsp/document.rs` | Open-document extraction, full-document change handling, formatting option validation, formatting edits, pull diagnostic conversion, and URI label mapping. |
| `cli/common/constants.rs` | Supported method lists, lifecycle method lists, schema names/versions, and JSON-RPC error-code constants. |
| `tests/cli_lsp.rs` | Capability metadata, stdio lifecycle, formatting, diagnostics, unsupported methods, invalid framing, and error-data contract tests. |

The LSP implementation deliberately keeps protocol mechanics in `cli/lsp` and
compiler semantics in the existing compiler APIs. A new language feature should
not be implemented in LSP code.

## Commands

`laniusc lsp` has two public modes:

| Command | Behavior |
| --- | --- |
| `laniusc lsp capabilities` | Prints a no-run JSON metadata document and exits. |
| `laniusc lsp serve --stdio` | Starts a JSON-RPC server over stdin/stdout using LSP Content-Length framing. |

Both modes accept the normal CLI diagnostic-format option only for invocation
errors before the server starts. Once `serve --stdio` is running, protocol
errors are JSON-RPC responses on stdout, not stderr diagnostics.

## Capability Metadata

The capability document is intentionally richer than the standard LSP
`initialize` response. It is meant for wrappers and editor experiments that need
to inspect the contract without starting a long-lived server.

`laniusc lsp capabilities` reports:

- schema name and version
- server name, version, stdio support, and supported method list
- language id
- position encoding
- diagnostic source and diagnostic registry
- diagnostic output formats
- distribution metadata
- transport contract metadata
- error-data contract metadata
- full-document text synchronization policy
- unsupported workspace claims
- formatter metadata
- lifecycle metadata
- pull-diagnostic metadata
- claim boundaries and no-run guards

The no-run guards in this command must stay false for source compilation,
source scanning, GPU device creation, and target codegen. If a future
capability command needs to inspect local source or create a compiler, it is no
longer a no-run metadata command and the contract must change explicitly.

## Initialize Response

The stdio server's `initialize` response reports the subset needed by an LSP
client:

| Capability | Current value |
| --- | --- |
| position encoding | compiler `LSP_POSITION_ENCODING` |
| text document sync | open/close plus full-document change kind |
| pull diagnostics | document diagnostics only |
| workspace diagnostics | unsupported |
| formatting | full-document formatting provider |
| workspace folders | unsupported |
| workspace symbols | unsupported |

The `experimental.laniusc` payload mirrors the richer metadata: diagnostic
registry, diagnostic formats, distribution status, transport/error-data
contracts, workspace metadata, formatting policy, lifecycle metadata, supported
methods, pull-diagnostic metadata, claim boundaries, and no-run guards.

Update both `capabilities_document` and `initialize_response` when adding or
removing public LSP behavior. A method implemented by the server but absent from
capability metadata is a client contract bug.

## Transport

The server uses stdio with LSP-style `Content-Length` framing:

- request bodies are UTF-8 JSON-RPC payloads
- `Content-Length` is required and measured in bytes
- header names are case-insensitive
- syntactically valid extra headers are ignored
- responses are written to stdout with `Content-Length`
- stderr is not used for protocol diagnostics

Invalid frames become JSON-RPC error responses when possible. The reader tries
to recover stream alignment by discarding the body of a known-length invalid
frame before reading the next message.

Examples of invalid transport conditions:

- missing `Content-Length`
- duplicate `Content-Length`
- malformed header line
- invalid length value
- body shorter than advertised
- body that is not JSON

Transport errors use LSP/JSON-RPC error codes and `LNC0029` diagnostic data
inside the JSON-RPC error payload. They should not escape as plain stderr text
while the server can still emit a protocol response.

## Lifecycle

The session loop tracks two booleans:

- whether `initialize` has been received
- whether `shutdown` has been received

Lifecycle rules:

| State | Accepted methods |
| --- | --- |
| Before initialize | `initialize`, `exit` |
| After initialize | supported method list |
| After shutdown | `exit` only |

Repeated `initialize` requests are rejected and do not reset server state.
Stateful notifications before initialization are ignored unless they carry an
id. Requests after shutdown are rejected with a post-shutdown failure boundary.
`exit` ends the loop.

The method inventory lives in constants:

- `LSP_STDIO_METHODS`
- `LSP_PRE_INITIALIZE_METHODS`
- `LSP_POST_SHUTDOWN_METHODS`

Keep those constants, capability metadata, help text, unsupported-method
diagnostics, and tests in sync.

## Supported Methods

The current stdio server supports:

| Method | Kind | Notes |
| --- | --- | --- |
| `initialize` | request | Returns server capabilities and experimental Lanius metadata. |
| `initialized` | notification or request | A request receives `null`; a notification records no state. |
| `textDocument/didOpen` | notification or request | Stores one explicit open-document text buffer. |
| `textDocument/didChange` | notification or request | Accepts full-document replacements only. |
| `textDocument/didClose` | notification or request | Removes the open-document entry. |
| `textDocument/formatting` | request | Returns full-document formatting edits for an open document. |
| `textDocument/diagnostic` | request | Returns a full pull-diagnostic report for an open document. |
| `shutdown` | request or notification | Marks the session shut down. |
| `exit` | notification or request | Ends the server loop. |

Unknown requests receive method-not-found JSON-RPC errors with `LNC0028`
diagnostic data. Unknown notifications are ignored without a response. This
matches JSON-RPC notification behavior and keeps protocol errors inside stdout
when a response id exists.

## Open Documents

The server keeps a `HashMap<String, OpenDocument>` keyed by URI. It does not
load documents from disk, source roots, package manifests, stdlib roots, or
workspace folders.

`textDocument/didOpen` requires:

- `params.textDocument.uri`
- `params.textDocument.languageId == "lanius"`
- `params.textDocument.text`

`textDocument/didChange` requires:

- an already-open document URI
- `params.contentChanges`
- at least one full-document change with `text`
- no `range`
- no `rangeLength`

If a client sends multiple full-document changes in one request, the last text
value becomes the open document. Ranged incremental changes are rejected so the
server always has one coherent source string for formatting and diagnostics.

`textDocument/didClose` removes the URI from the map. Formatting and diagnostic
requests for unopened documents are invalid-params responses and must not try to
read source from the URI.

## Formatting

LSP formatting reuses the lexical formatter through `format_source`.

Request requirements:

- the document must be open
- `params.options` must be an object
- `params.options.tabSize` must be the positive integer `4`
- `params.options.insertSpaces` must be `true`

Additional options are ignored. Range formatting is not supported.

Formatting returns either:

- an empty edit list when the source is already formatted
- one full-document replacement edit when formatting changes the text

The edit end position is computed in zero-based UTF-16 units. Formatting does
not compile source, scan roots, create a GPU device, or run target codegen.

## Pull Diagnostics

`textDocument/diagnostic` serves opened-document pull diagnostics only. It does
not implement `textDocument/publishDiagnostics`, workspace diagnostics, result
ids, inter-file dependencies, source-root loading, stdlib-root loading, or
target codegen.

The diagnostic path:

1. Look up the opened document by URI.
2. Run `type_check_source_with_gpu` on the current document text.
3. Return an empty `items` array if type checking succeeds.
4. Convert `CompileError::Diagnostic` to one LSP diagnostic item if type
   checking reports a structured diagnostic.
5. Rewrite the primary label path to the document URI path.
6. Return JSON-RPC internal error data if diagnostics fail outside structured
   `CompileError::Diagnostic`.

This is the one current LSP path that may create a GPU device. Its no-run guard
metadata should say source compilation and GPU device creation are true, while
source scanning and target codegen remain false.

## Error Data

Every LSP JSON-RPC error response built by the protocol helpers carries the
Lanius error-data schema:

- `schema_name`
- `schema_version`
- `failure_boundary`
- optional `requested_method`
- optional stable diagnostic object
- method lists or allowed-method lists when relevant
- no-run guards

Current failure boundaries:

| Boundary | Meaning |
| --- | --- |
| `lsp-protocol-message-validation` | Malformed frames, invalid JSON, invalid JSON-RPC objects, wrong version, missing method, or invalid params. |
| `lsp-lifecycle-pre-initialize` | Request rejected before initialization completed. |
| `lsp-lifecycle-post-shutdown` | Request rejected after shutdown. |
| `lsp-lifecycle-reinitialize` | Repeated initialize request. |
| `lsp-method-dispatch` | Unsupported or unknown request method. |
| `lsp-open-document-diagnostics` | Pull diagnostics reached the compiler but failed outside a structured diagnostic. |

Use `LNC0029` for invalid LSP messages and `LNC0028` for unsupported methods.
Do not invent unregistered diagnostic payloads for public protocol failures.

## Workspace Boundary

The current LSP server explicitly does not support:

- workspace folders
- workspace folder change notifications
- workspace symbols
- configuration requests
- file operations
- workspace diagnostics
- source-root loading
- stdlib-root loading
- initialize `rootUri` behavior
- initialize `workspaceFolders` behavior

Capability metadata must continue to say these are unsupported until there is
real implementation and test evidence. Do not add compatibility aliases or
empty success responses that imply workspace support for clients. An unsupported
workspace request should be an unsupported method unless a specific no-op has
been deliberately documented.

## Claim Boundaries

LSP capability metadata is not production-readiness or performance evidence.
The claim-boundary metadata records that:

- the server is a stdio protocol experiment
- diagnostics are single-open-document only
- workspace support is absent
- latency and throughput are not measured
- local performance artifacts are required for performance claims
- this is not a release artifact

Keep this conservative. A capability field that says a feature exists is a
contract with editor clients. It should be backed by behavior tests and, for
performance claims, local measurement artifacts.

## Adding LSP Behavior

Use this checklist for LSP changes:

1. Decide whether the behavior belongs to command routing, capability metadata,
   protocol framing, lifecycle, document state, formatting, diagnostics, or
   compiler APIs.
2. Add or update constants for method lists, schema names, schema versions, or
   JSON-RPC error codes when the public contract changes.
3. Update `capabilities_document` for no-run discovery.
4. Update `initialize_response` for client-visible capabilities.
5. Add session dispatch only after lifecycle rules are clear.
6. Keep notifications response-free unless the protocol deliberately treats the
   method as a request.
7. Preserve no-run guards for metadata and formatting paths.
8. Route source diagnostics through `Diagnostic` and LSP diagnostic conversion.
9. Add or update `tests/cli_lsp.rs` for the smallest protocol transcript that
   proves the contract.
10. Update this chapter and [CLI and tooling surface](cli.md) if the public
    command behavior changed.

If a feature needs source roots, package metadata, workspace state, or target
codegen, document and test that new boundary explicitly. Do not hide it behind
the existing open-document-only contract.

## Test Evidence

LSP tests should prove protocol behavior with small JSON-RPC transcripts:

- capability metadata shape and no-run guards
- initialize response capability fields
- pre-initialize rejection
- repeated initialize rejection
- post-shutdown rejection
- unsupported request and ignored unsupported notification behavior
- full-document didOpen/didChange/didClose state
- rejection of ranged incremental changes
- formatting request option validation
- formatting edit shape
- opened-document pull diagnostics
- unopened-document diagnostic rejection without source loading
- malformed framing recovery
- invalid JSON-RPC object errors
- error-data schema and failure-boundary metadata

Do not use broad editor integration tests as the first proof for a method. The
contract is the protocol transcript and the JSON response shape.

For docs-only edits to this chapter, run:

```bash
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

plus Markdown link, whitespace, and ASCII checks. LSP integration tests are
needed when protocol behavior, capabilities, constants, error-data fields, or
request handling changes.
