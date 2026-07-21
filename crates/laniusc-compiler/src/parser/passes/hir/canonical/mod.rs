use encase::ShaderType;

pub mod array_elements;
pub mod call_args;
pub mod core;
pub mod expr_forest;
pub mod fields;
pub mod generic_params;
pub mod local;
pub mod mark;
pub mod matches;
pub mod methods;
pub mod nav;
pub mod params;
pub mod parent_init;
pub mod paths;
pub mod predicates;
pub mod scatter;
pub mod strings;
pub mod type_args;
pub mod validate;
pub mod variants;

#[repr(C)]
#[derive(Clone, Copy, Default, ShaderType)]
pub struct CanonicalHirParams {
    pub raw_capacity: u32,
    pub canonical_capacity: u32,
    pub uses_status_count: u32,
    pub local_ancestor_span: u32,
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
    fn compact_hir_records_are_three_four_word_rows() {
        assert_eq!(core::mem::size_of::<HirCore>(), 16);
        assert_eq!(core::mem::size_of::<HirLinks>(), 16);
        assert_eq!(core::mem::size_of::<HirPayload>(), 16);
        assert_eq!(core::mem::size_of::<HirRange>(), 8);
        assert_eq!(core::mem::size_of::<HirParam>(), 16);
        assert_eq!(core::mem::size_of::<HirTypeArg>(), 16);
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
