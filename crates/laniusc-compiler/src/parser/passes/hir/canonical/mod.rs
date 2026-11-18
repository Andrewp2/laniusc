use encase::ShaderType;

pub mod build_canonical_end_heaps;
pub mod build_canonical_links;
pub mod build_canonical_rows;
/// Publishes dense operand and call-argument ownership edges.
pub mod build_expr_forest_edges;
pub mod count_canonical_rows_in_blocks;
pub mod gather_canonical_stmts;
pub mod index_declarations_by_name;
pub mod list_canonical_rows;
pub mod map_canonical_aliases;
pub mod mark_canonical_rows;
/// Seeds compact expression-root pointer jumping.
pub mod seed_expr_forest_roots;
pub mod validate_canonical_hir;
/// Resolves compact expression roots.
pub mod walk_expr_forest_roots;

#[repr(C)]
#[derive(Clone, Copy, Default, ShaderType)]
pub struct CanonicalHirParams {
    pub raw_capacity: u32,
    pub canonical_capacity: u32,
    pub uses_status_count: u32,
    pub local_ancestor_span: u32,
    pub records_use_token_rows: u32,
}

/// Canonical family discovery already has a bounded parallel relation walk.
/// Seed only the direct raw parent here; scanning a long local ancestor span
/// for every raw grammar node duplicates that parallel work and makes sparse
/// families cost proportional to `raw_nodes * span`.
pub const RELATION_LOCAL_ANCESTOR_SPAN: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, Default, ShaderType)]
pub struct CanonicalScanParams {
    pub item_count: u32,
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use crate::parser::buffers::{
        HirArrayElement,
        HirCore,
        HirField,
        HirGenericParam,
        HirLinks,
        HirMatchArm,
        HirMatchPayload,
        HirMethodCore,
        HirMethodSignature,
        HirParam,
        HirPath,
        HirPathSegment,
        HirPayload,
        HirPredicate,
        HirRange,
        HirSemanticFacts,
        HirString,
        HirTypeArg,
        HirVariant,
        HirVariantPayload,
    };

    fn dense_winners(anchors: &[Option<u32>], capacity: u32) -> Result<Vec<usize>, u32> {
        let mut winner_by_anchor = BTreeMap::<u32, usize>::new();
        for (raw, anchor) in anchors.iter().copied().enumerate() {
            let Some(anchor) = anchor else { continue };
            if anchor >= capacity {
                return Err(anchor);
            }
            winner_by_anchor
                .entry(anchor)
                .and_modify(|winner| *winner = (*winner).max(raw))
                .or_insert(raw);
        }
        let mut winners = winner_by_anchor.into_values().collect::<Vec<_>>();
        winners.sort_unstable();
        Ok(winners)
    }

    #[test]
    fn compact_hir_record_layout_is_stable() {
        assert_eq!(core::mem::size_of::<HirCore>(), 16);
        assert_eq!(core::mem::size_of::<HirLinks>(), 16);
        assert_eq!(core::mem::size_of::<HirPayload>(), 16);
        assert_eq!(core::mem::size_of::<HirRange>(), 8);
        assert_eq!(core::mem::size_of::<HirParam>(), 16);
        assert_eq!(core::mem::size_of::<HirTypeArg>(), 20);
        assert_eq!(core::mem::size_of::<HirGenericParam>(), 16);
        assert_eq!(core::mem::size_of::<HirPath>(), 16);
        assert_eq!(core::mem::size_of::<HirPathSegment>(), 16);
        assert_eq!(core::mem::size_of::<HirField>(), 16);
        assert_eq!(core::mem::size_of::<HirVariant>(), 16);
        assert_eq!(core::mem::size_of::<HirVariantPayload>(), 16);
        assert_eq!(core::mem::size_of::<HirMatchArm>(), 16);
        assert_eq!(core::mem::size_of::<HirMatchPayload>(), 16);
        assert_eq!(core::mem::size_of::<HirArrayElement>(), 16);
        assert_eq!(core::mem::size_of::<HirString>(), 16);
        assert_eq!(core::mem::size_of::<HirMethodCore>(), 16);
        assert_eq!(core::mem::size_of::<HirMethodSignature>(), 16);
        assert_eq!(core::mem::size_of::<HirPredicate>(), 16);
        assert_eq!(core::mem::size_of::<HirSemanticFacts>(), 32);
    }

    #[test]
    fn dense_ids_follow_raw_order_after_unique_anchor_selection() {
        let anchors = [Some(4), None, Some(2), Some(4), Some(8), Some(2)];
        assert_eq!(dense_winners(&anchors, 9), Ok(vec![3, 4, 5]));
    }

    #[test]
    fn anchor_outside_token_or_file_sentinel_capacity_is_rejected() {
        assert_eq!(dense_winners(&[Some(0), Some(5)], 5), Err(5));
    }

    #[test]
    fn payload_encodes_side_table_start_and_count_without_raw_node_ids() {
        let payload = HirPayload {
            a: 7,
            b: 41,
            c: 3,
            d: 0,
        };
        assert_eq!((payload.b, payload.c), (41, 3));
    }
}
