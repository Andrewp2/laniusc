use super::super::*;

/// Runtime half of the method-key graph fragment.
///
/// Method-specific code owns only the seed and validation boundaries. Stable
/// sorting is delegated to the shared radix operation, which owns strategy
/// selection, uniforms, reflected bindings, ping-pong, and dispatch order.
pub(in crate::type_checker) struct MethodKeyPipeline {
    _boundary_params: [LaniusBuffer<ModuleKeyRadixParams>; 2],
    seed_pass: PassData,
    seed: wgpu::BindGroup,
    sort: RadixSortOperation<ModuleKeyRadixParams>,
    validate_pass: PassData,
    validate: wgpu::BindGroup,
    token_dispatch_args: LaniusBuffer<u32>,
}

impl MethodKeyPipeline {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        label: &'static str,
        capacity: u32,
        n_blocks: u32,
    ) -> Result<Self> {
        let params = |key_step| ModuleKeyRadixParams {
            module_capacity: capacity,
            reserved: 0,
            n_blocks,
            key_step,
        };
        let seed_params = uniform_from_val(
            device,
            &format!("{label}.method_key.params.seed"),
            &params(0),
        );
        let seed = resources.reflected_bind_group_with_overrides(
            device,
            &format!("{label}.seed"),
            &passes.kernel("type_checker/methods/03/seed_key_order"),
            &[("gParams", seed_params.as_entire_binding())],
        )?;

        let radix_bases_dispatch_args =
            typed_buffer_from_resources(resources, "method_radix_bases_dispatch_args")?;
        let token_dispatch_args =
            typed_buffer_from_resources(resources, "method_token_dispatch_args")?;
        let radix_prefix_dispatch_args =
            typed_buffer_from_resources(resources, "method_radix_prefix_dispatch_args")?;
        let row_dispatch = RadixSortDispatch {
            small: RadixDispatchDomain::Indirect(&radix_bases_dispatch_args),
            rows: RadixDispatchDomain::Indirect(&token_dispatch_args),
            bucket_prefix: RadixDispatchDomain::Indirect(&radix_prefix_dispatch_args),
            bucket_bases: RadixDispatchDomain::Indirect(&radix_bases_dispatch_args),
        };
        let sort = RadixSortOperation::new_adaptive(
            device,
            passes,
            resources,
            n_blocks,
            compiler_graph::METHOD_KEY_RADIX_SORT.plan(
                capacity,
                METHOD_KEY_SMALL_SORT_CAPACITY,
                METHOD_KEY_RADIX_STEPS,
                row_dispatch,
            ),
            compiler_graph::METHOD_KEY_HIERARCHICAL_RADIX_SORT.plan(
                METHOD_KEY_RADIX_STEPS,
                HierarchicalRadixSortDispatch {
                    rows: &token_dispatch_args,
                    bucket_work_items: n_blocks
                        .div_ceil(256)
                        .saturating_mul(NAME_RADIX_BUCKETS)
                        .saturating_mul(256),
                    bucket_chunk_work_items: NAME_RADIX_BUCKETS.saturating_mul(256),
                    bucket_count: 256,
                },
            ),
            params,
        )?;

        let validate_params = uniform_from_val(
            device,
            &format!("{label}.method_key.params.validate"),
            &params(0),
        );
        let validate = resources.reflected_bind_group_with_overrides(
            device,
            &format!("{label}.validate"),
            &passes.kernel("type_checker/methods/05_validate_keys"),
            &[("gParams", validate_params.as_entire_binding())],
        )?;

        Ok(Self {
            _boundary_params: [seed_params, validate_params],
            seed_pass: passes
                .kernel("type_checker/methods/03/seed_key_order")
                .clone(),
            seed,
            sort,
            validate_pass: passes
                .kernel("type_checker/methods/05_validate_keys")
                .clone(),
            validate,
            token_dispatch_args: typed_buffer_from_resources(
                resources,
                "method_token_dispatch_args",
            )?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_compute_indirect(
            encoder,
            &self.seed_pass,
            &self.seed,
            "type_check.methods.seed_key_order",
            &self.token_dispatch_args,
        )?;
        self.sort.record(encoder)?;
        record_compute_indirect(
            encoder,
            &self.validate_pass,
            &self.validate,
            "type_check.methods.validate_keys",
            &self.token_dispatch_args,
        )
    }
}
