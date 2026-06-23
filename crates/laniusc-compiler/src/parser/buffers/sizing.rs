use crate::parser::tables::PrecomputedParseTables;

/// Derives resident tree capacity from token count and partial-parse emit width.
pub(crate) fn resident_partial_parse_tree_capacity_for_tables(
    n_tokens: u32,
    tables: &PrecomputedParseTables,
) -> u32 {
    let n_pairs = n_tokens.saturating_sub(1);
    let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0);
    let total_emit = n_pairs.saturating_mul(max_emit_len);
    resident_partial_parse_tree_capacity(total_emit)
}

/// Normalizes resident tree capacity to at least one row.
pub(super) fn resident_partial_parse_tree_capacity(total_emit: u32) -> u32 {
    total_emit.max(1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resident_tree_capacity_is_capacity_derived_and_bounded() {
        assert_eq!(resident_partial_parse_tree_capacity(1_000_000), 1_000_000);
        assert_eq!(resident_partial_parse_tree_capacity(25_000), 25_000);
        assert_eq!(resident_partial_parse_tree_capacity(0), 1);
    }

    #[test]
    fn resident_tree_capacity_from_tables_is_bounded_by_partial_parse_table() {
        let mut tables = PrecomputedParseTables::new(4, 1);
        tables.pp_len = vec![0, 7, 3, 1];

        assert_eq!(
            resident_partial_parse_tree_capacity_for_tables(10_000, &tables),
            69_993
        );
    }
}
