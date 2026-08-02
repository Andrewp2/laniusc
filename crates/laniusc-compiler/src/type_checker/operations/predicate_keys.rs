use super::super::*;

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum PredicateKeyKind {
    MethodContract,
    MethodParam,
    Owner,
    Impl,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct PredicateKeyDefinition {
    pub label: &'static str,
    pub mode: u32,
    pub steps: u32,
    pub seed_pass: &'static str,
    pub small_pass: &'static str,
    pub sort: RadixSortDefinition,
}

impl PredicateKeyDefinition {
    pub(in crate::type_checker) fn register(
        self,
        graph: &mut crate::gpu::compiler_graph::CompilerGraphBuilder,
        kernels: &impl crate::gpu::kernels::KernelReflections,
        capacity: u32,
        keys: &[&'static str],
    ) -> Result<(), String> {
        use crate::gpu::compiler_graph::{
            AccessMode,
            CompilerPhase,
            ReflectedResourceBinding,
            ResourceDomain,
        };

        let binding = |binding, resource, mode| -> std::result::Result<_, String> {
            Ok(ReflectedResourceBinding {
                binding,
                resource: graph.resource_id(resource).ok_or_else(|| {
                    format!("predicate key resource `{resource}` is not registered")
                })?,
                mode,
            })
        };
        let r = self.sort.resources;
        if capacity <= PREDICATE_KEY_SMALL_SORT_CAPACITY {
            let overrides = [
                binding("predicate_count_in", r.count, None)?,
                binding("radix_order", r.order, Some(AccessMode::Write))?,
            ];
            graph.add_kernel_pass_by_name(
                self.small_pass,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/predicates/01b2_sort_keys_small",
                &overrides,
            )?;
            graph.require_complete_reflection(self.small_pass)?;
        } else {
            let overrides = [
                binding("predicate_count_in", r.count, None)?,
                binding("predicate_key_order", r.order, Some(AccessMode::Write))?,
            ];
            graph.add_kernel_pass_by_name(
                self.seed_pass,
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                kernels,
                "type_checker/predicates/01b_seed_key_order",
                &overrides,
            )?;
            graph.require_complete_reflection(self.seed_pass)?;
            let key_bindings = keys.iter().map(|&name| (name, name)).collect::<Vec<_>>();
            self.sort.register_with_bindings(
                graph,
                self.steps,
                "predicate_count_in",
                &key_bindings,
            )?;
        }
        Ok(())
    }
}

impl PredicateKeyKind {
    fn definition(self) -> PredicateKeyDefinition {
        match self {
            Self::MethodContract => compiler_graph::PREDICATE_METHOD_CONTRACT_KEYS,
            Self::MethodParam => compiler_graph::PREDICATE_METHOD_PARAM_KEYS,
            Self::Owner => compiler_graph::PREDICATE_OWNER_KEYS,
            Self::Impl => compiler_graph::PREDICATE_IMPL_KEYS,
        }
    }
}

pub(in crate::type_checker) struct PredicateKeyBuild<'a> {
    pub kind: PredicateKeyKind,
    pub token_capacity: u32,
    pub predicate_capacity: u32,
    pub predicate_blocks: u32,
    pub resources: &'a ResourceMap<'a>,
}

pub(in crate::type_checker) struct PredicateKeyPipeline {
    definition: PredicateKeyDefinition,
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
        let definition = input.kind.definition();
        let params = |key_step| PredicateKeyParams {
            predicate_capacity: input.predicate_capacity,
            token_capacity: input.token_capacity,
            n_blocks: input.predicate_blocks,
            key_step,
            mode: definition.mode,
            reserved: 0,
        };
        let mut resources = input.resources.clone();
        resources.alias("predicate_count_in", "hir_active_count")?;
        let seed_params = uniform_from_val(
            device,
            &format!("{}.params.seed", definition.label),
            &params(0),
        );
        let seed = reflected_bind_group_with_overrides(
            device,
            definition.seed_pass,
            &passes.kernel("type_checker/predicates/01b_seed_key_order"),
            &resources,
            &[
                ("gParams", seed_params.as_entire_binding()),
                ("predicate_count_in", resources["hir_active_count"].clone()),
                (
                    "predicate_key_order",
                    resources[definition.sort.resources.order].clone(),
                ),
            ],
        )?;

        if input.predicate_capacity <= PREDICATE_KEY_SMALL_SORT_CAPACITY {
            input
                .resources
                .validate_graph_pass(definition.small_pass, &[])?;
        } else {
            input
                .resources
                .validate_graph_pass(definition.seed_pass, &[])?;
        }
        let sort = definition.sort.operation(
            device,
            passes,
            &resources,
            input.predicate_capacity,
            PREDICATE_KEY_SMALL_SORT_CAPACITY,
            definition.steps,
            RadixSortDispatch {
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
            params,
        )?;
        Ok(Self {
            definition,
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
                self.definition.seed_pass,
                &self.row_dispatch_args,
            )?;
        }
        self.sort.record(encoder)
    }
}
