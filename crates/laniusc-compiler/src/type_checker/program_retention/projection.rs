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
mod schema;
pub use schema::SchemaReport;

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
    },
    words_bytes,
};
use crate::{
    codegen::{lowering::GpuSemanticHirInputs, x86::GpuX86RelocatableObject},
    compiler::GpuCompiler,
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
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

/// Native identity of instance objects and symbols (codegen/x86/finalize.rs).
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

/// Error codes (pj_layout.slang PJ_E_*).
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
    /// target (projection/10_certify.slang). Detail: the failure bits;
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

// pj_layout.slang.
const INSTANCE_WORDS: u64 = 2;
const INFO_WORDS: u64 = 6;
const COLUMNS: u64 = 10;
const C_ROWS: usize = 0;
const C_TOKENS: usize = 1;
const C_REQUESTS: usize = 9;
const CFG_WORDS: usize = 8;
const CFG_RUN: usize = 0;
const CFG_BATCH_ROWS: usize = 1;
const CFG_BATCH: usize = 2;
const CFG_IDENTITY_MASK: usize = 4;
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

const KERNELS: &[&str] = &[
    "type_checker/retention/projection/00_plan",
    "type_checker/retention/projection/01_scan",
    "type_checker/retention/projection/02_requests",
    "type_checker/retention/projection/03a_layout_init",
    "type_checker/retention/projection/03_layout",
    "type_checker/retention/projection/04a_rows_init",
    "type_checker/retention/projection/04b_edges",
    "type_checker/retention/projection/05_check",
    "type_checker/retention/projection/05b_report",
    "type_checker/retention/projection/06_batch_plan",
    "type_checker/retention/projection/07_rows",
    "type_checker/retention/projection/08_side",
    "type_checker/retention/projection/09_batch_finish",
    "type_checker/retention/projection/10_certify",
    "type_checker/retention/projection/10b_certify_finish",
    "type_checker/retention/projection/04c_string_scan",
    "type_checker/retention/projection/08b_string_bytes",
    "type_checker/retention/projection/04d_pattern_roots",
    "type_checker/retention/projection/04e_pattern_payloads",
    "type_checker/retention/projection/03b_type_arguments",
    "type_checker/retention/projection/05c_calls",
];
const K_PLAN: usize = 0;
const K_SCAN: usize = 1;
const K_REQUESTS: usize = 2;
const K_LAYOUT_INIT: usize = 3;
const K_LAYOUT: usize = 4;
const K_ROWS_INIT: usize = 5;
const K_EDGES: usize = 6;
const K_CHECK: usize = 7;
const K_REPORT: usize = 8;
const K_BATCH_PLAN: usize = 9;
const K_ROWS: usize = 10;
const K_SIDE: usize = 11;
const K_BATCH_FINISH: usize = 12;
const K_CERTIFY: usize = 13;
const K_CERTIFY_FINISH: usize = 14;
const K_STRING_SCAN: usize = 15;
const K_STRING_BYTES: usize = 16;
const K_PATTERN_ROOTS: usize = 17;
const K_PATTERN_PAYLOADS: usize = 18;
const K_TYPE_ARGUMENTS: usize = 19;
const K_CALLS: usize = 20;

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

/// Test kernel: the explicit-instance producer (shaders/tests/retention_projection_producer.slang).
#[doc(hidden)]
pub const PRODUCER_KERNEL: &str = "tests/retention_projection_producer";

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
    // Type tables by TermId (03_layout writes them).
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
    schema: schema::SchemaProjection,
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
    /// One config buffer per string-scan step (`04c_string_scan`), kept
    /// between runs; each run rewrites the steps it records.
    string_scan_configs: Vec<wgpu::Buffer>,
    /// The root certification result (`10_certify`), rewritten every run.
    cert: wgpu::Buffer,
    /// Mappable staging for readbacks, grown to the largest one.
    staging: std::sync::Mutex<Option<wgpu::Buffer>>,
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
    /// Bind groups created by this recording, by kernel and extra buffers.
    /// Repeated rounds of one kernel (layout, pattern payloads) bind the
    /// same buffers, so they share a bind group. A recording runs under the
    /// store lock and resizes no projection table, so the other bindings of
    /// a kernel cannot change within it.
    binds: Vec<(usize, Vec<(String, wgpu::Buffer)>, wgpu::BindGroup)>,
    /// Dispatches not yet recorded: kernel, bind group and workgroups.
    /// Consecutive dispatches share one timed compute pass; wgpu orders their
    /// storage accesses. `encoder()` records them before a copy or clear.
    pending: Vec<(usize, wgpu::BindGroup, u32)>,
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
            string_scan_configs: Vec::new(),
            cert: storage(&device, "nc_cert", 16, false),
            staging: std::sync::Mutex::new(None),
            device,
            queue: gpu.queue.clone(),
            passes,
            substitution: RetainedSubstitution::new_with_device(gpu, substitution)?,
            schema: schema::SchemaProjection::new_with_device(gpu, substitution)?,
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
        mut encoder: wgpu::CommandEncoder,
        parts: &[(&wgpu::Buffer, usize)],
        report: &mut ProjectionReport,
    ) -> Result<Vec<Vec<u32>>> {
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
        let readback = staging.as_ref().unwrap();
        let mut at = 0;
        for ((buffer, _), size) in parts.iter().zip(&sizes) {
            if *size != 0 {
                encoder.copy_buffer_counted(buffer, 0, readback, at, *size);
            }
            at += size;
        }
        self.queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..bytes);
        map_readback_blocking(&self.device, &slice, "retained_projection.readback")?;
        let mut out = Vec::with_capacity(parts.len());
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
        readback.unmap();
        Ok(out)
    }

    fn bind(
        &self,
        kernel: usize,
        store: &Store,
        inputs: &ProjectionInputs,
        extra: &[(&str, &wgpu::Buffer)],
    ) -> Result<wgpu::BindGroup> {
        let pass = &self.passes[kernel];
        let names = reflected_names(pass);
        let mut entries = Vec::with_capacity(names.len());
        for name in &names {
            let n = name.as_str();
            let buffer = match n {
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
            .ok_or_else(|| anyhow!("{} binds unknown buffer {n}", pass.shader_id))?;
            entries.push((n, buffer.as_entire_binding()));
        }
        passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass.shader_id),
            pass,
            0,
            &entries,
        )
    }

    /// Records the root-call certification (10_certify) against this run's
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
        let cert = &self.cert;
        self.queue
            .write_buffer_counted(cert, 0, &words_bytes(&[0, u32::MAX, 0, 0]));
        let extra = [
            ("sb_results", results),
            ("sb_counts", counts),
            ("nc_use_abi", &roots.calls.abi),
            ("nc_use_args", &roots.calls.args),
            ("rr_routes", roots.routes),
            ("rr_readiness", roots.readiness),
            ("nc_cert", cert),
        ];
        r.dispatch(K_CERTIFY, guard, inputs, &extra, roots.calls.rows())?;
        r.dispatch_groups(K_CERTIFY_FINISH, guard, inputs, &extra, 1)
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
            binds: Vec::new(),
            pending: Vec::new(),
        }
    }

    fn write_config(&self, run: u32, options: &ProjectionOptions, batch: u32) {
        let mut words = [0u32; CFG_WORDS];
        words[CFG_RUN] = run;
        words[CFG_BATCH_ROWS] = options.batch_rows.max(1);
        words[CFG_BATCH] = batch;
        words[CFG_IDENTITY_MASK] = options.identity_mask;
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
        self.run_with_lowerer(store,inputs,options,roots,|bytes,tokens,rows,hir,semantic| {
            store_object(compiler.lower_projected_x86_batch(bytes,tokens,rows,hir,semantic,NATIVE_LIBRARY,NATIVE_NS_INSTANCE)?)
        })
    }

    /// Shared GPU projection; only the final lowering and object storage
    /// depend on the target. All discovery, layout and semantic checks agree.
    pub(crate) fn run_with_lowerer<T>(
        &mut self, store:&ProgramRetention, inputs:&ProjectionInputs,
        options:&ProjectionOptions, roots:Option<RootCertification<'_>>,
        mut lower:impl for<'a> FnMut(u32,u32,u32,GpuSemanticHirInputs<'a>,GpuSemanticArtifactView<'a>)->Result<T>,
    ) -> Result<ProjectionOutcome<T>> {
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
            r.dispatch(K_PLAN, &guard, inputs, &none, inputs.instance_capacity)?;
            r.dispatch_groups(K_SCAN, &guard, inputs, &none, 1)?;
            report.dispatches += r.finish();
            drop(guard);
            self.read(&self.status, STATUS_WORDS, &mut report)?
        };
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
                let (dispatches, mut read) = r.finish_read(&[(&self.cert, 3)], &mut report)?;
                report.dispatches += dispatches;
                if let Some(error) = cert_error(&read.pop().unwrap_or_default()) {
                    return Ok(ProjectionOutcome::Rejected { error, report });
                }
            }
            return Ok(ProjectionOutcome::Objects {
                objects: Vec::new(),
                report,
            });
        }

        // Substitution requests and the engine.
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
        {
            let guard = store.store.lock().unwrap();
            let requests = self.requests.as_ref().unwrap();
            let [requests_buffer, count_buffer] = requests.buffers();
            let extra = [
                requests_buffer,
                count_buffer,
                ("sb_results", &self.no_results),
                ("sb_counts", &self.no_counts),
            ];
            let mut r = self.recorder();
            r.dispatch(K_REQUESTS, &guard, inputs, &extra, report.requests.max(1))?;
            report.dispatches += r.finish();
        }
        let requests = self.requests.as_ref().unwrap();
        let substitution = match self.substitution.run(store, requests)? {
            SubstitutionRun::Published(report) => report,
            SubstitutionRun::RequestCapacity {
                requested,
                capacity,
            } => {
                bail!("projection wrote {requested} substitution requests into {capacity} rows")
            }
        };
        let run = substitution.publication.run;
        trace(&format!(
            "substitution: run {run}, statuses {:?}",
            substitution.status_counts()
        ));
        report.substitution = Some(substitution);
        report.substitution_us = started.elapsed().as_micros() as u64;

        // Realize nominal schema fields using their own exact binders. New
        // field types form the next frontier; no body is rechecked.
        report.schema = self.schema.run(store)?;

        // Layout, edges, check and the batch plan.
        let started = std::time::Instant::now();
        // The publication check reads the store generation, so it runs
        // before the store lock is taken.
        let publication = self
            .substitution
            .publication(store)
            .ok_or_else(|| anyhow!("the projection's substitution publication is not current"))?;
        let results = publication.results.clone();
        let counts = publication.counts.clone();
        let guard = store.store.lock().unwrap();
        // The substitution may have grown the term arena.
        let terms = guard.capacity.arenas[A_TERMS];
        self.ensure_types(terms, &mut report);
        self.ensure_rows(report.rows, &mut report);
        let batches = report.rows.div_ceil(options.batch_rows.max(1));
        self.ensure_batches(batches, &mut report);
        // The type tables are lowering inputs; the columns hold them.
        let current = self.columns.as_ref().map(|c| c.shape);
        self.ensure_columns(
            ColumnShape {
                rows: current.map_or(64, |c| c.rows),
                side: current.map_or(64, |c| c.side),
                types: self.type_capacity as u64,
                type_args: guard.capacity.arenas[A_TERM_ARGS] as u64,
                string_words: current.map_or(1, |c| c.string_words),
            },
            &mut report,
        );
        self.write_config(run, options, 0);
        // The scan doubles its distance from 1 past rows / 2: at most 33
        // steps for u32 rows, plus the first.
        while self.string_scan_configs.len() < 34 {
            self.string_scan_configs
                .push(storage(&self.device, "pj_string_scan_config", 16, false));
        }
        let extra = [("sb_results", &results), ("sb_counts", &counts)];
        // A type's layout completes one round after its element and field
        // layouts. The last round runs after its status word is cleared, so
        // the word reports whether that round still completed a layout. If
        // it did, the fixed point is not proven: the check reruns from the
        // plan's status with twice the rounds.
        let (table, cert, status) = loop {
            let mut r = self.recorder();
            trace("check: recording");
            r.dispatch(K_LAYOUT_INIT, &guard, inputs, &extra, self.type_capacity)?;
            r.dispatch(K_TYPE_ARGUMENTS, &guard, inputs, &extra, self.type_capacity)?;
            for _ in 1..self.layout_rounds {
                r.dispatch(K_LAYOUT, &guard, inputs, &extra, self.type_capacity)?;
            }
            r.dispatch(K_ROWS_INIT, &guard, inputs, &extra, report.rows.max(1))?;
            r.dispatch(K_EDGES, &guard, inputs, &extra, report.rows.max(1))?;
            let arms = totals[S_TOTALS + 4];
            let payloads = totals[S_TOTALS + 5];
            if arms != 0 || payloads != 0 {
                r.dispatch(K_PATTERN_ROOTS, &guard, inputs, &extra, arms.max(payloads))?;
                if payloads != 0 {
                    // The last round runs after its status word is cleared, as
                    // the last layout round does.
                    for _ in 1..self.pattern_rounds {
                        r.dispatch(K_PATTERN_PAYLOADS, &guard, inputs, &extra, payloads)?;
                    }
                    r.encoder()
                        .clear_buffer_counted(&self.status, S_PATTERN_CHANGED as u64 * 4, Some(4));
                    r.dispatch(K_PATTERN_PAYLOADS, &guard, inputs, &extra, payloads)?;
                }
            }
            if totals[S_TOTALS + 7] != 0 {
                let mut input = 0u32;
                let mut distance = 0u32;
                for config in &self.string_scan_configs {
                    self.queue
                        .write_buffer_counted(config, 0, &words_bytes(&[distance, input, 0, 0]));
                    let scan_extra = [
                        ("sb_results", &results),
                        ("sb_counts", &counts),
                        ("pj_string_scan_config", config),
                    ];
                    r.dispatch(K_STRING_SCAN, &guard, inputs, &scan_extra, report.rows + 1)?;
                    if distance == 0 {
                        distance = 1;
                    } else {
                        input ^= 1;
                        if distance > report.rows / 2 {
                            break;
                        }
                        distance *= 2;
                    }
                }
                if input == 1 {
                    r.encoder().copy_buffer_counted(
                        &self.rows["pj_string_scratch"],
                        0,
                        &self.rows["pj_string_offsets"],
                        0,
                        (report.rows as u64 + 1) * 4,
                    );
                }
            } else {
                r.encoder()
                    .clear_buffer_counted(&self.rows["pj_string_offsets"], 0, None);
            }
            // The row, edge, pattern and string kernels above do not read
            // layouts, so the last layout round is recorded after them.
            r.encoder()
                .clear_buffer_counted(&self.status, S_LAYOUT_CHANGED as u64 * 4, Some(4));
            r.dispatch(K_LAYOUT, &guard, inputs, &extra, self.type_capacity)?;
            r.dispatch(K_CHECK, &guard, inputs, &extra, report.rows.max(1))?;
            r.dispatch(K_CALLS, &guard, inputs, &extra, report.rows.max(1))?;
            r.dispatch_groups(K_REPORT, &guard, inputs, &extra, 1)?;
            r.dispatch(K_BATCH_PLAN, &guard, inputs, &extra, batches.max(1))?;
            // The certification and the batch table are read with the status;
            // they are used only when the check passed.
            if let Some(roots) = &roots {
                self.record_certify(&mut r, &guard, inputs, roots, &results, &counts)?;
            }
            let (dispatches, mut read) = r.finish_read(
                &[
                    (&self.status, STATUS_WORDS),
                    (&self.cert, if roots.is_some() { 3 } else { 0 }),
                    (self.batches.as_ref().unwrap(), batches as usize * BATCH_WORDS),
                ],
                &mut report,
            )?;
            report.dispatches += dispatches;
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
        for (b, batch) in all.iter().enumerate() {
            if batch.lo >= batch.hi {
                continue;
            }
            self.write_config(run, options, b as u32);
            let side = batch.side.iter().copied().max().unwrap_or(0).max(1);
            let mut r = self.recorder();
            r.dispatch(K_ROWS, &guard, inputs, &extra, batch.rows)?;
            r.dispatch(K_SIDE, &guard, inputs, &extra, side)?;
            if batch.string_words != 0 {
                r.dispatch(K_STRING_BYTES, &guard, inputs, &extra, batch.string_words)?;
            }
            r.dispatch_groups(K_BATCH_FINISH, &guard, inputs, &extra, 1)?;
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
            // Lowering sizes its string pool from the source bytes, so they
            // cover the batch's decoded strings.
            let string_bytes = u32::try_from(shape.string_words.saturating_mul(4)).unwrap_or(u32::MAX);
            objects.push(lower(
                token_capacity.saturating_mul(16).max(string_bytes).max(4096), token_capacity,
                shape.rows as u32, columns.hir(), columns.semantic(),
            )?);
        }
        drop(guard);
        report.lowering_us = started.elapsed().as_micros() as u64;
        Ok(ProjectionOutcome::Objects { objects, report })
    }
}

impl Recorder<'_> {
    fn dispatch(
        &mut self,
        kernel: usize,
        store: &Store,
        inputs: &ProjectionInputs,
        extra: &[(&str, &wgpu::Buffer)],
        lanes: u32,
    ) -> Result<()> {
        let groups = lanes.div_ceil(256).max(1);
        self.dispatch_groups(kernel, store, inputs, extra, groups)
    }

    fn dispatch_groups(
        &mut self,
        kernel: usize,
        store: &Store,
        inputs: &ProjectionInputs,
        extra: &[(&str, &wgpu::Buffer)],
        groups: u32,
    ) -> Result<()> {
        let cached = self.binds.iter().find(|(k, e, _)| {
            *k == kernel
                && e.len() == extra.len()
                && e.iter().zip(extra).all(|((n, b), (m, c))| n == m && b == *c)
        });
        let bind = match cached {
            Some((_, _, bind)) => bind.clone(),
            None => {
                let bind = self.projection.bind(kernel, store, inputs, extra)?;
                let key = extra.iter().map(|(n, b)| (n.to_string(), (*b).clone())).collect();
                self.binds.push((kernel, key, bind.clone()));
                bind
            }
        };
        self.pending.push((kernel, bind, groups));
        self.dispatches += 1;
        Ok(())
    }

    /// The encoder, after recording the pending dispatches in one pass.
    fn encoder(&mut self) -> &mut wgpu::CommandEncoder {
        let passes = &self.projection.passes;
        let steps = self
            .pending
            .iter()
            .map(|&(kernel, ref bind, groups)| {
                let launch = super::substitution::Launch::Groups(groups.min(65535), groups.div_ceil(65535), 1);
                (&passes[kernel], bind, launch)
            })
            .collect::<Vec<_>>();
        super::substitution::record_timed(&mut self.encoder, "retained_projection", &steps);
        self.pending.clear();
        &mut self.encoder
    }

    fn finish(mut self) -> u32 {
        self.encoder();
        self.projection.queue.submit(Some(self.encoder.finish()));
        self.dispatches
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
    map_readback_blocking(&gpu.device, &slice, "retained_projection.test_readback")?;
    let out = slice
        .get_mapped_range()
        .chunks_exact(4)
        .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
        .collect();
    readback.unmap();
    Ok(out)
}
