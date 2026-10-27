# Generic fixed-array specialization boundary

Status (2026-10-27): a deliberate limit, not a slip. Three places agree on it: the host packet check in `generic_body.rs` (`append_checked_node`), the GPU replay check in `semantic/artifact/01c2_validate_body_native_layout.slang` (detail 8: a replay argument wider than 0xffff words), and x86 call encoding, which packs stack words into 16 bits (`codegen/lir/x86/common.slang`). Removing only the host check moves the rejection to LNC0047 detail 8. Lifting it means widening the x86 frame and call-result encoding to 32-bit word counts. That change is not scheduled.

`input.lani` preserves the exact generic `[u8;65536]` layout reduction
formerly stored with TLS fixtures. It imports only `core::mem` and borrows
zero elements; it contains no TLS or cryptographic implementation/import.
Its existing source comment records the historical failed compiler probe.

No new compilation or runtime outcome is claimed by this relocation.
