# Function-address frame corruption dependency

The full confirmed reproducer is `../failures.lani`, compiled with the shared
pthread probe. Root retained the failing native executable at
`/tmp/laniusc_thread_lifecycle_failures_lani_1855884_1`; its debugger receipt is
`target/stdlib-work/thread-lifecycle-gdb.log`.

Every preflight assertion and the real echo-thread join complete. The parent
then receives the correct return instruction address, but its restored RBP is
`0x4195e7`, an emitted callback thunk address, instead of a stack address. It
faults at `0x41c756` while storing EAX at `[rbp-0x88]`.

Static disassembly identifies the write before that failure:

```text
preflight entry 0x4189d8:
  push rbp
  mov  rsp,rbp
  sub  0x8d0,rsp

0x419598: lea  0x4195a1,rax   # first echo callback thunk
0x41959f: jmp  0x4195db
... first C-entry thunk, whose body calls echo ...
0x4195db: mov  rax,r9         # real spawn callback argument
0x4195de: lea  0x4195e7,rax   # second, redundant echo callback thunk
0x4195e5: jmp  0x419621
... second C-entry thunk, also calls echo ...
0x419621: mov  rax,[rbp+0]    # overwrites saved caller RBP
0x419628: mov  rbx,r10
0x41962b: mov  r9,rsi
0x41962e: mov  r10,rdx
0x419631: lea  [rbp-0x600],rdi
0x419638: call std::thread::spawn
```

The observed corrupt value exactly matches the second thunk address. This is
an emitted frame-header store, not a pthread cleanup or interposer write.
The original test remains intact; neither a compiler change nor an assertion
workaround is included here.

`function_address_result_unwrap.lani` is a candidate small reduction preserving
the named function address passed into a call returning a record inside
`Result`, immediately followed by `.unwrap()`. It removes threads, C calls,
raw memory and allocation. Its runtime behavior is not yet confirmed; root
owns compiler/native runs. Expected correct behavior is a clean exit with
status zero and no output.

Three controls are ready for the same root-owned native driver:

- `function_address_named_local.lani` names `entry:ptr=echo` before the
  otherwise identical `make(entry,...).unwrap()` expression.
- `function_address_split_result.lani` also separates the call from unwrap.
- `thread_named_entry.lani` uses a real canonical thread with the named entry
  pointer, joins a null return value and then returns from its helper.

The integration driver registers the intended-success inline reproduction as
ignored while the dependency is unresolved, plus these three controls. None
has yet been executed in this reduced form. The full failing lifecycle gate
has not been weakened or ignored.
