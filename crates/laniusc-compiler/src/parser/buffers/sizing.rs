use crate::{
    lexer::features::{
        PARSER_FEATURE_ARRAYS,
        PARSER_FEATURE_ENUMS,
        PARSER_FEATURE_MATCHES,
        PARSER_FEATURE_STRUCTS,
    },
    parser::tables::PrecomputedParseTables,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct ParserFamilyCapacities {
    pub arrays: u32,
    pub enum_match: u32,
    pub structs: u32,
}

impl ParserFamilyCapacities {
    pub(super) fn new(tree_capacity: u32, parser_feature_flags: u32) -> Self {
        let tree_capacity = tree_capacity.max(1);
        Self {
            arrays: feature_capacity(tree_capacity, parser_feature_flags, PARSER_FEATURE_ARRAYS),
            enum_match: feature_capacity(
                tree_capacity,
                parser_feature_flags,
                PARSER_FEATURE_ENUMS | PARSER_FEATURE_MATCHES,
            ),
            structs: feature_capacity(tree_capacity, parser_feature_flags, PARSER_FEATURE_STRUCTS),
        }
    }
}

fn feature_capacity(tree_capacity: u32, parser_feature_flags: u32, mask: u32) -> u32 {
    if parser_feature_flags & mask == 0 {
        1
    } else {
        tree_capacity
    }
}

/// Derives resident tree capacity from token count and partial-parse emit width.
pub(crate) fn resident_partial_parse_tree_capacity_for_tables(
    n_tokens: u32,
    tables: &PrecomputedParseTables,
) -> u32 {
    let n_pairs = n_tokens.saturating_sub(1);
    let max_emit_len = resident_virtual_pair_width(&tables.pp_len, tables.n_kinds);
    let total_emit = n_pairs.saturating_mul(max_emit_len);
    resident_partial_parse_tree_capacity(total_emit)
}

/// Maximum table width emitted by one physical adjacent pair. A contextual
/// `>>` concatenates `(previous, inner-close)` and
/// `(inner-close, outer-close)`; no other physical pair expands.
pub(super) fn resident_virtual_pair_width(widths: &[u32], n_kinds: u32) -> u32 {
    let mut maximum = widths.iter().copied().max().unwrap_or(0);
    const GENERIC_CLOSE_KINDS: [u32; 4] = [132, 134, 176, 185];
    for previous in 0..n_kinds {
        for inner in GENERIC_CLOSE_KINDS {
            for outer in GENERIC_CLOSE_KINDS {
                let first = widths
                    .get((previous * n_kinds + inner) as usize)
                    .copied()
                    .unwrap_or(0);
                let second = widths
                    .get((inner * n_kinds + outer) as usize)
                    .copied()
                    .unwrap_or(0);
                maximum = maximum.max(first.saturating_add(second));
            }
        }
    }
    maximum
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

    #[test]
    fn absent_optional_parser_families_use_sentinel_capacity() {
        assert_eq!(
            ParserFamilyCapacities::new(1_000_000, 0),
            ParserFamilyCapacities {
                arrays: 1,
                enum_match: 1,
                structs: 1,
            }
        );
    }

    #[test]
    fn present_optional_parser_families_retain_full_tree_address_space() {
        assert_eq!(
            ParserFamilyCapacities::new(1_000_000, PARSER_FEATURE_ARRAYS),
            ParserFamilyCapacities {
                arrays: 1_000_000,
                enum_match: 1,
                structs: 1,
            }
        );
        assert_eq!(
            ParserFamilyCapacities::new(1_000_000, PARSER_FEATURE_ENUMS),
            ParserFamilyCapacities {
                arrays: 1,
                enum_match: 1_000_000,
                structs: 1,
            }
        );
        assert_eq!(
            ParserFamilyCapacities::new(1_000_000, PARSER_FEATURE_MATCHES),
            ParserFamilyCapacities {
                arrays: 1,
                enum_match: 1_000_000,
                structs: 1,
            }
        );
        assert_eq!(
            ParserFamilyCapacities::new(1_000_000, PARSER_FEATURE_STRUCTS),
            ParserFamilyCapacities {
                arrays: 1,
                enum_match: 1,
                structs: 1_000_000,
            }
        );
    }
}
