use super::*;

impl GpuWasmCodeGenerator {
    pub(super) fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentWasmBuffers>,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        hir_node_capacity: u32,
        inputs: GpuWasmCodegenInputs<'_>,
    ) -> Result<&'a ResidentWasmBuffers> {
        let needs_rebuild = slot.as_ref().is_none_or(|cached| {
            cached.input_fingerprint != input_fingerprint
                || cached.output_capacity < output_capacity
                || cached.token_capacity < token_capacity
                || cached.hir_node_capacity < hir_node_capacity
        });
        if needs_rebuild {
            *slot = Some(self.create_resident_buffers(
                device,
                input_fingerprint,
                output_capacity,
                token_capacity,
                hir_node_capacity,
                inputs,
            )?);
        }
        Ok(slot.as_ref().expect("resident wasm buffers allocated"))
    }
}
