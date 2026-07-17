use super::*;

/// GPU-measured compact capacities needed before resident typecheck allocation.
#[derive(Clone, Copy, Debug)]
pub struct TypeCheckPreflightCapacities {
    pub module_records: u32,
    pub call_param_rows: u32,
    pub call_arg_rows: u32,
}

impl TypeCheckPreflightCapacities {
    /// Whether these required row counts fit inside an allocated capacity set.
    pub(crate) fn fits_within(self, allocated: Self) -> bool {
        self.module_records <= allocated.module_records
            && self.call_param_rows <= allocated.call_param_rows
            && self.call_arg_rows <= allocated.call_arg_rows
    }

    /// Component-wise high-water mark suitable for later speculative allocation.
    pub(crate) fn union(self, other: Self) -> Self {
        Self {
            module_records: self.module_records.max(other.module_records),
            call_param_rows: self.call_param_rows.max(other.call_param_rows),
            call_arg_rows: self.call_arg_rows.max(other.call_arg_rows),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::TypeCheckPreflightCapacities;

    #[test]
    fn preflight_capacity_high_water_is_component_wise_and_safe() {
        let first = TypeCheckPreflightCapacities {
            module_records: 10,
            call_param_rows: 4,
            call_arg_rows: 8,
        };
        let second = TypeCheckPreflightCapacities {
            module_records: 7,
            call_param_rows: 6,
            call_arg_rows: 3,
        };
        let high_water = first.union(second);
        assert_eq!(high_water.module_records, 10);
        assert_eq!(high_water.call_param_rows, 6);
        assert_eq!(high_water.call_arg_rows, 8);
        assert!(first.fits_within(high_water));
        assert!(second.fits_within(high_water));
        assert!(!high_water.fits_within(first));
    }
}

/// Host-readable result of the GPU compact-record preflight.
pub struct RecordedModuleRecordCapacity {
    candidate_counts: LaniusBuffer<u32>,
    readback: wgpu::Buffer,
}

impl GpuTypeChecker {
    /// Counts compact module, parameter-capacity, and call-argument rows on the GPU.
    ///
    /// The output is a dedicated word because typechecking still consumes the
    /// parser semantic-count buffer after this boundary.
    pub fn record_module_record_capacity_preflight(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        parse_bufs: &crate::parser::buffers::ParserBuffers,
    ) -> Result<RecordedModuleRecordCapacity> {
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: parse_bufs.tree_capacity,
            n_source_files: source_file_capacity,
            parser_feature_flags: parse_bufs.parser_feature_flags,
        };
        queue.write_buffer(&self.params_buf, 0, &type_check_params_bytes(&params));

        let candidate_counts = typed_storage_u32_rw(
            device,
            "type_check.preflight_capacities",
            3,
            wgpu::BufferUsages::COPY_DST,
        );
        record_typecheck_clear_buffer(encoder, &candidate_counts, 0, Some(12));
        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_00a_count_record_candidates"),
            &self.passes.modules_count_record_candidates,
            0,
            &[
                ("gParams", self.params_buf.as_entire_binding()),
                (
                    "compact_hir_count",
                    parse_bufs.hir_canonical_count.as_entire_binding(),
                ),
                (
                    "compact_hir_core",
                    parse_bufs.hir_core.as_entire_binding(),
                ),
                (
                    "compact_hir_payload",
                    parse_bufs.hir_payload.as_entire_binding(),
                ),
                (
                    "compact_path_count",
                    parse_bufs.hir_path_table_count.as_entire_binding(),
                ),
                (
                    "compact_param_count",
                    parse_bufs.hir_param_table_count.as_entire_binding(),
                ),
                (
                    "compact_call_arg_count",
                    parse_bufs.hir_call_arg_table_count.as_entire_binding(),
                ),
                (
                    "compact_variant_count",
                    parse_bufs.hir_variant_table_count.as_entire_binding(),
                ),
                ("candidate_counts", candidate_counts.as_entire_binding()),
            ],
        )?;
        record_compute(
            encoder,
            &self.passes.modules_count_record_candidates,
            &bind_group,
            "type_check.modules.count_record_candidates",
            parse_bufs.tree_capacity,
        )?;

        let readback = readback_u32s(device, "rb.type_check.preflight_capacities", 3);
        record_typecheck_copy_buffer_to_buffer(encoder, &candidate_counts, 0, &readback, 0, 12);
        Ok(RecordedModuleRecordCapacity {
            candidate_counts,
            readback,
        })
    }

    /// Finishes the three-word compact-capacity readback.
    pub fn finish_module_record_capacity_preflight(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedModuleRecordCapacity,
    ) -> Result<TypeCheckPreflightCapacities> {
        let _keep_gpu_output_alive = &recorded.candidate_counts;
        let slice = recorded.readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            device,
            &slice,
            "type_check.preflight_capacities",
        )?;
        let mapped = slice.get_mapped_range();
        let [module_records, call_param_rows, call_arg_rows] =
            crate::gpu::readback::read_u32_words::<3>(&mapped, "type_check.preflight_capacities")?;
        drop(mapped);
        recorded.readback.unmap();
        Ok(TypeCheckPreflightCapacities {
            module_records: module_records.max(1),
            call_param_rows: call_param_rows.max(1),
            call_arg_rows: call_arg_rows.max(1),
        })
    }
}
