//! Retained instance projection (docs/compiler-retained-projection.md).
//!
//! A producer (discovery, or a test producer) writes instance records,
//! routes and a readiness record into [`ProjectionInputs`] on the GPU. The
//! projection plans each rank, substitutes every signature, row and use
//! term with [`RetainedSubstitution`], lays out the closed types, checks
//! every row (types, routes, signatures and the frontend's literal,
//! operator and destination rules) and, when nothing failed, writes the
//! existing lowering's input columns for one batch of ranks at a time and
//! lowers each batch to an x86 object with the existing pipeline. It never
//! runs a frontend, never reads instance text and never calls source
//! replay.
//!
//! The host allocates, records, submits and reads compact status: the
//! plan's totals (to size the request and row tables), the check's state
//! and first error, and the batch table (to size the batch columns and
//! record one lowering job per nonempty batch). It reads no instance,
//! term, row or route.

use crate::gpu::copies::{CountedCommands, CountedWrites};
mod schema_projection;
pub use schema_projection::SchemaReport;

use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail};

use super::{
    A_TERMS, A_TERM_ARGS,
    ProgramRetention,
    Store,
    reflected_names,
    storage,
    substitution::{
        RetainedSubstitution,
        SubstitutionCapacity,
        SubstitutionReport,
        SubstitutionRequests,
        SubstitutionRun,
        words as sub_words,
    },
    words_bytes,
};
use crate::{
    codegen::{lir::semantics::GpuSemanticHirInputs, x86::GpuX86RelocatableObject},
    compiler::GpuCompiler,
    gpu::{
        buffers::LaniusBuffer,
        operations::{StepProgramOperation, step_program_group_counts, step_program_group_variant},
    passes_core::{
            self,
            PassData,
            make_pass_data_from_shader_key,
            map_readback_blocking,
        },
    },
    parser::buffers::{
        HirArrayElement,
        HirCallArg,
        HirCore,
        HirField,
        HirLinks,
        HirMatchArm,
        HirMatchPayload,
        HirMethodCore,
        HirMethodSignature,
        HirParam,
        HirPayload,
        HirRange,
        HirString,
        HirVariant,
        HirVariantPayload,
    },
    type_checker::{GpuCheckedCallArtifact, GpuSemanticArtifactView},
};

/// Native identity of instance objects and symbols (codegen/x86/symbol_finalization.rs).
pub const NATIVE_LIBRARY: u32 = 0xffff_fffe;
pub const NATIVE_NS_INSTANCE: u32 = 0xffff_0002;
/// Route of a use that is not a call (a struct literal).
pub const ROUTE_NONE: u32 = 0xffff_ffff;
/// Instance flag: the program entry.
pub const FLAG_ENTRY: u32 = 1;
/// Readiness flag: routes published.
pub const READY_ROUTES: u32 = 1;
/// Readiness flag: the producer certified call ABIs.
pub const READY_ABI: u32 = 2;

/// Error codes (retained_projection_layout.slang PJ_E_*).
pub mod error {
    pub const READINESS: u32 = 1;
    pub const RECORD: u32 = 2;
    pub const DECL: u32 = 3;
    pub const DUPLICATE: u32 = 4;
    pub const ROUTES: u32 = 5;
    pub const ENTRY: u32 = 6;
    pub const SUBST: u32 = 7;
    pub const PUBLICATION: u32 = 8;
    pub const FORM: u32 = 9;
    pub const ROLE: u32 = 10;
    pub const INCOMPLETE: u32 = 11;
    pub const TYPE: u32 = 12;
    pub const LAYOUT: u32 = 13;
    pub const USE: u32 = 14;
    pub const ROUTE: u32 = 15;
    pub const SIGNATURE: u32 = 16;
    pub const RULE: u32 = 17;
    pub const DEPTH: u32 = 18;
    pub const FIELD: u32 = 19;
    pub const INPUT_CAPACITY: u32 = 20;
    /// A call from an original object does not match its root route's
    /// target (certify_retained_native_abi.slang). Detail: the failure bits;
    /// `row`: the lowest failing build-global use.
    pub const ROOT_ABI: u32 = 21;

    /// Rule details: the diagnostic in the top byte.
    pub const RULE_ASSIGN_MISMATCH: u32 = 3;
    pub const RULE_INTEGER_RANGE: u32 = 24;
    pub const RULE_FLOAT_LITERAL: u32 = 25;

    pub fn name(code: u32) -> &'static str {
        match code {
            READINESS => "readiness",
            RECORD => "instance record",
            DECL => "callable",
            DUPLICATE => "duplicate instance",
            ROUTES => "route range",
            ENTRY => "entry",
            SUBST => "substitution",
            PUBLICATION => "publication",
            FORM => "unsupported form",
            ROLE => "unsupported role",
            INCOMPLETE => "incomplete row",
            TYPE => "unsupported type",
            LAYOUT => "layout",
            USE => "unsupported use",
            ROUTE => "route",
            SIGNATURE => "signature",
            RULE => "language rule",
            DEPTH => "depth",
            FIELD => "field",
            INPUT_CAPACITY => "producer capacity",
            ROOT_ABI => "root call ABI",
            _ => "unknown",
        }
    }
}

// retained_projection_layout.slang.
const INSTANCE_WORDS: u64 = 2;
const INFO_WORDS: u64 = 6;
const COLUMNS: u64 = 10;
const C_ROWS: usize = 0;
const C_TOKENS: usize = 1;
const C_SIDE: usize = 2;
const SIDE_TABLES: usize = 7;
const C_REQUESTS: usize = 9;
const CFG_WORDS: usize = 12;
const CFG_RUN: usize = 0;
const CFG_BATCH_ROWS: usize = 1;
const CFG_BATCH: usize = 2;
const CFG_IDENTITY_MASK: usize = 4;
const CFG_ROW_CAP: usize = 5;
const CFG_TOKEN_CAP: usize = 6;
const CFG_SIDE_CAP: usize = 7;
const CFG_GATE: usize = 8;
const CFG_LAYOUT_ROUNDS: usize = 9;
const CFG_PATTERN_ROUNDS: usize = 10;
const GATE_ON: u32 = 1;
const GATE_FORCE_FAIL: u32 = 2;
const VERDICT_PASSED: u32 = 1;
const S_STATE: usize = 0;
const S_ERRORS: usize = 1;
const S_ERROR_RANK: usize = 2;
const S_ERROR_ROW: usize = 3;
const S_IDENTITY_OVERFLOW: usize = 12;
const S_INPUT_ERROR: usize = 13;
const S_INPUT_DETAIL: usize = 14;
const S_TOTALS: usize = 16;
const S_FIRST: usize = 32;
const S_BATCH_ROWS: usize = 40;
const S_BATCH_TOKENS: usize = 41;
const S_BATCH_SIDE: usize = 42;
const S_BATCH_NONEMPTY: usize = 43;
const S_BATCH_STRING_WORDS: usize = 44;
const S_BATCHES: usize = 9;
const S_LAYOUT_CHANGED: usize = 10;
const S_PATTERN_CHANGED: usize = 11;
const S_GATE: usize = 60;
const S_PROGRAM_FAILED: usize = 61;
const S_CALL_PROGRAM_FAILED: usize = 47;
const STATUS_WORDS: usize = 64;
const BATCH_WORDS: usize = 12;
const STATE_CHECKED: u32 = 1;
/// Layout rounds recorded by a new projection. One round completes at least
/// one nesting level of every type whose layout is still pending.
const LAYOUT_ROUNDS: u32 = 16;
/// Pattern payload rounds recorded by a new projection. One round resolves
/// one nesting level of every pending pattern payload.
const PATTERN_ROUNDS: u32 = 4;
const CALL_WORDS: u64 = 22;

const PREPARE_VALIDATION: &str = "type_checker/retention/projection/prepare_retained_validation";
const KERNELS: &[&str] = &[
    "type_checker/retention/projection/prepare_retained_projection",
    "type_checker/retention/projection/substitute_retained_projection_terms",
    PREPARE_VALIDATION,
    "type_checker/retention/projection/materialize_retained_batch",
    "type_checker/retention/projection/certify_retained_root_calls",
    "type_checker/retention/projection/validate_retained_call_routes",
];
const K_PLAN: usize = 0;
const K_REQUESTS: usize = 1;
const K_PREPARE_VALIDATION: usize = 2;
const K_MATERIALIZE: usize = 3;
const K_CERTIFY: usize = 4;
const K_CALLS: usize = 5;

/// The root routes of original objects and the caller ABI facts of their
/// calls (docs/compiler-retained-projection.md, "Native compilation").
/// `routes` holds one `(library, namespace, local, generation)` uint4 per
/// build-global use and `readiness` one `(generation, flags, instance count,
/// use count)` uint4. A run with roots sets `READY_ABI` in `readiness` only
/// when every call the original objects recorded matches its target.
pub struct RootCertification<'a> {
    pub routes: &'a wgpu::Buffer,
    pub readiness: &'a wgpu::Buffer,
    pub calls: &'a super::NativeCallTables,
}

/// Test kernel: the explicit-instance producer (shaders/tests/publish_test_projection_instances.slang).
#[doc(hidden)]
pub const PRODUCER_KERNEL: &str = "tests/publish_test_projection_instances";

/// The producer's GPU buffers: `pj_instances` (two uint4 per rank),
/// `pj_routes` (one uint4 per route) and `pj_readiness` (one uint4). The
/// host never writes or reads a row of them.
#[derive(Clone)]
pub struct ProjectionInputs {
    instances: wgpu::Buffer,
    routes: wgpu::Buffer,
    readiness: wgpu::Buffer,
    targets: wgpu::Buffer,
    instance_capacity: u32,
    route_capacity: u32,
}

impl ProjectionInputs {
    /// Buffers for up to `instances` ranks and `routes` routes.
    pub fn new(instances: u32, routes: u32) -> Self {
        Self::new_with_device(&crate::gpu::device::global().device, instances, routes)
    }

    pub(crate) fn new_with_device(device: &wgpu::Device, instances: u32, routes: u32) -> Self {
        let instances = instances.max(1);
        let routes = routes.max(1);
        Self {
            instances: storage(
                device,
                "pj_instances",
                instances as u64 * INSTANCE_WORDS * 16,
                false,
            ),
            routes: storage(device, "pj_routes", routes as u64 * 16, false),
            readiness: storage(device, "pj_readiness", 16, false),
            targets: storage(device,"pj_targets",routes as u64*8,false),
            instance_capacity: instances,
            route_capacity: routes,
        }
    }

    pub fn instance_capacity(&self) -> u32 {
        self.instance_capacity
    }

    pub fn route_capacity(&self) -> u32 {
        self.route_capacity
    }

    /// The buffers a producer binds, by binding name.
    pub fn buffers(&self) -> [(&'static str, &wgpu::Buffer); 4] {
        [
            ("pj_instances", &self.instances),
            ("pj_routes", &self.routes),
            ("pj_readiness", &self.readiness),
            ("pj_targets",&self.targets),
        ]
    }
}

/// Options of one projection run.
#[derive(Clone, Copy, Debug)]
pub struct ProjectionOptions {
    /// Global rows that start a new lowering batch: batch b holds the ranks
    /// whose first row is in `[b * batch_rows, (b + 1) * batch_rows)`.
    pub batch_rows: u32,
    /// Mask of the identity table's start slot (`u32::MAX` normally; 0
    /// puts every identity on one probe chain).
    pub identity_mask: u32,
}

impl Default for ProjectionOptions {
    fn default() -> Self {
        Self {
            batch_rows: 1 << 16,
            identity_mask: u32::MAX,
        }
    }
}

/// The first error of a rejected projection, in (rank, row) order, at its
/// template location.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProjectionError {
    pub code: u32,
    pub detail: u32,
    pub rank: u32,
    /// The rank's callable DeclId.
    pub decl: u32,
    /// Body-relative row, `u32::MAX` for an error of the instance record.
    pub row: u32,
    /// Body-relative token of the row's start.
    pub token: u32,
    /// The defining job's file id and the file-relative byte start.
    pub file: u32,
    pub byte: u32,
    /// Defining frontend job and source token length (diagnostic metadata).
    pub job: u32,
    pub len: u32,
}

impl std::fmt::Display for ProjectionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "retained projection rejected rank {} (DeclId {}): {} (code {}, detail {:#x})",
            self.rank,
            self.decl,
            error::name(self.code),
            self.code,
            self.detail
        )?;
        if self.row != u32::MAX {
            write!(
                f,
                " at template row {} token {} (file {}, byte {})",
                self.row, self.token, self.file, self.byte
            )?;
        }
        Ok(())
    }
}

/// One lowering batch.
#[derive(Clone, Copy, Debug)]
pub struct ProjectionBatch {
    /// Ranks `lo..hi`.
    pub lo: u32,
    pub hi: u32,
    /// Rows with the batch root, tokens, and side-table rows per table.
    pub rows: u32,
    pub tokens: u32,
    pub side: [u32; 7],
    pub string_words: u32,
}

/// What one projection run did.
#[derive(Clone, Debug, Default)]
pub struct ProjectionReport {
    pub instances: u32,
    pub rows: u32,
    pub tokens: u32,
    pub requests: u32,
    pub batches: Vec<ProjectionBatch>,
    pub substitution: Option<SubstitutionReport>,
    pub schema: SchemaReport,
    /// Projection dispatches (the substitution and lowering count their own).
    pub dispatches: u32,
    /// Host readbacks of projection status and the batch table.
    pub readbacks: u32,
    pub readback_bytes: u64,
    /// Bytes of projection tables and batch columns allocated now.
    pub allocated_bytes: u64,
    /// Times a projection table or the batch columns were (re)allocated.
    pub allocations: u32,
    /// Wall time of the phases, in microseconds: plan, substitution, check,
    /// batches (projection and lowering).
    pub plan_us: u64,
    pub substitution_us: u64,
    pub check_us: u64,
    pub lowering_us: u64,
    /// Lowerings recorded before the check readback, and those of them
    /// discarded because the check did not pass them.
    pub early_lowerings: u32,
    pub early_discarded: u32,
}

/// The outcome of [`RetainedProjection::run`].
pub enum ProjectionOutcome<T = GpuX86RelocatableObject> {
    /// Every rank checked and every batch lowered.
    Objects {
        objects: Vec<T>,
        report: ProjectionReport,
    },
    /// Nothing was lowered.
    Rejected {
        error: ProjectionError,
        report: ProjectionReport,
    },
}

impl<T> ProjectionOutcome<T> {
    pub fn objects(self) -> Result<(Vec<T>, ProjectionReport)> {
        match self {
            Self::Objects { objects, report } => Ok((objects, report)),
            Self::Rejected { error, .. } => bail!("{error}"),
        }
    }

    pub fn report(&self) -> &ProjectionReport {
        match self {
            Self::Objects { report, .. } | Self::Rejected { report, .. } => report,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct ColumnShape {
    rows: u64,
    side: u64,
    types: u64,
    string_words: u64,
    type_args: u64,
}

/// The lowering columns of one batch: compact HIR and semantic views over
/// buffers the projection writes (or that hold the empty-table values).
struct BatchColumns {
    shape: ColumnShape,
    words: BTreeMap<&'static str, LaniusBuffer<u32>>,
    core: LaniusBuffer<HirCore>,
    links: LaniusBuffer<HirLinks>,
    payload: LaniusBuffer<HirPayload>,
    call_args: LaniusBuffer<HirCallArg>,
    fields: LaniusBuffer<HirField>,
    params: LaniusBuffer<HirParam>,
    param_ranges: LaniusBuffer<HirRange>,
    generic_param_ranges: LaniusBuffer<HirRange>,
    variants: LaniusBuffer<HirVariant>,
    variant_payloads: LaniusBuffer<HirVariantPayload>,
    match_arms: LaniusBuffer<HirMatchArm>,
    match_payloads: LaniusBuffer<HirMatchPayload>,
    array_elements: LaniusBuffer<HirArrayElement>,
    strings: LaniusBuffer<HirString>,
    method_cores: LaniusBuffer<HirMethodCore>,
    method_signatures: LaniusBuffer<HirMethodSignature>,
    calls: LaniusBuffer<GpuCheckedCallArtifact>,
    counts: [LaniusBuffer<u32>; 8],
    bytes: u64,
}

const COUNT_NAMES: [&str; 8] = [
    "ob_count_rows",
    "ob_count_call_args",
    "ob_count_fields",
    "ob_count_match_arms",
    "ob_count_match_payloads",
    "ob_count_array_elements",
    "ob_count_strings",
    "ob_count_params",
];

#[derive(Clone, Copy)]
enum Size {
    Rows,
    Side,
    Types,
    One,
    StringWords,
    TypeArgs,
}

/// u32 columns: (name, size class, words per element, fill word).
const WORD_COLUMNS: &[(&str, Size, u64, u32)] = &[
    ("ob_fn_return_type", Size::Rows, 1, 0),
    ("ob_const_value", Size::Rows, 1, 0),
    ("ob_expr_parent", Size::Rows, 1, 0),
    ("ob_expr_root", Size::Rows, 1, 0),
    ("ob_nearest_loop", Size::Rows, 1, 0),
    ("ob_array_element_start", Size::Rows, 1, 0),
    ("ob_array_element_count", Size::Rows, 1, 0),
    ("ob_value_decl", Size::Rows, 1, 0),
    ("ob_value_type", Size::Rows, 1, 0),
    ("ob_value_const", Size::Rows, 2, 0),
    ("ob_value_const_present", Size::Rows, 1, 0),
    ("ob_argument_mode", Size::Rows, 1, 0),
    ("ob_param_ref_tag", Size::Side, 1, 0),
    ("ob_param_ref_payload", Size::Side, 1, 0),
    ("ob_enclosing_fn", Size::Rows, 1, 0),
    ("ob_function_return_type", Size::Rows, 1, 0),
    ("ob_function_entrypoint", Size::Rows, 1, 0),
    ("ob_function_host_service", Size::Rows, 1, 0),
    ("ob_function_native_abi", Size::Rows, 1, 0),
    ("ob_control_depth", Size::Rows, 1, 0),
    ("ob_call_native_abi", Size::Rows, 1, 0),
    ("ob_expr_ref_tag", Size::Rows, 1, 0),
    ("ob_expr_ref_payload", Size::Rows, 1, 0),
    ("ob_aggregate_decl_token", Size::Rows, 1, 0),
    ("ob_aggregate_word_count", Size::Rows, 1, 0),
    ("ob_array_length", Size::Rows, 1, 0),
    ("ob_member_field_ordinal", Size::Rows, 1, 0),
    ("ob_member_field_word_offset", Size::Rows, 1, 0),
    ("ob_member_field_word_count", Size::Rows, 1, 0),
    ("ob_iterable_kind", Size::Rows, 1, 0),
    ("ob_function_result_word_count", Size::Rows, 1, 0),
    ("ob_expr_scalar_type", Size::Rows, 1, 0),
    ("ob_public_decl_index", Size::Rows, 1, 0),
    ("ob_struct_init_field_ordinal", Size::Side, 1, 0),
    // Type tables by TermId (compute_closed_type_layouts writes them).
    ("ob_ti_kind", Size::Types, 1, 0),
    ("ob_ti_native_words", Size::Types, 1, 0),
    ("ob_ti_decl_token", Size::Types, 1, 0),
    ("ob_ti_elem_ref_tag", Size::Types, 1, 0),
    ("ob_ti_elem_ref_payload", Size::Types, 1, 0),
    ("ob_ti_len_kind", Size::Types, 1, 0),
    ("ob_ti_len_payload", Size::Types, 1, 0),
    ("ob_ti_arg_count", Size::Types, 1, 0),
    ("ob_ti_arg_start", Size::Types, 1, 0),
    ("ob_ext_library", Size::Types, 1, 0),
    ("ob_ext_unit", Size::Types, 1, 0),
    ("ob_ext_local", Size::Types, 1, 0),
    ("ob_imported_layout_kind", Size::Types, 1, 0),
    // Tables no projected row uses: the values of an empty table.
    ("z_ti_lookup_head", Size::Types, 1, 0),
    ("z_ti_lookup_next", Size::Types, 1, 0),
    ("z_ti_arg_ref_tag", Size::Types, 1, 0),
    ("z_ti_arg_ref_payload", Size::Types, 1, u32::MAX),
    ("ob_ti_arg_row_start", Size::Types, 1, 0),
    ("ob_ti_arg_row_count", Size::One, 1, 0),
    ("ob_ti_arg_row_ref_tag", Size::TypeArgs, 1, 0),
    ("ob_ti_arg_row_ref_payload", Size::TypeArgs, 1, u32::MAX),
    ("z_generic_param_slot", Size::Types, 1, u32::MAX),
    ("z_const_param_slot", Size::Types, 1, u32::MAX),
    ("ob_constant_atoms", Size::Types, 4, 0),
    ("z_constant_projections", Size::Rows, 4, 0),
    ("z_const_param_scalar", Size::Types, 1, 0),
    ("z_const_param_value", Size::Types, 1, u32::MAX),
    ("z_variant_count", Size::One, 1, 0),
    ("z_variant_payload_start", Size::Rows, 1, 0),
    ("z_variant_payload_count", Size::Rows, 1, 0),
    ("z_variant_payload_row_count", Size::One, 1, 0),
    ("ob_match_payload_start", Size::Side, 1, 0),
    ("ob_match_payload_count", Size::Side, 1, 0),
    ("ob_string_data", Size::StringWords, 1, 0),
    ("ob_string_pool_len", Size::One, 1, 0),
    ("z_method_count", Size::One, 1, 0),
];

fn filled(device: &wgpu::Device, label: &'static str, words: u64, fill: u32) -> wgpu::Buffer {
    let words = words.max(4).next_multiple_of(4);
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: words * 4,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: fill != 0,
    });
    if fill != 0 {
        {
            let bytes: Vec<u8> = (0..words).flat_map(|_| fill.to_le_bytes()).collect();
            buffer
                .slice(..)
                .get_mapped_range_mut()
                .slice(..)
                .copy_from_slice(&bytes);
        }
        buffer.unmap();
    }
    buffer
}

impl BatchColumns {
    /// Columns of `shape`. The TermId type tables of `previous` (written
    /// by the layout kernel of the current run) move over when its type
    /// capacity matches.
    fn new(device: &wgpu::Device, shape: ColumnShape, previous: Option<BatchColumns>) -> Self {
        let mut kept = previous
            .filter(|p| p.shape.types == shape.types)
            .map(|p| p.words)
            .unwrap_or_default();
        let mut bytes = 0u64;
        let mut make = |label: &'static str, words: u64, fill: u32| -> (wgpu::Buffer, u64) {
            let buffer = filled(device, label, words, fill);
            bytes += buffer.size();
            let size = buffer.size();
            (buffer, size)
        };
        let mut words = BTreeMap::new();
        for &(name, size, per, fill) in WORD_COLUMNS {
            if (matches!(size, Size::Types | Size::TypeArgs) || name == "ob_ti_arg_row_count")
                && let Some(buffer) = kept.remove(name)
                && (!matches!(size, Size::TypeArgs) || buffer.byte_size as u64 >= shape.type_args * 4)
            {
                words.insert(name, buffer);
                continue;
            }
            let count = match size {
                Size::Rows => shape.rows,
                Size::Side => shape.side,
                Size::Types => shape.types,
                Size::One => 1,
                Size::StringWords => shape.string_words,
                Size::TypeArgs => shape.type_args,
            };
            let (buffer, size) = make(name, count * per, fill);
            words.insert(
                name,
                LaniusBuffer::new((buffer, size), (count * per) as usize),
            );
        }
        let mut typed = |label: &'static str, count: u64, per: u64| {
            let (buffer, size) = make(label, count * per, 0);
            (buffer, size, count as usize)
        };
        macro_rules! typed {
            ($label:expr, $count:expr, $per:expr) => {{
                let (b, s, n) = typed($label, $count, $per);
                LaniusBuffer::new((b, s), n)
            }};
        }
        let rows = shape.rows;
        let side = shape.side;
        let core = typed!("ob_core", rows, 4);
        let links = typed!("ob_links", rows, 4);
        let payload = typed!("ob_payload", rows, 4);
        let call_args = typed!("ob_call_args", side, 4);
        let fields = typed!("ob_fields", side, 4);
        let params = typed!("ob_params", side, 4);
        let param_ranges = typed!("ob_param_ranges", rows, 2);
        let generic_param_ranges = typed!("ob_generic_param_ranges", rows, 2);
        let variants = typed!("z_variants", rows, 4);
        let variant_payloads = typed!("z_variant_payloads", rows, 4);
        let match_arms = typed!("ob_match_arms", side, 4);
        let match_payloads = typed!("ob_match_payloads", side, 4);
        let array_elements = typed!("ob_array_elements", side, 4);
        let strings = typed!("ob_strings", side, 4);
        let method_cores = typed!("z_method_cores", rows, 4);
        let method_signatures = typed!("z_method_signatures", rows, 4);
        let calls = typed!("ob_calls", rows, CALL_WORDS);
        let counts = COUNT_NAMES.map(|name| {
            let (b, s, n) = typed(name, 1, 1);
            LaniusBuffer::new((b, s), n)
        });
        Self {
            shape,
            words,
            core,
            links,
            payload,
            call_args,
            fields,
            params,
            param_ranges,
            generic_param_ranges,
            variants,
            variant_payloads,
            match_arms,
            match_payloads,
            array_elements,
            strings,
            method_cores,
            method_signatures,
            calls,
            counts,
            bytes,
        }
    }

    /// The buffer a projection kernel binds as `name`.
    fn binding(&self, name: &str) -> Option<&wgpu::Buffer> {
        if let Some(b) = self.words.get(name) {
            return Some(&b.buffer);
        }
        if let Some(i) = COUNT_NAMES.iter().position(|n| *n == name) {
            return Some(&self.counts[i].buffer);
        }
        Some(match name {
            "ob_core" => &self.core.buffer,
            "ob_links" => &self.links.buffer,
            "ob_payload" => &self.payload.buffer,
            "ob_call_args" => &self.call_args.buffer,
            "ob_fields" => &self.fields.buffer,
            "ob_match_arms" => &self.match_arms.buffer,
            "ob_match_payloads" => &self.match_payloads.buffer,
            "ob_array_elements" => &self.array_elements.buffer,
            "ob_strings" => &self.strings.buffer,
            "ob_params" => &self.params.buffer,
            "ob_param_ranges" => &self.param_ranges.buffer,
            "ob_generic_param_ranges" => &self.generic_param_ranges.buffer,
            "ob_calls" => &self.calls.buffer,
            _ => return None,
        })
    }

    fn w(&self, name: &str) -> &LaniusBuffer<u32> {
        &self.words[name]
    }

    fn hir(&self) -> GpuSemanticHirInputs<'_> {
        let [
            count,
            call_arg_count,
            field_count,
            match_arm_count,
            match_payload_row_count,
            array_element_row_count,
            string_count,
            param_count,
        ] = &self.counts;
        GpuSemanticHirInputs {
            count,
            core: &self.core,
            links: &self.links,
            payload: &self.payload,
            fn_return_type: self.w("ob_fn_return_type"),
            const_value: self.w("ob_const_value"),
            expr_parent: self.w("ob_expr_parent"),
            expr_root: self.w("ob_expr_root"),
            nearest_loop: self.w("ob_nearest_loop"),
            call_arg_count,
            call_args: &self.call_args,
            field_count,
            fields: &self.fields,
            variant_count: self.w("z_variant_count"),
            variants: &self.variants,
            variant_payload_start: self.w("z_variant_payload_start"),
            variant_payload_count: self.w("z_variant_payload_count"),
            variant_payload_row_count: self.w("z_variant_payload_row_count"),
            variant_payloads: &self.variant_payloads,
            match_arm_count,
            match_arms: &self.match_arms,
            match_payload_start: self.w("ob_match_payload_start"),
            match_payload_count: self.w("ob_match_payload_count"),
            match_payload_row_count,
            match_payloads: &self.match_payloads,
            array_element_start: self.w("ob_array_element_start"),
            array_element_count: self.w("ob_array_element_count"),
            array_element_row_count,
            array_elements: &self.array_elements,
            string_count,
            strings: &self.strings,
            string_data_words: self.w("ob_string_data"),
            string_pool_len: self.w("ob_string_pool_len"),
            param_count,
            params: &self.params,
            param_ranges: &self.param_ranges,
            generic_param_ranges: &self.generic_param_ranges,
            method_count: self.w("z_method_count"),
            method_cores: &self.method_cores,
            method_signatures: &self.method_signatures,
        }
    }

    fn semantic(&self) -> GpuSemanticArtifactView<'_> {
        GpuSemanticArtifactView {
            value_decl_by_hir: self.w("ob_value_decl"),
            value_type_by_hir: self.w("ob_value_type"),
            value_const_by_hir: self.w("ob_value_const"),
            value_const_present_by_hir: self.w("ob_value_const_present"),
            param_ref_tag_by_row: self.w("ob_param_ref_tag"),
            param_ref_payload_by_row: self.w("ob_param_ref_payload"),
            argument_mode_by_hir: self.w("ob_argument_mode"),
            enclosing_fn_by_hir: self.w("ob_enclosing_fn"),
            function_return_type_by_hir: self.w("ob_function_return_type"),
            function_entrypoint_by_hir: self.w("ob_function_entrypoint"),
            function_host_service_by_hir: self.w("ob_function_host_service"),
            function_native_abi_by_hir: self.w("ob_function_native_abi"),
            control_depth_by_hir: self.w("ob_control_depth"),
            calls_by_hir: &self.calls,
            call_native_abi_by_hir: self.w("ob_call_native_abi"),
            expr_ref_tag_by_hir: self.w("ob_expr_ref_tag"),
            expr_ref_payload_by_hir: self.w("ob_expr_ref_payload"),
            aggregate_decl_token_by_hir: self.w("ob_aggregate_decl_token"),
            aggregate_word_count_by_hir: self.w("ob_aggregate_word_count"),
            type_instance_native_words: self.w("ob_ti_native_words"),
            type_instance_kind: self.w("ob_ti_kind"),
            type_instance_lookup_head: self.w("z_ti_lookup_head"),
            type_instance_lookup_next: self.w("z_ti_lookup_next"),
            type_instance_decl_token: self.w("ob_ti_decl_token"),
            type_instance_arg_count: self.w("ob_ti_arg_count"),
            type_instance_arg_start: self.w("ob_ti_arg_start"),
            type_instance_arg_ref_tag: self.w("z_ti_arg_ref_tag"),
            type_instance_arg_ref_payload: self.w("z_ti_arg_ref_payload"),
            type_instance_arg_row_start: self.w("ob_ti_arg_row_start"),
            type_instance_arg_row_count: self.w("ob_ti_arg_row_count"),
            type_instance_arg_row_ref_tag: self.w("ob_ti_arg_row_ref_tag"),
            type_instance_arg_row_ref_payload: self.w("ob_ti_arg_row_ref_payload"),
            type_instance_elem_ref_tag: self.w("ob_ti_elem_ref_tag"),
            type_instance_elem_ref_payload: self.w("ob_ti_elem_ref_payload"),
            type_instance_len_kind: self.w("ob_ti_len_kind"),
            type_instance_len_payload: self.w("ob_ti_len_payload"),
            external_type_library_id: self.w("ob_ext_library"),
            external_type_unit_id: self.w("ob_ext_unit"),
            external_type_local_index: self.w("ob_ext_local"),
            imported_layout_kind: self.w("ob_imported_layout_kind"),
            type_generic_param_slot: self.w("z_generic_param_slot"),
            type_const_param_slot: self.w("z_const_param_slot"),
            checked_constant_atoms: self.w("ob_constant_atoms"),
            checked_constant_projections: self.w("z_constant_projections"),
            type_const_param_scalar: self.w("z_const_param_scalar"),
            type_const_param_value: self.w("z_const_param_value"),
            array_length_by_hir: self.w("ob_array_length"),
            member_field_ordinal_by_hir: self.w("ob_member_field_ordinal"),
            member_field_word_offset_by_hir: self.w("ob_member_field_word_offset"),
            member_field_word_count_by_hir: self.w("ob_member_field_word_count"),
            iterable_kind_by_hir: self.w("ob_iterable_kind"),
            function_result_word_count_by_hir: self.w("ob_function_result_word_count"),
            expr_scalar_type_by_hir: self.w("ob_expr_scalar_type"),
            public_decl_index_by_hir: self.w("ob_public_decl_index"),
            struct_init_field_ordinal_by_row: self.w("ob_struct_init_field_ordinal"),
            lowering_counts: &self.counts,
        }
    }
}

/// The projection's persistent allocations and pipelines. Nothing it
/// computes survives a run: every run plans, substitutes, checks and
/// projects again.
pub struct RetainedProjection {
    device: std::sync::Arc<wgpu::Device>,
    queue: std::sync::Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    substitution: RetainedSubstitution,
    schema: schema_projection::SchemaProjection,
    requests: Option<SubstitutionRequests>,
    /// Rank tables for `rank_capacity` ranks.
    rank_capacity: u32,
    ranks: BTreeMap<&'static str, wgpu::Buffer>,
    /// Global row tables for `row_capacity` rows.
    row_capacity: u32,
    rows: BTreeMap<&'static str, wgpu::Buffer>,
    /// Layouts for `type_capacity` TermIds.
    type_capacity: u32,
    layout: Option<wgpu::Buffer>,
    /// Layout rounds recorded per check. The count doubles when the last
    /// round still completed a layout, and it is kept for later runs.
    layout_rounds: u32,
    /// Pattern payload rounds recorded per check, grown the same way.
    pattern_rounds: u32,
    batch_capacity: u32,
    batches: Option<wgpu::Buffer>,
    columns: Option<BatchColumns>,
    config: wgpu::Buffer,
    status: wgpu::Buffer,
    /// An empty publication (state 0) the kernels bind before substitution.
    no_results: wgpu::Buffer,
    no_counts: wgpu::Buffer,
    /// One config buffer per string-scan step (`scan_projected_string_word_counts`), kept
    /// between runs; each run rewrites the steps it records.
    /// The root certification result (`certify_retained_native_abi`), rewritten every run.
    cert: wgpu::Buffer,
    no_root_readiness: wgpu::Buffer,
    /// Mappable staging for readbacks, grown to the largest one.
    staging: std::sync::Mutex<Option<wgpu::Buffer>>,
    gate_fault: ProjectionGateFault,
}

/// Test hook: how the gate of a batch recorded before the check readback
/// (`publish_retained_lowering_batch.slang`) fails.
#[doc(hidden)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ProjectionGateFault {
    #[default]
    None,
    /// The gate fails as it does after a failed check.
    Fail,
    /// The batch exceeds the token capacity it was recorded with.
    Capacity,
}

/// Lowers the projected batches of [`RetainedProjection::run_with_batch_lowerer`].
pub(crate) trait BatchLowerer {
    /// A batch lowering that is submitted and not yet read back.
    type Recorded;
    type Object;
    /// Whether the last batch may be recorded before the check is read back.
    /// A discarded recording is dropped, so it must leave nothing that a
    /// second recording of the batch does not replace.
    fn early(&self) -> bool;
    /// Records and submits the lowering of one batch over the columns `hir`
    /// and `semantic`. `last` tells whether it is the last batch.
    fn record(
        &mut self,
        source_bytes: u32,
        tokens: u32,
        rows: u32,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
        last: bool,
    ) -> Result<Self::Recorded>;
    /// Drops a lowering recorded before the check readback that the check
    /// did not pass.
    fn discard(&mut self, recorded: Self::Recorded) {
        drop(recorded);
    }
    /// Reads a recorded lowering back. The columns are the ones it was
    /// recorded over, for a retry.
    fn finish(
        &mut self,
        recorded: Self::Recorded,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
    ) -> Result<Self::Object>;
}

/// A lowering closure that records and reads back in one call.
struct LowerNow<F>(F);

impl<T, F> BatchLowerer for LowerNow<F>
where
    F: for<'a> FnMut(u32, u32, u32, GpuSemanticHirInputs<'a>, GpuSemanticArtifactView<'a>, bool) -> Result<T>,
{
    type Recorded = T;
    type Object = T;

    fn early(&self) -> bool {
        false
    }

    fn record(
        &mut self,
        source_bytes: u32,
        tokens: u32,
        rows: u32,
        hir: GpuSemanticHirInputs<'_>,
        semantic: GpuSemanticArtifactView<'_>,
        last: bool,
    ) -> Result<T> {
        (self.0)(source_bytes, tokens, rows, hir, semantic, last)
    }

    fn finish(&mut self, recorded: T, _: GpuSemanticHirInputs<'_>, _: GpuSemanticArtifactView<'_>) -> Result<T> {
        Ok(recorded)
    }
}

/// A readback `RetainedProjection::submit_read_begin` submitted.
struct PendingRead {
    staging: wgpu::Buffer,
    sizes: Vec<u64>,
    bytes: u64,
    map: passes_core::PendingReadbackMap,
}

/// The source bytes a batch lowering is sized for: the lowering sizes its
/// string pool from them, so they cover the batch's decoded strings.
fn lowering_source_bytes(token_capacity: u32, shape: ColumnShape) -> u32 {
    let string_bytes = u32::try_from(shape.string_words.saturating_mul(4)).unwrap_or(u32::MAX);
    token_capacity.saturating_mul(16).max(string_bytes).max(4096)
}

fn grown(current: u32, need: u32) -> u32 {
    if need <= current {
        current
    } else {
        need.max(current.saturating_mul(2))
            .max(16)
            .next_power_of_two()
    }
}

struct Recorder<'a> {
    projection: &'a RetainedProjection,
    encoder: wgpu::CommandEncoder,
    dispatches: u32,
}

impl RetainedProjection {
    /// A projection on the process-global GPU.
    pub fn new(substitution: SubstitutionCapacity) -> Result<Self> {
        Self::new_with_device(crate::gpu::device::global(), substitution)
    }

    pub(crate) fn new_with_device(gpu: &crate::gpu::device::GpuDevice, substitution: SubstitutionCapacity) -> Result<Self> {
        let device = gpu.device.clone();
        let passes = KERNELS
            .iter()
            .map(|&key| make_pass_data_from_shader_key(&device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        Ok(Self {
            config: storage(&device, "pj_config", CFG_WORDS as u64 * 4, false),
            status: storage(&device, "pj_status", STATUS_WORDS as u64 * 4, false),
            no_results: storage(&device, "pj_no_results", 64, false),
            no_counts: storage(&device, "pj_no_counts", 256, false),
            cert: storage(&device, "nc_cert", 16, false),
            no_root_readiness: storage(&device, "pj_no_root_readiness", 16, false),
            staging: std::sync::Mutex::new(None),
            gate_fault: ProjectionGateFault::None,
            device,
            queue: gpu.queue.clone(),
            passes,
            substitution: RetainedSubstitution::new_with_device(gpu, substitution)?,
            schema: schema_projection::SchemaProjection::new_with_device(gpu, substitution)?,
            requests: None,
            rank_capacity: 0,
            ranks: BTreeMap::new(),
            row_capacity: 0,
            rows: BTreeMap::new(),
            type_capacity: 0,
            layout: None,
            layout_rounds: LAYOUT_ROUNDS,
            pattern_rounds: PATTERN_ROUNDS,
            batch_capacity: 0,
            batches: None,
            columns: None,
        })
    }

    /// The substitution engine (its capacity grows across runs).
    pub fn substitution(&self) -> &RetainedSubstitution {
        &self.substitution
    }

    /// Test hook: the schema rounds start with `rows` request and field rows.
    #[doc(hidden)]
    pub fn set_schema_rows_for_test(&mut self, rows: u32) {
        self.schema.set_rows(rows);
    }

    /// Test hook: fails the gate of every batch recorded before the check
    /// readback, so the projection discards it and lowers the batch again.
    #[doc(hidden)]
    pub fn set_gate_fault_for_test(&mut self, fault: ProjectionGateFault) {
        self.gate_fault = fault;
    }

    fn ensure_ranks(&mut self, capacity: u32, report: &mut ProjectionReport) {
        if self.rank_capacity >= capacity {
            return;
        }
        let n = grown(self.rank_capacity, capacity) as u64;
        let slots = (n * 2).next_power_of_two();
        let d = &self.device;
        self.ranks = [
            ("pj_info", storage(d, "pj_info", n * INFO_WORDS * 16, false)),
            (
                "pj_base",
                storage(d, "pj_base", (n + 1) * COLUMNS * 4, false),
            ),
            ("pj_errors", storage(d, "pj_errors", n * 16, false)),
            ("pj_identity", storage(d, "pj_identity", slots * 4, false)),
            ("pj_scan_sums", storage(d, "pj_scan_sums", u64::from(crate::gpu::operations::STEP_PROGRAM_MAX_GROUPS) * 4, false)),
            ("pj_scan_total", storage(d, "pj_scan_total", COLUMNS as u64 * 4, false)),
        ]
        .into_iter()
        .collect();
        self.rank_capacity = n as u32;
        report.allocations += 1;
        report.allocated_bytes += self.ranks.values().map(wgpu::Buffer::size).sum::<u64>();
    }

    fn ensure_rows(&mut self, rows: u32, report: &mut ProjectionReport) {
        if self.row_capacity >= rows.max(1) {
            return;
        }
        let n = grown(self.row_capacity, rows.max(1)) as u64;
        let d = &self.device;
        self.rows = [
            ("pj_row_errors", storage(d, "pj_row_errors", n * 8, false)),
            ("pj_g_facts", storage(d, "pj_g_facts", n * 16, false)),
            ("pj_g_aux", storage(d, "pj_g_aux", n * 16, false)),
            (
                "pj_string_offsets",
                storage(d, "pj_string_offsets", (n + 1) * 4, false),
            ),
            (
                "pj_string_scratch",
                storage(d, "pj_string_scratch", (n + 1) * 4, false),
            ),
        ]
        .into_iter()
        .collect();
        self.row_capacity = n as u32;
        report.allocations += 1;
        report.allocated_bytes += self.rows.values().map(wgpu::Buffer::size).sum::<u64>();
    }

    fn ensure_types(&mut self, terms: u32, report: &mut ProjectionReport) -> bool {
        if self.type_capacity >= terms && self.layout.is_some() {
            return false;
        }
        let n = grown(self.type_capacity, terms);
        self.layout = Some(storage(&self.device, "pj_layout", n as u64 * 16, false));
        self.type_capacity = n;
        report.allocations += 1;
        report.allocated_bytes += n as u64 * 16;
        true
    }

    fn ensure_batches(&mut self, batches: u32, report: &mut ProjectionReport) {
        if self.batch_capacity >= batches.max(1) {
            return;
        }
        let n = grown(self.batch_capacity, batches.max(1));
        self.batches = Some(storage(
            &self.device,
            "pj_batches",
            n as u64 * BATCH_WORDS as u64 * 4,
            false,
        ));
        self.batch_capacity = n;
        report.allocations += 1;
        report.allocated_bytes += n as u64 * BATCH_WORDS as u64 * 4;
    }

    fn ensure_columns(&mut self, shape: ColumnShape, report: &mut ProjectionReport) {
        if let Some(columns) = &self.columns
            && columns.shape.rows >= shape.rows
            && columns.shape.side >= shape.side
            && columns.shape.types == shape.types
            && columns.shape.type_args >= shape.type_args
            && columns.shape.string_words >= shape.string_words
        {
            return;
        }
        let previous = self.columns.as_ref().map(|c| c.shape);
        let shape = ColumnShape {
            rows: grown(previous.map_or(0, |p| p.rows as u32), shape.rows as u32) as u64,
            side: grown(previous.map_or(0, |p| p.side as u32), shape.side as u32) as u64,
            types: shape.types,
            type_args: grown(previous.map_or(0, |p| p.type_args as u32), shape.type_args as u32) as u64,
            string_words: grown(
                previous.map_or(0, |p| p.string_words as u32),
                shape.string_words as u32,
            ) as u64,
        };
        let previous = self.columns.take();
        let columns = BatchColumns::new(&self.device, shape, previous);
        report.allocations += 1;
        report.allocated_bytes += columns.bytes;
        self.columns = Some(columns);
    }

    fn read(
        &self,
        buffer: &wgpu::Buffer,
        words: usize,
        report: &mut ProjectionReport,
    ) -> Result<Vec<u32>> {
        let encoder = self.device.create_command_encoder(&Default::default());
        Ok(self.submit_read(encoder, &[(buffer, words)], report)?.pop().unwrap_or_default())
    }

    /// Submits `encoder` with copies of the leading words of each buffer (at
    /// most its size) appended, and maps them: one readback for all parts.
    fn submit_read(
        &self,
        encoder: wgpu::CommandEncoder,
        parts: &[(&wgpu::Buffer, usize)],
        report: &mut ProjectionReport,
    ) -> Result<Vec<Vec<u32>>> {
        let pending = self.submit_read_begin(encoder, parts, report);
        self.finish_read(pending)
    }

    /// `submit_read` up to the submission; `finish_read` waits for the map.
    fn submit_read_begin(
        &self,
        mut encoder: wgpu::CommandEncoder,
        parts: &[(&wgpu::Buffer, usize)],
        report: &mut ProjectionReport,
    ) -> PendingRead {
        let sizes: Vec<u64> = parts
            .iter()
            .map(|(buffer, words)| (*words as u64 * 4).min(buffer.size()))
            .collect();
        let bytes: u64 = sizes.iter().sum::<u64>().max(4);
        report.readbacks += 1;
        report.readback_bytes += bytes;
        let mut staging = self.staging.lock().unwrap();
        if staging.as_ref().is_none_or(|b| b.size() < bytes) {
            *staging = Some(self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("retained_projection.readback"),
                size: bytes.next_power_of_two().max(256),
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            }));
        }
        let staging = staging.as_ref().unwrap().clone();
        let mut at = 0;
        for ((buffer, _), size) in parts.iter().zip(&sizes) {
            if *size != 0 {
                encoder.copy_buffer_counted(buffer, 0, &staging, at, *size);
            }
            at += size;
        }
        self.queue.submit(Some(encoder.finish()));
        let map = passes_core::begin_readback_map(&staging.slice(..bytes), crate::readback_label!("retained_projection.readback"));
        PendingRead { staging, sizes, bytes, map }
    }

    fn finish_read(&self, pending: PendingRead) -> Result<Vec<Vec<u32>>> {
        let PendingRead { staging, sizes, bytes, map } = pending;
        passes_core::finish_readback_map_blocking(&self.device, map)?;
        let slice = staging.slice(..bytes);
        let mut out = Vec::with_capacity(sizes.len());
        {
            let mapped = slice.get_mapped_range();
            let mut at = 0usize;
            for size in sizes {
                let end = at + size as usize;
                out.push(
                    mapped[at..end]
                        .chunks_exact(4)
                        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
                        .collect(),
                );
                at = end;
            }
        }
        staging.unmap();
        Ok(out)
    }

    fn bound_buffer<'a>(
        &'a self,
        store: &'a Store,
        inputs: &'a ProjectionInputs,
        extra: &[(&str, &'a wgpu::Buffer)],
        n: &str,
    ) -> Option<&'a wgpu::Buffer> {
        match n {
            "pj_config" => Some(&self.config),
            "pj_status" => Some(&self.status),
            "pj_layout" => self.layout.as_ref(),
            "pj_batches" => self.batches.as_ref(),
            _ => None,
        }
        .or_else(|| self.ranks.get(n))
        .or_else(|| self.rows.get(n))
        .or_else(|| self.schema.binding(n))
        .or_else(|| {
            inputs
                .buffers()
                .into_iter()
                .find(|(k, _)| *k == n)
                .map(|(_, b)| b)
        })
        .or_else(|| extra.iter().find(|(k, _)| *k == n).map(|(_, b)| *b))
        .or_else(|| self.columns.as_ref().and_then(|c| c.binding(n)))
        .or_else(|| store.buffers.get(n))
    }

    /// Records the root-call certification (certify_retained_native_abi) against this run's
    /// checked instances into `r`. Its result is `self.cert`; see
    /// [`cert_error`].
    fn record_certify(
        &self,
        r: &mut Recorder<'_>,
        guard: &Store,
        inputs: &ProjectionInputs,
        roots: &RootCertification<'_>,
        results: &wgpu::Buffer,
        counts: &wgpu::Buffer,
    ) -> Result<()> {
        self.reset_certification();
        let mut extra = vec![("sb_results", results), ("sb_counts", counts)];
        extra.extend(self.certification_bindings(Some(roots)));
        r.program(K_CERTIFY, guard, inputs, &extra, roots.calls.rows())
    }

    fn reset_certification(&self) {
        self.queue
            .write_buffer_counted(&self.cert, 0, &words_bytes(&[0, u32::MAX, 0, 0]));
    }

    fn certification_bindings<'a>(
        &'a self,
        roots: Option<&'a RootCertification<'_>>,
    ) -> [(&'static str, &'a wgpu::Buffer); 5] {
        [
            ("nc_use_abi", roots.map_or(&self.no_results, |root| &root.calls.abi)),
            ("nc_use_args", roots.map_or(&self.no_results, |root| &root.calls.args)),
            ("rr_routes", roots.map_or(&self.no_results, |root| root.routes)),
            ("rr_readiness", roots.map_or(&self.no_root_readiness, |root| root.readiness)),
            ("nc_cert", &self.cert),
        ]
    }

    fn recorder(&self) -> Recorder<'_> {
        Recorder {
            projection: self,
            encoder: self
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("retained_projection"),
                }),
            dispatches: 0,
        }
    }

    fn write_config(&self, run: u32, options: &ProjectionOptions, batch: u32) {
        let mut words = [0u32; CFG_WORDS];
        words[CFG_RUN] = run;
        words[CFG_BATCH_ROWS] = options.batch_rows.max(1);
        words[CFG_BATCH] = batch;
        words[CFG_IDENTITY_MASK] = options.identity_mask;
        words[CFG_LAYOUT_ROUNDS] = self.layout_rounds;
        words[CFG_PATTERN_ROUNDS] = self.pattern_rounds;
        self.queue
            .write_buffer_counted(&self.config, 0, &words_bytes(&words));
    }

    /// `write_config` for batch 0 recorded before the check readback: the
    /// gate (`GATE_*`) and the row, token and side capacities it checks.
    fn write_gated_config(&self, run: u32, options: &ProjectionOptions, caps: [u32; 3], gate: u32) {
        let mut words = [0u32; CFG_WORDS];
        words[CFG_RUN] = run;
        words[CFG_BATCH_ROWS] = options.batch_rows.max(1);
        words[CFG_IDENTITY_MASK] = options.identity_mask;
        words[CFG_LAYOUT_ROUNDS] = self.layout_rounds;
        words[CFG_PATTERN_ROUNDS] = self.pattern_rounds;
        words[CFG_ROW_CAP] = caps[0];
        words[CFG_TOKEN_CAP] = caps[1];
        words[CFG_SIDE_CAP] = caps[2];
        words[CFG_GATE] = gate;
        self.queue
            .write_buffer_counted(&self.config, 0, &words_bytes(&words));
    }

    /// Projects and lowers the producer's instances against `store`.
    pub fn run(
        &mut self,
        compiler: &GpuCompiler<'_>,
        store: &ProgramRetention,
        inputs: &ProjectionInputs,
        options: &ProjectionOptions,
    ) -> Result<ProjectionOutcome> {
        self.run_certified(compiler, store, inputs, options, None)
    }

    /// [`Self::run`], and with `roots` certifies the original objects' root
    /// calls after the instance check and before any lowering.
    pub fn run_certified(
        &mut self,
        compiler: &GpuCompiler<'_>,
        store: &ProgramRetention,
        inputs: &ProjectionInputs,
        options: &ProjectionOptions,
        roots: Option<RootCertification<'_>>,
    ) -> Result<ProjectionOutcome> {
        self.run_certified_with_storage(compiler, store, inputs, options, roots, Ok)
    }

    /// Stores each lowered batch before lowering the next one. File-backed
    /// builds release its section vectors here instead of accumulating them.
    pub(crate) fn run_certified_with_storage<T>(
        &mut self,
        compiler: &GpuCompiler<'_>,
        store: &ProgramRetention,
        inputs: &ProjectionInputs,
        options: &ProjectionOptions,
        roots: Option<RootCertification<'_>>,
        mut store_object: impl FnMut(GpuX86RelocatableObject) -> Result<T>,
    ) -> Result<ProjectionOutcome<T>> {
        self.run_with_lowerer(store,inputs,options,roots,|bytes,tokens,rows,hir,semantic,_last| {
            store_object(compiler.lower_projected_x86_batch(bytes,tokens,rows,hir,semantic,NATIVE_LIBRARY,NATIVE_NS_INSTANCE)?)
        })
    }

    /// Shared GPU projection; only the final lowering and object storage
    /// depend on the target. All discovery, layout and semantic checks agree.
    /// `lower` learns whether its batch is the last.
    pub(crate) fn run_with_lowerer<T>(
        &mut self, store:&ProgramRetention, inputs:&ProjectionInputs,
        options:&ProjectionOptions, roots:Option<RootCertification<'_>>,
        lower:impl for<'a> FnMut(u32,u32,u32,GpuSemanticHirInputs<'a>,GpuSemanticArtifactView<'a>,bool)->Result<T>,
    ) -> Result<ProjectionOutcome<T>> {
        self.run_with_batch_lowerer(store, inputs, options, roots, &mut LowerNow(lower))
    }

    /// [`Self::run_with_lowerer`] with a lowerer that may record the last
    /// batch before the check is read back ([`BatchLowerer::early`]).
    pub(crate) fn run_with_batch_lowerer<L: BatchLowerer>(
        &mut self, store:&ProgramRetention, inputs:&ProjectionInputs,
        options:&ProjectionOptions, roots:Option<RootCertification<'_>>,
        lowerer:&mut L,
    ) -> Result<ProjectionOutcome<L::Object>> {
        let mut report = ProjectionReport::default();
        let started = std::time::Instant::now();

        // Plan and scan.
        self.ensure_ranks(inputs.instance_capacity, &mut report);
        // Every kernel binds every projection table; the plan sizes the row
        // and batch tables later.
        self.ensure_rows(1, &mut report);
        self.ensure_batches(1, &mut report);
        let terms = store.store.lock().unwrap().capacity.arenas[A_TERMS];
        self.ensure_types(terms, &mut report);
        self.write_config(0, options, 0);
        let mut status = vec![0u32; STATUS_WORDS];
        status[S_ERROR_RANK] = u32::MAX;
        status[S_ERROR_ROW] = u32::MAX;
        self.queue
            .write_buffer_counted(&self.status, 0, &words_bytes(&status));
        let totals = {
            let guard = store.store.lock().unwrap();
            let mut r = self.recorder();
            r.encoder().clear_buffer_counted(&self.ranks["pj_identity"], 0, None);
            let none = [
                ("sb_results", &self.no_results),
                ("sb_counts", &self.no_counts),
            ];
            r.program(K_PLAN, &guard, inputs, &none, inputs.instance_capacity)?;
            report.dispatches += r.finish();
            drop(guard);
            self.read(&self.status, STATUS_WORDS, &mut report)?
        };
        if totals[S_PROGRAM_FAILED] != 0 {
            bail!("retention program {} failed to synchronize", KERNELS[K_PLAN]);
        }
        report.instances = totals[4];
        report.rows = totals[S_TOTALS + C_ROWS];
        report.tokens = totals[S_TOTALS + C_TOKENS];
        report.requests = totals[S_TOTALS + C_REQUESTS];
        report.plan_us = started.elapsed().as_micros() as u64;
        trace(&format!("plan: {totals:?}"));
        if totals[S_INPUT_ERROR] != 0 {
            return Ok(ProjectionOutcome::Rejected {
                error: ProjectionError {
                    code: totals[S_INPUT_ERROR],
                    detail: totals[S_INPUT_DETAIL],
                    rank: u32::MAX,
                    decl: u32::MAX,
                    row: u32::MAX,
                    token: u32::MAX,
                    file: u32::MAX,
                    byte: u32::MAX,
                    job: u32::MAX,
                    len: 0,
                },
                report,
            });
        }
        if report.instances == 0 {
            if let Some(roots) = &roots {
                let guard = store.store.lock().unwrap();
                let mut r = self.recorder();
                self.record_certify(
                    &mut r,
                    &guard,
                    inputs,
                    roots,
                    &self.no_results,
                    &self.no_counts,
                )?;
                let (dispatches, mut read) = r.finish_read(&[(&self.cert, 4)], &mut report)?;
                report.dispatches += dispatches;
                let cert = read.pop().unwrap_or_default();
                check_certification_sync(&cert)?;
                if let Some(error) = cert_error(&cert) {
                    return Ok(ProjectionOutcome::Rejected { error, report });
                }
            }
            return Ok(ProjectionOutcome::Objects {
                objects: Vec::new(),
                report,
            });
        }

        // Substitution requests, the substitution, the schema rounds and the
        // check, with one readback. The substitution is a chain of one run;
        // the schema rounds gate themselves on the GPU (schema.rs). The
        // check binds the run's buffers before the run is known to have
        // published, so the readback also carries the run's status words
        // and the schema's: a run that did not publish is substituted again
        // on the full path, stopped schema rounds are resumed, and the check
        // is recorded again.
        let started = std::time::Instant::now();
        if self
            .requests
            .as_ref()
            .is_none_or(|r| r.capacity() < report.requests.max(1))
        {
            let capacity = grown(
                self.requests.as_ref().map_or(0, |r| r.capacity()),
                report.requests.max(1),
            );
            self.requests = Some(SubstitutionRequests::new_with_device(&self.device, capacity));
            report.allocations += 1;
            report.allocated_bytes += capacity as u64 * 16;
        }
        let requests = self.requests.clone().unwrap();
        let mut run = self.substitution.begin_chain(&requests, 1)?[0];
        let generation = store.generation();
        self.schema.begin();
        let chained_dispatches;
        {
            let guard = store.store.lock().unwrap();
            let mut bindings = self.substitution.chain_bindings()?;
            bindings.extend(requests.buffers());
            let mut r = self.recorder();
            self.substitution.record_chain_prelude(r.encoder(), 0)?;
            r.program(K_REQUESTS, &guard, inputs, &bindings, report.requests.max(1))?;
            chained_dispatches = 1;
            report.dispatches += r.finish();
        }
        // Realize nominal schema fields using their own exact binders. New
        // field types form the next frontier; no body is rechecked.
        self.schema.record_chain(store, true)?;
        report.substitution_us = started.elapsed().as_micros() as u64;

        // Layout, edges, check and the batch plan.
        let started = std::time::Instant::now();
        let batches = report.rows.div_ceil(options.batch_rows.max(1));
        // A type's layout completes one round after its element and field
        // layouts. The last round runs after its status word is cleared, so
        // the word reports whether that round still completed a layout. If
        // it did, the fixed point is not proven: the check reruns from the
        // plan's status with twice the rounds.
        let mut chain = true;
        // With one batch, the batch and its lowering are recorded behind the
        // check, before its readback, so the GPU lowers while the host waits
        // for the check. They are sized from the plan's totals, which bound
        // every batch, and from the string column's capacity;
        // publish_retained_lowering_batch gates them on the check and those sizes.
        let early = lowerer.early()
            && batches == 1
            && std::env::var_os("LANIUS_PROJECTION_TRACE").is_none();
        let early_rows = report.rows.saturating_add(1);
        let early_tokens = report.tokens.saturating_add(1);
        let early_side = (0..SIDE_TABLES)
            .map(|k| totals[S_TOTALS + C_SIDE + k])
            .max()
            .unwrap_or(0)
            .max(1);
        let mut recorded_early = None;
        let (table, cert, status) = loop {
            // A check that runs again discards the lowering recorded behind
            // the previous one.
            if let Some(recorded) = recorded_early.take() {
                report.early_discarded += 1;
                lowerer.discard(recorded);
            }
            let guard = store.store.lock().unwrap();
            // A substitution on the full path may have grown the term arena.
            let terms = guard.capacity.arenas[A_TERMS];
            self.ensure_types(terms, &mut report);
            self.ensure_rows(report.rows, &mut report);
            self.ensure_batches(batches, &mut report);
            // The type tables are lowering inputs; the columns hold them.
            let current = self.columns.as_ref().map(|c| c.shape);
            let (rows, side) = if early {
                (u64::from(early_rows), u64::from(early_side.max(early_rows)))
            } else {
                (0, 0)
            };
            self.ensure_columns(
                ColumnShape {
                    rows: current.map_or(64, |c| c.rows).max(rows),
                    side: current.map_or(64, |c| c.side).max(side),
                    types: self.type_capacity as u64,
                    type_args: guard.capacity.arenas[A_TERM_ARGS] as u64,
                    string_words: current.map_or(1, |c| c.string_words),
                },
                &mut report,
            );
            if early {
                let mode = match self.gate_fault {
                    ProjectionGateFault::Fail => GATE_FORCE_FAIL,
                    _ => GATE_ON,
                };
                let tokens = match self.gate_fault {
                    ProjectionGateFault::Capacity => 1,
                    _ => early_tokens,
                };
                let shape = self.columns.as_ref().unwrap().shape;
                self.write_gated_config(run, options, [shape.rows as u32, tokens, shape.side as u32], mode);
            } else {
                self.write_config(run, options, 0);
            }
            let (results, counts) = self
                .substitution
                .chain_buffers()
                .map(|(r, c)| (r.clone(), c.clone()))
                .ok_or_else(|| anyhow!("the projection's substitution buffers are not allocated"))?;
            let extra = [("sb_results", &results), ("sb_counts", &counts)];
            let mut r = self.recorder();
            trace("check: recording");
            let payloads = totals[S_TOTALS + 5];
            let rows = self.type_capacity.max(report.rows).max(payloads);
            r.program(K_PREPARE_VALIDATION, &guard, inputs, &extra, rows)?;
            let mut bindings = extra.to_vec();
            bindings.extend(self.certification_bindings(roots.as_ref()));
            if roots.is_some() {
                self.reset_certification();
            }
            let cert_rows = roots.as_ref().map_or(0, |root| root.calls.rows());
            let rows = report.rows.max(batches).max(cert_rows);
            r.program_with_options(K_CALLS, &guard, inputs, &bindings, rows, u32::from(roots.is_some()))?;
            if early {
                // On settings, combining this with validation took 1.53 ms
                // across the two phases. Keep separate kernels in this submit.
                let shape = self.columns.as_ref().unwrap().shape;
                let rows = early_rows.max(early_side).max(shape.string_words as u32);
                r.materialize(&guard, inputs, &extra, rows)?;
            }
            let schema_status = self.schema.status_buffer().clone();
            let mut parts = vec![
                (&self.status, STATUS_WORDS),
                (&self.cert, if roots.is_some() { 4 } else { 0 }),
                (self.batches.as_ref().unwrap(), batches as usize * BATCH_WORDS),
            ];
            if chain {
                parts.extend([(&counts, sub_words::COUNT), (&schema_status, schema_projection::STATUS_WORDS)]);
            }
            let (dispatches, pending) = r.finish_read_begin(&parts, &mut report);
            let recorded = early.then(|| {
                let columns = self.columns.as_ref().unwrap();
                let shape = columns.shape;
                report.early_lowerings += 1;
                lowerer.record(
                    lowering_source_bytes(early_tokens, shape),
                    early_tokens,
                    shape.rows as u32,
                    columns.hir(),
                    columns.semantic(),
                    true,
                )
            });
            // The map finishes even when the recording failed, so the
            // staging buffer is free for the next readback.
            let mut read = self.finish_read(pending)?;
            recorded_early = recorded.transpose()?;
            drop(guard);
            report.dispatches += dispatches;
            if read[0][S_PROGRAM_FAILED] != 0 {
                bail!("retention program {PREPARE_VALIDATION} failed to synchronize");
            }
            if read[0][S_CALL_PROGRAM_FAILED] != 0 {
                bail!("retention program {} failed to synchronize", KERNELS[K_CALLS]);
            }
            check_certification_sync(&read[1])?;
            if chain {
                chain = false;
                let schema_words = read.pop().unwrap();
                let sb = read.pop().unwrap();
                let substitution = self
                    .substitution
                    .finish_chain_report(&sb, run, generation, chained_dispatches)?;
                let reran = substitution.is_none();
                let substitution = match substitution {
                    Some(substitution) => substitution,
                    None => match self.substitution.run(store, &requests)? {
                        SubstitutionRun::Published(substitution) => substitution,
                        SubstitutionRun::RequestCapacity {
                            requested,
                            capacity,
                        } => bail!(
                            "projection wrote {requested} substitution requests into {capacity} rows"
                        ),
                    },
                };
                run = substitution.publication.run;
                trace(&format!(
                    "substitution: run {run}, statuses {:?}",
                    substitution.status_counts()
                ));
                report.substitution = Some(substitution);
                // Terms the full path interned need schema rounds of their own.
                let (schema, resumed) = self.schema.settle(store, &schema_words, reran)?;
                report.schema = schema;
                if reran || resumed {
                    self.queue
                        .write_buffer_counted(&self.status, 0, &words_bytes(&totals));
                    continue;
                }
            }
            let table = read.pop().unwrap();
            let cert = read.pop().unwrap();
            let status = read.pop().unwrap();
            trace(&format!("check: {status:?}"));
            if status[S_LAYOUT_CHANGED] == 0 && status[S_PATTERN_CHANGED] == 0 {
                break (table, cert, status);
            }
            // Every unfinished round completes a layout (resolves a payload),
            // so the rounds a fixed point needs do not exceed the layout rows
            // (the payloads).
            if status[S_LAYOUT_CHANGED] != 0 {
                if self.layout_rounds > self.type_capacity {
                    bail!(
                        "retained projection layout did not settle in {} rounds",
                        self.layout_rounds
                    );
                }
                self.layout_rounds = self.layout_rounds.saturating_mul(2);
            }
            if status[S_PATTERN_CHANGED] != 0 {
                let payloads = totals[S_TOTALS + 5];
                if self.pattern_rounds > payloads {
                    bail!(
                        "retained projection pattern payloads did not settle in {} rounds",
                        self.pattern_rounds
                    );
                }
                self.pattern_rounds = self.pattern_rounds.saturating_mul(2);
            }
            self.queue
                .write_buffer_counted(&self.status, 0, &words_bytes(&totals));
        };
        let guard = store.store.lock().unwrap();
        let (results, counts) = self
            .substitution
            .chain_buffers()
            .map(|(r, c)| (r.clone(), c.clone()))
            .ok_or_else(|| anyhow!("the projection's substitution buffers are not allocated"))?;
        let extra = [("sb_results", &results), ("sb_counts", &counts)];
        report.check_us = started.elapsed().as_micros() as u64;
        if status[S_STATE] != STATE_CHECKED {
            let f = &status[S_FIRST..S_FIRST + 8];
            let error = ProjectionError {
                code: f[0],
                detail: f[1],
                rank: f[2],
                decl: f[3],
                row: f[4],
                token: f[5],
                file: f[6],
                byte: f[7],
                job: status[45],
                len: status[46],
            };
            if status[S_IDENTITY_OVERFLOW] != 0 && status[S_ERRORS] == 0 {
                bail!("retained projection identity table overflowed");
            }
            return Ok(ProjectionOutcome::Rejected { error, report });
        }
        if roots.is_some()
            && let Some(error) = cert_error(&cert)
        {
            return Ok(ProjectionOutcome::Rejected { error, report });
        }
        if status[S_BATCHES] != batches {
            bail!(
                "retained projection planned {} batches, expected {batches}",
                status[S_BATCHES]
            );
        }
        let all: Vec<ProjectionBatch> = table
            .chunks_exact(BATCH_WORDS)
            .map(|w| ProjectionBatch {
                lo: w[0],
                hi: w[1],
                rows: w[2],
                tokens: w[3],
                side: [w[4], w[5], w[6], w[7], w[8], w[9], w[10]],
                string_words: w[11],
            })
            .collect();
        report.batches = all.iter().copied().filter(|b| b.lo < b.hi).collect();
        if report.batches.len() as u32 != status[S_BATCH_NONEMPTY] {
            bail!("retained projection batch table disagrees with its status");
        }

        // The lowering recorded before the readback stands when the gate
        // passed the one batch at the capacities it was recorded with.
        if let Some(recorded) = recorded_early.take() {
            let exact_tokens = status[S_BATCH_TOKENS].max(1);
            if status[S_GATE] == VERDICT_PASSED
                && status[S_BATCHES] == 1
                && report.batches.len() == 1
                && exact_tokens <= early_tokens
            {
                let started = std::time::Instant::now();
                trace(&format!("lowering batch 0 early: {:?}", report.batches[0]));
                let columns = self.columns.as_ref().unwrap();
                let object = lowerer.finish(recorded, columns.hir(), columns.semantic())?;
                drop(guard);
                report.lowering_us = started.elapsed().as_micros() as u64;
                return Ok(ProjectionOutcome::Objects { objects: vec![object], report });
            }
            trace(&format!("early lowering discarded: gate {}", status[S_GATE]));
            report.early_discarded += 1;
            lowerer.discard(recorded);
        }

        // Batch columns and lowering.
        let started = std::time::Instant::now();
        let shape = ColumnShape {
            rows: status[S_BATCH_ROWS].max(1) as u64,
            side: (status[S_BATCH_SIDE].max(status[S_BATCH_ROWS])).max(1) as u64,
            types: self.type_capacity as u64,
            type_args: guard.capacity.arenas[A_TERM_ARGS] as u64,
            string_words: status[S_BATCH_STRING_WORDS].max(1) as u64,
        };
        let token_capacity = status[S_BATCH_TOKENS].max(1);
        self.ensure_columns(shape, &mut report);
        let shape = self.columns.as_ref().unwrap().shape;
        let mut objects = Vec::with_capacity(report.batches.len());
        let last = all.iter().rposition(|batch| batch.lo < batch.hi);
        for (b, batch) in all.iter().enumerate() {
            if batch.lo >= batch.hi {
                continue;
            }
            self.write_config(run, options, b as u32);
            let side = batch.side.iter().copied().max().unwrap_or(0).max(1);
            let mut r = self.recorder();
            r.materialize(&guard, inputs, &extra, batch.rows.max(side).max(batch.string_words))?;
            report.dispatches += r.finish();
            trace(&format!("lowering batch {b}: {batch:?}"));
            let columns = self.columns.as_ref().unwrap();
            if std::env::var_os("LANIUS_PROJECTION_TRACE").is_some() {
                let rows = batch.rows as usize;
                for name in [
                    "ob_function_entrypoint",
                    "ob_public_decl_index",
                    "ob_enclosing_fn",
                    "ob_expr_ref_tag",
                    "ob_expr_ref_payload",
                    "ob_value_type",
                    "ob_expr_scalar_type",
                    "ob_count_rows",
                ] {
                    let buffer = columns.binding(name).unwrap();
                    let words = self.read(buffer, rows, &mut report)?;
                    trace(&format!("{name}: {words:?}"));
                }
                for name in [
                    "ob_ti_kind",
                    "ob_ti_native_words",
                    "ob_ti_arg_count",
                    "ob_ti_decl_token",
                    "ob_ext_library",
                    "ob_imported_layout_kind",
                    "ob_ti_len_kind",
                ] {
                    let words = self.read(columns.binding(name).unwrap(), 64, &mut report)?;
                    trace(&format!("{name}[32..64]: {:?}", &words[32..64]));
                }
                let payload = self.read(&columns.payload.buffer, rows * 4, &mut report)?;
                trace(&format!(
                    "payload: {:?}",
                    payload.chunks(4).collect::<Vec<_>>()
                ));
                let core = self.read(&columns.core.buffer, rows * 4, &mut report)?;
                trace(&format!("core: {:?}", core.chunks(4).collect::<Vec<_>>()));
                let calls = self.read(&columns.calls.buffer, rows * 22, &mut report)?;
                for (i, c) in calls.chunks(22).enumerate() {
                    if c.iter().any(|&w| w != 0) {
                        trace(&format!("call {i}: {c:?}"));
                    }
                }
            }
            let recorded = lowerer.record(
                lowering_source_bytes(token_capacity, shape), token_capacity,
                shape.rows as u32, columns.hir(), columns.semantic(), last == Some(b),
            )?;
            objects.push(lowerer.finish(recorded, columns.hir(), columns.semantic())?);
        }
        drop(guard);
        report.lowering_us = started.elapsed().as_micros() as u64;
        Ok(ProjectionOutcome::Objects { objects, report })
    }
}

impl Recorder<'_> {
    fn materialize(
        &mut self,
        store: &Store,
        inputs: &ProjectionInputs,
        extra: &[(&str, &wgpu::Buffer)],
        rows: u32,
    ) -> Result<()> {
        self.clear_argument_modes();
        self.program(K_MATERIALIZE, store, inputs, extra, rows)
    }

    fn clear_argument_modes(&mut self) {
        let argument_modes = self.projection.columns.as_ref().unwrap().w("ob_argument_mode");
        self.encoder().clear_buffer_counted(argument_modes, 0, None);
    }

    fn program(
        &mut self,
        kernel: usize,
        store: &Store,
        inputs: &ProjectionInputs,
        extra: &[(&str, &wgpu::Buffer)],
        rows: u32,
    ) -> Result<()> {
        let options = if kernel == K_REQUESTS {
            super::substitution::FIRST_BATCH_OPTIONS
        } else {
            0
        };
        self.program_with_options(kernel, store, inputs, extra, rows, options)
    }

    fn program_with_options(
        &mut self,
        kernel: usize,
        store: &Store,
        inputs: &ProjectionInputs,
        extra: &[(&str, &wgpu::Buffer)],
        rows: u32,
        options: u32,
    ) -> Result<()> {
        let projection = self.projection;
        let pass = &projection.passes[kernel];
        let key = KERNELS[kernel];
        let status = &projection.status;
        let (slot, failure) = match kernel {
            K_PLAN => (super::PROJECTION_PLAN_SYNC_SLOT, Some((status, S_PROGRAM_FAILED))),
            K_REQUESTS => {
                let status = extra.iter().find(|(name, _)| *name == "sb_counts")
                    .map(|(_, buffer)| *buffer)
                    .ok_or_else(|| anyhow!("{key} has no substitution status"))?;
                (
                    super::PROJECTION_SUBSTITUTION_SYNC_SLOT,
                    Some((status, super::substitution::words::SYNC_FAILED)),
                )
            }
            K_PREPARE_VALIDATION => (super::VALIDATION_SYNC_SLOT, Some((status, S_PROGRAM_FAILED))),
            K_CALLS => (super::PROJECTION_CALLS_SYNC_SLOT, Some((status, S_CALL_PROGRAM_FAILED))),
            K_CERTIFY => (super::PROJECTION_CERTIFY_SYNC_SLOT, Some((&projection.cert, 3))),
            // The body and side steps publish disjoint rows, except for the
            // atomic argument-mode override. The program has no global wait.
            K_MATERIALIZE => (super::MATERIALIZE_SYNC_SLOT, None),
            _ => bail!("unknown retention program {key}"),
        };
        let names = reflected_names(pass);
        let mut bindings = Vec::with_capacity(names.len());
        for name in &names {
            if matches!(name.as_str(), "step_program_sync" | "program_launch") {
                continue;
            }
            let buffer = projection.bound_buffer(store, inputs, extra, name)
                .ok_or_else(|| anyhow!("{key} binds unknown buffer {name}"))?;
            bindings.push((name.as_str(), buffer.as_entire_binding()));
        }
        let groups = step_program_group_counts()[step_program_group_variant(u64::from(rows))];
        let program = StepProgramOperation::new_reflected(
            &projection.device, key, pass, &bindings,
            &store.step_program_sync, slot, groups, options,
        )?;
        let encoder = self.encoder();
        program.record(encoder)?;
        passes_core::flush_deferred_compute(encoder);
        if let Some((status, word)) = failure {
            encoder.copy_buffer_counted(
                &store.step_program_sync,
                StepProgramOperation::failed_offset(slot),
                status,
                (word * 4) as u64,
                4,
            );
        }
        if kernel != K_REQUESTS {
            self.dispatches += 1;
        }
        Ok(())
    }

    fn encoder(&mut self) -> &mut wgpu::CommandEncoder {
        &mut self.encoder
    }

    fn finish(self) -> u32 {
        self.projection.queue.submit(Some(self.encoder.finish()));
        self.dispatches
    }

    /// `finish_read` up to the submission.
    fn finish_read_begin(
        mut self,
        parts: &[(&wgpu::Buffer, usize)],
        report: &mut ProjectionReport,
    ) -> (u32, PendingRead) {
        self.encoder();
        let read = self.projection.submit_read_begin(self.encoder, parts, report);
        (self.dispatches, read)
    }

    /// Submits the recording with a readback of `parts` (see
    /// [`RetainedProjection::submit_read`]); returns the dispatch count.
    fn finish_read(
        mut self,
        parts: &[(&wgpu::Buffer, usize)],
        report: &mut ProjectionReport,
    ) -> Result<(u32, Vec<Vec<u32>>)> {
        self.encoder();
        let read = self.projection.submit_read(self.encoder, parts, report)?;
        Ok((self.dispatches, read))
    }
}

/// The certification's error, or `None` when every recorded root call
/// matches its target.
fn check_certification_sync(words: &[u32]) -> Result<()> {
    if words.get(3).copied() == Some(1) {
        bail!("retention program {} failed to synchronize", KERNELS[K_CERTIFY]);
    }
    Ok(())
}

fn cert_error(cert: &[u32]) -> Option<ProjectionError> {
    trace(&format!("certify: {cert:?}"));
    if cert[0] == 0 && cert[2] == 0 {
        return None;
    }
    Some(ProjectionError {
        code: error::ROOT_ABI,
        detail: cert[2],
        rank: u32::MAX,
        decl: u32::MAX,
        row: cert[1],
        token: u32::MAX,
        file: u32::MAX,
        byte: u32::MAX,
        job: u32::MAX,
        len: 0,
    })
}

fn trace(message: &str) {
    if std::env::var_os("LANIUS_PROJECTION_TRACE").is_some() {
        eprintln!("retained projection: {message}");
    }
}

/// Test hook: runs the producer kernel `key` over `lanes` lanes with
/// `fx_config` (`config`), the projection inputs, the store, `requests`
/// and `extra` buffers bound by name. Returns `out_words` of `fx_out`.
#[doc(hidden)]
pub fn run_producer_kernel(
    store: &ProgramRetention,
    key: &str,
    inputs: &ProjectionInputs,
    requests: &SubstitutionRequests,
    config: &[u32],
    out: &wgpu::Buffer,
    lanes: u32,
    extra: &[(&str, &wgpu::Buffer)],
) -> Result<()> {
    let device = &store.device;
    let queue = &store.queue;
    let pass = make_pass_data_from_shader_key(device, key, "main", key)?;
    let guard = store.store.lock().unwrap();
    let config_buffer = storage(device, "fx_config", (config.len().max(4) * 4) as u64, false);
    let mut words = config.to_vec();
    words.resize(config.len().max(4), 0);
    queue.write_buffer_counted(&config_buffer, 0, &words_bytes(&words));
    let names = reflected_names(&pass);
    let [request_rows, request_count] = requests.buffers();
    let mut entries = Vec::new();
    for name in &names {
        let n = name.as_str();
        let buffer = match n {
            "fx_config" => &config_buffer,
            "fx_out" => out,
            _ => inputs
                .buffers()
                .into_iter()
                .chain([request_rows, request_count])
                .chain(extra.iter().copied())
                .find(|(k, _)| *k == n)
                .map(|(_, b)| b)
                .or_else(|| guard.buffers.get(n))
                .ok_or_else(|| anyhow!("{key} binds unknown buffer {n}"))?,
        };
        entries.push((n, buffer.as_entire_binding()));
    }
    let bind = passes_core::bind_group::create_bind_group_from_bindings(
        device,
        Some(&pass.shader_id),
        &pass,
        0,
        &entries,
    )?;
    let mut encoder = device.create_command_encoder(&Default::default());
    super::substitution::record_timed(
        &mut encoder,
        "retained_projection.producer",
        &[(&pass, &bind, super::substitution::Launch::Groups(lanes.div_ceil(64).max(1), 1, 1))],
    );
    queue.submit(Some(encoder.finish()));
    Ok(())
}

/// A zeroed storage buffer of `words` words (test producer output).
#[doc(hidden)]
pub fn test_buffer(words: usize) -> wgpu::Buffer {
    storage(
        &crate::gpu::device::global().device,
        "fx_out",
        (words.max(4) * 4) as u64,
        false,
    )
}

/// Test oracle: `words` words of `buffer`.
#[doc(hidden)]
pub fn read_test_buffer(buffer: &wgpu::Buffer, words: usize) -> Result<Vec<u32>> {
    let gpu = crate::gpu::device::global();
    let bytes = (words as u64 * 4).min(buffer.size());
    let readback = gpu.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("retained_projection.test_readback"),
        size: bytes.max(4),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = gpu.device.create_command_encoder(&Default::default());
    encoder.copy_buffer_counted(buffer, 0, &readback, 0, bytes);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, crate::debug_readback_label!("retained_projection.test_readback"))?;
    let out = slice
        .get_mapped_range()
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    readback.unmap();
    Ok(out)
}
