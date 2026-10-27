# Lexer workspace verification

This revision's native acceptance is pending. The unchanged independent model
still supplies 576 cases and the explicit tables 63. Historical per-rule scratch
allocation counts do not describe the new cursor owner.

`reuse.lani` uses actual Lexer/Cursor APIs. Its nine ACK checkpoints expose two
independent concurrent cursor workspaces, interleaved matching, retirement of
one while the other progresses, exact usage, completed skips before failure,
refused later-rule admission, empty/invalid input admission, and token backing
after cursor and compiled-owner destruction. It adds no production hooks.

`resources.py` imports the unchanged TempFile raw ELF verifier and
`archive_source/ledger.py`. It requires verified executable instruction ranges,
no named fallback, the exact 0x22/0x62 runtime profile at each allocation site,
full-width addresses, and original requested byte lengths. Checkpoints compare
live mappings with `/proc` and require only stdin/stdout/stderr descriptors.
Native exit cannot stand in for explicit release.

In the reuse probe, normal nonterminal next calls perform no selected native
work. All next calls allocate no source storage. EOF/error/destroy may release
their own storage once; repeated fused calls release nothing. Source owner sets
prove that retiring one cursor leaves the other cursor and compiled rules live.
The empty-input and invalid-UTF-8 admission phase neither maps nor releases.

`allocations.lani` now checks the actual fallible boundary: nonempty scan creates
scratch and can return `lexer::AllocationFailed` before a Cursor exists. A
successful constructor has zero usage. The campaign derives all reached source
allocation ordinals from the current baseline, binds the complete request prefix
and native instruction sites, and checks the exact input/pattern/build/first
constructor/second constructor error stage. Healthy rescan after a constructor
failure reads the original program and input. There is no per-rule search OOM
expectation. Later-rule WorkLimit/call/work admission semantics remain in the
unchanged contracts and semantic tables.

Python-only controls pass **30** assertions (17 reused provenance controls and
13 phase/causal controls). They execute no compiler or native Lanius.

Focused Rust filters in `extended_lexer_execution`:

- `independent_cursor_workspaces_preserve_tokens_and_allocate_only_during_construction`
- `every_reached_lexer_allocation_failure_preserves_sources_and_releases_exact_owners`
- `longest_and_lexer_match_independent_full_context_endpoint_model`
- `lexer_explicit_assertion_nullable_capture_validation_and_limit_tables`
- `lexer_build_and_input_admission_validate_bounds_exact_caps_and_cleanup`
- `longest_prefix_and_lexer_contracts_preserve_context_priority_progress_and_budgets`

Run one group at a time. The two Python native campaigns have finite deadlines;
root coordinates GPU compilation and all native execution.
