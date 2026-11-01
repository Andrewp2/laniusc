# String byte ownership transfer contracts

`contracts.lani` exercises `alloc::string::from_utf8_vec` and
`String::into_bytes`. Eight valid inputs cover unallocated/reserved empties,
ASCII, embedded NUL, all UTF-8 widths and scalar range boundaries. Twelve
invalid inputs check the first malformed sequence offset and preserve every
initialized byte, storage pointer, length and spare capacity before repair.
Two truncated initialized prefixes ensure validation ignores unused capacity.

The fixture checks the exact backing pointer and capacity through transfers
and repeated adoption, and reuses the emptied Vec and String independently.
Every allocation is explicitly released; repeated destruction of emptied
owners must remain harmless. Forty-two `P`/`p` phases contain validation and
ownership transfer. The Rust driver requires no traced host call inside them,
and matches all 37 successful allocations to one release of the same address
and extent before the final `D` checkpoint.

## Accepted execution

`owned-input-string-transfer-first.log` records one passing native Linux
x86_64 test in 6.77 seconds, after a 1.87-second driver build. The strict ELF
driver accepted all 42 validation/transfer phases and all 37 address/extent
matched owner releases. The tested String source SHA256 is
`2196e427ba4091eafc7de4c13ae66c640027fa1f3ad1b5c63b2c53b2348d6282`.

The phase check observes only the selected traced syscalls (`execve`, `write`,
`mmap`, `mremap`, `munmap`, `brk`, `exit` and `exit_group`); it is not a universal
host-call observation. This receipt covers these finite executable contracts
on native CPU output from the GPU compiler. Physical backing and manual
owner/borrow discipline remain caller obligations.
