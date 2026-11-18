// SDC digit-growth tables adapted from Rust core::num::dec2flt::decimal_seq.
// SPDX-License-Identifier: MIT OR Apache-2.0
// See third_party/rust-dec2flt/NOTICE.md. Only shifts 0..28 are retained.
static const uint FLOAT_DECIMAL_LEFT_SHIFT_TABLE[30] = {
    0x0000u, 0x0800u, 0x0801u, 0x0803u, 0x1006u, 0x1009u, 0x100du, 0x1812u, 0x1817u, 0x181du,
    0x2024u, 0x202bu, 0x2033u, 0x203cu, 0x2846u, 0x2850u, 0x285bu, 0x3067u, 0x3073u, 0x3080u,
    0x388eu, 0x389cu, 0x38abu, 0x38bbu, 0x40ccu, 0x40ddu, 0x40efu, 0x4902u, 0x4915u, 0x4929u,
};
static const uint FLOAT_DECIMAL_LEFT_SHIFT_POW5[297] = {
    5u, 2u, 5u, 1u, 2u, 5u, 6u, 2u, 5u, 3u, 1u, 2u, 5u, 1u, 5u, 6u, 2u, 5u, 7u, 8u, 1u, 2u, 5u, 3u, 9u,
    0u, 6u, 2u, 5u, 1u, 9u, 5u, 3u, 1u, 2u, 5u, 9u, 7u, 6u, 5u, 6u, 2u, 5u, 4u, 8u, 8u, 2u, 8u, 1u, 2u,
    5u, 2u, 4u, 4u, 1u, 4u, 0u, 6u, 2u, 5u, 1u, 2u, 2u, 0u, 7u, 0u, 3u, 1u, 2u, 5u, 6u, 1u, 0u, 3u, 5u,
    1u, 5u, 6u, 2u, 5u, 3u, 0u, 5u, 1u, 7u, 5u, 7u, 8u, 1u, 2u, 5u, 1u, 5u, 2u, 5u, 8u, 7u, 8u, 9u, 0u,
    6u, 2u, 5u, 7u, 6u, 2u, 9u, 3u, 9u, 4u, 5u, 3u, 1u, 2u, 5u, 3u, 8u, 1u, 4u, 6u, 9u, 7u, 2u, 6u, 5u,
    6u, 2u, 5u, 1u, 9u, 0u, 7u, 3u, 4u, 8u, 6u, 3u, 2u, 8u, 1u, 2u, 5u, 9u, 5u, 3u, 6u, 7u, 4u, 3u, 1u,
    6u, 4u, 0u, 6u, 2u, 5u, 4u, 7u, 6u, 8u, 3u, 7u, 1u, 5u, 8u, 2u, 0u, 3u, 1u, 2u, 5u, 2u, 3u, 8u, 4u,
    1u, 8u, 5u, 7u, 9u, 1u, 0u, 1u, 5u, 6u, 2u, 5u, 1u, 1u, 9u, 2u, 0u, 9u, 2u, 8u, 9u, 5u, 5u, 0u, 7u,
    8u, 1u, 2u, 5u, 5u, 9u, 6u, 0u, 4u, 6u, 4u, 4u, 7u, 7u, 5u, 3u, 9u, 0u, 6u, 2u, 5u, 2u, 9u, 8u, 0u,
    2u, 3u, 2u, 2u, 3u, 8u, 7u, 6u, 9u, 5u, 3u, 1u, 2u, 5u, 1u, 4u, 9u, 0u, 1u, 1u, 6u, 1u, 1u, 9u, 3u,
    8u, 4u, 7u, 6u, 5u, 6u, 2u, 5u, 7u, 4u, 5u, 0u, 5u, 8u, 0u, 5u, 9u, 6u, 9u, 2u, 3u, 8u, 2u, 8u, 1u,
    2u, 5u, 3u, 7u, 2u, 5u, 2u, 9u, 0u, 2u, 9u, 8u, 4u, 6u, 1u, 9u, 1u, 4u, 0u, 6u, 2u, 5u,
};
