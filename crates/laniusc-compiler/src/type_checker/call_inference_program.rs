use super::*;
use crate::gpu::{
    compiler_graph::{
        AccessMode, CompilerPhase, ReflectedComputeSpec, ReflectedResourceAlias, ResourceDomain,
    },
    operations::StepProgramOperation,
};

pub(super) const PROGRAM_SLOTS: usize = 2;
// Latches wait failures across rounds until the existing status readback.
pub(super) const STATUS_WORDS: usize = 5;
pub(super) const STATUS_BYTES: u64 = (STATUS_WORDS * size_of::<u32>()) as u64;

const SYNC: ReflectedResourceAlias = ReflectedResourceAlias {
    binding: "step_program_sync",
    resource: "call_inference_step_program_sync",
    mode: Some(AccessMode::ReadWrite),
};

const FIELD_GRID: ReflectedResourceAlias = ReflectedResourceAlias {
    binding: "inference_program_args",
    resource: "inference_field_program_args",
    mode: Some(AccessMode::Read),
};

const INDEX_GRID: ReflectedResourceAlias = ReflectedResourceAlias {
    resource: "inference_index_program_args",
    ..FIELD_GRID
};

pub(super) const EXPAND_CALL_FIELDS: ReflectedComputeSpec = ReflectedComputeSpec::new(
    "type_check.substitution.expand_call_fields",
    "type_checker/substitution/expand_call_fields",
    CompilerPhase::TypeCheck,
    ResourceDomain::HirNodes,
)
.with_aliases(&[
    SYNC,
    FIELD_GRID,
    ReflectedResourceAlias {
        binding: "canonical_type_roots",
        resource: "call_parameter_canonical_type_roots",
        mode: Some(AccessMode::Read),
    },
])
.with_initializes(&["step_program_sync"])
.with_modes(&[
    ("type_native_word_count", AccessMode::Write),
    ("type_native_scalar_identity", AccessMode::Write),
])
.with_indirect_dispatch(FIELD_GRID.resource);

pub(super) const BUILD_CALL_CLAIM_INDEXES: ReflectedComputeSpec = ReflectedComputeSpec::new(
    "type_check.calls.build_call_claim_indexes",
    "type_checker/calls/claims/build_call_claim_indexes",
    CompilerPhase::TypeCheck,
    ResourceDomain::CallArguments,
)
.with_aliases(&[SYNC, INDEX_GRID])
.with_initializes(&[
    "step_program_sync",
    "call_generic_claim_lookup_next",
    "call_const_claim_lookup_next",
    "call_const_env_binding",
])
.with_indirect_dispatch(INDEX_GRID.resource);

#[derive(encase::ShaderType)]
pub(super) struct ProgramLimits {
    pub field_groups: u32,
}

pub(super) fn build_program(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    resources: &ResourceMap<'_>,
    passes: &TypeCheckPasses,
    spec: ReflectedComputeSpec,
    slot: u32,
) -> Result<StepProgramOperation> {
    let sync = graph.u32_buffer("call_inference_step_program_sync")?;
    let mut resources = resources.clone();
    resources.buffer("call_inference_step_program_sync", &sync);
    let args = typed_buffer_from_resources(
        &resources,
        spec.indirect_dispatch.expect("call inference program must declare its dispatch grid"),
    )?;
    StepProgramOperation::new_indirect(
        device, graph, &resources, spec.name, passes.kernel(spec.kernel), &sync, slot, &args,
    )
}
