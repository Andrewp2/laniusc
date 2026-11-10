//! Storage planning for one exclusive GPU native-layout job. A plan is a fresh
//! upload image bound to an exact source reference and proof-store submission;
//! it is neither proof authority nor an accepted layout. The dispatcher owns
//! execution, exact-buffer readback, and any resulting acceptance capability.

use std::sync::Arc;

use anyhow::{Result, ensure};

use super::abi::{INVALID, add, mul};

pub(super) const NATIVE_LAYOUT_WORK_MAGIC: u32 = 0x504c_4d31; // PLM1
pub(super) const NATIVE_LAYOUT_WORK_VERSION: u32 = 2;
pub(super) const NATIVE_LAYOUT_WORK_DIRECTORY: u32 = 24;
pub(super) const NATIVE_LAYOUT_WORK_TABLES: usize = 7;
pub(super) const NATIVE_LAYOUT_WORK_FIXED_WORDS: u32 =
    NATIVE_LAYOUT_WORK_DIRECTORY + NATIVE_LAYOUT_WORK_TABLES as u32 * 3;
pub(super) const NATIVE_LAYOUT_WORK_WIDTHS: [u32; NATIVE_LAYOUT_WORK_TABLES] =
    [8, 2, 2, 2, 4, 8, 4];

/// Descriptive provenance, not a constructible proof or accepted native value.
/// The reference is copied verbatim; the GPU validates its kind and admission.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct NativeLayoutSource {
    pub epoch: u64,
    pub arena_id: u64,
    pub serial: u32,
    pub reference: [u32; 2],
}

/// Allocation/work policy chosen by the caller. These totals are independent
/// of any source-language callable or nominal argument arity limits. Zero
/// capacities are allowed; a job that needs more storage must fail explicitly.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct NativeLayoutWorkLimits {
    pub nodes: u32,
    pub edges: u32,
    pub groups: u32,
    pub payload_roots: u32,
    pub visits: u32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct NativeLayoutWorkDirectory {
    pub offset: u32,
    pub capacity: u32,
    pub width: u32,
}

/// Immutable upload image. Cloning a plan copies descriptive storage only; a
/// previous GPU result cannot become this plan's fresh completion receipt.
#[derive(Clone, Debug)]
pub(super) struct NativeLayoutWorkPlan {
    pub source: NativeLayoutSource,
    pub limits: NativeLayoutWorkLimits,
    pub dirs: [NativeLayoutWorkDirectory; NATIVE_LAYOUT_WORK_TABLES],
    pub word_count: u32,
    pub words: Arc<[u32]>,
}

impl NativeLayoutWorkPlan {
    pub fn new(source: NativeLayoutSource, limits: NativeLayoutWorkLimits) -> Result<Self> {
        ensure!(
            source.epoch != 0
                && source.arena_id != 0
                && source.serial != 0
                && source.serial != INVALID,
            "native layout work has a reserved owner or serial"
        );
        ensure!(
            limits.visits != 0,
            "native layout work requires a nonzero visit limit"
        );
        // NodeLayouts has exactly one potential row for each semantic node.
        // Status and Result are single fixed rows even for a scalar-only job.
        let capacities = [
            limits.nodes,
            limits.edges,
            limits.groups,
            limits.payload_roots,
            limits.nodes,
            1,
            1,
        ];
        let mut dirs = [NativeLayoutWorkDirectory::default(); NATIVE_LAYOUT_WORK_TABLES];
        let mut word_count = NATIVE_LAYOUT_WORK_FIXED_WORDS;
        for (table, capacity) in capacities.into_iter().enumerate() {
            ensure!(
                capacity != INVALID,
                "native layout work capacity uses reserved row identity"
            );
            let width = NATIVE_LAYOUT_WORK_WIDTHS[table];
            let offset = if capacity == 0 { 0 } else { word_count };
            word_count = add(
                word_count,
                mul(capacity, width, "native layout work table")?,
                "native layout work arena",
            )?;
            dirs[table] = NativeLayoutWorkDirectory {
                offset,
                capacity,
                width,
            };
        }
        let mut words = Vec::new();
        words.try_reserve_exact(word_count as usize)?;
        words.resize(word_count as usize, 0);
        words[..13].copy_from_slice(&[
            NATIVE_LAYOUT_WORK_MAGIC,
            NATIVE_LAYOUT_WORK_VERSION,
            source.epoch as u32,
            (source.epoch >> 32) as u32,
            source.arena_id as u32,
            (source.arena_id >> 32) as u32,
            source.serial,
            0,
            source.reference[0],
            source.reference[1],
            0,
            0,
            word_count,
        ]);
        words[17] = limits.visits;
        // Words13..16: used rows; word18: charged visits; words19..20:
        // GPU-written initial semantic node/edge prefix. All begin at zero.
        // Words21..23 are reserved and also remain zero.
        for (table, directory) in dirs.iter().enumerate() {
            let at = NATIVE_LAYOUT_WORK_DIRECTORY as usize + table * 3;
            words[at..at + 3].copy_from_slice(&[
                directory.offset,
                directory.capacity,
                directory.width,
            ]);
        }
        let result = dirs[6].offset as usize;
        words[result..result + 4].copy_from_slice(&[0, INVALID, INVALID, 0]);
        Ok(Self {
            source,
            limits,
            dirs,
            word_count,
            words: words.into(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn source() -> NativeLayoutSource {
        NativeLayoutSource {
            epoch: 0x1234_5678_90ab_cdef,
            arena_id: 0xfedc_ba98_7654_3210,
            serial: 19,
            reference: [3, 81],
        }
    }

    fn empty_limits() -> NativeLayoutWorkLimits {
        NativeLayoutWorkLimits {
            nodes: 0,
            edges: 0,
            groups: 0,
            payload_roots: 0,
            visits: 1,
        }
    }

    #[test]
    fn native_layout_work_preserves_exact_source_and_starts_empty() {
        let source = source();
        let plan = NativeLayoutWorkPlan::new(source, empty_limits()).unwrap();
        assert_eq!(plan.source, source);
        assert_eq!(plan.word_count, 57);
        assert_eq!(
            &plan.words[..13],
            &[
                NATIVE_LAYOUT_WORK_MAGIC,
                2,
                0x90ab_cdef,
                0x1234_5678,
                0x7654_3210,
                0xfedc_ba98,
                19,
                0,
                3,
                81,
                0,
                0,
                57,
            ]
        );
        assert_eq!(&plan.words[13..17], &[0; 4]);
        assert_eq!(plan.words[17], 1);
        assert_eq!(&plan.words[18..24], &[0; 6]);
        for (table, directory) in plan.dirs[..5].iter().enumerate() {
            assert_eq!((directory.offset, directory.capacity), (0, 0));
            assert_eq!(directory.width, NATIVE_LAYOUT_WORK_WIDTHS[table]);
        }
        assert_eq!((plan.dirs[5].offset, plan.dirs[5].capacity), (45, 1));
        assert_eq!((plan.dirs[6].offset, plan.dirs[6].capacity), (53, 1));
        assert_eq!(&plan.words[45..53], &[0; 8]);
        assert_eq!(&plan.words[53..57], &[0, INVALID, INVALID, 0]);
        for (table, directory) in plan.dirs.iter().enumerate() {
            let at = 24 + table * 3;
            assert_eq!(
                &plan.words[at..at + 3],
                &[directory.offset, directory.capacity, directory.width]
            );
        }
        // Source identity remains descriptive: invalid semantic tags are passed
        // intact for GPU rejection, rather than treated as host proof authority.
        let invalid_reference = NativeLayoutSource {
            reference: [2, 9],
            ..source
        };
        let fresh = NativeLayoutWorkPlan::new(invalid_reference, empty_limits()).unwrap();
        assert_eq!(&fresh.words[8..10], &[2, 9]);
        assert_eq!(&fresh.words[45..53], &[0; 8]);
        assert_eq!(plan.source, source);
    }

    #[test]
    fn native_layout_work_uses_configured_capacity_and_rejects_arithmetic_overflow() {
        let limits = NativeLayoutWorkLimits {
            nodes: 129,
            edges: 257,
            groups: 65,
            payload_roots: 1025,
            visits: 65_000,
        };
        let plan = NativeLayoutWorkPlan::new(source(), limits).unwrap();
        assert_eq!(plan.limits, limits);
        assert_eq!(
            plan.dirs.map(|directory| directory.capacity),
            [129, 257, 65, 1025, 129, 1, 1]
        );
        assert_eq!(plan.word_count, 4299);
        assert_eq!(plan.words.len(), plan.word_count as usize);
        assert_eq!(plan.words[17], 65_000);
        assert_eq!(&plan.words[13..17], &[0; 4]);
        assert_eq!(&plan.words[18..24], &[0; 6]);
        assert!(
            plan.words[45..plan.dirs[6].offset as usize]
                .iter()
                .all(|&word| word == 0)
        );
        for (bad, message) in [
            (
                NativeLayoutWorkLimits {
                    nodes: INVALID,
                    ..limits
                },
                "reserved",
            ),
            (
                NativeLayoutWorkLimits {
                    nodes: 1 << 29,
                    ..limits
                },
                "overflow",
            ),
            (
                NativeLayoutWorkLimits {
                    payload_roots: 1 << 31,
                    ..limits
                },
                "overflow",
            ),
            (
                NativeLayoutWorkLimits {
                    visits: 0,
                    ..limits
                },
                "visit limit",
            ),
        ] {
            assert!(
                NativeLayoutWorkPlan::new(source(), bad)
                    .unwrap_err()
                    .to_string()
                    .contains(message)
            );
        }
        for invalid in [
            NativeLayoutSource {
                epoch: 0,
                ..source()
            },
            NativeLayoutSource {
                arena_id: 0,
                ..source()
            },
            NativeLayoutSource {
                serial: 0,
                ..source()
            },
            NativeLayoutSource {
                serial: INVALID,
                ..source()
            },
        ] {
            assert!(
                NativeLayoutWorkPlan::new(invalid, limits)
                    .unwrap_err()
                    .to_string()
                    .contains("reserved")
            );
        }
    }
}
