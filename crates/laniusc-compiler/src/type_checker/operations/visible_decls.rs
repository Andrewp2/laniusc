use super::super::*;

/// Stable ordering of compact declarations used by lexical lookup.
///
/// The caller supplies the values, key projection is compiled into the visible
/// declaration kernels, and the radix operation owns all sorting machinery.
pub(in crate::type_checker) struct VisibleDeclSort {
    _dispatch_params: Option<LaniusBuffer<ModuleKeyRadixParams>>,
    dispatch: Option<ComputeOperation>,
    uses_radix: bool,
    sort: RadixSortOperation<ModuleKeyRadixParams>,
}

impl VisibleDeclSort {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        capacity: u32,
        n_blocks: u32,
    ) -> Result<Self> {
        let capacity = capacity.max(1);
        let radix_bits = visible_decl_key_radix_bits(capacity);
        let radix_steps = visible_decl_key_radix_steps(capacity);
        let params = |key_step| ModuleKeyRadixParams {
            module_capacity: capacity,
            reserved: radix_bits,
            n_blocks,
            key_step,
        };
        let uses_radix = capacity > VISIBLE_DECL_SMALL_SORT_CAPACITY;
        let dispatch_args = uses_radix
            .then(|| {
                typed_buffer_from_resources(resources, "hir_visible_decl_key_radix_dispatch_args")
            })
            .transpose()?;
        let dispatch_params = uses_radix.then(|| {
            uniform_from_val(
                device,
                "type_check.visible.declarations.dispatch.params",
                &params(0),
            )
        });
        let dispatch = dispatch_params
            .as_ref()
            .map(|dispatch_params| {
                ComputeOperation::direct_with_uniform(
                    device,
                    graph,
                    resources,
                    compiler_graph::VISIBLE_RADIX_DISPATCH_PASS,
                    &passes.kernel("radix/dispatch_args"),
                    dispatch_params,
                    1,
                )
            })
            .transpose()?;
        let row_dispatch = dispatch_args.as_ref().map_or(
            RadixDispatchDomain::Direct(1),
            RadixDispatchDomain::Indirect,
        );
        let sort = compiler_graph::VISIBLE_RADIX_SORT.operation(
            device,
            passes,
            resources,
            capacity,
            VISIBLE_DECL_SMALL_SORT_CAPACITY,
            radix_steps,
            RadixSortDispatch {
                small: RadixDispatchDomain::Direct(256),
                rows: row_dispatch,
                bucket_prefix: RadixDispatchDomain::Direct(RADIX_U8_BUCKET_COUNT * 256),
                bucket_bases: RadixDispatchDomain::Direct(256),
            },
            params,
        )?;

        Ok(Self {
            _dispatch_params: dispatch_params,
            dispatch,
            uses_radix,
            sort,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        if self.uses_radix {
            let dispatch = self
                .dispatch
                .as_ref()
                .expect("scalable visible-declaration sort has dispatch bindings");
            dispatch.record(encoder)?;
        }
        self.sort.record(encoder)
    }
}
