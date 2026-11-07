# Function-address frame regression

These four executable regressions cover function addresses passed to a call
returning a record inside `Result`, followed by `.unwrap()` and a return from
the enclosing helper. All four originally corrupted the caller's saved RBP
and terminated with SIGSEGV, including the named-local and split-result forms.
Naming the pointer was not a safe workaround.

The x86 lowering count pass treated the CALL-shaped function-address node as
an ordinary call and counted an inlined callee body. Scatter instead emitted
a C callback entry address. The inconsistent row counts produced a duplicate
callback thunk whose result store overwrote the saved frame pointer.

`shaders/codegen/lir/x86/c_entry.slang` now supplies one classification shared
by count and scatter. Function addresses have no call-argument or callee-body
rows. No IR format, runtime, ABI or formal-proof change was required.

- `function_address_result_unwrap.lani` passes the function address inline.
  It needs no threads, C calls, raw memory or allocation.
- `function_address_named_local.lani` names the address before the call.
- `function_address_split_result.lani` also separates the call from unwrap.
- `thread_named_entry.lani` starts a real canonical thread, joins its null
  result and returns from the helper.

All four now exit successfully with no output through
`tests/stdlib_thread_lifecycle_execution.rs`. The complete seven-test driver,
including the original `../failures.lani` lifecycle fixture, passes on native
Linux x86_64/glibc in 12.04 seconds. No case is ignored or weakened.
