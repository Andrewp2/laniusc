use super::support::scan_steps_for_blocks;

pub(super) struct WasmBufferCapacities {
    pub body_item_capacity: u32,
    pub body_scan_blocks: u32,
    pub body_scan_steps: Vec<u32>,
    pub arg_record_capacity: u32,
    pub arg_scan_blocks: u32,
    pub arg_scan_steps: Vec<u32>,
    pub func_scan_blocks: u32,
    pub func_scan_steps: Vec<u32>,
}

impl WasmBufferCapacities {
    pub(super) fn for_input(token_capacity: u32, hir_node_capacity: u32) -> Self {
        let body_item_capacity = token_capacity.saturating_mul(2);
        let body_scan_blocks = body_item_capacity.div_ceil(256).max(1);
        let arg_record_capacity = hir_node_capacity.saturating_mul(2).max(1);
        let arg_scan_blocks = arg_record_capacity.div_ceil(256).max(1);
        let func_scan_blocks = token_capacity.div_ceil(256).max(1);

        Self {
            body_item_capacity,
            body_scan_blocks,
            body_scan_steps: scan_steps_for_blocks(body_scan_blocks as usize),
            arg_record_capacity,
            arg_scan_blocks,
            arg_scan_steps: scan_steps_for_blocks(arg_scan_blocks as usize),
            func_scan_blocks,
            func_scan_steps: scan_steps_for_blocks(func_scan_blocks as usize),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capacities_saturate_and_keep_at_least_one_scan_block() {
        let empty = WasmBufferCapacities::for_input(0, 0);
        assert_eq!(empty.body_scan_blocks, 1);
        assert_eq!(empty.arg_scan_blocks, 1);
        assert_eq!(empty.func_scan_blocks, 1);

        let saturated = WasmBufferCapacities::for_input(u32::MAX, u32::MAX);
        assert_eq!(saturated.body_item_capacity, u32::MAX);
        assert_eq!(saturated.arg_record_capacity, u32::MAX);
    }
}
