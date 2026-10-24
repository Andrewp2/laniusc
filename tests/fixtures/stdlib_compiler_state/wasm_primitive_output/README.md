# Historical primitive-output compiler control

`stdio_print_i32.lani` preserves the exact source previously stored at
`sample_programs/stdio_print_i32.lani` before its checked native-output
migration. `tests/cli_wasm_execution.rs` uses this source to retain its
existing Wasm primitive-output compiler regression context and unchanged
`34\n55\n` output contract.

This fixture is historical compiler evidence. It is not a production library
output interface or a fallback for the migrated native sample.
