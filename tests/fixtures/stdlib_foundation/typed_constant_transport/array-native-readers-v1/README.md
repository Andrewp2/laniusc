# Unexecuted source cases

No parser, shader, compiler, x86 or GPU run was performed in this lane. These are inputs for root integration, not evidence of working runtime behavior.

- `runtime_enum_array_field.lani`: expected executable exit 0; nested enum array counts resolve from a typed named U64 constant, and the trailing field checks total layout/offset.
- `runtime_adjusted_receiver.lani`: expected executable exit 0; borrowed fixed array method receiver is dereferenced, then forwarded through a generic body and selected concrete replay.
- `reject_negative_count.lani`: semantic count rejection; signed negative must not become a low-word count.
- `reject_native_marker_count.lani`: count fits U32 but collides with native runtime-slice marker; compilation must fail explicitly rather than lower it as a slice.
- `reject_native_invalid_count.lani`: all U32 bits set remains a valid constant but cannot become an absent native extent; compilation must fail explicitly.

Reuse the prior array-source package's runtime_count_identity and runtime_empty_count cases for equal counts under distinct atom rows, mixed declared scalar widths, nested arrays and zero repetitions. Its reject_count_fit covers a nonzero high limb.

A focused pass-level probe is still required at integration for receiver rows: symbolic integer/projection -> ARRAY_PAIR + INVALID and function flag cleared; concrete selected atom -> exact extent and selected function definition; invalid projection/float/negative/overflow -> explicit failure. Source inputs alone cannot demonstrate malformed retained graph rejection.
