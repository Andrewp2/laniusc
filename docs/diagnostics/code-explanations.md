# Diagnostic Code Explanations

This page explains the stable `LNC####` diagnostic codes exposed by the
current compiler. It is the user-facing companion to the generated
[diagnostic code index](generated/error-index.md), which is rebuilt from the
compiler registry.

Use this page when a diagnostic code is known and you need to understand what
kind of problem it names. Use the generated index when you need the exact
current code list, primary-label policy, category counts, unsupported-boundary
metadata, or fail-closed codegen table.

The live metadata command is:

```bash
laniusc diagnostics explain CODE
```

For example:

```bash
laniusc diagnostics explain LNC0017
```

`diagnostics explain` is a no-run metadata command. It does not compile source,
scan source files, create a GPU device, or run target codegen.

## Reading A Code

Start with the diagnostic's primary label when one exists. The label should
point at the source construct, CLI argument, output path, package selector, or
backend boundary that made the compiler reject the request.

Then use the code category:

| Category | First place to look |
| --- | --- |
| `package/import loading` | source-root, stdlib-root, package manifest, lockfile, module declaration, or import docs |
| `module resolution` | module declarations, import syntax, import graph, and module path rules |
| `name resolution` | declaration visibility, namespace, local binding, and path lookup rules |
| `type checking` | expression type, function/call, generic, aggregate, and assignment rules |
| `trait solving` | trait declarations, bounds, impl contracts, and method dispatch boundaries |
| `parsing` | token spelling and grammar shape |
| `native codegen` | x86 target lowering, ABI, descriptor output, or native fail-closed boundary |
| `target codegen` | selected non-x86 backend boundary |
| `runtime binding` | stdlib or host-service APIs that are known but not executable yet |
| `tooling` | CLI, formatter, LSP, output path, or metadata command usage |

If a code is an unsupported-boundary code, the compiler rejected the program to
avoid pretending unsupported behavior succeeded. In those cases, `laniusc check`
is often the right command to separate frontend validity from target execution.

## Package And Import Loading

### LNC0001: Missing Source-Root Module

The source-root loader could not find the module named by an import or package
edge in the supplied roots.

Typical causes:

- the imported module file is absent from every `--source-root`
- the file exists but its leading `module` declaration names a different module
- a package or lockfile names a module that is not present in the current input
  identity

What to do:

- add the missing `.lani` source file under a configured source root
- fix the file's `module a::b;` declaration so it matches the import
- regenerate or validate package lockfiles after changing source-root layout

The primary label should point at the import or package edge that requested the
missing module.

### LNC0003: Ambiguous Source-Root Module

More than one source file or root can satisfy the same module identity.

Typical causes:

- two source roots contain files with the same module declaration
- package metadata and live source roots both claim the same module
- a lockfile replay sees duplicate module identities

What to do:

- keep one authoritative file for each module identity
- remove duplicate source roots or duplicate package entries
- make module declarations unique before compiling through a source-root or
  package workflow

The primary label should identify the import, module declaration, or package
entry that exposed the ambiguity.

### LNC0004: Source-Root Escape

A source-root or package path resolved outside the root that was supposed to
contain it.

Typical causes:

- a symlink or relative path points outside the declared source root
- package metadata contains a non-canonical source path
- a lockfile references a path that no longer belongs to the input identity

What to do:

- keep source files inside the declared source roots
- use canonical package metadata and regenerate stale lockfiles
- avoid relying on filesystem paths as semantic module names

The primary label should point at the path or source-root edge that escaped.

### LNC0024: Source-Root Package Boundary

Source-root loading rejected an import edge that crosses from stdlib roots back
into package or user source roots.

Typical causes:

- a stdlib module imports an application module
- source roots are arranged so a stdlib dependency resolves into package source
- package metadata tries to make stdlib declarations depend on user code

What to do:

- keep stdlib roots independent from package and user roots
- move shared contracts into stdlib roots or package-visible modules
- use package manifest and lockfile metadata for package source graphs

This is an unsupported-boundary code. The compiler rejects the edge before
stdlib metadata can depend on user source.

### LNC0030: Non-Source Source-Root Module

An import resolved to a path that is not a `.lani` source file.

Typical causes:

- a source-looking symlink resolves to a directory or non-source artifact
- a source root contains generated output beside source modules
- package or lockfile metadata points at a non-source file

What to do:

- move non-source artifacts out of source roots
- ensure imported module paths resolve to `.lani` files
- regenerate package metadata after deleting or moving generated files

The primary label should identify the import or source-root path that resolved
to a non-source target.

### LNC0037: Package Metadata Invalid

Package manifest, lockfile, descriptor, or package metadata validation failed
before normal source compilation.

Typical causes:

- manifest JSON is malformed or missing required fields
- an entry source lies outside declared roots
- lockfile identity sections are missing or stale
- package artifact metadata cannot be read or validated

What to do:

- inspect the package manifest or lockfile named by the diagnostic
- regenerate lockfiles after source graph changes
- use package commands to validate metadata before compiling source

This code often has no primary source label because the invalid input is a
metadata file or command argument rather than a Lanius source token.

## Module Resolution

### LNC0002: Import Cycle

Module imports form a cycle that the current resolver cannot accept.

Typical causes:

- module `a` imports `b`, and `b` imports `a`
- a longer package graph loops back to an earlier module
- lockfile replay preserves an import cycle from stale source

What to do:

- move shared declarations into a third module
- break dependency cycles by passing values through function parameters
- regenerate lockfiles after changing the import graph

The primary label should point at the import edge that completes the cycle.

### LNC0010: Unresolved Import

The import syntax was recognized, but the resolver could not bind it to a
visible module through the active source roots, stdlib roots, or package graph.

Typical causes:

- the module is not imported through the active source-root or stdlib-root set
- the import path is misspelled
- package metadata omits the dependency edge

What to do:

- check the imported module's `module` declaration
- pass the source or stdlib root that contains the module
- regenerate package lockfiles when imports change

The primary label should point at the unresolved import path.

### LNC0011: Unsupported Import Form

The compiler recognized an import position but rejected the import shape.

Typical causes:

- quoted imports
- import aliases
- glob imports
- imports before the leading module declaration in package replay contexts

What to do:

- use module-path imports such as `import app::module;`
- avoid alias, glob, quoted, filesystem, or dotted import forms in the current
  edition
- keep module identity metadata first where source-root and package loading
  require it

This is an unsupported-boundary code. It prevents incomplete host-side import
metadata from becoming trusted compiler input.

### LNC0012: Import Path Too Deep

The import path exceeded the compiler's currently supported module depth.

What to do:

- shorten or flatten the module path
- introduce a shallower public module that re-exports or wraps the needed API
  when the language grows such support
- keep current `unstable-alpha` imports inside the bounded path depth

The primary label should point at the import path segment or full import path.

### LNC0013: Duplicate Module Declaration

A source file contains more module identity declarations than the current
source-root/package model accepts.

What to do:

- keep one leading `module a::b;` declaration per source file
- split unrelated modules into separate files
- remove stale copied declarations when moving source between modules

The primary label should point at the duplicate module declaration.

### LNC0014: Module Path Too Deep

A `module` declaration exceeded the current module path depth.

What to do:

- shorten or flatten the module path
- align imports and package metadata with the shallower path
- avoid relying on deep filesystem layout as semantic module identity

This is an unsupported-boundary code. It is separate from `LNC0012`, which
reports an over-deep import path.

### LNC0015: Invalid Module Path

A module path has invalid shape for the current module grammar or loader.

Typical causes:

- empty path segments
- non-identifier path segments
- separators outside the documented `::` form
- a module declaration that does not match source-root expectations

What to do:

- use ASCII identifier segments separated by `::`
- keep module declarations and imports in the documented module-path syntax
- check package metadata if the path came from a manifest or lockfile

## Name Resolution

### LNC0005: Unresolved Identifier

A value, type, field, variant, method, or local name could not be resolved in
the namespace required by the use site.

Typical causes:

- a local binding or function is misspelled
- a declaration is private or not imported
- a name is used in the wrong namespace
- a method or field is not available for the receiver type

What to do:

- check the spelling and namespace of the use site
- import the module that owns the declaration
- make the declaration public when it is intentionally cross-module
- use the field, method, or enum variant supported by the resolved type

The primary label should point at the unresolved identifier or path segment.

## Type Checking

### LNC0006: Type Mismatch

An expression, assignment, return, call argument, pattern arm, aggregate field,
or local declaration has a type that does not match the expected type.

Typical causes:

- assigning `bool` where `i32` was expected
- returning the wrong type from a function
- passing an argument that does not match a parameter
- giving a struct field or array element the wrong type

What to do:

- compare the expected type named by the diagnostic with the expression's type
- add or fix a type annotation when inference chose the wrong expectation
- update the function signature, return expression, call argument, or aggregate
  field so they agree

The primary label should identify the expression that made the types diverge.

### LNC0007: Unknown Type

A type-position path did not resolve to a primitive type, struct, enum, trait
where accepted, type alias, or generic parameter.

Typical causes:

- misspelled type name
- missing import for a module-owned type
- using a value name where a type is expected
- relying on a type alias that is private or unsupported in the current context

What to do:

- check the declaration and visibility of the type
- import the module that owns the type
- use a type-position name, not a function or value item

The primary label should point at the unknown type path.

### LNC0027: Call Resolution Failed

The compiler could not resolve or validate a call target for the current call
expression.

Typical causes:

- callee does not name a function, extern function, enum constructor, or
  supported method target
- argument count or argument types do not match the selected callable
- method dispatch is outside the current bounded receiver rows
- generic call inference or substitution fails

What to do:

- check the callee path and imports
- compare arguments with the function or method signature
- use [Functions and calls](../language/functions-and-calls.md) for direct,
  generic, constructor, and method call boundaries
- simplify unsupported method-level generic or trait-dispatch calls until the
  current slice supports them

The primary label should point at the call, callee, receiver, or offending
argument.

### LNC0033: Invalid Generic Parameter List

A generic parameter list parsed but failed semantic validation.

Typical causes:

- duplicate generic parameter names
- unsupported const-generic placement
- malformed or unsupported generic signature shape
- generic parameter metadata that cannot be represented by current HIR rows

What to do:

- keep generic parameter lists simple and unique
- check [Generics and bounds](../language/generics-and-bounds.md) for current
  supported forms
- move unsupported constraints into simpler where clauses only when the current
  trait-bound rows support them

The primary label should point at the generic parameter list or offending
parameter.

## Trait Solving

### LNC0008: Unsatisfied Trait Bound

A required trait obligation could not be proven for the current type or generic
argument.

Typical causes:

- no visible impl satisfies a `where` clause or inline bound
- a predicate argument uses a private or unsupported type
- a const-generic subject or over-deep bound chain is outside current support
- generic substitution did not produce the trait arguments required by the impl

What to do:

- add or import the impl that satisfies the bound
- fix the type arguments used in the bound
- keep predicate shapes within the current bounded rows
- check [Traits and impls](../language/traits-and-impls.md) and
  [Generics and bounds](../language/generics-and-bounds.md)

The primary label should point at the bound, type argument, call, or declaration
that required the obligation.

### LNC0009: Ambiguous Trait Bound

The compiler found more than one possible trait obligation candidate, or could
not choose one unambiguously under the current trait-solving rules.

What to do:

- make the trait path or type arguments more specific
- remove duplicate or conflicting impls
- avoid relying on unsupported overload, blanket impl, or dynamic dispatch
  behavior

The primary label should point at the ambiguous bound or use site.

### LNC0021: Invalid Trait Implementation

A trait impl or inherent impl violates the current impl contract.

Typical causes:

- impl header does not resolve to a trait for `impl Trait for Type`
- required trait method is missing
- extra method appears in a trait impl
- method arity, parameter type, return type, visibility, or duplicate method
  rules do not match the trait declaration
- method-level generics or nested receiver arguments are outside the bounded
  slice

What to do:

- compare the impl methods against the trait declaration by name and signature
- remove extra methods or add missing required methods
- make method visibility match the trait contract
- keep impl headers and receiver types within the current supported rows

The primary label should point at the impl header or the method declaration
that violates the contract.

## Parsing

### LNC0016: Syntax Error

The lexer or parser could not turn source text into the documented grammar
shape.

Typical causes:

- missing punctuation such as `;`, `,`, `)`, or `}`
- token spelling outside the current lexical structure
- source-root replay encountering malformed comments or string literals
- an imported source file with invalid syntax

What to do:

- check the token at the primary label and the token before it
- compare the source with [Lexical structure](../language/lexical-structure.md)
  and [Syntax reference](../language/syntax.md)
- fix imported files as well as the entry file when source-root diagnostics
  name an import

The primary label should point at the narrowest token or source span the parser
can identify.

## Native And Target Codegen

### LNC0017: X86 Backend Boundary

The program reached a source construct that passed earlier phases but is
outside the current x86 lowering slice.

Typical causes:

- unsupported literal, prefix/postfix expression, aggregate member path, enum
  payload, short-circuit shape, slice index, or runtime call
- helper parameters beyond the current SysV register-backed ABI slice
- an x86 fail-closed path that prevents partial native instruction output

What to do:

- run `laniusc check` to verify frontend validity without native codegen
- use the language chapter for the rejected construct to find the current
  support boundary
- choose another target only when that target has evidence for the same shape

This is an unsupported-boundary and codegen-boundary code. Target bytes should
not be emitted when this diagnostic is produced.

### LNC0022: Linked-Output Contract Descriptor

Descriptor-mode linked output did not satisfy the JSON contract metadata shape
expected by that mode.

Typical causes:

- treating descriptor output as executable bytes
- malformed descriptor data
- incoherent linked-output contract metadata

What to do:

- treat descriptor-mode linked output as JSON contract metadata
- use non-descriptor compilation when target bytes are required
- inspect [Targets and output](../targets.md) and
  [Artifact descriptors](../compiler/artifact-descriptors.md)

This is an unsupported-boundary code for descriptor-mode output, not a normal
source-language type error.

### LNC0036: WASM Backend Boundary

The program reached the WASM backend, but the current WASM lowering slice cannot
emit the requested construct.

What to do:

- use `laniusc check` for frontend diagnostics without target codegen
- use `x86_64` only if the same source shape is covered by x86 rows
- check [Targets and output](../targets.md) and
  [WASM backend internals](../compiler/wasm-backend.md)

This is an unsupported-boundary and codegen-boundary code. The backend should
fail closed before emitting a partial module prefix.

## Runtime Binding

### LNC0038: Runtime Service Boundary

The program reached a known stdlib or host API whose runtime service descriptor
exists, but the current compiler/linker/runtime contract does not provide an
executable binding.

Typical causes:

- calling `std::io`, filesystem, process, environment, allocator, network,
  thread, random, GPU host-service, panic-hook, or test-harness APIs that are
  currently metadata-only
- compiling source-level stdlib contracts as if they were linked host services

What to do:

- treat the API as contract metadata unless the runtime diagnostics say it is
  executable
- inspect the service with `laniusc diagnostics runtime-service SERVICE`
- inspect an API with `laniusc diagnostics runtime-api API`
- use the matching `*_requires_runtime_binding()` helper in source-level
  contracts where appropriate

The primary label should point at the runtime-bound call or source construct
that forced executable lowering.

## Tooling

### LNC0018: Unsupported CLI Option Value

A recognized CLI option was given a value outside the current accepted set.

Typical causes:

- unsupported `--emit` target
- unsupported target triple
- unsupported diagnostic format
- unsupported version or metadata selector

What to do:

- run the command's help or metadata command to list accepted values
- use `laniusc diagnostics version-policy` for version and selector boundaries
- choose one of the supported values named in the diagnostic notes

This code usually has no source label because it is a command-line problem.

### LNC0019: Formatter Check Failed

Formatter check mode found source that would be reformatted.

What to do:

- run `laniusc fmt PATH` to rewrite the file
- keep `laniusc fmt --check PATH` for CI or no-write checks
- inspect the primary label when the formatter reports the first changed span

This code is not a source-language rejection. It means the formatter contract
would change the input.

### LNC0020: Unknown CLI Option

The command line contains a flag or option that the current CLI does not know.

What to do:

- check spelling and command placement
- run `laniusc help` or the subcommand help
- remove old or unsupported flags instead of relying on compatibility aliases

This code normally has no source label because source loading has not started.

### LNC0023: Missing CLI Option Value

A flag that requires a value was provided without one.

What to do:

- provide the missing value immediately after the option
- use the command help to see whether the option requires a path, selector, or
  format name
- quote shell values that contain spaces

### LNC0025: Missing CLI Subcommand

A command family was invoked without the required subcommand.

What to do:

- run the command family with help or a concrete subcommand
- for diagnostics metadata, use commands such as `diagnostics codes`,
  `diagnostics explain CODE`, `diagnostics runtime-apis`, or
  `diagnostics version-policy`

### LNC0026: Missing CLI Argument

A command or subcommand is missing a required positional argument.

What to do:

- provide the path, code, service selector, package selector, or other argument
  named by the diagnostic
- run help for the specific subcommand

### LNC0028: Unsupported LSP Method

The LSP server received a JSON-RPC method outside its current supported method
set.

What to do:

- check `laniusc lsp capabilities` for the supported editor-facing surface
- avoid assuming workspace diagnostics, result ids, or unsupported requests are
  implemented
- make the client handle method-not-found responses

This is a no-run tooling diagnostic. It should not compile source.

### LNC0029: Invalid LSP Message

The LSP server received malformed JSON-RPC, invalid framing, wrong language id,
an invalid lifecycle request, or malformed request parameters.

What to do:

- check JSON-RPC `Content-Length` framing
- send `initialize` before stateful requests
- use the `lanius` language id
- include required formatting or diagnostic parameters

The server should reject the message without opening documents unexpectedly,
mutating stored text, compiling source, or creating a GPU device.

### LNC0031: Unexpected CLI Argument

A command received an extra positional argument or argument in a position where
the command does not accept one.

What to do:

- remove the extra argument
- use the command help to check which arguments are positional and which must be
  passed as options
- for package commands, distinguish manifest paths from source input paths

### LNC0032: Incompatible CLI Options

Two or more individually valid CLI options cannot be used together.

Typical causes:

- mixing output modes that have conflicting contracts
- selecting check/no-run behavior while also requesting target output
- combining package/source-root modes in a way the current CLI forbids

What to do:

- choose one workflow: check, compile, format, source-root, package, descriptor,
  or metadata query
- split incompatible operations into separate commands
- use [Compiler invocation](../invocation.md) for command-mode boundaries

### LNC0034: Output Write Failed

The compiler or formatter could not write to a requested file path.

Typical causes:

- parent directory does not exist
- permission denied
- read-only file or filesystem
- output path is a directory
- disk or filesystem error

What to do:

- create the parent directory
- choose a writable output path
- avoid overwriting directories or protected files
- rerun after resolving filesystem permissions

The primary label or diagnostic path should identify the output target when one
is available.

### LNC0035: Output Stream Write Failed

The compiler could not write to stdout or stderr.

Typical causes:

- downstream pipe closed early
- terminal or wrapper stream failed
- process output was interrupted

What to do:

- check the command or wrapper that consumes compiler output
- avoid treating this as a source-language failure
- rerun without a closed pipe when you need the full output

### LNC0039: Unknown CLI Subcommand

A command family recognized the parent command but not the selected subcommand.

What to do:

- check spelling
- run the parent command help
- use the supported subcommands listed by the current binary

This code usually has no source label because source loading has not started.

### LNC0040: Input Read Failed

The compiler, formatter, or source loader could not read an input path or stdin
payload.

Typical causes:

- file does not exist
- permission denied
- stdin is not valid UTF-8 for a source-reading command
- path points at a directory when a file is required

What to do:

- check that the path exists and is readable
- fix permissions
- pass a source file instead of a directory
- ensure stdin input is valid UTF-8 source text

The primary label or diagnostic path should identify the unreadable input when
one is available.

## Keeping This Page Current

When diagnostic behavior changes:

1. Update the compiler diagnostic registry and focused tests.
2. Regenerate [generated/error-index.md](generated/error-index.md) if code
   metadata, unsupported-boundary rows, or codegen-boundary rows changed.
3. Update this page when the user-facing explanation, likely cause, or recovery
   action changes.
4. Run `tools/docs_check.py`.
