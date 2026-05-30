# Lanius Compiler Architecture Contract

Follow `docs/RECOMMENDATIONS.md` and
`docs/COMPILER_ALIGNMENT_FAILURES.md`. This file is the short operational
contract for future changes.

## Non-Negotiable Pipeline

- Source bytes enter GPU-resident buffers.
- Lexing produces token records; parsing produces parse/HIR records.
- Semantic passes consume GPU-resident HIR, resolver, type-instance, and
  literal records. After lexeme extraction, they must not rediscover meaning
  from source bytes, token spelling, helper names, or source-neighborhood
  layouts.
- Backend lowering consumes attributed HIR/AST records only.
- Instruction counting is node-local. Instruction locations come from prefix
  sums over those node-local counts.
- Instruction generation emits generic virtual instruction records per node,
  with virtual registers before allocation.
- Register allocation consumes virtual instruction/register records.
- x86_64 byte emission consumes allocated instruction records and relocation or
  layout records.
- CPU code may launch GPU passes, move artifacts, page jobs, read/write files,
  and perform other control-plane work. It must not parse, type-check,
  monomorphize, link, patch, or rewrite massive program data as a semantic
  fallback.

## Forbidden Patterns

- No helper-name matching in semantic analysis or backend lowering.
- No stdlib-function-specific backend cases.
- No function-body, return-expression, terminal-branch, or source-shape
  recognizers.
- No token spelling or source-byte inspection after the lexeme-to-semantic-record
  pass.
- No backend cases named after source patterns, helper functions, narrow tests,
  or historical hacks such as `RETURN_EVAL`, `extract_return`, or
  `extract_terminal`.
- No deleting, renaming, or bypassing `AGENTS.MD` to avoid this contract.

## Required Review Notes For Compiler Changes

Every compiler change should state:

- the pipeline stage changed;
- the input record arrays consumed;
- the output record arrays produced;
- whether any source text, token spelling, helper name, or function-body shape
  was inspected.

If the answer to the last item is yes outside lexeme extraction, redesign the
change instead of extending the exception.

## Test Discipline

- Tests should prove behavior, record invariants, diagnostics, artifact
  contracts, executable output, or scaling boundaries.
- Do not add tests that read compiler or shader source files and assert that
  specific strings, helper names, function names, loop spellings, or private
  implementation vocabulary are present or absent.
- If a test is meant to catch helper-name matching or source-shape hacks, use a
  behavioral property such as renamed helpers compiling the same way, equivalent
  source rewrites producing the same output, or GPU record arrays carrying the
  semantic information that later stages consume.
