use super::super::*;

/// Stable ordering of compact declarations used by lexical lookup.
///
/// The caller supplies the values, key projection is compiled into the visible
/// declaration kernels, and the radix operation owns all sorting machinery.
pub(in crate::type_checker) struct VisibleDeclSort {
    _dispatch_params: LaniusBuffer<ModuleKeyRadixParams>,
    dispatch: wgpu::BindGroup,
    dispatch_args: LaniusBuffer<u32>,
    seed: wgpu::BindGroup,
    sort: RadixSortOperation<ModuleKeyRadixParams>,
}

impl VisibleDeclSort {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        resources: &HashMap<String, wgpu::BindingResource<'_>>,
        capacity: u32,
        n_blocks: u32,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<Self> {
        let capacity = capacity.max(1);
        let radix_bytes = visible_decl_key_radix_bytes(capacity);
        let params = |key_step| ModuleKeyRadixParams {
            module_capacity: capacity,
            reserved: radix_bytes,
            n_blocks,
            key_step,
        };
        let dispatch_params = uniform_from_val(
            device,
            "type_check.visible.declarations.dispatch.params",
            &params(0),
        );
        let dispatch = reflected_bind_group_with_overrides(
            device,
            "type_check.visible.declarations.dispatch",
            &passes.names_radix_dispatch_args,
            resources,
            &[
                ("gParams", dispatch_params.as_entire_binding()),
                (
                    "name_count_in",
                    resources["hir_visible_decl_count_out"].clone(),
                ),
                ("radix_dispatch_args", dispatch_args.as_entire_binding()),
            ],
        )?;
        let seed = reflected_bind_group_with_overrides(
            device,
            "type_check.visible.declarations.seed",
            &passes.visible_seed_hir_decl_order,
            resources,
            &[("gParams", dispatch_params.as_entire_binding())],
        )?;
        let sort = RadixSortOperation::new(
            device,
            resources,
            RadixSortPlan {
                label: compiler_graph::VISIBLE_RADIX_SORT.label(),
                capacity,
                small_capacity: VISIBLE_DECL_SMALL_SORT_CAPACITY,
                steps: visible_decl_key_radix_steps(capacity),
                passes: RadixSortPasses {
                    small: Some(&passes.visible_sort_hir_decl_keys_small),
                    histogram: &passes.visible_sort_hir_decl_keys,
                    bucket_prefix: &passes.names_radix_bucket_prefix,
                    bucket_bases: &passes.names_radix_bucket_bases,
                    scatter: &passes.visible_sort_hir_decl_keys_scatter,
                },
                dispatch: RadixSortDispatch {
                    small: RadixDispatchDomain::Direct(256),
                    rows: RadixDispatchDomain::Indirect(dispatch_args),
                    bucket_prefix: RadixDispatchDomain::Direct(NAME_RADIX_BUCKETS * 256),
                    bucket_bases: RadixDispatchDomain::Direct(256),
                },
                resources: compiler_graph::VISIBLE_RADIX_SORT.resources,
            },
            params,
        )?;

        Ok(Self {
            _dispatch_params: dispatch_params,
            dispatch,
            dispatch_args: typed_alias_storage_u32(dispatch_args, 3),
            seed,
            sort,
        })
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
            "type_check.visible.hir_decl_key_radix_dispatch_args",
            1,
        )?;
        record_compute_indirect(
            encoder,
            &passes.visible_seed_hir_decl_order,
            &self.seed,
            "type_check.visible.seed_hir_decl_order",
            &self.dispatch_args,
        )?;
        self.sort.record(encoder)
    }
}
