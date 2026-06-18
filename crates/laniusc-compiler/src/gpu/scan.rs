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
