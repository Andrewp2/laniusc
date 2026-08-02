use super::super::*;

/// The two stable orderings used to assign generic-parameter identities.
///
/// Small workloads use the existing fused shader. Larger workloads remain two
/// ordinary radix sorts, recorded in shared compute passes to preserve the
/// existing submission behavior.
pub(in crate::type_checker) struct GenericParameterSorts {
    _dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    dispatch: wgpu::BindGroup,
    dispatch_args: LaniusBuffer<u32>,
    small: Option<wgpu::BindGroup>,
    key: Option<RadixSortOperation<ModuleKeyRadixParams>>,
    slot: Option<RadixSortOperation<ModuleKeyRadixParams>>,
}

impl GenericParameterSorts {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        capacity: u32,
        n_blocks: u32,
        radix_bytes: u32,
        radix_steps: u32,
    ) -> Result<Self> {
        let dispatch_args =
            buffer_from_resources(resources, "generic_param_key_radix_dispatch_args")?;
        let make_params = |key_step| ModuleKeyRadixParams {
            module_capacity: capacity,
            reserved: radix_bytes,
            n_blocks,
            key_step,
        };
        let dispatch_params = uniform_from_val(
            device,
            "type_check.type_instances.generic_params.dispatch.params",
            &make_params(0),
        );
        let dispatch = reflected_bind_group_with_overrides(
            device,
            "type_check.type_instances.generic_params.dispatch",
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            resources,
            &[
                ("gParams", dispatch_params.as_entire_binding()),
                (
                    "name_count_in",
                    resources["generic_param_count_out"].clone(),
                ),
                ("radix_dispatch_args", dispatch_args.as_entire_binding()),
            ],
        )?;

        if capacity <= GENERIC_PARAM_SMALL_SORT_CAPACITY {
            let small = reflected_bind_group_with_overrides(
                device,
                "type_check.type_instances.generic_params.small",
                &passes.kernel("type_checker/type/instances/00b2_sort_generic_params_small"),
                resources,
                &[("gParams", dispatch_params.as_entire_binding())],
            )?;
            return Ok(Self {
                _dispatch_params: dispatch_params,
                dispatch,
                dispatch_args: typed_alias_storage_u32(dispatch_args, 3),
                small: Some(small),
                key: None,
                slot: None,
            });
        }

        let key = compiler_graph::GENERIC_PARAMETER_RADIX_SORTS
            .key
            .operation(
                device,
                passes,
                resources,
                capacity,
                0,
                radix_steps,
                RadixSortDispatch {
                    small: RadixDispatchDomain::Direct(256),
                    rows: RadixDispatchDomain::Indirect(dispatch_args),
                    bucket_prefix: RadixDispatchDomain::Direct(
                        NAME_RADIX_BUCKETS.saturating_mul(256),
                    ),
                    bucket_bases: RadixDispatchDomain::Direct(256),
                },
                make_params,
            )?;
        let slot = compiler_graph::GENERIC_PARAMETER_RADIX_SORTS
            .slot
            .operation(
                device,
                passes,
                resources,
                capacity,
                0,
                radix_steps,
                RadixSortDispatch {
                    small: RadixDispatchDomain::Direct(256),
                    rows: RadixDispatchDomain::Indirect(dispatch_args),
                    bucket_prefix: RadixDispatchDomain::Direct(
                        NAME_RADIX_BUCKETS.saturating_mul(256),
                    ),
                    bucket_bases: RadixDispatchDomain::Direct(256),
                },
                make_params,
            )?;
        Ok(Self {
            _dispatch_params: dispatch_params,
            dispatch,
            dispatch_args: typed_alias_storage_u32(dispatch_args, 3),
            small: None,
            key: Some(key),
            slot: Some(slot),
        })
    }

    pub(in crate::type_checker) fn record(
        &self,
        passes: &TypeCheckPasses,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        record_compute(
            encoder,
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &self.dispatch,
            "type_check.type_instances.generic_parameter_dispatch_args",
            1,
        )?;
        if let Some(small) = &self.small {
            return record_compute_indirect(
                encoder,
                &passes.kernel("type_checker/type/instances/00b2_sort_generic_params_small"),
                small,
                "type_check.type_instances.generic_parameters.small",
                &self.dispatch_args,
            );
        }
        let key = self
            .key
            .as_ref()
            .expect("large generic-parameter sort has key ordering");
        let slot = self
            .slot
            .as_ref()
            .expect("large generic-parameter sort has slot ordering");
        let items = [
            RadixSortBatchItem { sort: key },
            RadixSortBatchItem { sort: slot },
        ];
        record_radix_sort_batch(&items, encoder)
    }
}
