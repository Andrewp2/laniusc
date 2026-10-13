# Array cases (not executed)

Use the existing executable compiler harness after root integration. Keep every command below two minutes.

- runtime_count_identity.lani: x86 compile/specialize/link/run, expected exit0. Tests authored U32 counts vs independent named u64/i16 values, u8 inference, symbolic U64 forwarding, nested literal context, and indexing. Every count must resolve from its atom value rather than its storage row.
- runtime_empty_count.lani: independent empty-array executable case, expected exit0; a zero count is a valid closed value.
- reject_array_parameter_bool.lani: explicit invalid-array-count diagnostic even in an otherwise unused generic declaration.
- reject_count_fit.lani: explicit count-fit rejection for a named U64 value with nonzero high limb.

Reuse source package reject_negative_array, reject_noninteger_array and grammar_and_hir_boundaries. Do not allocate a u32::MAX array to test scalar validity. Add an integrated map-backed GPU probe for an unresolved projection (count reader false), mapped negative/high-limb parameter (false), and mapped small positive value (true) when root runs the focused GPU gate. Descriptor equality is not executable closure evidence.
