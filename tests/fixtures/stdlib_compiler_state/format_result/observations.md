# Observed native compiler outcomes

Recorded 2026-10-23 using the existing native CLI and current stdlib. Each compiler command had a 100 second limit; each emitted executable had a 10 second limit. Compiler source was unchanged.

| Case | Compiler exit | Native result |
| --- | --- | --- |
| forward-nested | 1 | not emitted |
| forward-typed | 1 | not emitted |
| direct-nested | 1 | not emitted |
| direct-typed | 1 | not emitted |
| unwrap-original | 1 | not emitted |
| unwrap-control | 0 | exit 0; stdout b''; stderr b'' |
| context-original | 0 | exit 1; stdout b''; stderr b'' |
| context-control | 0 | exit 1; stdout b''; stderr b'' |

### forward-nested

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-forward-nested -o /tmp/lanius-state-forward-nested /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/primitive-display.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-forward-nested/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### forward-typed

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-forward-typed -o /tmp/lanius-state-forward-typed /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/primitive-display-typed.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-forward-typed/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### direct-nested

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-direct-nested -o /tmp/lanius-state-direct-nested /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/primitive-display.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-direct-nested/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### direct-typed

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-direct-typed -o /tmp/lanius-state-direct-typed /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/primitive-display-typed.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-direct-typed/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### unwrap-original

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-unwrap-original -o /tmp/lanius-state-unwrap-original /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/unwrap-driver.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-unwrap-original/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### unwrap-control

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-unwrap-control -o /tmp/lanius-state-unwrap-control /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/unwrap-driver.lani
```

No compiler diagnostic.

Native outcome: exit 0; stdout b''; stderr b''.

### context-original

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-context-original -o /tmp/lanius-state-context-original /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/context-repro.lani
```

No compiler diagnostic.

Native outcome: exit 1; stdout b''; stderr b''.

### context-control

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-context-control -o /tmp/lanius-state-context-control /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/context-control.lani
```

No compiler diagnostic.

Native outcome: exit 1; stdout b''; stderr b''.

## Recheck against final production imports

After removing the unused core::fmt import from core::format and excluding the generic owned helper from production, each temporary stdlib was copied from the final production tree and only alloc/format.lani was replaced by the preserved prototype. No baseline/core/format override was used here.

| Case | Compiler exit | Native result |
| --- | --- | --- |
| final-primitive | 1 | not emitted |
| final-unwrap-original | 1 | not emitted |
| final-unwrap-control | 0 | exit 0; stdout b''; stderr b'' |

### final-primitive

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-final-primitive -o /tmp/lanius-state-final-primitive /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/primitive-display-typed.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-final-primitive/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### final-unwrap-original

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-final-unwrap-original -o /tmp/lanius-state-final-unwrap-original /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/unwrap-driver.lani
```

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-final-unwrap-original/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

Native outcome: not emitted.

### final-unwrap-control

```sh
/home/andrew-peterson/code/laniusc/target/stdlib-build/debug/laniusc --stdlib-root /tmp/lanius-state-root-final-unwrap-control -o /tmp/lanius-state-final-unwrap-control /home/andrew-peterson/code/laniusc/tests/fixtures/stdlib_compiler_state/format_result/unwrap-driver.lani
```

No compiler diagnostic.

Native outcome: exit 0; stdout b''; stderr b''.
