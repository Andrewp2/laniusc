const PAIR_01: &str = include_str!("../shaders/lexer/pair_01_sum_inblock.slang");
const PAIR_02: &str = include_str!("../shaders/lexer/pair_02_scan_block_totals.slang");
const PAIR_03: &str = include_str!("../shaders/lexer/pair_03_apply_block_prefix.slang");
const COMPACT: &str = include_str!("../shaders/lexer/compact_boundaries.slang");
const TOKENS_BUILD: &str = include_str!("../shaders/lexer/tokens_build.slang");
const TOKENS_FILE_IDS: &str = include_str!("../shaders/lexer/tokens_file_ids.slang");

#[test]
fn lexer_byte_thread_passes_linearize_2d_dispatch_ids() {
    for (name, shader) in [
        ("pair_02_scan_block_totals", PAIR_02),
        ("compact_boundaries", COMPACT),
        ("tokens_build", TOKENS_BUILD),
        ("tokens_file_ids", TOKENS_FILE_IDS),
    ] {
        assert!(
            shader.contains("linear_dispatch_thread_id_2d"),
            "{name} must consume both dispatch dimensions when D1 dispatch tiling crosses 65535 workgroups"
        );
    }
}

#[test]
fn lexer_block_group_passes_linearize_2d_group_ids() {
    for (name, shader) in [
        ("pair_01_sum_inblock", PAIR_01),
        ("pair_03_apply_block_prefix", PAIR_03),
    ] {
        assert!(
            shader.contains("ggrp.y * MAX_GROUPS_X + ggrp.x"),
            "{name} must consume both group dimensions when source byte blocks cross 65535 workgroups"
        );
    }
}
