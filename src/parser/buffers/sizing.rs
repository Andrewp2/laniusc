use crate::parser::tables::PrecomputedParseTables;

pub(super) const LL1_BLOCK_SIZE: u32 = 8192;
pub(super) const LL1_BLOCK_EMIT_STRIDE: u32 = 65_536;
pub(super) const LL1_SEED_PLAN_STATUS_WORDS: usize = 8;

pub(super) fn parser_table_uses_ll1_tree_stream(tables: &PrecomputedParseTables) -> bool {
    // The live parser follows Pareas/the Parallel LL paper: adjacent token-pair
    // table extraction plus prefix packing and bracket validation. The LL(1)
    // tables remain useful for tests and grammar diagnostics, but the seeded
    // LL(1) replay path is not the production tree stream.
    let _ = tables;
    false
}

pub(super) fn pair_capacity_for_tree_stream(tree_stream_uses_ll1: bool, n_pairs: usize) -> usize {
    if tree_stream_uses_ll1 {
        1
    } else {
        n_pairs.max(1)
    }
}

pub(crate) fn resident_projected_tree_capacity_for_tables(
    n_tokens: u32,
    tables: &PrecomputedParseTables,
) -> u32 {
    let n_pairs = n_tokens.saturating_sub(1);
    let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0);
    let total_emit = n_pairs.saturating_mul(max_emit_len);
    resident_projected_tree_capacity(total_emit)
}

pub(super) fn resident_projected_tree_capacity(total_emit: u32) -> u32 {
    total_emit.max(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn live_parser_does_not_select_legacy_ll1_tree_stream() {
        let mut tables = PrecomputedParseTables::new(4, 1);
        tables.n_nonterminals = 1;
        tables.ll1_predict = vec![0; tables.n_kinds as usize];
        tables.pp_superseq = vec![1, 2, 3];

        assert!(!parser_table_uses_ll1_tree_stream(&tables));
    }

    #[test]
    fn pair_capacity_only_shrinks_when_ll1_tree_stream_is_explicit() {
        assert_eq!(pair_capacity_for_tree_stream(false, 50_000), 50_000);
        assert_eq!(pair_capacity_for_tree_stream(true, 50_000), 1);
        assert_eq!(pair_capacity_for_tree_stream(false, 0), 1);
    }

    #[test]
    fn resident_tree_capacity_is_capacity_derived_and_bounded() {
        assert_eq!(resident_projected_tree_capacity(1_000_000), 1_000_000);
        assert_eq!(resident_projected_tree_capacity(25_000), 25_000);
        assert_eq!(resident_projected_tree_capacity(0), 1);
    }

    #[test]
    fn resident_tree_capacity_from_tables_is_bounded_by_table_projection() {
        let mut tables = PrecomputedParseTables::new(4, 1);
        tables.pp_len = vec![0, 7, 3, 1];

        assert_eq!(
            resident_projected_tree_capacity_for_tables(10_000, &tables),
            69_993
        );
    }
}
