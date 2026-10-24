# Empty function definitions

An empty block is a real function definition. Its callable identity must resolve
to a native body that returns normally. A required trait method ending in `;`
has no definition and must still require an implementation.

`native.lani` exercises these forms with no allocations or host IO:

- Two distinct local free empty functions and two public imported empty functions.
- An empty nested block and an explicit bare-return control.
- Imported inherent static and receiver methods with empty blocks.
- Entry-local empty implementations of an imported nongeneric trait and an
  imported generic `Destroy<T>` trait.
- Direct, local generic, and imported generic dispatch to those implementations.
- Nonempty functions before, between, and after empty calls, preserving negative
  `i32` and high `u64` record payloads.
- A nonempty void function that mutates borrowed storage and returns implicitly.

`empty_entry.lani` and `bare_return_entry.lani` cover the corresponding minimal
void entry functions. The rejection entries keep the bodyless required trait
declaration but supply no implementation: one calls through the imported bound
helper and one attempts a direct call.

The Rust driver checks each produced executable with the common strict x86
control-transfer checker, executes it, and requires zero exit status and no
output. It repeats the main fixture after rejected compilation jobs to exercise
reuse in the same GPU process.

```sh
cargo test --test compiler_empty_body_execution -- --test-threads=1
```

This is focused coverage of GPU-compiled x86-64 Linux execution. The test-only
empty methods operate on trivial copied records and intentionally do no work;
they are not production ownership APIs.
