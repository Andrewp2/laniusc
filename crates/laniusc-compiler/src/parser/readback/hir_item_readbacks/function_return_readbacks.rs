use super::super::*;

/// Narrow readback for parser-owned function return-type records.
///
/// This is intentionally smaller than `ParserHirItemReadbacks`: downstream
/// type checking and backends need the function -> return type node edge, not
/// the full parser debug tree.
pub struct ParserHirFunctionReturnReadbacks {
    pub ll1_status: wgpu::Buffer,
    pub hir_kind: wgpu::Buffer,
    pub hir_token_pos: wgpu::Buffer,
    pub hir_token_end: wgpu::Buffer,
    pub hir_node_file_id: wgpu::Buffer,
    pub hir_type_form: wgpu::Buffer,
    pub hir_type_file_id: wgpu::Buffer,
    pub hir_fn_return_type_node: wgpu::Buffer,
    pub hir_method_signature_flags: wgpu::Buffer,
    pub hir_method_name_token: wgpu::Buffer,
    pub hir_item_kind: wgpu::Buffer,
    pub hir_item_name_token: wgpu::Buffer,
    pub hir_item_file_id: wgpu::Buffer,
}

/// Decoded parser-owned function return-type readback data.
pub struct DecodedParserHirFunctionReturnReadbacks {
    pub ll1_status: [u32; 6],
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_node_file_id: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_method_signature_flags: Vec<u32>,
    pub hir_method_name_token: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
}

impl ParserHirFunctionReturnReadbacks {
    /// Creates staging buffers for function return-type record readback.
    pub fn create(device: &wgpu::Device, bufs: &ParserBuffers) -> Self {
        let mk = |label: &str, size: u64| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            })
        };

        Self {
            ll1_status: mk(
                "rb.parser.hir_fn_return_records.ll1_status",
                bufs.ll1_status.byte_size as u64,
            ),
            hir_kind: mk(
                "rb.parser.hir_fn_return_records.hir_kind",
                bufs.hir_kind.byte_size as u64,
            ),
            hir_token_pos: mk(
                "rb.parser.hir_fn_return_records.hir_token_pos",
                bufs.hir_token_pos.byte_size as u64,
            ),
            hir_token_end: mk(
                "rb.parser.hir_fn_return_records.hir_token_end",
                bufs.hir_token_end.byte_size as u64,
            ),
            hir_node_file_id: mk(
                "rb.parser.hir_fn_return_records.hir_node_file_id",
                bufs.hir_token_file_id.byte_size as u64,
            ),
            hir_type_form: mk(
                "rb.parser.hir_fn_return_records.hir_type_form",
                bufs.hir_type_form.byte_size as u64,
            ),
            hir_type_file_id: mk(
                "rb.parser.hir_fn_return_records.hir_type_file_id",
                bufs.hir_type_file_id.byte_size as u64,
            ),
            hir_fn_return_type_node: mk(
                "rb.parser.hir_fn_return_records.hir_fn_return_type_node",
                bufs.hir_fn_return_type_node.byte_size as u64,
            ),
            hir_method_signature_flags: mk(
                "rb.parser.hir_fn_return_records.hir_method_signature_flags",
                bufs.hir_method_signature_flags.byte_size as u64,
            ),
            hir_method_name_token: mk(
                "rb.parser.hir_fn_return_records.hir_method_name_token",
                bufs.hir_method_name_token.byte_size as u64,
            ),
            hir_item_kind: mk(
                "rb.parser.hir_fn_return_records.hir_item_kind",
                bufs.hir_item_kind.byte_size as u64,
            ),
            hir_item_name_token: mk(
                "rb.parser.hir_fn_return_records.hir_item_name_token",
                bufs.hir_item_name_token.byte_size as u64,
            ),
            hir_item_file_id: mk(
                "rb.parser.hir_fn_return_records.hir_item_file_id",
                bufs.hir_item_file_id.byte_size as u64,
            ),
        }
    }

    /// Encodes copies for function return-type record readback.
    pub fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_status,
            0,
            &self.ll1_status,
            0,
            bufs.ll1_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_kind,
            0,
            &self.hir_kind,
            0,
            bufs.hir_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_pos,
            0,
            &self.hir_token_pos,
            0,
            bufs.hir_token_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_end,
            0,
            &self.hir_token_end,
            0,
            bufs.hir_token_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_file_id,
            0,
            &self.hir_node_file_id,
            0,
            bufs.hir_token_file_id.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_form,
            0,
            &self.hir_type_form,
            0,
            bufs.hir_type_form.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_file_id,
            0,
            &self.hir_type_file_id,
            0,
            bufs.hir_type_file_id.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_fn_return_type_node,
            0,
            &self.hir_fn_return_type_node,
            0,
            bufs.hir_fn_return_type_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_signature_flags,
            0,
            &self.hir_method_signature_flags,
            0,
            bufs.hir_method_signature_flags.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_name_token,
            0,
            &self.hir_method_name_token,
            0,
            bufs.hir_method_name_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_kind,
            0,
            &self.hir_item_kind,
            0,
            bufs.hir_item_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_name_token,
            0,
            &self.hir_item_name_token,
            0,
            bufs.hir_item_name_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_file_id,
            0,
            &self.hir_item_file_id,
            0,
            bufs.hir_item_file_id.byte_size as u64,
        );
    }

    /// Maps and decodes function return-type record readback data.
    pub fn map_and_decode(
        self,
        device: &wgpu::Device,
        bufs: &ParserBuffers,
    ) -> Result<DecodedParserHirFunctionReturnReadbacks> {
        let map = |name: &str, b: &wgpu::Buffer| {
            crate::gpu::passes_core::map_readback_for_progress(
                &b.slice(..),
                &format!("parser.hir_fn_return_readback.{name}"),
            );
        };
        map("ll1_status", &self.ll1_status);
        map("hir_kind", &self.hir_kind);
        map("hir_token_pos", &self.hir_token_pos);
        map("hir_token_end", &self.hir_token_end);
        map("hir_node_file_id", &self.hir_node_file_id);
        map("hir_type_form", &self.hir_type_form);
        map("hir_type_file_id", &self.hir_type_file_id);
        map("hir_fn_return_type_node", &self.hir_fn_return_type_node);
        map(
            "hir_method_signature_flags",
            &self.hir_method_signature_flags,
        );
        map("hir_method_name_token", &self.hir_method_name_token);
        map("hir_item_kind", &self.hir_item_kind);
        map("hir_item_name_token", &self.hir_item_name_token);
        map("hir_item_file_id", &self.hir_item_file_id);

        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "parser.hir_fn_return_readback",
            wgpu::PollType::wait_indefinitely(),
        );

        let ll1_status = read_u32_array::<6>(&self.ll1_status, "ll1_status")?;
        let tree_len = active_tree_readback_len(
            "hir_fn_return_readback.tree",
            bufs.tree_count_uses_status,
            ll1_status[5],
            bufs.total_emit,
            bufs.hir_kind.count,
        )?;

        let decoded = DecodedParserHirFunctionReturnReadbacks {
            ll1_status,
            hir_kind: read_u32_vec(&self.hir_kind, tree_len),
            hir_token_pos: read_u32_vec(&self.hir_token_pos, tree_len),
            hir_token_end: read_u32_vec(&self.hir_token_end, tree_len),
            hir_node_file_id: read_u32_vec(&self.hir_node_file_id, tree_len),
            hir_type_form: read_u32_vec(&self.hir_type_form, tree_len),
            hir_type_file_id: read_u32_vec(&self.hir_type_file_id, tree_len),
            hir_fn_return_type_node: read_u32_vec(&self.hir_fn_return_type_node, tree_len),
            hir_method_signature_flags: read_u32_vec(&self.hir_method_signature_flags, tree_len),
            hir_method_name_token: read_u32_vec(&self.hir_method_name_token, tree_len),
            hir_item_kind: read_u32_vec(&self.hir_item_kind, tree_len),
            hir_item_name_token: read_u32_vec(&self.hir_item_name_token, tree_len),
            hir_item_file_id: read_u32_vec(&self.hir_item_file_id, tree_len),
        };
        validate_hir_source_address_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_file_id,
        )?;
        validate_hir_function_return_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_fn_return_type_node,
            &decoded.hir_item_kind,
            &decoded.hir_item_name_token,
            &decoded.hir_item_file_id,
            &decoded.hir_method_signature_flags,
            &decoded.hir_method_name_token,
        )?;
        Ok(decoded)
    }
}
