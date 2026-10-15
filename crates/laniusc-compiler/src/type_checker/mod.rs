//! GPU-resident type checking and semantic metadata retention.
//!
//! The type checker records compute passes over token and parser HIR buffers
//! rather than walking an AST on the host. It builds module, name,
//! type-instance, call, method, visibility, predicate, and backend metadata
//! relations on the GPU, then exposes retained buffers to backend phases only
//! through explicit wrapper structs. The maintainer guide for pass-family
//! ownership and resident cache invariants lives in
//! `docs/compiler/type-checker.md`.

use std::sync::Mutex;

mod bind_groups;
mod bind_models;
mod bind_support;
mod canonical_passes;
mod compiler_graph;
mod generic_body;
mod generic_calls;
mod owner_spans;
pub(crate) use owner_spans::{CheckedOwnerSpan, CheckedOwnerSpans};
mod checked_contracts;
#[cfg(test)]
mod scoped_type_graph_tests;
pub(crate) use checked_contracts::{
    CheckedCallOwner, CheckedNominalRecipe, CheckedNominalRecipeKind, CheckedUnitContracts,
};
#[cfg(test)]
pub(crate) use checked_contracts::{
    CheckedCallableOwner, CheckedContractOwner, CheckedImplementationContract,
    CheckedPredicateContract,
};
pub(crate) use generic_body::{BODY_COPY_TARGET, CheckedBodySpecialization, CheckedBodySpecializationBatch, MAX_BODY_ENTRIES};
pub(crate) use generic_calls::{
    CheckedBinderIdentity, CheckedGenericConstantValue, CheckedGenericParameter,
    CheckedNominalIdentity, CheckedParameterDomain, CheckedParameterIdentity,
};
pub(crate) use generic_calls::{
    CheckedGenericApplicationArgument,
    CheckedGenericArgument,
    CheckedGenericCall,
    CheckedGenericConstant,
    CheckedGenericTarget,
    CheckedGenericType,
    dependency_method_requirements,
    resolve_generic_requirements,
    scope_generic_type_identities,
};
mod dependency_interface;
mod module_path;
mod operations;
mod params;
mod preflight;
mod record;
mod match_passes;
mod resident;
mod substitution_passes;
mod semantic_interface;
pub use semantic_interface::RecordedSemanticInterface;
mod util;

use anyhow::Result;
use bind_models::*;
use bind_support::*;
pub(crate) use dependency_interface::{GpuDependencyInterfacePages, GpuDependencyInterfaceState};
use module_path::*;
use operations::*;
use params::*;
use record::*;
use util::*;
use wgpu::util::DeviceExt;

use crate::gpu::{
    buffers::{
        CapacityBufferCache,
        LaniusBuffer,
        TrackedBufferView,
        storage_ro_from_bytes,
        storage_ro_from_u32s,
        uniform_from_val,
    },
    compiler_graph::{CompilerGraphBindings, PrefixScanWorkspace},
    device,
    kernels::KernelRegistry,
    operations::{
        ComputeInvocation,
        ExactLookupOperation,
        PrefixScanOperation,
        PrefixScanPairOperation,
        RadixDispatchDomain,
        RadixSortDefinition,
        RadixSortDispatch,
        RadixSortKernels,
        RadixSortOperation,
        RadixSortResources,
    },
    passes_core::{
        DispatchDim,
        InputElements,
        PassData,
        plan_workgroups,
        recorded_compute_pass_count,
    },
    resource_registry::{ResourceMap, typed_buffer_from_resources},
    scan::{PrefixScanHierarchyParams, PrefixScanParams},
};

/// Semantic rejection classes reported by GPU type-check status words.
///
/// The numeric mapping is owned by GPU status buffers and shader constants.
/// Host diagnostics should preserve the source token or HIR row that made the
/// rejection user-visible.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuTypeCheckCode {
    UnknownType,
    UnresolvedIdent,
    AssignMismatch,
    ReturnMismatch,
    ConditionType,
    BadHir,
    LoopControl,
    InvalidMemberAccess,
    InvalidArrayReturn,
    CallMismatch,
    NameLimit,
    ImportCycle,
    TraitBoundUnsatisfied,
    TraitBoundAmbiguous,
    UnresolvedImport,
    UnsupportedImport,
    InvalidTraitImplementation,
    DuplicateModule,
    InvalidModulePath,
    InvalidAssignmentTarget,
    InvalidArrayLength,
    IntegerLiteralRange,
    FloatLiteral,
    ComputedFloatConstant,
    InvalidCast,
    MissingConstantBinding,
    GenericInstantiationBoundary,
    Unknown(u32),
}

impl GpuTypeCheckCode {
    fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::UnknownType,
            2 => Self::UnresolvedIdent,
            3 => Self::AssignMismatch,
            4 => Self::ReturnMismatch,
            5 => Self::ConditionType,
            6 => Self::BadHir,
            7 => Self::LoopControl,
            8 => Self::InvalidMemberAccess,
            9 => Self::InvalidArrayReturn,
            10 => Self::CallMismatch,
            11 => Self::NameLimit,
            12 => Self::ImportCycle,
            13 => Self::TraitBoundUnsatisfied,
            14 => Self::TraitBoundAmbiguous,
            15 => Self::UnresolvedImport,
            16 => Self::UnsupportedImport,
            17 => Self::InvalidTraitImplementation,
            18 => Self::DuplicateModule,
            20 => Self::InvalidModulePath,
            21 => Self::InvalidAssignmentTarget,
            22 => Self::InvalidArrayLength,
            23 => Self::MissingConstantBinding,
            24 => Self::IntegerLiteralRange,
            25 => Self::FloatLiteral,
            26 => Self::ComputedFloatConstant,
            27 => Self::InvalidCast,
            other => Self::Unknown(other),
        }
    }

    fn description(self) -> String {
        match self {
            Self::UnknownType => "unknown type".to_string(),
            Self::UnresolvedIdent => "unresolved identifier".to_string(),
            Self::AssignMismatch => "type mismatch".to_string(),
            Self::ReturnMismatch => "return type mismatch".to_string(),
            Self::ConditionType => "condition has the wrong type".to_string(),
            Self::BadHir => "invalid syntax or lowered syntax tree".to_string(),
            Self::LoopControl => "invalid loop control".to_string(),
            Self::InvalidMemberAccess => "invalid member access".to_string(),
            Self::InvalidArrayReturn => "invalid array return".to_string(),
            Self::CallMismatch => "call does not match a resolved function or method".to_string(),
            Self::NameLimit => "name is outside the current compiler limit".to_string(),
            Self::ImportCycle => "import cycle".to_string(),
            Self::TraitBoundUnsatisfied => "unsatisfied trait bound".to_string(),
            Self::TraitBoundAmbiguous => "ambiguous trait bound".to_string(),
            Self::UnresolvedImport => "unresolved import".to_string(),
            Self::UnsupportedImport => "unsupported import form".to_string(),
            Self::InvalidTraitImplementation => "invalid trait implementation".to_string(),
            Self::DuplicateModule => "duplicate module declaration".to_string(),
            Self::InvalidModulePath => "invalid module path".to_string(),
            Self::InvalidAssignmentTarget => "invalid assignment target".to_string(),
            Self::InvalidArrayLength => "array length must have an integer type".to_string(),
            Self::IntegerLiteralRange => "integer literal is outside its checked type range".to_string(),
            Self::FloatLiteral => "floating literal cannot be represented by its checked type".to_string(),
            Self::ComputedFloatConstant => "computed floating constant is not supported".to_string(),
            Self::InvalidCast => "invalid cast".to_string(),
            Self::MissingConstantBinding => "constant parameter could not be inferred".to_string(),
            Self::GenericInstantiationBoundary => {
                "generic type instantiation reached a compiler boundary".to_string()
            }
            Self::Unknown(code) => format!("unknown type-check error (code {code})"),
        }
    }
}

/// Error returned after a recorded type-check pass sequence is finished.
#[derive(Debug)]
pub enum GpuTypeCheckError {
    /// The GPU status buffer rejected the program and supplied a token/code
    /// tuple for host-side diagnostic mapping.
    Rejected {
        token: u32,
        code: GpuTypeCheckCode,
        detail: u32,
    },
    /// GPU setup, submission, or readback failed before semantic status could
    /// be decoded.
    Gpu(anyhow::Error),
}

/// Internal recording policy derived by compiler orchestration. This is not
/// proof authority. Pending originals cannot publish an object before whole-program
/// admission; only a validated program replay request may select replay.
#[derive(Clone, Copy, Default)]
pub(crate) enum FrontendTraitCheck {
    #[default]
    Strict,
    /// Original definitions and call graphs are checked, but implementation
    /// selection belongs to a later whole-program admission.
    PendingOriginal,
    /// Rechecked calls defer selection to the same program: selected-body calls
    /// receive fresh proofs and ordinary siblings must retain their admitted facts.
    AuthorizedReplay { selected_function_hir: u32 },
}

impl FrontendTraitCheck {
    pub(crate) fn shader_words(self) -> (u32, u32) {
        match self {
            Self::Strict => (0, u32::MAX),
            Self::PendingOriginal => (1, u32::MAX),
            Self::AuthorizedReplay { selected_function_hir } => (2, selected_function_hir),
        }
    }
}

/// Compact HIR plus the explicitly scoped upstream workspace consumed by the
/// current type-check recording path.
///
/// This value is borrowed for the duration of a recorded check. Anything
/// needed after parser resident buffers are released must be read from `hir`.
#[derive(Clone, Copy)]
pub struct GpuTypeCheckHirItemBuffers<'a> {
    /// Host-visible semantic feature summary measured by the GPU parser.
    pub parser_feature_flags: u32,
    /// Token-bounded upper capacity for compact module/path record families.
    pub module_record_capacity: u32,
    /// GPU-counted compact local parameters plus the dependency-parameter
    /// upper bound of one row per compact call argument.
    pub call_param_row_capacity: u32,
    /// Token-bounded upper capacity for compact call-argument rows.
    pub call_arg_row_capacity: u32,
    /// Whether this job records a persisted semantic interface after type
    /// checking. Ordinary executable compilation leaves the interface-only
    /// workspace unmaterialized.
    pub semantic_interface_required: bool,
    /// One explicit body replay. Ordinary jobs upload an empty packet.
    pub(crate) body_specialization: Option<&'a CheckedBodySpecializationBatch>,
    /// Derived from the same private frontend request as the body packet.
    pub(crate) frontend_trait_check: FrontendTraitCheck,
    /// The parser's compact semantic artifact. Keeping this as one typed view
    /// preserves allocation identity for compiler-graph validation and makes
    /// it impossible for type-check code to assemble a partial HIR from raw
    /// parser rows.
    pub hir: &'a crate::parser::buffers::GpuHirView,
    /// Dead parser-phase storage available to the type-check graph's slot
    /// allocator. These buffers contain no semantic input at this boundary.
    pub upstream_workspace: &'a [crate::gpu::buffers::TrackedBufferView<'a>],
}

impl std::fmt::Display for GpuTypeCheckError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GpuTypeCheckError::Rejected { code, .. } => {
                write!(f, "type check error: {}", code.description())
            }
            GpuTypeCheckError::Gpu(_) => {
                f.write_str("type-check execution failed before semantic status could be decoded")
            }
        }
    }
}

impl std::error::Error for GpuTypeCheckError {}

#[cfg(test)]
mod tests {
    use super::{GpuTypeCheckCode, GpuTypeCheckError};

    #[test]
    fn type_check_error_display_is_user_facing() {
        let error = GpuTypeCheckError::Rejected {
            token: 12,
            code: GpuTypeCheckCode::UnknownType,
            detail: 7,
        };

        let message = error.to_string();
        assert_eq!(message, "type check error: unknown type");
        assert!(!message.contains("GPU"));
        assert!(!message.contains("near token"));
        assert!(!message.contains("status token"));
    }

    #[test]
    fn type_check_gpu_error_display_omits_backend_detail() {
        let error = GpuTypeCheckError::Gpu(anyhow::anyhow!(
            "typecheck.modules.projected_refs status readback failed"
        ));

        let message = error.to_string();
        assert_eq!(
            message,
            "type-check execution failed before semantic status could be decoded"
        );
        assert!(!message.contains("projected_refs"));
        assert!(!message.contains("readback"));
        assert!(!message.contains("GPU"));
    }
}

impl From<anyhow::Error> for GpuTypeCheckError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

/// GPU type-check driver and resident state cache.
///
/// A `GpuTypeChecker` owns pass pipelines, the main status buffer, and reusable
/// resident bind groups/scratch storage. Callers record type-check work into an
/// existing command encoder and finish it after submission/readback.
pub struct GpuTypeChecker {
    passes: TypeCheckPasses,
    params_buf: LaniusBuffer<TypeCheckParams>,
    body_specialization_inputs: LaniusBuffer<u32>,
    empty_dependency_words: LaniusBuffer<u32>,
    status_buf: LaniusBuffer<u32>,
    status_readback: LaniusBuffer<u32>,
    call_inference_state: LaniusBuffer<u32>,
    call_inference_readback: LaniusBuffer<u32>,
    /// Host-visible `ct_counts` after each canonical interning batch.
    canonical_counts_readback: LaniusBuffer<u32>,
    /// Debug-only canonical validation counters.
    canonical_validation_readback: LaniusBuffer<u32>,
    preflight_graph: preflight::TypeCheckPreflightGraph,
    /// Canonical table capacity scale for the next workspace; doubled when a
    /// job's canonical stage overflows, then kept for later jobs.
    canonical_scale: std::sync::atomic::AtomicU32,
    resident_workspace: Mutex<Option<ResidentTypeCheckWorkspace>>,
    current_semantic_artifact: Mutex<Option<OwnedGpuSemanticArtifact>>,
    dependency_interface_state: Mutex<Option<GpuDependencyInterfaceState>>,
    semantic_interface_buffers: CapacityBufferCache,
}

/// Marker returned when type-check work has been recorded into a command
/// encoder and must still be submitted/read back by the caller.
pub struct RecordedTypeCheck {
    /// The status words with which call inference stopped on an error.
    inference_error: Option<[u32; 4]>,
}

#[derive(Clone, Copy)]
struct ResidentTypeCheckCacheKey {
    source_byte_capacity: u32,
    source_file_capacity: u32,
    token_capacity: u32,
    hir_node_capacity: u32,
    module_record_capacity: u32,
    call_param_row_capacity: u32,
    call_arg_row_capacity: u32,
    parser_feature_flags: u32,
    semantic_interface_required: bool,
    /// Canonical table capacity scale (`canonical_passes::CanonicalCapacity`).
    /// It only grows: a job whose canonical stage overflowed is recorded again
    /// with twice the scale, and later jobs keep it.
    canonical_scale: u32,
    input_fingerprint: u64,
}

impl ResidentTypeCheckCacheKey {
    const ROW_CAPACITY_GRANULARITY: u32 = 4 * 1024;
    const FILE_CAPACITY_GRANULARITY: u32 = 64;

    fn capacity_bucket(value: u32, granularity: u32) -> u32 {
        value
            .max(1)
            .div_ceil(granularity)
            .saturating_mul(granularity)
    }

    fn bucketed(self) -> Self {
        let rows = Self::ROW_CAPACITY_GRANULARITY;
        Self {
            source_byte_capacity: Self::capacity_bucket(self.source_byte_capacity, rows),
            source_file_capacity: Self::capacity_bucket(
                self.source_file_capacity,
                Self::FILE_CAPACITY_GRANULARITY,
            ),
            token_capacity: Self::capacity_bucket(self.token_capacity, rows),
            hir_node_capacity: Self::capacity_bucket(self.hir_node_capacity, rows),
            module_record_capacity: Self::capacity_bucket(self.module_record_capacity, rows),
            call_param_row_capacity: Self::capacity_bucket(self.call_param_row_capacity, rows),
            call_arg_row_capacity: Self::capacity_bucket(self.call_arg_row_capacity, rows),
            parser_feature_flags: self.parser_feature_flags,
            semantic_interface_required: self.semantic_interface_required,
            canonical_scale: self.canonical_scale.max(1),
            input_fingerprint: self.input_fingerprint,
        }
    }

    fn grow_to_cover(self, required: Self) -> Self {
        Self {
            source_byte_capacity: self.source_byte_capacity.max(required.source_byte_capacity),
            source_file_capacity: self.source_file_capacity.max(required.source_file_capacity),
            token_capacity: self.token_capacity.max(required.token_capacity),
            hir_node_capacity: self.hir_node_capacity.max(required.hir_node_capacity),
            module_record_capacity: self
                .module_record_capacity
                .max(required.module_record_capacity),
            call_param_row_capacity: self
                .call_param_row_capacity
                .max(required.call_param_row_capacity),
            call_arg_row_capacity: self
                .call_arg_row_capacity
                .max(required.call_arg_row_capacity),
            parser_feature_flags: self.parser_feature_flags | required.parser_feature_flags,
            semantic_interface_required: self.semantic_interface_required
                || required.semantic_interface_required,
            canonical_scale: self.canonical_scale.max(required.canonical_scale),
            // Buffer identities describe the bindings used by the replacement
            // workspace. Capacities and optional storage remain monotonic even
            // when one upstream slot grows and changes that identity.
            input_fingerprint: required.input_fingerprint,
        }
    }

    fn covers(self, required: Self) -> bool {
        self.input_fingerprint == required.input_fingerprint
            && self.source_byte_capacity >= required.source_byte_capacity
            && self.source_file_capacity >= required.source_file_capacity
            && self.token_capacity >= required.token_capacity
            && self.hir_node_capacity >= required.hir_node_capacity
            && self.module_record_capacity >= required.module_record_capacity
            && self.call_param_row_capacity >= required.call_param_row_capacity
            && self.call_arg_row_capacity >= required.call_arg_row_capacity
            && self.parser_feature_flags & required.parser_feature_flags
                == required.parser_feature_flags
            && (self.semantic_interface_required || !required.semantic_interface_required)
            && self.canonical_scale >= required.canonical_scale
    }
}

#[cfg(test)]
mod resident_typecheck_cache_key_tests {
    use super::ResidentTypeCheckCacheKey;

    fn key(capacity: u32, features: u32, fingerprint: u64) -> ResidentTypeCheckCacheKey {
        ResidentTypeCheckCacheKey {
            source_byte_capacity: capacity,
            source_file_capacity: capacity,
            token_capacity: capacity,
            hir_node_capacity: capacity,
            module_record_capacity: capacity,
            call_param_row_capacity: capacity,
            call_arg_row_capacity: capacity,
            parser_feature_flags: features,
            semantic_interface_required: false,
            canonical_scale: 1,
            input_fingerprint: fingerprint,
        }
    }

    #[test]
    fn replacement_workspace_retains_capacity_and_optional_feature_storage() {
        let allocation = key(100, 0b0101, 11).grow_to_cover(key(80, 0b1010, 22));
        assert_eq!(allocation.source_byte_capacity, 100);
        assert_eq!(allocation.parser_feature_flags, 0b1111);
        assert_eq!(allocation.input_fingerprint, 22);
        assert!(allocation.covers(key(80, 0b0010, 22)));
        assert!(allocation.covers(key(100, 0b0101, 22)));
    }

    #[test]
    fn bucketed_workspace_capacity_covers_ordinary_source_edits() {
        let allocation = key(5_238_075, 0b0101, 11).bucketed();
        let mut edited = key(5_238_075, 0b0101, 11);
        edited.source_byte_capacity = 5_238_111;
        assert_eq!(allocation.source_byte_capacity, 5_238_784);
        assert!(allocation.covers(edited));
    }

    #[test]
    fn interface_workspace_grows_monotonically_only_when_requested() {
        let ordinary = key(100, 0, 11);
        let mut interface = ordinary;
        interface.semantic_interface_required = true;
        assert!(!ordinary.covers(interface));
        let grown = ordinary.grow_to_cover(interface);
        assert!(grown.covers(interface));
        assert!(grown.covers(ordinary));
    }

    #[test]
    fn canonical_overflow_retry_rebuilds_and_keeps_the_larger_scale() {
        let ordinary = key(100, 0, 11);
        let mut retry = ordinary;
        retry.canonical_scale = super::canonical_passes::canonical_retry_scale(1, 2).unwrap();
        assert_eq!(retry.canonical_scale, 2);
        assert!(!ordinary.covers(retry));
        let grown = ordinary.grow_to_cover(retry);
        assert_eq!(grown.canonical_scale, 2);
        assert!(grown.covers(retry));
        // A later job asks for scale 1 and reuses the grown workspace.
        assert!(grown.covers(ordinary));
        assert_eq!(grown.bucketed().canonical_scale, 2);
    }

    #[test]
    fn canonical_retry_only_for_capacity_bits_and_below_the_limit() {
        use super::canonical_passes::{CANONICAL_MAX_SCALE, canonical_retry_scale};
        assert_eq!(canonical_retry_scale(1, 1), Some(2));
        assert_eq!(canonical_retry_scale(4, 4 | 8), Some(8));
        // The substitution memo and the frontier lists grow with the scale.
        assert_eq!(canonical_retry_scale(2, 16), Some(4));
        assert_eq!(canonical_retry_scale(2, 32), Some(4));
        assert_eq!(canonical_retry_scale(1, 8), None);
        // A full substitution memo (CT_OVERFLOW_SUBST_MEMO) also retries.
        assert_eq!(canonical_retry_scale(2, 16), Some(4));
        assert_eq!(canonical_retry_scale(1, 0), None);
        assert_eq!(canonical_retry_scale(CANONICAL_MAX_SCALE, 2), None);
    }

    #[test]
    fn canonical_dynamic_capacity_reaches_its_bound_at_the_largest_scale() {
        use super::canonical_passes::{CANONICAL_MAX_SCALE, canonical_scaled_capacity};
        // A bound that the scale does not divide still reaches it exactly.
        let bound = 5_499_963;
        assert_eq!(canonical_scaled_capacity(bound, 4096, 1), bound.div_ceil(64));
        assert_eq!(canonical_scaled_capacity(bound, 4096, CANONICAL_MAX_SCALE), bound);
        let mut previous = 0;
        let mut scale = 1;
        while scale <= CANONICAL_MAX_SCALE {
            let capacity = canonical_scaled_capacity(bound, 4096, scale);
            assert!(capacity > previous && capacity <= bound);
            previous = capacity;
            scale *= 2;
        }
        // A small job keeps the floor at every scale.
        assert_eq!(canonical_scaled_capacity(100, 4096, 1), 4096);
        assert_eq!(canonical_scaled_capacity(100, 4096, CANONICAL_MAX_SCALE), 4096);
    }
}

struct TypeSemanticBuffers {
    row_by_token: LaniusBuffer<u32>,
    scan_input: LaniusBuffer<u32>,
    prefix: LaniusBuffer<u32>,
    count_out: LaniusBuffer<u32>,
    row_by_ordinal: LaniusBuffer<u32>,
}

/// Type checking uses the compiler-wide kernel registry.  Artifact keys are
/// the kernel identity; semantic graph-node names remain invocation identity.
type TypeCheckPasses = KernelRegistry;

// Resident type-checking keeps buffers and bind groups in this owner so GPU
// resources stay alive across the retained pipeline even when a field is only
// consumed indirectly by a reflected bind group.
struct ResidentTypeCheckWorkspace {
    _constant_storage_plan: LaniusBuffer<ConstantStoragePlan>,
    resettable_buffers: Vec<crate::gpu::buffers::ResettableBuffer>,
    /// Dead storage inherited from the parser/lexer boundary.
    ///
    /// The type-check graph may consume only a subset of these allocations.
    /// Keep the complete set alive and forward it to semantic lowering after
    /// type checking so an allocation does not disappear from the reusable
    /// workspace merely because this phase had no compatible slot for it.
    upstream_workspace: Vec<LaniusBuffer<u8>>,
    cache_key: ResidentTypeCheckCacheKey,
    typecheck_graph: compiler_graph::TypeCheckCompilerGraph,
    name_capacity: u32,
    if_depth_n_blocks: u32,
    fn_n_blocks: u32,
    if_depth_params: LaniusBuffer<IfDepthParams>,
    fn_params: LaniusBuffer<FnContextParams>,
    language_symbol_bytes: LaniusBuffer<u8>,
    _language_name_id: LaniusBuffer<u32>,
    name_order_in: LaniusBuffer<u32>,
    name_order_tmp: LaniusBuffer<u32>,
    name_id_by_token: LaniusBuffer<u32>,
    module_path: ModulePathState,
    visible_decl: LaniusBuffer<u32>,
    visible_type: LaniusBuffer<u32>,
    hir_active_dispatch_args: LaniusBuffer<u32>,
    hir_active_dispatch: ComputeOperation,
    semantic_features: SemanticFeaturesOperation,
    status_readback: crate::gpu::operations::CopyBufferOperation,
    type_instance_decl_token: LaniusBuffer<u32>,
    _type_instance_aggregate_word_count: LaniusBuffer<u32>,
    _call_dependency_library_id: LaniusBuffer<u32>,
    _call_dependency_unit_id: LaniusBuffer<u32>,
    _call_dependency_local_index: LaniusBuffer<u32>,
    _call_dependency_host_service: LaniusBuffer<u32>,
    name_bind_groups: NameBindGroups,
    language_name_bind_groups: LanguageNameBindGroups,
    if_depth_bind_groups: IfDepthBindGroups,
    fn_context_bind_groups: FnContextBindGroups,
    visible_bind_groups: VisibleBindGroups,
    calls: CallBindGroups,
    methods: MethodBindGroups,
    predicates: PredicateBindGroups,
    type_instances: TypeInstanceBindGroups,
    returns: ReturnValidationOperation,
    condition_finalization: ConditionFinalizationOperation,
    semantic_projection: SemanticProjectionOperations,
    aggregate_comparison: AggregateComparisonOperation,
    scope_hir: ComputeOperation,
}

impl ResidentTypeCheckWorkspace {
    fn can_reuse_for(&self, key: ResidentTypeCheckCacheKey) -> bool {
        self.cache_key.covers(key)
    }

    fn semantic_artifact(
        &self,
        hir: &crate::parser::buffers::GpuHirView,
        parser_feature_flags: u32,
        dependency_interfaces_present: bool,
        semantic_interface_required: bool,
    ) -> Result<OwnedGpuSemanticArtifact> {
        let graph = &self.typecheck_graph;
        Ok(OwnedGpuSemanticArtifact {
            value_decl_by_hir: graph.buffer("semantic_value_decl_by_hir")?,
            value_type_by_hir: graph.buffer("semantic_value_type_by_hir")?,
            value_const_by_hir: graph.buffer("semantic_value_const_by_hir")?,
            value_const_present_by_hir: graph.buffer("semantic_value_const_present_by_hir")?,
            argument_mode_by_hir: graph.buffer("semantic_argument_mode_by_hir")?,
            param_ref_tag_by_row: graph.buffer("semantic_param_ref_tag_by_row")?,
            param_ref_payload_by_row: graph.buffer("semantic_param_ref_payload_by_row")?,
            enclosing_fn_by_hir: graph.buffer("semantic_enclosing_fn_by_hir")?,
            function_return_type_by_hir: graph.buffer("semantic_function_return_type_by_hir")?,
            function_entrypoint_by_hir: graph.buffer("semantic_function_entrypoint_by_hir")?,
            function_host_service_by_hir: graph.buffer("semantic_function_host_service_by_hir")?,
            control_depth_by_hir: graph.buffer("semantic_control_depth_by_hir")?,
            calls_by_hir: graph.buffer("semantic_calls_by_hir")?,
            expr_ref_tag_by_hir: graph.buffer("semantic_expr_ref_tag_by_hir")?,
            expr_ref_payload_by_hir: graph.buffer("semantic_expr_ref_payload_by_hir")?,
            aggregate_decl_token_by_hir: graph.buffer("semantic_aggregate_decl_token_by_hir")?,
            aggregate_word_count_by_hir: graph.buffer("semantic_aggregate_word_count_by_hir")?,
            type_instance_native_words: graph.buffer("type_native_word_count")?,
            type_instance_kind: graph.buffer("type_instance_kind")?,
            type_instance_lookup_head: graph.buffer("type_instance_lookup_head")?,
            type_instance_lookup_next: graph.buffer("type_instance_lookup_next")?,
            type_instance_decl_token: graph.buffer("type_instance_decl_token")?,
            type_instance_arg_count: graph.buffer("type_instance_arg_count")?,
            type_instance_arg_start: graph.buffer("type_instance_arg_start")?,
            type_instance_arg_ref_tag: graph.buffer("type_instance_arg_ref_tag")?,
            type_instance_arg_ref_payload: graph.buffer("type_instance_arg_ref_payload")?,
            type_instance_arg_row_start: graph.buffer("type_instance_arg_row_start")?,
            type_instance_arg_row_count: graph.buffer("type_instance_arg_row_count_out")?,
            type_instance_arg_row_ref_tag: graph.buffer("type_instance_arg_row_ref_tag")?,
            type_instance_arg_row_ref_payload: graph.buffer("type_instance_arg_row_ref_payload")?,
            type_instance_elem_ref_tag: graph.buffer("type_instance_elem_ref_tag")?,
            type_instance_elem_ref_payload: graph.buffer("type_instance_elem_ref_payload")?,
            type_instance_len_kind: graph.buffer("type_instance_len_kind")?,
            type_instance_len_payload: graph.buffer("type_instance_len_payload")?,
            external_type_library_id: graph.buffer("external_type_library_id")?,
            external_type_unit_id: graph.buffer("external_type_unit_id")?,
            external_type_local_index: graph.buffer("external_type_local_index")?,
            type_generic_param_slot: graph.buffer("type_generic_param_slot_by_token")?,
            type_const_param_slot: graph.buffer("type_const_param_slot_by_token")?,
            checked_constant_atoms: graph.buffer("checked_constant_atoms")?,
            checked_constant_projections: graph.buffer("checked_constant_projections")?,
            type_const_param_scalar: graph.buffer("type_const_param_scalar_by_token")?,
            type_const_param_value: graph.buffer("type_const_param_value_by_token")?,
            array_length_by_hir: graph.buffer("semantic_array_length_by_hir")?,
            member_field_ordinal_by_hir: graph.buffer("semantic_member_field_ordinal_by_hir")?,
            member_field_word_offset_by_hir: graph
                .buffer("semantic_member_field_word_offset_by_hir")?,
            member_field_word_count_by_hir: graph
                .buffer("semantic_member_field_word_count_by_hir")?,
            iterable_kind_by_hir: graph.buffer("semantic_iterable_kind_by_hir")?,
            function_result_word_count_by_hir: graph
                .buffer("semantic_function_result_word_count_by_hir")?,
            expr_scalar_type_by_hir: graph.buffer("semantic_expr_scalar_type_by_hir")?,
            public_decl_index_by_hir: self.module_path.interface_public_decl_index_by_hir.clone(),
            struct_init_field_ordinal_by_row: graph.buffer("struct_init_field_ordinal_by_row")?,
            generic_call_inputs: semantic_interface_required
                .then(|| {
                    generic_calls::RetainedGenericCallInputs::new(
                        graph,
                        hir,
                        parser_feature_flags,
                        dependency_interfaces_present,
                    )
                })
                .transpose()?,
        })
    }

    fn post_typecheck_workspace<'a>(
        &'a self,
        semantic: &OwnedGpuSemanticArtifact,
    ) -> Vec<crate::gpu::buffers::TrackedBufferView<'a>> {
        let retained = semantic.retained_allocation_ids();
        let mut reusable =
            std::collections::BTreeMap::<u64, crate::gpu::buffers::TrackedBufferView<'a>>::new();
        let candidates = self
            .resettable_buffers
            .iter()
            .map(crate::gpu::buffers::ResettableBuffer::tracked_view)
            .chain(self.upstream_workspace.iter().map(Into::into));
        for candidate in candidates {
            let Some(allocation) = candidate.allocation_id() else {
                continue;
            };
            if retained.contains(&allocation) {
                continue;
            }
            reusable
                .entry(allocation)
                .and_modify(|current| {
                    if candidate.byte_size > current.byte_size {
                        *current = candidate;
                    }
                })
                .or_insert(candidate);
        }
        reusable.into_values().collect()
    }
}

/// Typed allocation-preserving view used by the shared semantic lowering
/// stage. Keeping this narrow prevents the new backend boundary from
/// inheriting the legacy backend's token-indexed metadata surface.
#[derive(Clone, Copy)]
#[repr(C)]
#[derive(encase::ShaderType)]
pub(crate) struct GpuCheckedCallArtifact {
    pub target_token: u32,
    pub dependency_library_id: u32,
    pub dependency_unit_id: u32,
    pub dependency_local_index: u32,
    pub dependency_host_service: u32,
    pub intrinsic_tag: u32,
    pub return_type: u32,
    pub receiver_hir: u32,
    pub arg_count: u32,
    pub return_ref_tag: u32,
    pub return_ref_payload: u32,
    pub callable_kind: u32,
    pub callable_hir: u32,
    pub callable_ordinal: u32,
    pub receiver_adjustment_kind: u32,
    pub receiver_deref_count: u32,
    pub receiver_matched_ref_tag: u32,
    pub receiver_matched_ref_payload: u32,
    pub receiver_parameter_ref_tag: u32,
    pub receiver_parameter_ref_payload: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuSemanticArtifactView<'a> {
    /// Resolved declaration identity for each compact HIR value row.
    pub value_decl_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved type identity for each compact HIR value row.
    pub value_type_by_hir: &'a LaniusBuffer<u32>,
    /// Literal low/high u32 pairs for each dense HIR row. The raw u32 buffer
    /// therefore contains two words per row; Slang reads uint2 elements.
    pub value_const_by_hir: &'a LaniusBuffer<u32>,
    /// Nonzero when the corresponding row names an imported constant.
    pub value_const_present_by_hir: &'a LaniusBuffer<u32>,
    /// Complete checked declaration type for each compact parameter row,
    /// including implicit receivers without a written type node.
    pub param_ref_tag_by_row: &'a LaniusBuffer<u32>,
    pub param_ref_payload_by_row: &'a LaniusBuffer<u32>,
    /// Parameter passing mode retained before dependency pages expire.
    pub argument_mode_by_hir: &'a LaniusBuffer<u32>,
    /// Encoded enclosing compact-HIR function identity for each HIR row.
    pub enclosing_fn_by_hir: &'a LaniusBuffer<u32>,
    /// Checked return type keyed by dense function HIR row.
    pub function_return_type_by_hir: &'a LaniusBuffer<u32>,
    /// Checked entrypoint tag keyed by dense function HIR row.
    pub function_entrypoint_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved runtime host-service identity keyed by dense function HIR row.
    pub function_host_service_by_hir: &'a LaniusBuffer<u32>,
    /// Structured-control nesting depth keyed by dense HIR row.
    pub control_depth_by_hir: &'a LaniusBuffer<u32>,
    /// Canonical checked call resolution keyed by call-expression HIR row.
    pub calls_by_hir: &'a LaniusBuffer<GpuCheckedCallArtifact>,
    /// Canonical checked type-reference tag keyed by dense expression HIR row.
    pub expr_ref_tag_by_hir: &'a LaniusBuffer<u32>,
    /// Canonical checked type-reference payload keyed by dense expression HIR row.
    pub expr_ref_payload_by_hir: &'a LaniusBuffer<u32>,
    /// Resolved declaration-name token for named aggregate expressions.
    pub aggregate_decl_token_by_hir: &'a LaniusBuffer<u32>,
    /// Checked aggregate ABI width keyed by dense expression HIR row.
    pub aggregate_word_count_by_hir: &'a LaniusBuffer<u32>,
    /// Checked type-instance relation retained for concrete enum layout.
    pub type_instance_native_words: &'a LaniusBuffer<u32>,
    pub type_instance_kind: &'a LaniusBuffer<u32>,
    pub type_instance_lookup_head: &'a LaniusBuffer<u32>,
    pub type_instance_lookup_next: &'a LaniusBuffer<u32>,
    pub type_instance_decl_token: &'a LaniusBuffer<u32>,
    pub type_instance_arg_count: &'a LaniusBuffer<u32>,
    pub type_instance_arg_start: &'a LaniusBuffer<u32>,
    pub type_instance_arg_ref_tag: &'a LaniusBuffer<u32>,
    pub type_instance_arg_ref_payload: &'a LaniusBuffer<u32>,
    pub type_instance_arg_row_start: &'a LaniusBuffer<u32>,
    pub type_instance_arg_row_count: &'a LaniusBuffer<u32>,
    pub type_instance_arg_row_ref_tag: &'a LaniusBuffer<u32>,
    pub type_instance_arg_row_ref_payload: &'a LaniusBuffer<u32>,
    pub type_instance_elem_ref_tag: &'a LaniusBuffer<u32>,
    pub type_instance_elem_ref_payload: &'a LaniusBuffer<u32>,
    pub type_instance_len_kind: &'a LaniusBuffer<u32>,
    pub type_instance_len_payload: &'a LaniusBuffer<u32>,
    pub external_type_library_id: &'a LaniusBuffer<u32>,
    pub external_type_unit_id: &'a LaniusBuffer<u32>,
    pub external_type_local_index: &'a LaniusBuffer<u32>,
    pub type_generic_param_slot: &'a LaniusBuffer<u32>,
    pub type_const_param_slot: &'a LaniusBuffer<u32>,
    /// Immutable checked constant rows, exposed as four raw words per row.
    pub checked_constant_atoms: &'a LaniusBuffer<u32>,
    pub checked_constant_projections: &'a LaniusBuffer<u32>,
    pub type_const_param_scalar: &'a LaniusBuffer<u32>,
    pub type_const_param_value: &'a LaniusBuffer<u32>,
    /// Checked fixed-array length keyed by dense expression HIR row.
    pub array_length_by_hir: &'a LaniusBuffer<u32>,
    /// Checked field ordinal keyed by dense member-expression HIR row.
    pub member_field_ordinal_by_hir: &'a LaniusBuffer<u32>,
    /// Imported field's accepted native range, retained before its page expires.
    pub member_field_word_offset_by_hir: &'a LaniusBuffer<u32>,
    pub member_field_word_count_by_hir: &'a LaniusBuffer<u32>,
    /// Checked iteration representation keyed by dense for-statement HIR row.
    pub iterable_kind_by_hir: &'a LaniusBuffer<u32>,
    /// Checked target-word width keyed by dense function HIR row.
    pub function_result_word_count_by_hir: &'a LaniusBuffer<u32>,
    /// Final scalar expression type after type-checker pointer jumping.
    pub expr_scalar_type_by_hir: &'a LaniusBuffer<u32>,
    /// Persisted public-declaration index keyed by dense compact HIR node.
    pub public_decl_index_by_hir: &'a LaniusBuffer<u32>,
    /// Canonical declaration-order ordinal for each compact literal-field row.
    pub struct_init_field_ordinal_by_row: &'a LaniusBuffer<u32>,
}

/// Independently owned compact semantic boundary for one checked unit.
///
/// Cloning these handles does not copy GPU data. It detaches artifact lifetime
/// from the mutex-protected resident type-check workspace, allowing frontend
/// scratch to be recolored or released without changing backend contracts.
#[derive(Clone)]
pub(crate) struct OwnedGpuSemanticArtifact {
    generic_call_inputs: Option<generic_calls::RetainedGenericCallInputs>,
    value_decl_by_hir: LaniusBuffer<u32>,
    value_type_by_hir: LaniusBuffer<u32>,
    value_const_by_hir: LaniusBuffer<u32>,
    value_const_present_by_hir: LaniusBuffer<u32>,
    param_ref_tag_by_row: LaniusBuffer<u32>,
    param_ref_payload_by_row: LaniusBuffer<u32>,
    argument_mode_by_hir: LaniusBuffer<u32>,
    enclosing_fn_by_hir: LaniusBuffer<u32>,
    function_return_type_by_hir: LaniusBuffer<u32>,
    function_entrypoint_by_hir: LaniusBuffer<u32>,
    function_host_service_by_hir: LaniusBuffer<u32>,
    control_depth_by_hir: LaniusBuffer<u32>,
    calls_by_hir: LaniusBuffer<GpuCheckedCallArtifact>,
    expr_ref_tag_by_hir: LaniusBuffer<u32>,
    expr_ref_payload_by_hir: LaniusBuffer<u32>,
    aggregate_decl_token_by_hir: LaniusBuffer<u32>,
    aggregate_word_count_by_hir: LaniusBuffer<u32>,
    type_instance_native_words: LaniusBuffer<u32>,
    type_instance_kind: LaniusBuffer<u32>,
    type_instance_lookup_head: LaniusBuffer<u32>,
    type_instance_lookup_next: LaniusBuffer<u32>,
    type_instance_decl_token: LaniusBuffer<u32>,
    type_instance_arg_count: LaniusBuffer<u32>,
    type_instance_arg_start: LaniusBuffer<u32>,
    type_instance_arg_ref_tag: LaniusBuffer<u32>,
    type_instance_arg_ref_payload: LaniusBuffer<u32>,
    type_instance_arg_row_start: LaniusBuffer<u32>,
    type_instance_arg_row_count: LaniusBuffer<u32>,
    type_instance_arg_row_ref_tag: LaniusBuffer<u32>,
    type_instance_arg_row_ref_payload: LaniusBuffer<u32>,
    type_instance_elem_ref_tag: LaniusBuffer<u32>,
    type_instance_elem_ref_payload: LaniusBuffer<u32>,
    type_instance_len_kind: LaniusBuffer<u32>,
    type_instance_len_payload: LaniusBuffer<u32>,
    external_type_library_id: LaniusBuffer<u32>,
    external_type_unit_id: LaniusBuffer<u32>,
    external_type_local_index: LaniusBuffer<u32>,
    type_generic_param_slot: LaniusBuffer<u32>,
    type_const_param_slot: LaniusBuffer<u32>,
    checked_constant_atoms: LaniusBuffer<u32>,
    checked_constant_projections: LaniusBuffer<u32>,
    type_const_param_scalar: LaniusBuffer<u32>,
    type_const_param_value: LaniusBuffer<u32>,
    array_length_by_hir: LaniusBuffer<u32>,
    member_field_ordinal_by_hir: LaniusBuffer<u32>,
    member_field_word_offset_by_hir: LaniusBuffer<u32>,
    member_field_word_count_by_hir: LaniusBuffer<u32>,
    iterable_kind_by_hir: LaniusBuffer<u32>,
    function_result_word_count_by_hir: LaniusBuffer<u32>,
    expr_scalar_type_by_hir: LaniusBuffer<u32>,
    public_decl_index_by_hir: LaniusBuffer<u32>,
    struct_init_field_ordinal_by_row: LaniusBuffer<u32>,
}

impl OwnedGpuSemanticArtifact {
    fn retained_buffers(&self) -> Vec<crate::gpu::buffers::TrackedBufferView<'_>> {
        let mut buffers = vec![
            (&self.value_decl_by_hir).into(),
            (&self.value_type_by_hir).into(),
            (&self.value_const_by_hir).into(),
            (&self.value_const_present_by_hir).into(),
            (&self.param_ref_tag_by_row).into(),
            (&self.param_ref_payload_by_row).into(),
            (&self.argument_mode_by_hir).into(),
            (&self.enclosing_fn_by_hir).into(),
            (&self.function_return_type_by_hir).into(),
            (&self.function_entrypoint_by_hir).into(),
            (&self.function_host_service_by_hir).into(),
            (&self.control_depth_by_hir).into(),
            (&self.calls_by_hir).into(),
            (&self.expr_ref_tag_by_hir).into(),
            (&self.expr_ref_payload_by_hir).into(),
            (&self.aggregate_decl_token_by_hir).into(),
            (&self.aggregate_word_count_by_hir).into(),
            (&self.type_instance_native_words).into(),
            (&self.type_instance_kind).into(),
            (&self.type_instance_lookup_head).into(),
            (&self.type_instance_lookup_next).into(),
            (&self.type_instance_decl_token).into(),
            (&self.type_instance_arg_count).into(),
            (&self.type_instance_arg_start).into(),
            (&self.type_instance_arg_ref_tag).into(),
            (&self.type_instance_arg_ref_payload).into(),
            (&self.type_instance_arg_row_start).into(),
            (&self.type_instance_arg_row_count).into(),
            (&self.type_instance_arg_row_ref_tag).into(),
            (&self.type_instance_arg_row_ref_payload).into(),
            (&self.type_instance_elem_ref_tag).into(),
            (&self.type_instance_elem_ref_payload).into(),
            (&self.type_instance_len_kind).into(),
            (&self.type_instance_len_payload).into(),
            (&self.external_type_library_id).into(),
            (&self.external_type_unit_id).into(),
            (&self.external_type_local_index).into(),
            (&self.type_generic_param_slot).into(),
            (&self.type_const_param_slot).into(),
            (&self.checked_constant_atoms).into(),
            (&self.checked_constant_projections).into(),
            (&self.type_const_param_scalar).into(),
            (&self.type_const_param_value).into(),
            (&self.array_length_by_hir).into(),
            (&self.member_field_ordinal_by_hir).into(),
            (&self.member_field_word_offset_by_hir).into(),
            (&self.member_field_word_count_by_hir).into(),
            (&self.iterable_kind_by_hir).into(),
            (&self.function_result_word_count_by_hir).into(),
            (&self.expr_scalar_type_by_hir).into(),
            (&self.public_decl_index_by_hir).into(),
            (&self.struct_init_field_ordinal_by_row).into(),
        ];
        if let Some(inputs) = self.generic_call_inputs.as_ref() {
            buffers.extend(inputs.retained_buffers());
        }
        buffers
    }

    fn retained_allocation_ids(&self) -> std::collections::HashSet<u64> {
        self.retained_buffers()
            .into_iter()
            .filter_map(crate::gpu::buffers::TrackedBufferView::allocation_id)
            .collect()
    }

    pub(crate) fn view(&self) -> GpuSemanticArtifactView<'_> {
        GpuSemanticArtifactView {
            value_decl_by_hir: &self.value_decl_by_hir,
            value_type_by_hir: &self.value_type_by_hir,
            value_const_by_hir: &self.value_const_by_hir,
            value_const_present_by_hir: &self.value_const_present_by_hir,
            param_ref_tag_by_row: &self.param_ref_tag_by_row,
            param_ref_payload_by_row: &self.param_ref_payload_by_row,
            argument_mode_by_hir: &self.argument_mode_by_hir,
            enclosing_fn_by_hir: &self.enclosing_fn_by_hir,
            function_return_type_by_hir: &self.function_return_type_by_hir,
            function_entrypoint_by_hir: &self.function_entrypoint_by_hir,
            function_host_service_by_hir: &self.function_host_service_by_hir,
            control_depth_by_hir: &self.control_depth_by_hir,
            calls_by_hir: &self.calls_by_hir,
            expr_ref_tag_by_hir: &self.expr_ref_tag_by_hir,
            expr_ref_payload_by_hir: &self.expr_ref_payload_by_hir,
            aggregate_decl_token_by_hir: &self.aggregate_decl_token_by_hir,
            aggregate_word_count_by_hir: &self.aggregate_word_count_by_hir,
            type_instance_native_words: &self.type_instance_native_words,
            type_instance_kind: &self.type_instance_kind,
            type_instance_lookup_head: &self.type_instance_lookup_head,
            type_instance_lookup_next: &self.type_instance_lookup_next,
            type_instance_decl_token: &self.type_instance_decl_token,
            type_instance_arg_count: &self.type_instance_arg_count,
            type_instance_arg_start: &self.type_instance_arg_start,
            type_instance_arg_ref_tag: &self.type_instance_arg_ref_tag,
            type_instance_arg_ref_payload: &self.type_instance_arg_ref_payload,
            type_instance_arg_row_start: &self.type_instance_arg_row_start,
            type_instance_arg_row_count: &self.type_instance_arg_row_count,
            type_instance_arg_row_ref_tag: &self.type_instance_arg_row_ref_tag,
            type_instance_arg_row_ref_payload: &self.type_instance_arg_row_ref_payload,
            type_instance_elem_ref_tag: &self.type_instance_elem_ref_tag,
            type_instance_elem_ref_payload: &self.type_instance_elem_ref_payload,
            type_instance_len_kind: &self.type_instance_len_kind,
            type_instance_len_payload: &self.type_instance_len_payload,
            external_type_library_id: &self.external_type_library_id,
            external_type_unit_id: &self.external_type_unit_id,
            external_type_local_index: &self.external_type_local_index,
            type_generic_param_slot: &self.type_generic_param_slot,
            type_const_param_slot: &self.type_const_param_slot,
            checked_constant_atoms: &self.checked_constant_atoms,
            checked_constant_projections: &self.checked_constant_projections,
            type_const_param_scalar: &self.type_const_param_scalar,
            type_const_param_value: &self.type_const_param_value,
            array_length_by_hir: &self.array_length_by_hir,
            member_field_ordinal_by_hir: &self.member_field_ordinal_by_hir,
            member_field_word_offset_by_hir: &self.member_field_word_offset_by_hir,
            member_field_word_count_by_hir: &self.member_field_word_count_by_hir,
            iterable_kind_by_hir: &self.iterable_kind_by_hir,
            function_result_word_count_by_hir: &self.function_result_word_count_by_hir,
            expr_scalar_type_by_hir: &self.expr_scalar_type_by_hir,
            public_decl_index_by_hir: &self.public_decl_index_by_hir,
            struct_init_field_ordinal_by_row: &self.struct_init_field_ordinal_by_row,
        }
    }
}

/// Borrowed GPU tables required to canonicalize a bounded unit's public
/// semantic interface. Source bytes and parser-owned signature/member tables
/// are supplied separately by the compiler orchestration layer.
#[derive(Clone, Copy)]
pub struct GpuSemanticInterfaceIdentityBuffers<'a> {
    /// Logical row capacities are kept separately from the physical WGPU
    /// buffers.  A graph workspace may alias a larger dead allocation for a
    /// smaller logical resource, so `wgpu::Buffer::size()` is not a valid
    /// source of semantic-domain bounds.
    pub name_capacity: u32,
    pub module_capacity: u32,
    pub declaration_capacity: u32,
    pub module_segment_capacity: u32,
    pub name_count_out: TrackedBufferView<'a>,
    pub name_spans: TrackedBufferView<'a>,
    pub name_hash_lo: TrackedBufferView<'a>,
    pub name_hash_hi: TrackedBufferView<'a>,
    pub name_id_by_token: TrackedBufferView<'a>,
    pub language_symbol_bytes: TrackedBufferView<'a>,
    pub module_count_out: TrackedBufferView<'a>,
    pub module_key_segment_count: TrackedBufferView<'a>,
    pub module_key_segment_base: TrackedBufferView<'a>,
    pub module_key_segment_name_id: TrackedBufferView<'a>,
    pub decl_count_out: TrackedBufferView<'a>,
    pub decl_module_id: TrackedBufferView<'a>,
    pub decl_name_id: TrackedBufferView<'a>,
    pub decl_kind: TrackedBufferView<'a>,
    pub decl_namespace: TrackedBufferView<'a>,
    pub decl_visibility: TrackedBufferView<'a>,
    pub decl_parent_type_decl: TrackedBufferView<'a>,
    pub decl_hir_node: TrackedBufferView<'a>,
    /// Evaluated scalar constant bits keyed by dense HIR row.
    pub semantic_value_const_by_hir: TrackedBufferView<'a>,
    /// Constant-presence state keyed by dense HIR row.
    pub semantic_value_const_present_by_hir: TrackedBufferView<'a>,
    /// Runtime host-service identity for an extern function declaration,
    /// keyed by its dense HIR row. Non-host declarations carry `u32::MAX`.
    pub function_host_service_by_hir: TrackedBufferView<'a>,
    pub public_decl_count: TrackedBufferView<'a>,
    pub public_decl_local_id: TrackedBufferView<'a>,
    pub public_decl_index_by_local: TrackedBufferView<'a>,
    pub public_decl_index_by_hir: TrackedBufferView<'a>,
    pub type_expr_ref_tag: TrackedBufferView<'a>,
    pub type_expr_ref_payload: TrackedBufferView<'a>,
    pub type_generic_param_slot_by_token: TrackedBufferView<'a>,
    pub type_const_param_slot_by_token: TrackedBufferView<'a>,
    pub type_instance_decl_token: TrackedBufferView<'a>,
    pub external_type_library_id: TrackedBufferView<'a>,
    pub external_type_unit_id: TrackedBufferView<'a>,
    pub external_type_local_index: TrackedBufferView<'a>,
    pub semantic_type_ref_tag_by_hir: TrackedBufferView<'a>,
    pub semantic_type_ref_payload_by_hir: TrackedBufferView<'a>,
    pub semantic_type_generic_param_slot_by_hir: TrackedBufferView<'a>,
    pub semantic_type_external_library_id_by_hir: TrackedBufferView<'a>,
    pub semantic_type_external_unit_id_by_hir: TrackedBufferView<'a>,
    pub semantic_type_external_local_index_by_hir: TrackedBufferView<'a>,
    pub resolved_dependency_library_id: TrackedBufferView<'a>,
    pub resolved_dependency_unit_id: TrackedBufferView<'a>,
    pub resolved_dependency_local_index: TrackedBufferView<'a>,
    pub resolved_dependency_trait_header: TrackedBufferView<'a>,
    pub path_id_by_owner_hir: TrackedBufferView<'a>,
    pub path_id_by_owner_token: TrackedBufferView<'a>,
    pub resolved_type_decl: TrackedBufferView<'a>,
    pub decl_id_by_name_token: TrackedBufferView<'a>,
    pub generic_param_count_out: TrackedBufferView<'a>,
    pub generic_param_owner_token: TrackedBufferView<'a>,
    pub generic_param_name_id: TrackedBufferView<'a>,
    pub generic_param_token: TrackedBufferView<'a>,
    pub generic_param_kind: TrackedBufferView<'a>,
    pub generic_param_lookup_state: TrackedBufferView<'a>,
    pub generic_decl_owner_by_node_a: TrackedBufferView<'a>,
    pub type_decl_generic_param_count_by_owner_token: TrackedBufferView<'a>,
    pub type_decl_const_param_count_by_owner_token: TrackedBufferView<'a>,
}

/// Parser-owned checked HIR relations needed to discover the public signature
/// type forest without inspecting source text or function bodies.
#[derive(Clone, Copy)]
pub struct GpuSemanticInterfaceHirBuffers<'a> {
    /// Dense HIR capacity is a logical view over the parser-owned buffer;
    /// the physical allocation can be larger when workspace slots are reused.
    pub compact_hir_capacity: u32,
    pub compact_hir_count: &'a LaniusBuffer<u32>,
    pub compact_hir_core: &'a LaniusBuffer<crate::parser::buffers::HirCore>,
    pub compact_hir_links: &'a LaniusBuffer<crate::parser::buffers::HirLinks>,
    pub compact_hir_payload: &'a LaniusBuffer<crate::parser::buffers::HirPayload>,
    pub compact_hir_semantic_facts: &'a LaniusBuffer<crate::parser::buffers::HirSemanticFacts>,
    pub compact_const_value: &'a LaniusBuffer<u32>,
    pub compact_fn_return_type: &'a LaniusBuffer<u32>,
    pub compact_type_alias_target: &'a LaniusBuffer<u32>,
    pub compact_const_type: &'a LaniusBuffer<u32>,
    pub compact_param_count: &'a LaniusBuffer<u32>,
    pub compact_params: &'a LaniusBuffer<crate::parser::buffers::HirParam>,
    pub compact_param_ranges: &'a LaniusBuffer<crate::parser::buffers::HirRange>,
    pub compact_predicate_count: &'a LaniusBuffer<u32>,
    pub compact_predicates: &'a LaniusBuffer<crate::parser::buffers::HirPredicate>,
    pub compact_type_arg_count: &'a LaniusBuffer<u32>,
    pub compact_type_args: &'a LaniusBuffer<crate::parser::buffers::HirTypeArg>,
    pub compact_type_arg_ranges: &'a LaniusBuffer<crate::parser::buffers::HirRange>,
    pub compact_generic_param_count: &'a LaniusBuffer<u32>,
    pub compact_generic_params: &'a LaniusBuffer<crate::parser::buffers::HirGenericParam>,
    pub compact_generic_param_ranges: &'a LaniusBuffer<crate::parser::buffers::HirRange>,
    pub compact_path_count: &'a LaniusBuffer<u32>,
    pub compact_paths: &'a LaniusBuffer<crate::parser::buffers::HirPath>,
    pub compact_path_segment_count: &'a LaniusBuffer<u32>,
    pub compact_path_segments: &'a LaniusBuffer<crate::parser::buffers::HirPathSegment>,
    pub compact_field_count: &'a LaniusBuffer<u32>,
    pub compact_fields: &'a LaniusBuffer<crate::parser::buffers::HirField>,
    pub compact_variant_count: &'a LaniusBuffer<u32>,
    pub compact_variants: &'a LaniusBuffer<crate::parser::buffers::HirVariant>,
    pub compact_variant_payload_count: &'a LaniusBuffer<u32>,
    pub compact_variant_payload_row_count: &'a LaniusBuffer<u32>,
    pub compact_variant_payloads: &'a LaniusBuffer<crate::parser::buffers::HirVariantPayload>,
    pub compact_method_count: &'a LaniusBuffer<u32>,
    pub compact_method_cores: &'a LaniusBuffer<crate::parser::buffers::HirMethodCore>,
    pub compact_method_signatures: &'a LaniusBuffer<crate::parser::buffers::HirMethodSignature>,
}
