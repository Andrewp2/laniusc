//! Build-scoped program retention store (docs/compiler-program-retention.md).
//!
//! One [`ProgramRetention`] lives for one build. At the end of each frontend
//! semantic job, before the job's workspace can be reused, the GPU exports
//! the job's declarations, parameters, symbolic and closed terms, binder
//! maps, signatures, nominal schemas, call uses and generic body segments
//! into the store's own arenas (`shaders/type_checker/retention`). Every
//! export is a transaction: a job that overflows any arena or table is
//! rolled back on the GPU, the host grows the store from the demand the GPU
//! recorded, and the export runs again over the same job tables.
//!
//! The host only allocates, transfers, submits and reads the compact status
//! words (`rt_counts`). All semantic work (identity interning, term
//! translation, ownership validation, relative encoding, commit) runs on the
//! GPU.

use crate::gpu::copies::{CountedCommands, CountedWrites};
use std::{
    collections::BTreeMap,
    num::NonZeroU64,
    sync::{Arc, Mutex},
};

use anyhow::{Result, anyhow, bail};

pub mod discovery;
mod method_routes;
mod native_calls;
pub use native_calls::NativeCallTables;
pub mod projection;
pub mod substitution;

use crate::gpu::{
    buffers::LaniusBuffer,
    compiler_graph::{CompilerGraph, CompilerGraphBuilder, ResourceClass},
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

/// Type-check graph tables the export reads. An interface job with a store
/// attached keeps them alive until the job's end (`retention_reader_graph`).
pub(crate) const RETAINED_PROGRAM_INPUTS: &[&str] = &[
    "ct_head",
    "ct_meta",
    "ct_extra",
    "ct_args",
    "ct_slot",
    "ct_counts",
    "canonical_row",
    "canonical_atom",
    "canonical_projection",
    "canonical_dependency_type",
    "call_env_ct",
    "semantic_calls_by_hir",
    "semantic_call_native_abi_by_hir",
    "semantic_function_native_abi_by_hir",
    "semantic_function_host_service_by_hir",
    "semantic_expr_ref_tag_by_hir",
    "semantic_expr_ref_payload_by_hir",
    "semantic_type_ref_tag_by_hir",
    "semantic_type_ref_payload_by_hir",
    "semantic_param_ref_tag_by_row",
    "semantic_param_ref_payload_by_row",
    "semantic_value_decl_by_hir",
    "semantic_value_const_by_hir",
    "semantic_value_const_present_by_hir",
    "semantic_argument_mode_by_hir",
    "semantic_iterable_kind_by_hir",
    "semantic_member_field_ordinal_by_hir",
    "decl_id_by_name_token",
    "interface_public_decl_index_by_local",
    "interface_public_decl_index_by_hir",
    "type_const_param_scalar_by_token",
    "struct_init_field_ordinal_by_row",
    "compact_string_data_words",
    "compact_method_count",
    "compact_method_cores",
    "compact_method_signatures",
    // Trait facts (export steps 14b-14d): the predicate and method
    // validators' accepted columns.
    "predicate_status",
    "predicate_owner_node",
    "predicate_bound_reference",
    "predicate_bound_arg_count",
    "predicate_bound_token",
    "predicate_method_contract_owner_count",
    "predicate_method_validation_status",
    "predicate_method_validation_required_symbol",
    "semantic_function_native_symbol_by_hir",
    "semantic_predicate_subject_parameter_token_by_hir",
    "decl_hir_node",
    "resolved_dependency_library_id",
    "resolved_dependency_unit_id",
    "resolved_dependency_local_index",
    "resolved_dependency_trait_header",
];

/// The consumer contract of the export: every retained input the producer
/// owns is promoted to live until the producer graph's end.
pub(crate) fn retention_reader_graph(producer: &CompilerGraph) -> Result<CompilerGraph> {
    let mut reader = CompilerGraphBuilder::new();
    for &name in RETAINED_PROGRAM_INPUTS {
        let Some(id) = producer.resource_id(name) else { continue };
        let resource = producer
            .resource(id)
            .ok_or_else(|| anyhow!("missing resource {name}"))?;
        reader
            .add_storage(name, resource.domain, ResourceClass::External, resource.bytes)
            .map_err(anyhow::Error::msg)?;
    }
    reader.build().map_err(anyhow::Error::msg)
}

// Arena indexes (retention_store.slang RT_A_*).
const A_DECLS: usize = 0;
const A_PARAMS: usize = 1;
const A_TERMS: usize = 2;
const A_TERM_ARGS: usize = 3;
const A_DIR: usize = 4;
const A_BINDERS: usize = 5;
const A_SIGS: usize = 6;
const A_SCHEMA: usize = 7;
const A_USES: usize = 8;
const A_SEGMENTS: usize = 9;
const A_SEG_ROWS: usize = 10;
const A_SEG_SIDE: usize = 11;
const A_SEG_BYTES: usize = 12;
const A_SEG_TOKENS: usize = 13;
const A_TRAITS: usize = 14;
const A_JOBS: usize = 15;
const ARENAS: usize = 16;

/// rt_counts words (retention_store.slang RT_C_*).
pub mod counts {
    pub const JOB_BASE: usize = 16;
    pub const DEMAND: usize = 32;
    pub const SPARE: usize = 48;
    pub const OVERFLOW: usize = 64;
    pub const INVARIANTS: usize = 65;
    pub const FIRST_INVARIANT: usize = 66;
    pub const JOBS: usize = 67;
    pub const JOB_STATE: usize = 68;
    pub const ROLLBACKS: usize = 69;
    pub const CONFLICTS: usize = 72;
    pub const INVARIANT_TOTAL: usize = 74;
    pub const INCOMPLETE: usize = 75;
    pub const INCOMPLETE_TOTAL: usize = 76;
    pub const READY: usize = 77;
    /// Build generation (retention_store.slang RT_C_GENERATION).
    pub const GENERATION: usize = 78;
    /// The build's first fault (retention_store.slang RT_C_FAULT*): reason,
    /// job, file, byte and length of the faulting row's first token.
    pub const FAULT: usize = 89;
    pub const FAULT_JOB: usize = 90;
    pub const FAULT_FILE: usize = 91;
    pub const FAULT_BYTE: usize = 92;
    pub const FAULT_LEN: usize = 93;
    pub const FAULT_STAT: u32 = 16;
    pub const FAULT_LOCATED: u32 = 0x100;
    pub const WORDS: usize = 96;
    pub const JOB_COMMITTED: u32 = 2;
    pub const JOB_ROLLED_BACK: u32 = 3;
    pub const OVERFLOW_DECL_TABLE: u32 = 1 << 16;
    pub const OVERFLOW_PARAM_TABLE: u32 = 1 << 17;
    pub const OVERFLOW_TERM_TABLE: u32 = 1 << 18;
}

const RT_FIRST_TERM: u32 = 32;
const X_WORDS: usize = 256;
const DISPATCH_WORDS: u64 = 3 * 16;
const D_HIR: u64 = 0;
const D_PARAMS: u64 = 1;
const D_RECORDS: u64 = 2;
const D_ROUND: u64 = 3;
const D_SIDE: u64 = 4;
const D_SCHEMA: u64 = 5;
const D_COMMIT_DIR: u64 = 6;
const D_ROLLBACK: u64 = 7;
const HEIGHTS: usize = 80;

/// Bytes per record of each arena, in arena order.
const RECORD_BYTES: [u64; ARENAS] = [
    16 + 4,      // decl key + definition
    16,          // param key
    16 + 16 + 8, // term head, meta, owners
    4,           // term args
    64 + 16,     // directory entry, trait column
    4,           // binders
    4,           // signatures
    16,          // schema
    48,          // uses
    96,          // segments
    112,         // segment rows
    16,          // side records (2 per side row)
    4,           // string bytes and body text
    16,          // body tokens
    32,          // trait facts (predicates, impl method bindings)
    16,          // committed job identity (including jobs with no declarations)
];

/// Record capacities of the store's arenas and hash tables.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProgramRetentionCapacity {
    /// Records per arena, in `RT_A_*` order.
    pub arenas: [u32; ARENAS],
    /// Slots of the decl, param and term hash tables (powers of two).
    pub slots: [u32; 3],
}

impl Default for ProgramRetentionCapacity {
    fn default() -> Self {
        Self {
            arenas: [
                4096, 4096, 16384, 32768, 4096, 8192, 16384, 8192, 16384, 2048, 65536, 32768,
                65536, 65536, 4096, 64,
            ],
            slots: [8192, 8192, 32768],
        }
    }
}

impl ProgramRetentionCapacity {
    /// Deliberately tiny capacities: a test of the overflow/retry protocol.
    pub fn tiny() -> Self {
        Self {
            arenas: [4, 4, 34, 4, 2, 2, 2, 2, 2, 1, 4, 4, 4, 4, 1, 1],
            slots: [8, 8, 8],
        }
    }

    fn table_bytes(&self) -> u64 {
        self.slots.iter().map(|&s| s as u64 * 4).sum()
    }

    /// Bytes the store's arenas and tables occupy.
    pub fn bytes(&self) -> u64 {
        self.arenas
            .iter()
            .zip(RECORD_BYTES)
            .map(|(&n, b)| n as u64 * b)
            .sum::<u64>()
            + self.table_bytes()
    }
}

/// A store buffer: name, bytes per record, arena or table it holds.
#[derive(Clone, Copy)]
enum Sized {
    Arena(usize, u64),
    Table(usize),
    Fixed(u64),
}

const STORE_BUFFERS: &[(&str, Sized)] = &[
    ("rt_counts", Sized::Fixed(counts::WORDS as u64 * 4)),
    ("rt_config", Sized::Fixed(16)),
    ("rt_decl_key", Sized::Arena(A_DECLS, 16)),
    ("rt_decl_def", Sized::Arena(A_DECLS, 4)),
    ("rt_decl_slot", Sized::Table(0)),
    ("rt_param_key", Sized::Arena(A_PARAMS, 16)),
    ("rt_param_slot", Sized::Table(1)),
    ("rt_term_head", Sized::Arena(A_TERMS, 16)),
    ("rt_term_meta", Sized::Arena(A_TERMS, 16)),
    ("rt_term_owner", Sized::Arena(A_TERMS, 8)),
    ("rt_term_args", Sized::Arena(A_TERM_ARGS, 4)),
    ("rt_term_slot", Sized::Table(2)),
    ("rt_dir", Sized::Arena(A_DIR, 64)),
    ("rt_dir_trait", Sized::Arena(A_DIR, 16)),
    ("rt_binders", Sized::Arena(A_BINDERS, 4)),
    ("rt_sigs", Sized::Arena(A_SIGS, 4)),
    ("rt_schema", Sized::Arena(A_SCHEMA, 16)),
    ("rt_uses", Sized::Arena(A_USES, 48)),
    ("rt_use_spans", Sized::Arena(A_USES, 16)),
    ("rt_segments", Sized::Arena(A_SEGMENTS, 96)),
    ("rt_seg_rows", Sized::Arena(A_SEG_ROWS, 112)),
    ("rt_seg_side", Sized::Arena(A_SEG_SIDE, 16)),
    ("rt_seg_bytes", Sized::Arena(A_SEG_BYTES, 4)),
    ("rt_seg_tokens", Sized::Arena(A_SEG_TOKENS, 16)),
    ("rt_traits", Sized::Arena(A_TRAITS, 32)),
    ("rt_jobs", Sized::Arena(A_JOBS, 16)),
];

const EXPORT_KERNELS: &[&str] = &[
    "type_checker/retention/export/00_begin",
    "type_checker/retention/export/01_params",
    "type_checker/retention/export/01b_decl_tokens",
    "type_checker/retention/export/02_rows",
    "type_checker/retention/export/03_heights",
    "type_checker/retention/export/04_height_plan",
    "type_checker/retention/export/05_height_scatter",
    "type_checker/retention/export/06_translate",
    "type_checker/retention/export/07_advance",
    "type_checker/retention/export/08_scan_local",
    "type_checker/retention/export/08_scan_blocks",
    "type_checker/retention/export/08_scan_apply",
    "type_checker/retention/export/09_reserve",
    "type_checker/retention/export/10_decls",
    "type_checker/retention/export/11_rows",
    "type_checker/retention/export/12_side",
    "type_checker/retention/export/12b_text_clear",
    "type_checker/retention/export/12c_text_copy",
    "type_checker/retention/export/13_schema",
    "type_checker/retention/export/14_uses",
    "type_checker/retention/export/14b_trait_flags",
    "type_checker/retention/export/14c_trait_reserve",
    "type_checker/retention/export/14d_trait_facts",
    "type_checker/retention/export/14e_bound_links",
    "type_checker/retention/export/15_finish",
    "type_checker/retention/export/16_commit",
    "type_checker/retention/export/17_publish",
    "type_checker/retention/export/18_rollback",
];
const REHASH_KERNEL: &str = "type_checker/retention/store_rehash";
const UNCOMMIT_KERNEL: &str = "type_checker/retention/export/19_uncommit";
/// Words of the call rewrite's status (native_calls.rs).
const NC_STATUS_WORDS: usize = 4;
const SNAPSHOT_ROWS_KERNEL: &str = "type_checker/retention/snapshot_rows";

/// Job tables the snapshot copies by their counted rows
/// (`snapshot_rows.slang`): the table, the table whose word 0 counts its
/// rows, its words per row, and whether it holds one row per HIR row. The
/// export kernels read these tables only below that count
/// (retention_job.slang `valid_row`, side_tables.slang `side_rows`,
/// trait_common.slang `method_rows` and `predicate_rows`). A table whose
/// size does not match its rows is copied whole.
const SNAPSHOT_ROW_TABLES: &[(&str, &str, u64, bool)] = &[
    ("compact_hir_core", "compact_hir_count", 4, true),
    ("compact_hir_links", "compact_hir_count", 4, true),
    ("compact_hir_payload", "compact_hir_count", 4, true),
    ("compact_hir_semantic_facts", "compact_hir_count", 8, true),
    ("compact_hir_nearest_fn", "compact_hir_count", 1, true),
    ("compact_fn_return_type", "compact_hir_count", 1, true),
    ("compact_const_value", "compact_hir_count", 1, true),
    ("compact_const_type", "compact_hir_count", 1, true),
    ("compact_array_element_start", "compact_hir_count", 1, true),
    ("compact_array_element_count", "compact_hir_count", 1, true),
    ("compact_generic_param_ranges", "compact_hir_count", 2, true),
    ("compact_type_arg_ranges", "compact_hir_count", 2, true),
    ("semantic_calls_by_hir", "compact_hir_count", 22, true),
    ("semantic_value_const_by_hir", "compact_hir_count", 2, true),
    ("semantic_value_decl_by_hir", "compact_hir_count", 1, true),
    ("semantic_value_const_present_by_hir", "compact_hir_count", 1, true),
    ("semantic_type_ref_tag_by_hir", "compact_hir_count", 1, true),
    ("semantic_type_ref_payload_by_hir", "compact_hir_count", 1, true),
    ("semantic_member_field_ordinal_by_hir", "compact_hir_count", 1, true),
    ("semantic_iterable_kind_by_hir", "compact_hir_count", 1, true),
    ("semantic_function_native_abi_by_hir", "compact_hir_count", 1, true),
    ("semantic_function_host_service_by_hir", "compact_hir_count", 1, true),
    ("semantic_expr_ref_tag_by_hir", "compact_hir_count", 1, true),
    ("semantic_expr_ref_payload_by_hir", "compact_hir_count", 1, true),
    ("semantic_call_native_abi_by_hir", "compact_hir_count", 1, true),
    ("semantic_argument_mode_by_hir", "compact_hir_count", 1, true),
    ("compact_type_args", "compact_type_arg_count", 5, true),
    ("compact_variants", "compact_variant_count", 4, true),
    ("compact_variant_payloads", "compact_variant_payload_row_count", 4, true),
    ("compact_strings", "compact_string_count", 4, true),
    ("compact_predicates", "compact_predicate_count", 4, true),
    ("compact_params", "compact_param_count", 4, true),
    ("compact_method_cores", "compact_method_count", 4, true),
    ("compact_method_signatures", "compact_method_count", 4, true),
    ("compact_match_payloads", "compact_match_payload_row_count", 4, true),
    ("compact_match_arms", "compact_match_arm_count", 4, true),
    ("compact_generic_params", "compact_generic_param_count", 4, true),
    ("compact_fields", "compact_field_count", 4, true),
    ("compact_call_args", "compact_call_arg_count", 4, true),
    ("compact_array_elements", "compact_array_element_row_count", 4, true),
    // Keyed by parameter, field or match arm index (12_side.slang, 13_schema.slang).
    ("semantic_param_ref_tag_by_row", "compact_param_count", 1, true),
    ("semantic_param_ref_payload_by_row", "compact_param_count", 1, true),
    ("struct_init_field_ordinal_by_row", "compact_field_count", 1, true),
    ("compact_match_payload_start", "compact_match_arm_count", 1, false),
    ("compact_match_payload_count", "compact_match_arm_count", 1, false),
];
/// Tables per `snapshot_rows` dispatch, and that dispatch's parameter words.
const SNAPSHOT_ROWS_PER_DISPATCH: usize = 16;
const SNAPSHOT_ROWS_PARAM_WORDS: usize = 4 + 4 * SNAPSHOT_ROWS_PER_DISPATCH;
/// Pool keys of the parameter buffers, one per dispatch.
const SNAPSHOT_ROWS_PARAMS: [&str; 4] = [
    "snapshot_rows.params0",
    "snapshot_rows.params1",
    "snapshot_rows.params2",
    "snapshot_rows.params3",
];
const RESOLVE_KERNEL: &str = "tests/retention_resolve";
const TRAIT_PROBE_KERNEL: &str = "tests/retention_traits";

/// Words per directory entry the trait-fact probe writes
/// (shaders/tests/retention_traits.slang).
pub const TRAIT_PROBE_WORDS: usize = 16;

/// Words per use the acceptance probe writes (shaders/tests/retention_resolve.slang).
pub const PROBE_WORDS: usize = 40;

fn storage(device: &wgpu::Device, label: &str, bytes: u64, indirect: bool) -> wgpu::Buffer {
    let mut usage =
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST;
    if indirect {
        usage |= wgpu::BufferUsages::INDIRECT;
    }
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes.max(16).next_multiple_of(16),
        usage,
        mapped_at_creation: false,
    })
}

/// A job table bound by its name: a view into a graph or parser allocation.
#[derive(Clone)]
pub(crate) struct JobTable {
    pub buffer: wgpu::Buffer,
    pub offset: u64,
    pub size: u64,
}

impl JobTable {
    pub(crate) fn from_lanius<T>(buffer: &LaniusBuffer<T>) -> Self {
        Self {
            buffer: buffer.buffer.clone(),
            offset: buffer.byte_offset,
            size: buffer.byte_size as u64,
        }
    }
}

/// The `snapshot_rows.slang` entry of job table `name` (source word,
/// words per row, words, count word) and its count table, or `None` when the
/// table is copied whole.
fn snapshot_row_entry<'a>(
    name: &str,
    table: &JobTable,
    live: &'a BTreeMap<&'static str, JobTable>,
    hir_rows: u64,
) -> Option<(&'a JobTable, [u32; 4])> {
    let &(_, count_name, stride, by_hir) = SNAPSHOT_ROW_TABLES.iter().find(|row| row.0 == name)?;
    let count = live.get(count_name)?;
    let row_bytes = stride * 4;
    let fits = if by_hir { table.size == hir_rows * row_bytes } else { table.size % row_bytes == 0 };
    if !fits || count.offset % 4 != 0 || count.size < 4 {
        return None;
    }
    Some((count, [
        u32::try_from(table.offset / 4).ok()?,
        stride as u32,
        u32::try_from(table.size / 4).ok()?,
        u32::try_from(count.offset / 4).ok()?,
    ]))
}

/// The lexer tables of the job being recorded that the export copies body
/// source provenance from: token records, source bytes and file starts.
pub(crate) fn retention_source_tables(
    lexer: &crate::lexer::buffers::GpuBuffers,
) -> Vec<(&'static str, JobTable)> {
    let word_view = |buffer: &wgpu::Buffer, offset: u64, bytes: u64| JobTable {
        buffer: buffer.clone(),
        offset,
        size: bytes.next_multiple_of(4).min(buffer.size() - offset).max(4),
    };
    vec![
        ("rt_job_tokens", JobTable::from_lanius(&lexer.tokens_out)),
        (
            "rt_job_source",
            word_view(&lexer.in_bytes.buffer, lexer.in_bytes.byte_offset, lexer.in_bytes.byte_size as u64),
        ),
        ("rt_job_file_start", JobTable::from_lanius(&lexer.source_file_start)),
    ]
}

/// The capacities a job's scratch is sized for.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
struct ScratchShape {
    rows: u64,
    records: u64,
    args: u64,
    param_slots: u64,
    tokens: u64,
    job_tokens: u64,
}

struct Store {
    capacity: ProgramRetentionCapacity,
    buffers: BTreeMap<&'static str, wgpu::Buffer>,
    hash_mask: u32,
    scratch_shape: Option<ScratchShape>,
    scratch: BTreeMap<&'static str, wgpu::Buffer>,
    stack_lanes: u64,
    reports: Vec<JobReport>,
    growths: u32,
    builds: u32,
    /// Build generation of the current build (`counts::GENERATION`).
    generation: u32,
    /// Source bytes and exports of the build's jobs so far, which size the
    /// store ([`source_capacity`]).
    source_bytes: u64,
    exports: u32,
    /// False only in tests that start from a fixed capacity.
    source_sizing: bool,
    /// Changes whenever `buffers` or `scratch` are replaced, so a prepared
    /// export knows whether the buffers it bound are still the store's.
    epoch: u64,
}

/// Next build generation, shared by every store of the process, so a
/// generation names one build of one store.
static NEXT_GENERATION: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(1);

fn next_generation() -> Result<u32> {
    use std::sync::atomic::Ordering;
    NEXT_GENERATION
        .try_update(Ordering::Relaxed, Ordering::Relaxed, |g| g.checked_add(1))
        .map_err(|_| anyhow!("program retention build generations are exhausted"))
}

/// What one job's export did.
#[derive(Clone, Debug)]
pub struct JobReport {
    /// Export attempts (1 when the first attempt committed).
    pub attempts: u32,
    /// Status words of the committed attempt.
    pub counts: Vec<u32>,
    /// Canonical records that did not translate.
    pub untranslated_records: u32,
    /// All committed exports so far have no invariant failures or entries
    /// marked incomplete. This covers the current retained schema only;
    /// it does not certify the missing lowering/admission inputs.
    pub ready: bool,
}

/// Live retained bytes from the GPU counters against allocated capacity.
#[derive(Clone, Debug)]
pub struct RetentionBytes {
    /// Bytes of committed records per arena (`RT_A_*` order).
    pub live: [u64; ARENAS],
    /// Allocated bytes per arena.
    pub capacity: [u64; ARENAS],
    /// Hash-table bytes (not records; sized by slot count).
    pub tables: u64,
    /// Bytes of discovery records (resident for the whole build).
    pub resident_discovery: u64,
    /// Bytes of body payloads (streamable).
    pub streamable_bodies: u64,
}

#[derive(Clone, Copy)]
enum ExportFault {
    Fill(&'static str, u32),
    MissingCallResults,
}

/// The build-scoped store. Attach it to a compiler with
/// `GpuCompiler::attach_program_retention`; each interface job then exports
/// into it before its workspace is reused.
pub struct ProgramRetention {
    /// Only the native retained driver withholds all original generic bodies.
    native_projection: bool,
    native_call_pass: std::sync::OnceLock<PassData>,
    /// The native call pass's own buffers, kept across builds (grown by
    /// powers of two) so a warm build binds the same ones.
    native_call_scratch: Mutex<BTreeMap<&'static str, wgpu::Buffer>>,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    passes: Vec<PassData>,
    rehash: PassData,
    /// Restores the store to a job's watermark (export/19_uncommit.slang).
    uncommit: PassData,
    /// Copies the counted rows of the snapshot's row tables.
    snapshot_rows: PassData,
    resolve: Mutex<Option<PassData>>,
    trait_probe: Mutex<Option<PassData>>,
    /// Test fault applied to the export's snapshot, never the frontend.
    export_fault: Mutex<Option<ExportFault>>,
    store: Mutex<Store>,
    /// Every job table name an export kernel binds.
    job_inputs: std::collections::BTreeSet<String>,
    /// Snapshot buffer sets of finished jobs, reused by later jobs.
    snapshot_pool: Arc<Mutex<Vec<BTreeMap<&'static str, wgpu::Buffer>>>>,
    /// Records the GPU work that follows an export ([`ExportFollower`]).
    follower_recorder: Mutex<Option<ExportFollowerRecorder>>,
    /// That work, recorded and not yet submitted.
    follower: Mutex<Option<PreparedFollower>>,
    /// The words its reads returned, for the build's next consumer.
    followed: Mutex<Option<FollowedWords>>,
}

/// GPU work that a later stage records before a job's export has produced
/// the store's counters, sized from the store's capacities: the export's
/// tail submits it behind the call rewrite, and the host reads `reads` with
/// the job's object ([`ProgramRetention::export_reads`]), so the work runs
/// without the GPU waiting on the host.
pub(crate) struct ExportFollower {
    pub(crate) commands: wgpu::CommandBuffer,
    /// Buffers whose first `words` words are read with the rewrite.
    pub(crate) reads: Vec<(wgpu::Buffer, usize)>,
    /// The recorder's own state (its buffers and plan), returned with the
    /// words in [`FollowedWords::state`].
    pub(crate) state: Box<dyn std::any::Any + Send + Sync>,
}

/// Records the [`ExportFollower`] of the store's current state, or none.
pub(crate) type ExportFollowerRecorder =
    Box<dyn Fn(&ProgramRetention) -> Result<Option<ExportFollower>> + Send + Sync>;

struct PreparedFollower {
    follower: ExportFollower,
    epoch: u64,
    generation: u32,
}

/// What an [`ExportFollower`]'s reads returned, and after which committed
/// export of which build.
pub(crate) struct FollowedWords {
    pub(crate) generation: u32,
    /// Committed exports of the build when the follower ran (it followed
    /// the last one).
    pub(crate) jobs: usize,
    pub(crate) words: Vec<Vec<u32>>,
    /// [`ExportFollower::state`].
    pub(crate) state: Box<dyn std::any::Any + Send + Sync>,
}

/// One job's export inputs, copied into buffers the store owns when the
/// job's type check has been recorded and before anything later in the job
/// (semantic interface, lowering, output retries) runs. The export reads
/// only these copies: lowering may reuse the frontend's arenas, and two
/// frontend tables that share one arena cannot be bound with different
/// access in one dispatch. Each table has its own buffer.
pub(crate) struct JobSnapshot {
    tables: BTreeMap<&'static str, JobTable>,
    buffers: BTreeMap<&'static str, wgpu::Buffer>,
    pool: Arc<Mutex<Vec<BTreeMap<&'static str, wgpu::Buffer>>>>,
    /// The export of a native job, submitted right behind the job's type
    /// check ([`ProgramRetention::submit_export_now`]).
    early: Mutex<Option<EarlyExport>>,
}

/// A native job's export, submitted before the host has read any of the
/// job's statuses. The steps run to the commit or the rollback on the GPU;
/// the tail ([`ProgramRetention::submit_export_tail`]) follows it, and the
/// host reads the words of both with the job's object
/// ([`ProgramRetention::export_reads`]). Dropped before the host accepted
/// the job, it uncommits the job on the GPU.
struct EarlyExport {
    epoch: u64,
    generation: u32,
    tail: Option<ExportTail>,
    uncommit: Uncommit,
}

/// What the tail submitted: the call rewrite's status words and the
/// follower's reads and state.
struct ExportTail {
    rewrite_status: Option<wgpu::Buffer>,
    follower: Option<(Vec<(wgpu::Buffer, usize)>, Box<dyn std::any::Any + Send + Sync>)>,
}

/// Restores the store to a job's watermark (export/19_uncommit.slang) when
/// dropped armed: the frontend or the lowering asked for a retry after the
/// job's export was submitted, or the build failed.
struct Uncommit {
    armed: bool,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    pass: PassData,
    buffers: Vec<(&'static str, wgpu::Buffer)>,
    lanes: u64,
}

impl Drop for Uncommit {
    fn drop(&mut self) {
        if !self.armed {
            return;
        }
        let entries = self.buffers.iter().map(|(name, buffer)| (*name, buffer.as_entire_binding())).collect::<Vec<_>>();
        let Ok(bind) = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&self.pass.shader_id),
            &self.pass,
            0,
            &entries,
        ) else {
            return;
        };
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("program_retention.uncommit"),
        });
        let g = self.lanes.div_ceil(256).max(1);
        substitution::record_timed(
            &mut encoder,
            "program_retention.uncommit",
            &[(&self.pass, &bind, substitution::Launch::Groups(g.min(65535) as u32, g.div_ceil(65535) as u32, 1))],
        );
        self.queue.submit(Some(encoder.finish()));
    }
}

/// The original object's rows the call rewrite updates in place, before the
/// object is read (shaders/type_checker/retention/native/00_provisional.slang).
pub(crate) struct ObjectCallRows<'a> {
    /// 0: x86 undefined-symbol rows (four words per symbol) with
    /// `call_hirs`; 1: Wasm relocation rows (eight words per row).
    pub mode: u32,
    pub rows: JobTable,
    pub call_hirs: Option<JobTable>,
    /// The word that counts the rows: (buffer, byte offset).
    pub count: (wgpu::Buffer, u64),
    /// Rows the buffers hold.
    pub lanes: u32,
    /// Records the copy of the rewritten identity words (three per symbol)
    /// into the resident link's parked object.
    pub park_identities: Option<Box<dyn FnOnce(&mut wgpu::CommandEncoder, &wgpu::Buffer) + 'a>>,
}

impl JobSnapshot {
    pub(crate) fn tables(&self) -> &BTreeMap<&'static str, JobTable> {
        &self.tables
    }
}

impl Drop for JobSnapshot {
    fn drop(&mut self) {
        let buffers = std::mem::take(&mut self.buffers);
        if let Ok(mut pool) = self.pool.lock() {
            pool.push(buffers);
        }
    }
}

impl ProgramRetention {
    /// A store on the process-global GPU with `capacity`.
    pub fn new(capacity: ProgramRetentionCapacity) -> Result<Arc<Self>> {
        Self::new_with_mode(crate::gpu::device::global(), capacity, false)
    }

    pub(crate) fn new_native(gpu: &crate::gpu::device::GpuDevice, capacity: ProgramRetentionCapacity) -> Result<Arc<Self>> {
        Self::new_with_mode(gpu, capacity, true)
    }

    pub(crate) fn native_projection(&self) -> bool {
        self.native_projection
    }

    fn new_with_mode(gpu: &crate::gpu::device::GpuDevice, capacity: ProgramRetentionCapacity, native_projection: bool) -> Result<Arc<Self>> {
        let device = gpu.device.clone();
        let queue = gpu.queue.clone();
        let passes = EXPORT_KERNELS
            .iter()
            .map(|&key| make_pass_data_from_shader_key(&device, key, "main", key))
            .collect::<Result<Vec<_>>>()?;
        let rehash = make_pass_data_from_shader_key(&device, REHASH_KERNEL, "main", REHASH_KERNEL)?;
        let uncommit = make_pass_data_from_shader_key(&device, UNCOMMIT_KERNEL, "main", UNCOMMIT_KERNEL)?;
        let snapshot_rows =
            make_pass_data_from_shader_key(&device, SNAPSHOT_ROWS_KERNEL, "main", SNAPSHOT_ROWS_KERNEL)?;
        let mut store = Store {
            capacity,
            buffers: BTreeMap::new(),
            hash_mask: u32::MAX,
            scratch_shape: None,
            scratch: BTreeMap::new(),
            stack_lanes: 0,
            reports: Vec::new(),
            growths: 0,
            builds: 0,
            generation: 0,
            source_bytes: 0,
            exports: 0,
            source_sizing: true,
            epoch: 0,
        };
        store.buffers = allocate_store(&device, &capacity, None);
        let job_inputs = passes
            .iter()
            .flat_map(reflected_names)
            // Store buffers and job scratch are `rt_*`; job tables are not,
            // except the job's lexer source tables.
            .filter(|name| !name.starts_with("rt_") || name.starts_with("rt_job_"))
            .collect();
        let this = Arc::new(Self {
            native_projection,
            native_call_pass: std::sync::OnceLock::new(),
            native_call_scratch: Mutex::new(BTreeMap::new()),
            device,
            queue,
            passes,
            rehash,
            uncommit,
            snapshot_rows,
            resolve: Mutex::new(None),
            trait_probe: Mutex::new(None),
            export_fault: Mutex::new(None),
            store: Mutex::new(store),
            job_inputs,
            snapshot_pool: Arc::new(Mutex::new(Vec::new())),
            follower_recorder: Mutex::new(None),
            follower: Mutex::new(None),
            followed: Mutex::new(None),
        });
        this.begin_build()?;
        Ok(this)
    }

    /// Starts a new build in the same allocations: clears the counters and
    /// the hash tables only. Arena contents past the counters are dead and
    /// never read; nothing of an earlier build is reused.
    pub fn begin_build(&self) -> Result<()> {
        let mut store = self.store.lock().unwrap();
        let generation = next_generation()?;
        let mut encoder = self.device.create_command_encoder(&Default::default());
        for name in ["rt_decl_slot", "rt_param_slot", "rt_term_slot"] {
            encoder.clear_buffer_counted(&store.buffers[name], 0, None);
        }
        let mut words = vec![0u32; counts::WORDS];
        words[A_DECLS] = 1;
        words[A_PARAMS] = 1;
        words[A_TERMS] = RT_FIRST_TERM;
        words[counts::FIRST_INVARIANT] = u32::MAX;
        words[counts::READY] = 1;
        words[counts::GENERATION] = generation;
        self.queue.write_buffer_counted(&store.buffers["rt_counts"], 0, &words_bytes(&words));
        self.queue.write_buffer_counted(
            &store.buffers["rt_config"],
            0,
            &words_bytes(&[store.hash_mask, 0, 0, 0]),
        );
        self.queue.submit(Some(encoder.finish()));
        store.reports.clear();
        *self.followed.lock().unwrap() = None;
        store.builds += 1;
        store.generation = generation;
        store.source_bytes = 0;
        store.exports = 0;
        Ok(())
    }

    /// The current build's generation: nonzero, and unique over every build
    /// of every store in this process. The GPU copy is
    /// `rt_counts[counts::GENERATION]`.
    pub fn generation(&self) -> u32 {
        self.store.lock().unwrap().generation
    }

    /// Forces every hash onto one probe chain (mask 0) for the rest of this
    /// store's builds, or restores the full hash (`u32::MAX`).
    pub fn set_hash_mask(&self, mask: u32) {
        let mut store = self.store.lock().unwrap();
        store.hash_mask = mask;
        self.queue.write_buffer_counted(&store.buffers["rt_config"], 0, &words_bytes(&[mask]));
    }

    /// Exports the current job. `job` names every job table the kernels
    /// read. Retries after growth until the job commits.
    /// Records copies of the job tables every export kernel reads into
    /// store-owned buffers, in `encoder` after the job's type check. The
    /// tables of [`SNAPSHOT_ROW_TABLES`] are copied up to their counted rows
    /// on the GPU; `hir_rows` is the job's HIR row capacity.
    pub(crate) fn record_job_snapshot(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        live: &BTreeMap<&'static str, JobTable>,
        hir_rows: u64,
    ) -> Result<JobSnapshot> {
        let mut buffers = self.snapshot_pool.lock().unwrap().pop().unwrap_or_default();
        let mut tables = BTreeMap::new();
        // Copies and dispatches below must follow the job's recorded work.
        passes_core::flush_deferred_compute(encoder);
        let mut by_rows: Vec<(&JobTable, wgpu::Buffer, &JobTable, [u32; 4])> = Vec::new();
        for (&name, table) in live {
            if !self.job_inputs.contains(name) {
                continue;
            }
            if table.offset % 4 != 0 || table.size % 4 != 0 {
                bail!("program retention input {name} is not word aligned ({} + {})", table.offset, table.size);
            }
            if !table.buffer.usage().contains(wgpu::BufferUsages::COPY_SRC) {
                bail!("program retention input {name} cannot be copied");
            }
            let fits = buffers.get(name).is_some_and(|b: &wgpu::Buffer| b.size() >= table.size);
            if !fits {
                let size = table.size.max(16).next_power_of_two();
                buffers.insert(name, self.device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some(&format!("program_retention.snapshot.{name}")),
                    size,
                    usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                    mapped_at_creation: false,
                }));
            }
            let buffer = buffers[name].clone();
            match snapshot_row_entry(name, table, live, hir_rows) {
                Some((count, entry)) => by_rows.push((table, buffer.clone(), count, entry)),
                None => encoder.copy_buffer_counted(&table.buffer, table.offset, &buffer, 0, table.size),
            }
            tables.insert(name, JobTable { buffer, offset: 0, size: table.size });
        }
        for (dispatch, group) in by_rows.chunks(SNAPSHOT_ROWS_PER_DISPATCH).enumerate() {
            let key = *SNAPSHOT_ROWS_PARAMS
                .get(dispatch)
                .ok_or_else(|| anyhow!("program retention snapshot has too many row tables"))?;
            let params = buffers
                .entry(key)
                .or_insert_with(|| {
                    self.device.create_buffer(&wgpu::BufferDescriptor {
                        label: Some("program_retention.snapshot_rows.params"),
                        size: (SNAPSHOT_ROWS_PARAM_WORDS * 4) as u64,
                        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    })
                })
                .clone();
            let mut words = [0u32; SNAPSHOT_ROWS_PARAM_WORDS];
            let largest = group.iter().map(|(_, _, _, entry)| entry[2]).max().unwrap_or(0);
            let workgroups = largest.div_ceil(256).clamp(1, 1024);
            words[0] = workgroups * 256;
            words[1] = group.len() as u32;
            for (slot, (_, _, _, entry)) in group.iter().enumerate() {
                words[4 + 4 * slot..8 + 4 * slot].copy_from_slice(entry);
            }
            self.queue.write_buffer_counted(&params, 0, &words_bytes(&words));
            let names = (0..SNAPSHOT_ROWS_PER_DISPATCH)
                .flat_map(|slot| [format!("sr_src{slot}"), format!("sr_count{slot}"), format!("sr_dst{slot}")])
                .collect::<Vec<_>>();
            let mut entries = vec![("gSR", params.as_entire_binding())];
            for slot in 0..SNAPSHOT_ROWS_PER_DISPATCH {
                // Unused slots repeat the first table; `tables` stops the kernel before them.
                let (src, dst, count, _) = &group[if slot < group.len() { slot } else { 0 }];
                entries.push((names[3 * slot].as_str(), src.buffer.as_entire_binding()));
                entries.push((names[3 * slot + 1].as_str(), count.buffer.as_entire_binding()));
                entries.push((names[3 * slot + 2].as_str(), dst.as_entire_binding()));
            }
            let label = "program_retention.snapshot_rows";
            let bind = passes_core::bind_group::create_bind_group_from_bindings(
                &self.device,
                Some(label),
                &self.snapshot_rows,
                0,
                &entries,
            )?;
            passes_core::record_or_defer_compute_direct(encoder, &self.snapshot_rows, &bind, label, (workgroups, 1, 1));
        }
        // Work recorded after the snapshot may rewrite its sources.
        passes_core::flush_deferred_compute(encoder);
        Ok(JobSnapshot { tables, buffers, pool: self.snapshot_pool.clone(), early: Mutex::new(None) })
    }

    /// Records and submits the job's first export attempt without waiting
    /// for it; [`Self::finish_export_job`] reads it. Until then the caller
    /// may do host work while the GPU exports. A caller that does not finish
    /// it calls [`Self::abandon_export`].
    pub(crate) fn submit_export_job(&self, snapshot: &JobSnapshot) -> Result<ExportSubmitted> {
        let result = self.submit_export_attempt(snapshot);
        if result.is_err() {
            self.abandon_export();
        }
        result
    }

    /// Sets the recorder of the work that follows each export.
    pub(crate) fn set_export_follower(&self, recorder: Option<ExportFollowerRecorder>) {
        *self.follower_recorder.lock().unwrap() = recorder;
        *self.follower.lock().unwrap() = None;
    }

    /// Records the export follower while the host waits for a job, after
    /// [`Self::prepare_export_job`]. The store lock is not held while the
    /// recorder runs.
    pub(crate) fn prepare_export_follower(&self) -> Result<()> {
        if self.follower.lock().unwrap().is_some() {
            return Ok(());
        }
        let recorder = self.follower_recorder.lock().unwrap();
        let Some(recorder) = recorder.as_ref() else {
            return Ok(());
        };
        // A later export supersedes the words of an earlier one; dropping
        // them first releases the buffers they hold for this recording.
        *self.followed.lock().unwrap() = None;
        let (epoch, generation) = {
            let store = self.store.lock().unwrap();
            (store.epoch, store.generation)
        };
        if let Some(follower) = recorder(self)? {
            *self.follower.lock().unwrap() = Some(PreparedFollower { follower, epoch, generation });
        }
        Ok(())
    }

    /// The prepared follower if it bound the store's current buffers.
    fn take_follower(&self, store: &Store) -> Option<ExportFollower> {
        self.follower
            .lock()
            .unwrap()
            .take()
            .filter(|prepared| prepared.epoch == store.epoch && prepared.generation == store.generation)
            .map(|prepared| prepared.follower)
    }

    /// The words of the follower that ran behind this build's last export.
    pub(crate) fn take_followed_words(&self) -> Option<FollowedWords> {
        let followed = self.followed.lock().unwrap().take()?;
        let store = self.store.lock().unwrap();
        (followed.generation == store.generation && followed.jobs == store.reports.len()).then_some(followed)
    }

    /// Submits a native job's whole export right behind the job's type
    /// check, before the host records the job's semantic interface and
    /// lowering, so the GPU exports while the host records them. The store
    /// is first sized from the source bytes of the build's jobs
    /// ([`source_capacity`]), not from counters read back. The steps commit
    /// the job or roll it back on the GPU; the host reads which with the
    /// job's object ([`Self::export_reads`], [`Self::accept_export`]). A
    /// snapshot dropped before the host accepted its job uncommits it.
    pub(crate) fn submit_export_now(&self, snapshot: &JobSnapshot, source_bytes: u64) -> Result<()> {
        if snapshot.early.lock().unwrap().is_some() {
            return Ok(());
        }
        let job = &snapshot.tables;
        self.apply_export_fault(job)?;
        let shape = export_shape(job)?;
        let mut store = self.store.lock().unwrap();
        store.source_bytes += source_bytes;
        store.exports += 1;
        let target = source_capacity(&store.capacity, store.source_bytes, store.exports);
        if store.source_sizing && target != store.capacity {
            self.grow(&mut store, target)?;
        }
        self.ensure_scratch(&mut store, shape);
        self.queue.submit(Some(self.record_export(&store, job, shape)?));
        let names = reflected_names(&self.uncommit);
        let buffers = names
            .iter()
            .map(|name| {
                let (&key, buffer) = store
                    .buffers
                    .get_key_value(name.as_str())
                    .ok_or_else(|| anyhow!("{UNCOMMIT_KERNEL} binds unknown buffer {name}"))?;
                Ok((key, buffer.clone()))
            })
            .collect::<Result<Vec<_>>>()?;
        let lanes = u64::from(store.capacity.arenas[A_DECLS].max(store.capacity.slots.into_iter().max().unwrap_or(0)));
        *snapshot.early.lock().unwrap() = Some(EarlyExport {
            epoch: store.epoch,
            generation: store.generation,
            tail: None,
            uncommit: Uncommit {
                armed: true,
                device: self.device.clone(),
                queue: self.queue.clone(),
                pass: self.uncommit.clone(),
                buffers,
                lanes,
            },
        });
        Ok(())
    }

    /// Submits the work that follows a native job's export, in one
    /// submission behind it: the rewrite of the original object's calls to
    /// generic templates (`rows`, native_calls.rs) and the export follower
    /// (the trait catalog's count passes). Both bind only buffers sized from
    /// capacities and are gated on the GPU by the job's commit word. Runs
    /// once per export.
    pub(crate) fn submit_export_tail(
        &self,
        snapshot: &JobSnapshot,
        rows: Option<(ObjectCallRows<'_>, &mut NativeCallTables)>,
    ) -> Result<()> {
        if snapshot.early.lock().unwrap().as_ref().is_none_or(|early| early.tail.is_some()) {
            return Ok(());
        }
        // The recorder takes the store lock itself.
        self.prepare_export_follower()?;
        let store = self.store.lock().unwrap();
        let mut guard = snapshot.early.lock().unwrap();
        let early = guard.as_mut().expect("checked above");
        if early.epoch != store.epoch || early.generation != store.generation {
            bail!("program retention store changed under a submitted export");
        }
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("program_retention.export.tail"),
        });
        let rewrite_status = match rows {
            Some((rows, tables)) => Some(self.record_call_rewrite(&mut encoder, &store, snapshot, tables, rows)?),
            None => None,
        };
        let follower = self.take_follower(&store);
        let mut commands = vec![encoder.finish()];
        let follower = follower.map(|follower| {
            commands.push(follower.commands);
            (follower.reads, follower.state)
        });
        self.queue.submit(commands);
        early.tail = Some(ExportTail { rewrite_status, follower });
        Ok(())
    }

    /// The buffers and leading words the host reads, with the job's object,
    /// to learn what a native job's export and its tail did: the store's
    /// counters, the export scratch counters, the call rewrite's status and
    /// the follower's reads. Empty when the job has no early export.
    pub(crate) fn export_reads(&self, snapshot: &JobSnapshot) -> Vec<(wgpu::Buffer, usize)> {
        let guard = snapshot.early.lock().unwrap();
        let Some(early) = guard.as_ref() else {
            return Vec::new();
        };
        let store = self.store.lock().unwrap();
        let mut reads = vec![
            (store.buffers["rt_counts"].clone(), counts::WORDS),
            (store.scratch["rt_x_counts"].clone(), X_WORDS),
        ];
        if let Some(tail) = &early.tail {
            reads.extend(tail.rewrite_status.iter().map(|status| (status.clone(), NC_STATUS_WORDS)));
            reads.extend(tail.follower.iter().flat_map(|(follower, _)| follower.iter().cloned()));
        }
        reads
    }

    /// Takes the words of [`Self::export_reads`]. `Ok(true)`: the job
    /// committed and the store keeps it. `Ok(false)`: the export overflowed
    /// and rolled back on the GPU; the store has grown from the demand the
    /// GPU recorded and the caller runs the job again.
    pub(crate) fn accept_export(&self, snapshot: &JobSnapshot, mut words: Vec<Vec<u32>>) -> Result<bool> {
        let Some(mut early) = snapshot.early.lock().unwrap().take() else {
            bail!("program retention export was not submitted");
        };
        early.uncommit.armed = false;
        let tail = early.tail.take();
        let rewrite = tail.as_ref().is_some_and(|tail| tail.rewrite_status.is_some());
        if words.len() < 2 + usize::from(rewrite) {
            bail!("program retention export words are missing");
        }
        let followed = words.split_off(2 + usize::from(rewrite));
        let status = rewrite.then(|| words.pop().unwrap_or_default());
        let x = words.pop().unwrap_or_default();
        let counts_words = words.pop().unwrap_or_default();
        if counts_words.len() < counts::WORDS || x.len() < X_WORDS {
            bail!("program retention export words are short");
        }
        let mut store = self.store.lock().unwrap();
        if early.epoch != store.epoch || early.generation != store.generation {
            bail!("program retention store changed under a submitted export");
        }
        let Some(report) = committed_export(1, counts_words.clone(), &x) else {
            if counts_words[counts::JOB_STATE] != counts::JOB_ROLLED_BACK {
                bail!(
                    "program retention export left job state {} (status {:?})",
                    counts_words[counts::JOB_STATE],
                    &counts_words[..80],
                );
            }
            let grown = grown_capacity(&store.capacity, &counts_words);
            self.grow(&mut store, grown)?;
            return Ok(false);
        };
        if let Some(status) = status {
            let bits = status.first().copied().unwrap_or(u32::MAX);
            if bits != 0 {
                bail!("retained original call symbols failed on the GPU (status {bits:#x})");
            }
        }
        store.reports.push(report);
        if let Some((_, state)) = tail.and_then(|tail| tail.follower) {
            *self.followed.lock().unwrap() = Some(FollowedWords {
                generation: store.generation,
                jobs: store.reports.len(),
                words: followed,
                state,
            });
        }
        Ok(true)
    }

    /// Reads and accepts a native job's export words in their own readback,
    /// for a job with no object to read them with.
    pub(crate) fn finish_export_now(&self, snapshot: &JobSnapshot) -> Result<bool> {
        self.submit_export_tail(snapshot, None)?;
        let reads = self.export_reads(snapshot);
        let parts = reads.iter().map(|(buffer, words)| (buffer, *words)).collect::<Vec<_>>();
        let words = self.read_parts(&parts)?;
        self.accept_export(snapshot, words)
    }

    /// Applies the test fault to a snapshot's tables before its export.
    fn apply_export_fault(&self, job: &BTreeMap<&'static str, JobTable>) -> Result<()> {
        let Some(fault) = *self.export_fault.lock().unwrap() else {
            return Ok(());
        };
        match fault {
            ExportFault::Fill(name, word) => {
                let table = job.get(name).ok_or_else(|| anyhow!("export fault names absent job table {name}"))?;
                self.queue.write_buffer_counted(&table.buffer, table.offset, &words_bytes(&vec![word; (table.size / 4) as usize]));
            }
            ExportFault::MissingCallResults => {
                let table = &job["semantic_calls_by_hir"];
                let stride = std::mem::size_of::<super::GpuCheckedCallArtifact>();
                let field = std::mem::offset_of!(super::GpuCheckedCallArtifact, return_ref_tag) as u64;
                for row in (0..table.size).step_by(stride) {
                    self.queue.write_buffer_counted(&table.buffer, table.offset + row + field, &[0; 8]);
                }
            }
        }
        Ok(())
    }

    fn ensure_scratch(&self, store: &mut Store, shape: ScratchShape) {
        if store.scratch_shape != Some(shape) {
            store.scratch = allocate_scratch(&self.device, shape);
            store.scratch_shape = Some(shape);
            store.epoch += 1;
        }
    }

    /// Reads the submitted export and retries it with grown capacity until
    /// it commits.
    pub(crate) fn finish_export_job(
        &self,
        job: &BTreeMap<&'static str, JobTable>,
        submitted: ExportSubmitted,
    ) -> Result<JobReport> {
        let result = self.export_job_attempts(job, submitted.shape);
        if result.is_err() {
            self.abandon_export();
        }
        result
    }

    /// Invalidates this build's store. An incomplete transfer/readback
    /// invalidates it even if its last GPU attempt committed. A driver must
    /// not reuse the preceding successful prefix after an export error.
    pub(crate) fn abandon_export(&self) {
        let store = self.store.lock().unwrap();
        self.queue.write_buffer_counted(&store.buffers["rt_counts"], (counts::READY * 4) as u64, &0u32.to_le_bytes());
        self.queue.submit(None);
    }

    fn submit_export_attempt(&self, snapshot: &JobSnapshot) -> Result<ExportSubmitted> {
        let job = &snapshot.tables;
        let shape = export_shape(job)?;
        self.apply_export_fault(job)?;
        let mut store = self.store.lock().unwrap();
        self.ensure_scratch(&mut store, shape);
        self.queue.submit(Some(self.record_export(&store, job, shape)?));
        Ok(ExportSubmitted { shape })
    }

    fn export_job_attempts(
        &self,
        job: &BTreeMap<&'static str, JobTable>,
        shape: ScratchShape,
    ) -> Result<JobReport> {
        let mut store = self.store.lock().unwrap();
        for attempt in 1..=8u32 {
            if attempt > 1 {
                self.queue.submit(Some(self.record_export(&store, job, shape)?));
            }
            let mut read = self.read_parts(&[
                (&store.buffers["rt_counts"], counts::WORDS),
                (&store.scratch["rt_x_counts"], X_WORDS),
            ])?;
            let x = read.pop().unwrap_or_default();
            let words = read.pop().unwrap_or_default();
            if let Some(report) = committed_export(attempt, words.clone(), &x) {
                store.reports.push(report.clone());
                return Ok(report);
            }
            if words[counts::JOB_STATE] != counts::JOB_ROLLED_BACK {
                bail!(
                    "program retention export left job state {} (status {:?}, scratch {:?})",
                    words[counts::JOB_STATE],
                    &words[..80],
                    &x[160..200]
                );
            }
            let grown = grown_capacity(&store.capacity, &words);
            self.grow(&mut store, grown)?;
        }
        bail!("program retention export did not fit after repeated growth")
    }

    fn record_export(
        &self,
        store: &Store,
        job: &BTreeMap<&'static str, JobTable>,
        shape: ScratchShape,
    ) -> Result<wgpu::CommandBuffer> {
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("program_retention.export"),
        });
        for (name, buffer) in &store.scratch {
            if *name != "rt_s_stack" {
                encoder.clear_buffer_counted(buffer, 0, None);
            }
        }
        let groups = |lanes: u64| -> [u32; 3] {
            let g = lanes.div_ceil(256).max(1);
            [g.min(65535) as u32, g.div_ceil(65535) as u32, 1]
        };
        let bind_groups = self
            .passes
            .iter()
            .map(|pass| self.bind(pass, store, job, &[]))
            .collect::<Result<Vec<_>>>()?;
        // The trait-fact scan runs the 08 kernels again over the trait flags
        // with their own counters (export/trait_common.slang).
        const TRAIT_SCAN: &[(&str, &str)] = &[
            ("rt_x_flags", "rt_x_tflags"),
            ("rt_x_scan", "rt_x_tscan"),
            ("rt_x_blocks", "rt_x_tblocks"),
            ("rt_x_counts", "rt_x_tcounts"),
        ];
        // Bind groups past the kernel list are the trait scan's: index
        // `EXPORT_KERNELS.len() + k` runs scan kernel 9 + k.
        let mut bind_groups = bind_groups;
        for index in 9..12 {
            bind_groups.push(self.bind(&self.passes[index], store, job, TRAIT_SCAN)?);
        }
        let indirect = &store.scratch["rt_x_dispatch"];
        {
            let mut steps = Vec::new();
            let mut run = |index: usize, dispatch: Dispatch| {
                let kernel = index.checked_sub(EXPORT_KERNELS.len()).map_or(index, |k| 9 + k);
                let launch = match dispatch {
                    Dispatch::Direct([x, y, z]) => substitution::Launch::Groups(x, y, z),
                    Dispatch::Indirect(slot) => substitution::Launch::Indirect(indirect, 3 * slot * 4),
                };
                steps.push((&self.passes[kernel], &bind_groups[index], launch));
            };
            use Dispatch::{Direct, Indirect};
            let one = Direct([1, 1, 1]);
            // Indexes follow EXPORT_KERNELS.
            run(0, one);
            run(1, Indirect(D_PARAMS));
            run(2, Direct(groups(shape.rows.max(shape.tokens))));
            run(3, Indirect(D_HIR));
            run(4, Indirect(D_RECORDS));
            run(5, one);
            run(6, Indirect(D_RECORDS));
            for _ in 1..HEIGHTS {
                run(7, Indirect(D_ROUND));
                run(8, one);
            }
            run(9, Direct(groups(shape.rows)));
            run(10, one);
            run(11, Direct(groups(shape.rows)));
            run(12, one);
            run(13, Indirect(D_HIR));
            run(14, Indirect(D_HIR));
            run(15, Indirect(D_SIDE));
            run(16, Direct(groups(shape.job_tokens)));
            run(17, Direct(groups(shape.job_tokens)));
            run(18, Indirect(D_SCHEMA));
            run(19, Indirect(D_HIR));
            run(20, Indirect(D_HIR));
            let trait_scan = EXPORT_KERNELS.len();
            run(trait_scan, Direct(groups(shape.rows)));
            run(trait_scan + 1, one);
            run(trait_scan + 2, Direct(groups(shape.rows)));
            run(21, one);
            run(22, Indirect(D_HIR));
            run(23, Indirect(D_HIR));
            run(24, Indirect(D_HIR));
            run(25, one);
            run(26, Indirect(D_COMMIT_DIR));
            run(27, Indirect(D_ROLLBACK));
            substitution::record_timed(&mut encoder, "program_retention.export", &steps);
        }
        Ok(encoder.finish())
    }

    /// Binds `pass` by reflected name; `aliases` binds a name to another
    /// scratch buffer.
    fn bind(
        &self,
        pass: &PassData,
        store: &Store,
        job: &BTreeMap<&'static str, JobTable>,
        aliases: &[(&str, &str)],
    ) -> Result<wgpu::BindGroup> {
        let names = reflected_names(pass);
        let mut entries = Vec::with_capacity(names.len());
        for name in &names {
            let alias = aliases.iter().find(|(from, _)| *from == name.as_str()).map(|(_, to)| *to);
            let resource = if let Some(buffer) = alias.and_then(|to| store.scratch.get(to)) {
                buffer.as_entire_binding()
            } else if let Some(buffer) = store.buffers.get(name.as_str()) {
                buffer.as_entire_binding()
            } else if let Some(buffer) = store.scratch.get(name.as_str()) {
                buffer.as_entire_binding()
            } else if let Some(table) = job.get(name.as_str()) {
                wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                    buffer: &table.buffer,
                    offset: table.offset,
                    size: NonZeroU64::new(table.size),
                })
            } else {
                bail!("{} requires missing buffer {name}", pass.shader_id);
            };
            entries.push((name.as_str(), resource));
        }
        passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass.shader_id),
            pass,
            0,
            &entries,
        )
    }

    /// Grows the store to `capacity`, keeping every committed record: the
    /// arenas are copied, the hash tables are rebuilt by the rehash kernel.
    /// Fixed buffers keep their identity for the store's entire lifetime:
    /// old consumer bindings must observe generation and READY changes.
    fn grow(&self, store: &mut Store, capacity: ProgramRetentionCapacity) -> Result<()> {
        let fresh = allocate_store(&self.device, &capacity, Some(&store.buffers));
        let mut encoder = self.device.create_command_encoder(&Default::default());
        for (name, sized) in STORE_BUFFERS {
            if !matches!(sized, Sized::Arena(..)) {
                continue;
            }
            let old = &store.buffers[name];
            encoder.copy_buffer_counted(old, 0, &fresh[name], 0, old.size().min(fresh[name].size()));
        }
        let lanes = capacity.arenas[A_DECLS]
            .max(capacity.arenas[A_PARAMS])
            .max(capacity.arenas[A_TERMS]) as u64;
        store.buffers = fresh;
        store.capacity = capacity;
        store.growths += 1;
        store.epoch += 1;
        let names = reflected_names(&self.rehash);
        let entries = names
            .iter()
            .map(|name| (name.as_str(), store.buffers[name.as_str()].as_entire_binding()))
            .collect::<Vec<_>>();
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&self.rehash.shader_id),
            &self.rehash,
            0,
            &entries,
        )?;
        let g = lanes.div_ceil(256).max(1);
        substitution::record_timed(
            &mut encoder,
            "program_retention.rehash",
            &[(&self.rehash, &bind, substitution::Launch::Groups(g.min(65535) as u32, g.div_ceil(65535) as u32, 1))],
        );
        self.queue.submit(Some(encoder.finish()));
        Ok(())
    }

    fn read(&self, buffer: &wgpu::Buffer, words: usize) -> Result<Vec<u32>> {
        Ok(self.read_parts(&[(buffer, words)])?.pop().unwrap_or_default())
    }

    /// The leading words of each buffer (at most its size), in one readback.
    fn read_parts(&self, parts: &[(&wgpu::Buffer, usize)]) -> Result<Vec<Vec<u32>>> {
        let sizes: Vec<u64> = parts
            .iter()
            .map(|(buffer, words)| (*words as u64 * 4).min(buffer.size()))
            .collect();
        let bytes: u64 = sizes.iter().sum();
        if bytes == 0 {
            return Ok(vec![Vec::new(); parts.len()]);
        }
        let readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("program_retention.readback"),
            size: bytes,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder = self.device.create_command_encoder(&Default::default());
        let mut at = 0;
        for ((buffer, _), size) in parts.iter().zip(&sizes) {
            if *size != 0 {
                encoder.copy_buffer_counted(buffer, 0, &readback, at, *size);
            }
            at += size;
        }
        self.queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        map_readback_blocking(&self.device, &slice, crate::readback_label!("program_retention.readback"))?;
        let words = slice
            .get_mapped_range()
            .chunks_exact(4)
            .map(|w| u32::from_le_bytes([w[0], w[1], w[2], w[3]]))
            .collect::<Vec<_>>();
        readback.unmap();
        let mut out = Vec::with_capacity(parts.len());
        let mut at = 0;
        for size in sizes {
            let n = (size / 4) as usize;
            out.push(words[at..at + n].to_vec());
            at += n;
        }
        Ok(out)
    }

    /// Runs `f` with the store's buffers and the current build generation
    /// while holding the store lock, so no export, growth or `begin_build`
    /// changes the store while a consumer records and runs. Consumers (the
    /// retained trait catalog) bind the buffers by reflected name.
    pub(crate) fn with_store_buffers<R>(
        &self,
        f: impl FnOnce(&BTreeMap<&'static str, wgpu::Buffer>, u32) -> Result<R>,
    ) -> Result<R> {
        let store = self.store.lock().unwrap();
        f(&store.buffers, store.generation)
    }

    /// The store's status words.
    pub fn status(&self) -> Result<Vec<u32>> {
        let store = self.store.lock().unwrap();
        self.read(&store.buffers["rt_counts"], counts::WORDS)
    }

    /// Reports of the jobs exported in this build.
    pub fn job_reports(&self) -> Vec<JobReport> {
        self.store.lock().unwrap().reports.clone()
    }

    /// Current capacity and how many times the store grew.
    pub fn capacity(&self) -> (ProgramRetentionCapacity, u32) {
        let store = self.store.lock().unwrap();
        (store.capacity, store.growths)
    }

    /// Test oracle: the first `words` words of a store buffer.
    #[doc(hidden)]
    pub fn read_store_words(&self, name: &str, words: usize) -> Result<Vec<u32>> {
        let store = self.store.lock().unwrap();
        let buffer = store
            .buffers
            .get(name)
            .ok_or_else(|| anyhow!("no store buffer {name}"))?;
        self.read(buffer, words)
    }

    /// Test oracle: retain an actual binding across store growth or reset.
    #[doc(hidden)]
    pub fn clone_store_buffer_for_test(&self, name: &str) -> Result<wgpu::Buffer> {
        self.store.lock().unwrap().buffers.get(name).cloned()
            .ok_or_else(|| anyhow!("no store buffer {name}"))
    }

    /// Test hook: whether exports size the store from the build's source
    /// bytes ([`source_capacity`]).
    #[doc(hidden)]
    pub fn set_source_sizing_for_test(&self, enabled: bool) {
        self.store.lock().unwrap().source_sizing = enabled;
    }

    /// Test fault: fills job table `name` of every later export's snapshot
    /// with `word` (the frontend's own tables are untouched), or clears it.
    #[doc(hidden)]
    pub fn set_export_fault(&self, fault: Option<(&'static str, u32)>) {
        *self.export_fault.lock().unwrap() = fault.map(|(name, word)| ExportFault::Fill(name, word));
    }

    /// Test fault: remove accepted call results while preserving the
    /// callee, environment and expression rows. Clear with set_export_fault(None).
    #[doc(hidden)]
    pub fn set_missing_call_results_fault(&self) {
        *self.export_fault.lock().unwrap() = Some(ExportFault::MissingCallResults);
    }

    /// Test fault: overwrites words of a store buffer from `offset` words.
    #[doc(hidden)]
    pub fn write_store_words(&self, name: &str, offset: u64, words: &[u32]) -> Result<()> {
        let store = self.store.lock().unwrap();
        let buffer = store.buffers.get(name).ok_or_else(|| anyhow!("no store buffer {name}"))?;
        self.queue.write_buffer_counted(buffer, offset * 4, &words_bytes(words));
        self.queue.submit(None);
        Ok(())
    }

    /// Trait-fact probe (shaders/tests/retention_traits.slang): reads only
    /// the store and returns `TRAIT_PROBE_WORDS` words per directory entry.
    #[doc(hidden)]
    pub fn trait_probe(&self) -> Result<Vec<u32>> {
        let mut probe = self.trait_probe.lock().unwrap();
        if probe.is_none() {
            *probe = Some(make_pass_data_from_shader_key(&self.device, TRAIT_PROBE_KERNEL, "main", TRAIT_PROBE_KERNEL)?);
        }
        let pass_data = probe.as_ref().unwrap();
        let store = self.store.lock().unwrap();
        let entries = self.read(&store.buffers["rt_counts"], counts::WORDS)?[A_DIR] as u64;
        let out = storage(&self.device, "rt_test_out", entries.max(1) * TRAIT_PROBE_WORDS as u64 * 4, false);
        let names = reflected_names(pass_data);
        let mut entries_bound = Vec::new();
        for name in &names {
            let buffer = match name.as_str() {
                "rt_test_out" => &out,
                other => store
                    .buffers
                    .get(other)
                    .ok_or_else(|| anyhow!("trait probe binds unknown buffer {other}"))?,
            };
            entries_bound.push((name.as_str(), buffer.as_entire_binding()));
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass_data.shader_id),
            pass_data,
            0,
            &entries_bound,
        )?;
        let mut encoder = self.device.create_command_encoder(&Default::default());
        substitution::record_timed(
            &mut encoder,
            "program_retention.trait_probe",
            &[(pass_data, &bind, substitution::Launch::Groups(entries.div_ceil(64).max(1) as u32, 1, 1))],
        );
        self.queue.submit(Some(encoder.finish()));
        drop(store);
        self.read(&out, entries as usize * TRAIT_PROBE_WORDS)
    }

    /// Test oracle: overwrites exporter scratch with a poison pattern, so a
    /// later read of its job maps would be visible. This does not touch the
    /// frontend's parser or type-checker storage.
    #[doc(hidden)]
    pub fn poison_scratch(&self) {
        let store = self.store.lock().unwrap();
        for buffer in store.scratch.values() {
            let words = vec![0xa5a5_a5a5u32; (buffer.size() / 4) as usize];
            self.queue.write_buffer_counted(buffer, 0, &words_bytes(&words));
        }
        self.queue.submit(None);
    }

    /// Live retained bytes from the GPU counters.
    pub fn retained_bytes(&self) -> Result<RetentionBytes> {
        let words = self.status()?;
        let store = self.store.lock().unwrap();
        let mut live = [0u64; ARENAS];
        let mut capacity = [0u64; ARENAS];
        for arena in 0..ARENAS {
            let first = match arena {
                A_DECLS | A_PARAMS => 1,
                A_TERMS => RT_FIRST_TERM,
                _ => 0,
            };
            live[arena] = words[arena].saturating_sub(first) as u64 * RECORD_BYTES[arena];
            capacity[arena] = store.capacity.arenas[arena] as u64 * RECORD_BYTES[arena];
        }
        let resident_discovery = [A_DECLS, A_PARAMS, A_TERMS, A_TERM_ARGS, A_DIR, A_BINDERS, A_SIGS, A_SCHEMA, A_USES, A_TRAITS, A_JOBS]
            .iter()
            .map(|&a| live[a])
            .sum();
        let streamable_bodies = [A_SEGMENTS, A_SEG_ROWS, A_SEG_SIDE, A_SEG_BYTES, A_SEG_TOKENS]
            .iter()
            .map(|&a| live[a])
            .sum();
        Ok(RetentionBytes {
            live,
            capacity,
            tables: store.capacity.table_bytes(),
            resident_discovery,
            streamable_bodies,
        })
    }

    /// Acceptance probe (shaders/tests/retention_resolve.slang): reads only
    /// the store and returns `PROBE_WORDS` words per committed use, then
    /// per explicit request `(callee DeclId, type argument count, argument
    /// 0, argument 1)`.
    #[doc(hidden)]
    pub fn resolve_probe(&self, requests: &[[u32; 4]]) -> Result<Vec<u32>> {
        let mut resolve = self.resolve.lock().unwrap();
        if resolve.is_none() {
            *resolve = Some(make_pass_data_from_shader_key(&self.device, RESOLVE_KERNEL, "main", RESOLVE_KERNEL)?);
        }
        let pass_data = resolve.as_ref().unwrap();
        let mut store = self.store.lock().unwrap();
        let uses = self.read(&store.buffers["rt_counts"], counts::WORDS)?[A_USES] as u64;
        let lanes = uses + requests.len() as u64;
        if store.stack_lanes < lanes.max(1) {
            store.stack_lanes = lanes.max(1).next_power_of_two();
        }
        let stack = storage(&self.device, "rt_s_stack", store.stack_lanes * 256 * 4, false);
        let out = storage(&self.device, "rt_test_out", lanes.max(1) * PROBE_WORDS as u64 * 4, false);
        let request_words = requests.iter().flatten().copied().collect::<Vec<_>>();
        let request_buffer = storage(&self.device, "rt_test_requests", (request_words.len() as u64 * 4).max(16), false);
        self.queue.write_buffer_counted(&request_buffer, 0, &words_bytes(&request_words));
        let meta = storage(&self.device, "rt_test_meta", 16, false);
        self.queue.write_buffer_counted(&meta, 0, &words_bytes(&[requests.len() as u32, 0, 0, 0]));
        let names = reflected_names(pass_data);
        let mut entries = Vec::new();
        for name in &names {
            let buffer = match name.as_str() {
                "rt_s_stack" => &stack,
                "rt_test_out" => &out,
                "rt_test_requests" => &request_buffer,
                "rt_test_meta" => &meta,
                other => store
                    .buffers
                    .get(other)
                    .ok_or_else(|| anyhow!("resolve probe binds unknown buffer {other}"))?,
            };
            entries.push((name.as_str(), buffer.as_entire_binding()));
        }
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            &self.device,
            Some(&pass_data.shader_id),
            pass_data,
            0,
            &entries,
        )?;
        let mut encoder = self.device.create_command_encoder(&Default::default());
        substitution::record_timed(
            &mut encoder,
            "program_retention.resolve",
            &[(pass_data, &bind, substitution::Launch::Groups(lanes.div_ceil(64).max(1) as u32, 1, 1))],
        );
        self.queue.submit(Some(encoder.finish()));
        drop(store);
        self.read(&out, lanes as usize * PROBE_WORDS)
    }
}

/// An export attempt submitted by [`ProgramRetention::submit_export_job`].
#[must_use]
pub(crate) struct ExportSubmitted {
    shape: ScratchShape,
}

#[derive(Clone, Copy)]
enum Dispatch {
    Direct([u32; 3]),
    Indirect(u64),
}

/// The report of an export attempt whose counters (`rt_counts`,
/// `rt_x_counts`) show that it committed.
fn committed_export(attempt: u32, words: Vec<u32>, x: &[u32]) -> Option<JobReport> {
    if words[counts::JOB_STATE] == counts::JOB_COMMITTED && crate::options::get().report.resources.is_some() {
        eprintln!(
            "[program_retention] export term_rows={} spare_term_rows={}",
            words[A_TERMS], words[counts::SPARE + A_TERMS],
        );
    }
    (words[counts::JOB_STATE] == counts::JOB_COMMITTED).then(|| JobReport {
        attempts: attempt,
        ready: words[counts::READY] != 0,
        counts: words,
        untranslated_records: x[188],
    })
}

/// The export scratch a job needs.
fn export_shape(job: &BTreeMap<&'static str, JobTable>) -> Result<ScratchShape> {
    let rows = table_words(job, "compact_hir_core")? / 4;
    let records = table_words(job, "ct_head")? / 4;
    let args = table_words(job, "ct_args")?;
    let generic = table_words(job, "compact_generic_params")? / 4;
    Ok(ScratchShape {
        rows: rows.max(1),
        records: records.max(1),
        args: args.max(1),
        param_slots: (2 * generic + rows / 4 + 64).next_power_of_two(),
        tokens: table_words(job, "decl_id_by_name_token")?.max(1),
        job_tokens: (table_words(job, "rt_job_tokens")? / 3).max(1),
    })
}

fn reflected_names(pass: &PassData) -> Vec<String> {
    let layout = pass
        .reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref());
    let parameters = match layout {
        Some(layout) => layout
            .parameters
            .first()
            .map(|set| set.parameters.as_slice())
            .unwrap_or_default(),
        None => pass.reflection.parameters.as_slice(),
    };
    parameters
        .iter()
        .filter(|p| p.binding.index.is_some() && p.ty.kind.is_some())
        .map(|p| p.name.clone())
        .collect()
}

fn table_words(job: &BTreeMap<&'static str, JobTable>, name: &str) -> Result<u64> {
    job.get(name)
        .map(|table| table.size / 4)
        .ok_or_else(|| anyhow!("program retention needs job table {name}"))
}

fn allocate_store(
    device: &wgpu::Device,
    capacity: &ProgramRetentionCapacity,
    previous: Option<&BTreeMap<&'static str, wgpu::Buffer>>,
) -> BTreeMap<&'static str, wgpu::Buffer> {
    STORE_BUFFERS
        .iter()
        .map(|&(name, sized)| {
            if matches!(sized, Sized::Fixed(_)) {
                if let Some(previous) = previous {
                    return (name, previous[name].clone());
                }
            }
            let bytes = match sized {
                Sized::Fixed(bytes) => bytes,
                Sized::Arena(arena, record) => capacity.arenas[arena] as u64 * record,
                Sized::Table(table) => capacity.slots[table] as u64 * 4,
            };
            (name, storage(device, name, bytes, false))
        })
        .collect()
}

fn allocate_scratch(device: &wgpu::Device, shape: ScratchShape) -> BTreeMap<&'static str, wgpu::Buffer> {
    let ScratchShape { rows, records, args, param_slots, tokens, .. } = shape;
    let blocks = rows.div_ceil(256).max(1);
    [
        ("rt_x_counts", X_WORDS as u64 * 4, false),
        ("rt_x_dispatch", DISPATCH_WORDS * 4, true),
        ("rt_x_param_key", param_slots * 4, false),
        ("rt_x_param_val", param_slots * 4, false),
        ("rt_x_term_map", records * 4, false),
        ("rt_x_order", records * 4, false),
        ("rt_x_args", args * 4, false),
        ("rt_x_row", rows * 16, false),
        ("rt_x_span", rows * 4, false),
        ("rt_x_stats", rows * 16, false),
        ("rt_x_flags", rows * 16, false),
        ("rt_x_scan", rows * 16, false),
        ("rt_x_blocks", blocks * 16, false),
        ("rt_x_fn_by_token", tokens * 4, false),
        ("rt_x_decl_by_token", tokens * 4, false),
        ("rt_x_seg_token", rows * 4, false),
        ("rt_x_callee", rows * 4, false),
        ("rt_x_tflags", rows * 16, false),
        ("rt_x_tscan", rows * 16, false),
        ("rt_x_tblocks", blocks * 16, false),
        ("rt_x_tcounts", X_WORDS as u64 * 4, false),
    ]
    .into_iter()
    .map(|(name, bytes, indirect)| (name, storage(device, name, bytes, indirect)))
    .collect()
}

/// Records per KiB of source that the store holds for a build, per arena:
/// about twice what the settings program's jobs export (1.75 MiB of source,
/// 2026-11-17), so a build of similar density fits without growing. A
/// denser build overflows, rolls back on the GPU and runs its job again in a
/// store grown from the recorded demand ([`grown_capacity`]).
const RECORDS_PER_SOURCE_KIB: [u32; ARENAS] = [8, 2, 24, 20, 8, 2, 16, 5, 24, 1, 32, 10, 64, 72, 1, 0];

/// The store's capacity for a build whose jobs lexed `source_bytes` bytes
/// in `exports` exports so far: never below `current`.
fn source_capacity(current: &ProgramRetentionCapacity, source_bytes: u64, exports: u32) -> ProgramRetentionCapacity {
    let mut next = *current;
    let kib = source_bytes.div_ceil(1024);
    for arena in 0..ARENAS {
        let records = (kib * u64::from(RECORDS_PER_SOURCE_KIB[arena])).min(u64::from(u32::MAX / 4)) as u32;
        next.arenas[arena] = next.arenas[arena].max(records);
    }
    next.arenas[A_JOBS] = next.arenas[A_JOBS].max(exports.saturating_mul(2));
    for (table, arena) in [A_DECLS, A_PARAMS, A_TERMS].into_iter().enumerate() {
        let need = (u64::from(next.arenas[arena]) * 2).next_power_of_two().min(1 << 30) as u32;
        next.slots[table] = next.slots[table].max(need);
    }
    next
}

/// Capacity covering a rolled-back job's recorded demand, with headroom.
fn grown_capacity(current: &ProgramRetentionCapacity, words: &[u32]) -> ProgramRetentionCapacity {
    let mut next = *current;
    let overflow = words[counts::OVERFLOW];
    for arena in 0..ARENAS {
        if overflow & (1 << arena) != 0 {
            let demand = words[counts::DEMAND + arena].max(current.arenas[arena] + 1);
            next.arenas[arena] = (demand as u64 * 2).min(u32::MAX as u64 / 2) as u32;
        }
    }
    // A table holds at most its arena's records; keep it at least twice that.
    for (table, (arena, bit)) in [
        (A_DECLS, counts::OVERFLOW_DECL_TABLE),
        (A_PARAMS, counts::OVERFLOW_PARAM_TABLE),
        (A_TERMS, counts::OVERFLOW_TERM_TABLE),
    ]
    .into_iter()
    .enumerate()
    {
        let need = (next.arenas[arena] as u64 * 2).next_power_of_two() as u32;
        if overflow & bit != 0 {
            next.slots[table] = next.slots[table].saturating_mul(2).max(need);
        } else {
            next.slots[table] = next.slots[table].max(need);
        }
    }
    next
}

fn words_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|w| w.to_le_bytes()).collect()
}
