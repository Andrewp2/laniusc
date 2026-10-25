# Generic fixed-array specialization boundary

`input.lani` preserves the exact generic `[u8;65536]` layout reduction
formerly stored with TLS fixtures. It imports only `core::mem` and borrows
zero elements; it contains no TLS or cryptographic implementation/import.
Its existing source comment records the historical failed compiler probe.

No new compilation or runtime outcome is claimed by this relocation.
