/// One ping/pong prefix-scan recording step.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PingPongScanStep {
    /// Scan stride or final-copy marker consumed by the shader.
    pub scan_step: u32,
    /// Whether this step reads from the first buffer.
    pub read_from_a: bool,
    /// Whether this step writes to the first buffer.
    pub write_to_a: bool,
}

/// One level in a 256-way hierarchical prefix scan.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HierarchicalScanLevel {
    /// Number of level elements covered by one element at this level.
    pub divisor: u32,
    /// Maximum number of active elements at this level.
    pub count: u32,
    /// Offset of this level in the compact upper-level scratch buffer.
    /// Level zero uses the separate block-prefix buffer and therefore has
    /// offset zero without occupying hierarchy scratch.
    pub offset: u32,
}

/// Plans a 256-way scan hierarchy whose top level fits one workgroup.
pub fn hierarchical_scan_levels(n_blocks: u32) -> Vec<HierarchicalScanLevel> {
    let mut levels = vec![HierarchicalScanLevel {
        divisor: 1,
        count: n_blocks.max(1),
        offset: 0,
    }];
    let mut hierarchy_offset = 0u32;
    while levels.last().is_some_and(|level| level.count > 256) {
        let child = *levels.last().expect("hierarchical scan level");
        let parent_count = child.count.div_ceil(256);
        levels.push(HierarchicalScanLevel {
            divisor: child
                .divisor
                .checked_mul(256)
                .expect("u32 block count cannot require a wider scan divisor"),
            count: parent_count,
            offset: hierarchy_offset,
        });
        hierarchy_offset = hierarchy_offset
            .checked_add(parent_count)
            .expect("hierarchical scan scratch offset overflow");
    }
    debug_assert!(hierarchy_offset <= n_blocks.max(1));
    levels
}

/// Policy for adding a final ping/pong scan step.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ScanFinalize {
    /// Do not add a final step.
    None,
    /// Always append a final step with this marker/stride.
    Always(u32),
    /// Append a final copy-to-A step only when the last writer is B.
    CopyToAIfNeeded(u32),
}

/// Returns scan stride values for a simple ping/pong scan.
pub fn scan_step_values(n_blocks: u32) -> Vec<u32> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::None)
        .into_iter()
        .map(|step| step.scan_step)
        .collect()
}

/// Plans ping/pong scan buffer roles for `n_blocks`.
pub fn ping_pong_scan_steps(n_blocks: u32, finalize: ScanFinalize) -> Vec<PingPongScanStep> {
    let mut steps = Vec::new();
    steps.push(PingPongScanStep {
        scan_step: 0,
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(PingPongScanStep {
            scan_step: step,
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    match finalize {
        ScanFinalize::None => {}
        ScanFinalize::Always(final_step) => {
            let read_from_a = step_count % 2 == 0;
            steps.push(PingPongScanStep {
                scan_step: final_step,
                read_from_a,
                write_to_a: !read_from_a,
            });
        }
        ScanFinalize::CopyToAIfNeeded(final_step) => {
            if step_count % 2 == 1 {
                steps.push(PingPongScanStep {
                    scan_step: final_step,
                    read_from_a: false,
                    write_to_a: true,
                });
            }
        }
    }

    steps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hierarchical_scan_plan_handles_workgroup_boundaries() {
        assert_eq!(
            hierarchical_scan_levels(256),
            vec![HierarchicalScanLevel {
                divisor: 1,
                count: 256,
                offset: 0,
            }]
        );
        assert_eq!(
            hierarchical_scan_levels(257),
            vec![
                HierarchicalScanLevel {
                    divisor: 1,
                    count: 257,
                    offset: 0,
                },
                HierarchicalScanLevel {
                    divisor: 256,
                    count: 2,
                    offset: 0,
                },
            ]
        );
    }

    #[test]
    fn hierarchical_scan_plan_recurses_and_fits_block_sized_scratch() {
        for n_blocks in [1, 257, 65_537, 16_777_217, u32::MAX] {
            let levels = hierarchical_scan_levels(n_blocks);
            assert!(levels.last().is_some_and(|level| level.count <= 256));
            for pair in levels.windows(2) {
                assert_eq!(pair[1].count, pair[0].count.div_ceil(256));
                assert_eq!(pair[1].divisor, pair[0].divisor * 256);
            }
            let scratch_end = levels
                .iter()
                .skip(1)
                .map(|level| level.offset + level.count)
                .max()
                .unwrap_or(0);
            assert!(scratch_end <= n_blocks.max(1));
        }
    }
}
