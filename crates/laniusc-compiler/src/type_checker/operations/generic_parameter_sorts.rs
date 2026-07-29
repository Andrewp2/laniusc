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
        resources: &HashMap<String, wgpu::BindingResource<'_>>,
        capacity: u32,
        n_blocks: u32,
        radix_bytes: u32,
        radix_steps: u32,
        dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
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
            &passes.names_radix_dispatch_args,
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
                &passes.type_instances_sort_generic_params_small,
                resources,
                &[("gParams", dispatch_params.as_entire_binding())],
            )?;
            return Ok(Self {
                _dispatch_params: dispatch_params,
                dispatch,
                dispatch_args: dispatch_args.clone(),
                small: Some(small),
                key: None,
                slot: None,
            });
        }

        let key = RadixSortOperation::new(
            device,
            resources,
            RadixSortPlan {
                label: compiler_graph::GENERIC_PARAMETER_RADIX_SORTS.key.label(),
                capacity,
                small_capacity: 0,
                steps: radix_steps,
                passes: Self::key_passes(passes),
                dispatch: RadixSortDispatch {
                    small: RadixDispatchDomain::Direct(256),
                    rows: RadixDispatchDomain::Indirect(dispatch_args),
                    bucket_prefix: RadixDispatchDomain::Direct(
                        NAME_RADIX_BUCKETS.saturating_mul(256),
                    ),
                    bucket_bases: RadixDispatchDomain::Direct(256),
                },
                resources: compiler_graph::GENERIC_PARAMETER_RADIX_SORTS.key.resources,
            },
            make_params,
        )?;
        let slot = RadixSortOperation::new(
            device,
            resources,
            RadixSortPlan {
                label: compiler_graph::GENERIC_PARAMETER_RADIX_SORTS.slot.label(),
                capacity,
                small_capacity: 0,
                steps: radix_steps,
                passes: Self::slot_passes(passes),
                dispatch: RadixSortDispatch {
                    small: RadixDispatchDomain::Direct(256),
                    rows: RadixDispatchDomain::Indirect(dispatch_args),
                    bucket_prefix: RadixDispatchDomain::Direct(
                        NAME_RADIX_BUCKETS.saturating_mul(256),
                    ),
                    bucket_bases: RadixDispatchDomain::Direct(256),
                },
                resources: compiler_graph::GENERIC_PARAMETER_RADIX_SORTS.slot.resources,
            },
            make_params,
        )?;
        Ok(Self {
            _dispatch_params: dispatch_params,
            dispatch,
            dispatch_args: dispatch_args.clone(),
            small: None,
            key: Some(key),
            slot: Some(slot),
        })
    }

    fn key_passes(passes: &TypeCheckPasses) -> RadixSortPasses<'_> {
        RadixSortPasses {
            small: None,
            histogram: &passes.type_instances_sort_generic_param_keys,
            bucket_prefix: &passes.names_radix_bucket_prefix,
            bucket_bases: &passes.names_radix_bucket_bases,
            scatter: &passes.type_instances_sort_generic_param_keys_scatter,
        }
    }

    fn slot_passes(passes: &TypeCheckPasses) -> RadixSortPasses<'_> {
        RadixSortPasses {
            small: None,
            histogram: &passes.type_instances_sort_generic_param_slots,
            bucket_prefix: &passes.names_radix_bucket_prefix,
            bucket_bases: &passes.names_radix_bucket_bases,
            scatter: &passes.type_instances_sort_generic_param_slots_scatter,
        }
    }

    pub(in crate::type_checker) fn record(
        &self,
        passes: &TypeCheckPasses,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        record_compute(
            encoder,
            &passes.names_radix_dispatch_args,
            &self.dispatch,
            "type_check.type_instances.generic_parameter_dispatch_args",
            1,
        )?;
        if let Some(small) = &self.small {
            return record_compute_indirect(
                encoder,
                &passes.type_instances_sort_generic_params_small,
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
