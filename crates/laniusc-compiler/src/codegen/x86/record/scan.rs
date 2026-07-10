use super::super::{
    X86RegallocParams,
    X86ScanParams,
    support::{
        UniformBindingArray,
        scan_steps_for_blocks,
        uniform_u32_struct_array,
        x86_regalloc_params_bytes,
        x86_scan_params_bytes,
    },
};

/// Builds scan parameter uniforms for a block-count-derived step sequence.
pub(super) fn scan_params(
    device: &wgpu::Device,
    label: &str,
    n_items: usize,
    n_blocks: usize,
    inst_capacity: usize,
) -> UniformBindingArray {
    let steps = scan_steps_for_blocks(n_blocks);
    scan_params_for_steps(device, label, &steps, n_items, n_blocks, inst_capacity)
}

/// Builds scan parameter uniforms for an explicit step sequence.
pub(super) fn scan_params_for_steps(
    device: &wgpu::Device,
    label: &str,
    steps: &[u32],
    n_items: usize,
    n_blocks: usize,
    inst_capacity: usize,
) -> UniformBindingArray {
    let param_bytes = steps
        .iter()
        .map(|step| {
            let params = X86ScanParams {
                n_items: n_items as u32,
                n_blocks: n_blocks as u32,
                scan_step: *step,
                inst_capacity: inst_capacity as u32,
            };
            x86_scan_params_bytes(&params)
        })
        .collect::<Vec<_>>();
    uniform_u32_struct_array(device, label, &param_bytes)
}

/// Builds register-allocation chunk parameter uniforms.
pub(super) fn regalloc_params(
    device: &wgpu::Device,
    label: &str,
    _chunk_count: usize,
) -> UniformBindingArray {
    let param_bytes = [
        X86RegallocParams {
            chunk_start: 0,
            chunk_len: 0,
            init_status: 1,
            reserved: 0,
        },
        X86RegallocParams {
            chunk_start: 0,
            chunk_len: 0,
            init_status: 0,
            reserved: 0,
        },
    ]
    .iter()
    .map(x86_regalloc_params_bytes)
    .collect::<Vec<_>>();
    uniform_u32_struct_array(device, label, &param_bytes)
}

/// Returns the ping-pong prefix buffer holding the final scan result.
pub(super) fn final_ping_pong_scan_prefix<'a>(
    params: &UniformBindingArray,
    prefix_a: &'a wgpu::Buffer,
    prefix_b: &'a wgpu::Buffer,
) -> &'a wgpu::Buffer {
    if (params.len() - 1) % 2 == 0 {
        prefix_a
    } else {
        prefix_b
    }
}
