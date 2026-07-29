use super::super::*;

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum PredicateKeyKind {
    MethodContract,
    MethodParam,
    Owner,
    Impl,
}

#[derive(Clone, Copy)]
struct PredicateKeyConfig {
    label: &'static str,
    mode: u32,
    steps: u32,
    seed_label: &'static str,
    order: &'static str,
    temporary_order: &'static str,
}

impl PredicateKeyKind {
    fn config(self) -> PredicateKeyConfig {
        match self {
            Self::MethodContract => PredicateKeyConfig {
                label: "type_check.predicates.method_contract_keys",
                mode: PREDICATE_KEY_MODE_METHOD_CONTRACT,
                steps: PREDICATE_METHOD_CONTRACT_KEY_RADIX_STEPS,
                seed_label: "type_check.predicates.seed_method_contract_key_order",
                order: "predicate_method_contract_key_order",
                temporary_order: "predicate_method_contract_key_order_tmp",
            },
            Self::MethodParam => PredicateKeyConfig {
                label: "type_check.predicates.method_param_keys",
                mode: PREDICATE_KEY_MODE_METHOD_PARAM,
                steps: PREDICATE_METHOD_PARAM_KEY_RADIX_STEPS,
                seed_label: "type_check.predicates.seed_method_param_key_order",
                order: "predicate_method_param_key_order",
                temporary_order: "predicate_method_param_key_order_tmp",
            },
            Self::Owner => PredicateKeyConfig {
                label: "type_check.predicates.owner_keys",
                mode: PREDICATE_KEY_MODE_OWNER,
                steps: PREDICATE_OWNER_KEY_RADIX_STEPS,
                seed_label: "type_check.predicates.seed_owner_key_order",
                order: "predicate_owner_key_order",
                temporary_order: "predicate_owner_key_order_tmp",
            },
            Self::Impl => PredicateKeyConfig {
                label: "type_check.predicates.impl_keys",
                mode: PREDICATE_KEY_MODE_IMPL,
                steps: PREDICATE_IMPL_KEY_RADIX_STEPS,
                seed_label: "type_check.predicates.seed_impl_key_order",
                order: "predicate_impl_key_order",
                temporary_order: "predicate_impl_key_order_tmp",
            },
        }
    }
}

pub(in crate::type_checker) struct PredicateKeyBuild<'a> {
    pub kind: PredicateKeyKind,
    pub token_capacity: u32,
    pub predicate_capacity: u32,
    pub predicate_blocks: u32,
    pub resources: &'a HashMap<String, wgpu::BindingResource<'a>>,
}

pub(in crate::type_checker) struct PredicateKeyPipeline {
    config: PredicateKeyConfig,
    _seed_params: LaniusBuffer<PredicateKeyParams>,
    seed: wgpu::BindGroup,
    row_dispatch_args: wgpu::Buffer,
    sort: RadixSortOperation<PredicateKeyParams>,
}

impl PredicateKeyPipeline {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        input: PredicateKeyBuild<'_>,
    ) -> Result<Self> {
        let config = input.kind.config();
        let params = |key_step| PredicateKeyParams {
            predicate_capacity: input.predicate_capacity,
            token_capacity: input.token_capacity,
            n_blocks: input.predicate_blocks,
            key_step,
            mode: config.mode,
            reserved: 0,
        };
        let seed_params =
            uniform_from_val(device, &format!("{}.params.seed", config.label), &params(0));
        let seed = reflected_bind_group_with_overrides(
            device,
            config.seed_label,
            &passes.kernel("type_checker/predicates/01b_seed_key_order"),
            input.resources,
            &[
                ("gParams", seed_params.as_entire_binding()),
                (
                    "predicate_count_in",
                    input.resources["hir_active_count"].clone(),
                ),
                ("predicate_key_order", input.resources[config.order].clone()),
            ],
        )?;

        let mut resources = input.resources.clone();
        resources.insert(
            "predicate_count_in".into(),
            input.resources["hir_active_count"].clone(),
        );
        resources.insert(
            "predicate_sort_order".into(),
            input.resources[config.order].clone(),
        );
        resources.insert(
            "predicate_sort_order_tmp".into(),
            input.resources[config.temporary_order].clone(),
        );
        resources.insert(
            "predicate_sort_histogram".into(),
            input.resources["predicate_key_radix_block_histogram"].clone(),
        );
        resources.insert(
            "predicate_sort_bucket_prefix".into(),
            input.resources["predicate_key_radix_block_bucket_prefix"].clone(),
        );
        resources.insert(
            "predicate_sort_bucket_total".into(),
            input.resources["predicate_key_radix_bucket_total"].clone(),
        );
        resources.insert(
            "predicate_sort_bucket_base".into(),
            input.resources["predicate_key_radix_bucket_base"].clone(),
        );
        let sort = RadixSortOperation::new(
            device,
            passes,
            &resources,
            RadixSortPlan {
                label: config.label,
                capacity: input.predicate_capacity,
                small_capacity: PREDICATE_KEY_SMALL_SORT_CAPACITY,
                steps: config.steps,
                kernels: RadixSortKernels::new(
                    "type_checker/predicates/01c_sort_keys",
                    "type_checker/predicates/01d_sort_keys_scatter",
                )
                .with_small("type_checker/predicates/01b2_sort_keys_small"),
                dispatch: RadixSortDispatch {
                    small: RadixDispatchDomain::Indirect(buffer_from_resources(
                        input.resources,
                        "predicate_radix_bases_dispatch_args",
                    )?),
                    rows: RadixDispatchDomain::Indirect(buffer_from_resources(
                        input.resources,
                        "predicate_hir_dispatch_args",
                    )?),
                    bucket_prefix: RadixDispatchDomain::Indirect(buffer_from_resources(
                        input.resources,
                        "predicate_radix_prefix_dispatch_args",
                    )?),
                    bucket_bases: RadixDispatchDomain::Indirect(buffer_from_resources(
                        input.resources,
                        "predicate_radix_bases_dispatch_args",
                    )?),
                },
                resources: RadixSortResources {
                    count: "predicate_count_in",
                    order: "predicate_sort_order",
                    temporary_order: "predicate_sort_order_tmp",
                    histogram: "predicate_sort_histogram",
                    bucket_prefix: "predicate_sort_bucket_prefix",
                    bucket_total: "predicate_sort_bucket_total",
                    bucket_base: "predicate_sort_bucket_base",
                },
            },
            params,
        )?;
        Ok(Self {
            config,
            _seed_params: seed_params,
            seed,
            row_dispatch_args: buffer_from_resources(
                input.resources,
                "predicate_hir_dispatch_args",
            )?
            .clone(),
            sort,
        })
    }

    pub(in crate::type_checker) fn record(
        &self,
        passes: &TypeCheckPasses,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        if !self.sort.uses_small_kernel() {
            record_compute_indirect(
                encoder,
                &passes.kernel("type_checker/predicates/01b_seed_key_order"),
                &self.seed,
                self.config.seed_label,
                &self.row_dispatch_args,
            )?;
        }
        self.sort.record(encoder)
    }
}
