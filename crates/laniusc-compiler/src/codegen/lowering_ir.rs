//! GPU-resident lowering contracts between compact semantic HIR and targets.

use encase::ShaderType;

use crate::gpu::{
    compiler_graph::{
        CompilerGraph,
        CompilerGraphBuilder,
        CompilerPhase,
        PassAccess,
        PassDesc,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
        ResourceId,
    },
    workspace::WorkspaceUsageClass,
};

/// Constants generated from `shaders/codegen/lowering_ir.slang`.
pub mod opcode {
    include!(concat!(env!("OUT_DIR"), "/lowering_ir_opcodes.rs"));
}

/// Target-independent runtime service selected by checked semantic lowering.
///
/// Values intentionally match the canonical builtin-symbol slots consumed by
/// type checking. Targets lower this enum to syscalls, runtime thunks, or Wasm
/// imports; they never rediscover a service from source text.
#[repr(u32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HostService {
    OpenReadPath = opcode::HOST_SERVICE_OPEN_READ_PATH,
    OpenWritePath = opcode::HOST_SERVICE_OPEN_WRITE_PATH,
    ReadI32 = opcode::HOST_SERVICE_READ_I32,
    WriteText = opcode::HOST_SERVICE_WRITE_TEXT,
    WriteI32 = opcode::HOST_SERVICE_WRITE_I32,
    WriteByte = opcode::HOST_SERVICE_WRITE_BYTE,
    WriteNewline = opcode::HOST_SERVICE_WRITE_NEWLINE,
    CloseFile = opcode::HOST_SERVICE_CLOSE_FILE,
    I32ToF32 = opcode::HOST_SERVICE_I32_TO_F32,
    Exit = opcode::HOST_SERVICE_EXIT,
    SecureU32 = opcode::HOST_SERVICE_SECURE_U32,
    Alloc = opcode::HOST_SERVICE_ALLOC,
    Dealloc = opcode::HOST_SERVICE_DEALLOC,
    Argc = opcode::HOST_SERVICE_ARGC,
    ArgLen = opcode::HOST_SERVICE_ARG_LEN,
    ArgRead = opcode::HOST_SERVICE_ARG_READ,
    UnixSeconds = opcode::HOST_SERVICE_UNIX_SECONDS,
    CurrentDirRead = opcode::HOST_SERVICE_CURRENT_DIR_READ,
    VarCount = opcode::HOST_SERVICE_VAR_COUNT,
    VarKeyLen = opcode::HOST_SERVICE_VAR_KEY_LEN,
    VarKeyRead = opcode::HOST_SERVICE_VAR_KEY_READ,
    VarLen = opcode::HOST_SERVICE_VAR_LEN,
    VarRead = opcode::HOST_SERVICE_VAR_READ,
    Close = opcode::HOST_SERVICE_CLOSE,
    Read = opcode::HOST_SERVICE_READ,
    Write = opcode::HOST_SERVICE_WRITE,
    OpenRead = opcode::HOST_SERVICE_OPEN_READ,
    OpenWrite = opcode::HOST_SERVICE_OPEN_WRITE,
    OpenAppend = opcode::HOST_SERVICE_OPEN_APPEND,
    WriteStdout = opcode::HOST_SERVICE_WRITE_STDOUT,
    WriteStderr = opcode::HOST_SERVICE_WRITE_STDERR,
    ReadStdin = opcode::HOST_SERVICE_READ_STDIN,
    FillSecureBytes = opcode::HOST_SERVICE_FILL_SECURE_BYTES,
    RemoveFile = opcode::HOST_SERVICE_REMOVE_FILE,
    CreateDir = opcode::HOST_SERVICE_CREATE_DIR,
    RemoveDir = opcode::HOST_SERVICE_REMOVE_DIR,
    Rename = opcode::HOST_SERVICE_RENAME,
    MonotonicRead = opcode::HOST_SERVICE_MONOTONIC_READ,
    SystemRead = opcode::HOST_SERVICE_SYSTEM_READ,
    SleepMsI32 = opcode::HOST_SERVICE_SLEEP_MS_I32,
    Realloc = opcode::HOST_SERVICE_REALLOC,
    AllocFailed = opcode::HOST_SERVICE_ALLOC_FAILED,
}

impl HostService {
    pub const fn symbol_slot(self) -> u32 {
        self as u32
    }

    pub fn from_symbol_slot(slot: u32) -> Option<Self> {
        Some(match slot {
            opcode::HOST_SERVICE_OPEN_READ_PATH => Self::OpenReadPath,
            opcode::HOST_SERVICE_OPEN_WRITE_PATH => Self::OpenWritePath,
            opcode::HOST_SERVICE_READ_I32 => Self::ReadI32,
            opcode::HOST_SERVICE_WRITE_TEXT => Self::WriteText,
            opcode::HOST_SERVICE_WRITE_I32 => Self::WriteI32,
            opcode::HOST_SERVICE_WRITE_BYTE => Self::WriteByte,
            opcode::HOST_SERVICE_WRITE_NEWLINE => Self::WriteNewline,
            opcode::HOST_SERVICE_CLOSE_FILE => Self::CloseFile,
            opcode::HOST_SERVICE_I32_TO_F32 => Self::I32ToF32,
            opcode::HOST_SERVICE_EXIT => Self::Exit,
            opcode::HOST_SERVICE_SECURE_U32 => Self::SecureU32,
            opcode::HOST_SERVICE_ALLOC => Self::Alloc,
            opcode::HOST_SERVICE_DEALLOC => Self::Dealloc,
            opcode::HOST_SERVICE_ARGC => Self::Argc,
            opcode::HOST_SERVICE_ARG_LEN => Self::ArgLen,
            opcode::HOST_SERVICE_ARG_READ => Self::ArgRead,
            opcode::HOST_SERVICE_UNIX_SECONDS => Self::UnixSeconds,
            opcode::HOST_SERVICE_CURRENT_DIR_READ => Self::CurrentDirRead,
            opcode::HOST_SERVICE_VAR_COUNT => Self::VarCount,
            opcode::HOST_SERVICE_VAR_KEY_LEN => Self::VarKeyLen,
            opcode::HOST_SERVICE_VAR_KEY_READ => Self::VarKeyRead,
            opcode::HOST_SERVICE_VAR_LEN => Self::VarLen,
            opcode::HOST_SERVICE_VAR_READ => Self::VarRead,
            opcode::HOST_SERVICE_CLOSE => Self::Close,
            opcode::HOST_SERVICE_READ => Self::Read,
            opcode::HOST_SERVICE_WRITE => Self::Write,
            opcode::HOST_SERVICE_OPEN_READ => Self::OpenRead,
            opcode::HOST_SERVICE_OPEN_WRITE => Self::OpenWrite,
            opcode::HOST_SERVICE_OPEN_APPEND => Self::OpenAppend,
            opcode::HOST_SERVICE_WRITE_STDOUT => Self::WriteStdout,
            opcode::HOST_SERVICE_WRITE_STDERR => Self::WriteStderr,
            opcode::HOST_SERVICE_READ_STDIN => Self::ReadStdin,
            opcode::HOST_SERVICE_FILL_SECURE_BYTES => Self::FillSecureBytes,
            opcode::HOST_SERVICE_REMOVE_FILE => Self::RemoveFile,
            opcode::HOST_SERVICE_CREATE_DIR => Self::CreateDir,
            opcode::HOST_SERVICE_REMOVE_DIR => Self::RemoveDir,
            opcode::HOST_SERVICE_RENAME => Self::Rename,
            opcode::HOST_SERVICE_MONOTONIC_READ => Self::MonotonicRead,
            opcode::HOST_SERVICE_SYSTEM_READ => Self::SystemRead,
            opcode::HOST_SERVICE_SLEEP_MS_I32 => Self::SleepMsI32,
            opcode::HOST_SERVICE_REALLOC => Self::Realloc,
            opcode::HOST_SERVICE_ALLOC_FAILED => Self::AllocFailed,
            _ => return None,
        })
    }
}

/// Resident schedule keys contain three packed `u32` words. The default
/// five-MiB frontend-unit bound needs at most 72 significant bits, including
/// the expression-tie and sentinel encodings.
pub(crate) const TARGET_SCHEDULE_MAX_RADIX_STEPS: u32 = 9;

/// Capacity-derived bit layout for the semantic schedule key.
///
/// The three ordering fields are packed into one continuous LSD bit stream instead of
/// rounding each field independently to bytes. Expression ties occupy the
/// source representation's high `0x7fff_ffff - depth` band; the radix key
/// extractor maps that band above all ordinary local-row ties and below the
/// `u32::MAX` sentinel. Function identity is intentionally absent: compact HIR
/// functions follow flat source order, every execution region is a global
/// packed-token position inside its owning function's source span, and those
/// spans do not overlap. Region order therefore already partitions and orders
/// functions. Digit zero initializes the identity order in whichever ping-pong
/// buffer makes the last scatter finish in the canonical order.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct TargetScheduleRadixLayout {
    pub(crate) packed_bits: u32,
    pub(crate) steps: u32,
    pub(crate) total_bits: u32,
}

impl TargetScheduleRadixLayout {
    pub(crate) fn for_capacities(capacities: LoweringCapacities) -> Self {
        let token_or_hir = capacities.tokens.max(capacities.hir_nodes);
        let ordinary_tie_capacity = capacities.semantic_instructions.max(token_or_hir);
        let bits = [
            radix_bits_for_capacity(ordinary_tie_capacity.saturating_add(capacities.hir_nodes)),
            radix_bits_for_capacity(token_or_hir),
            radix_bits_for_capacity(token_or_hir),
        ];
        let total_bits = bits.iter().copied().sum::<u32>();
        let steps = total_bits.div_ceil(8);
        let packed_bits = (1u32 << 31) | bits[0] | (bits[1] << 6) | (bits[2] << 12);
        debug_assert!(steps > 0);
        Self {
            packed_bits,
            steps,
            total_bits,
        }
    }

    #[cfg(test)]
    pub(crate) const fn packed_width() -> Self {
        Self {
            packed_bits: (1 << 31) | 24 | (24 << 6) | (24 << 12),
            steps: TARGET_SCHEDULE_MAX_RADIX_STEPS,
            total_bits: 72,
        }
    }
}

fn radix_bits_for_capacity(capacity: u32) -> u32 {
    (u32::BITS - capacity.leading_zeros()).max(1)
}

/// Number of target-independent instructions processed by one lowering
/// dispatch. The logical stream may contain any number of pages. One million
/// rows remains comfortably below the two-dimensional dispatch limit while
/// avoiding hundreds of tiny page dispatches for ordinary compilation units.
pub(crate) const SEMANTIC_LIR_PAGE_ROWS: u32 = 1_048_576;
/// Target instructions are replayable: only this many complete target records
/// are resident while counting bytes or emitting the final artifact. Each
/// target record table uses 16 MiB at this page size, below WebGPU's minimum
/// 128 MiB storage-buffer binding limit, while global counts and offsets remain
/// compact arrays.
pub(crate) const TARGET_LIR_PAGE_ROWS: u32 = 1_048_576;
#[derive(Clone, Copy)]
struct WasmAbiGraphResources {
    param_widths: ResourceId,
    param_prefix: ResourceId,
    param_scan_local: ResourceId,
    param_scan_block_sum: ResourceId,
    param_scan_block_prefix: ResourceId,
    param_scan_hierarchy: ResourceId,
    param_value_total: ResourceId,
    local_widths: ResourceId,
    local_prefix: ResourceId,
    local_scan_local: ResourceId,
    local_scan_block_sum: ResourceId,
    local_scan_block_prefix: ResourceId,
    local_scan_hierarchy: ResourceId,
    local_value_total: ResourceId,
    functions: ResourceId,
    local_index_by_token: ResourceId,
}

#[derive(Clone, Copy)]
struct WasmModuleGraphResources {
    type_lengths: ResourceId,
    type_offsets: ResourceId,
    type_scan_local: ResourceId,
    type_scan_block_sum: ResourceId,
    type_scan_block_prefix: ResourceId,
    type_scan_hierarchy: ResourceId,
    type_total: ResourceId,
    code_lengths: ResourceId,
    code_offsets: ResourceId,
    code_scan_local: ResourceId,
    code_scan_block_sum: ResourceId,
    code_scan_block_prefix: ResourceId,
    code_scan_hierarchy: ResourceId,
    code_total: ResourceId,
    entrypoint_state: ResourceId,
    layout: ResourceId,
    module_length: ResourceId,
    module_bytes: ResourceId,
    module_length_readback: Option<ResourceId>,
}

#[derive(Clone, Copy)]
struct WasmObjectGraphResources {
    relocation_flags: ResourceId,
    relocation_prefix: ResourceId,
    relocation_scan_local: ResourceId,
    relocation_scan_block_sum: ResourceId,
    relocation_scan_block_prefix: ResourceId,
    relocation_scan_hierarchy: ResourceId,
    relocation_total: ResourceId,
    symbol_flags: ResourceId,
    symbol_prefix: ResourceId,
    symbol_scan_local: ResourceId,
    symbol_scan_block_sum: ResourceId,
    symbol_scan_block_prefix: ResourceId,
    symbol_scan_hierarchy: ResourceId,
    symbol_total: ResourceId,
    definition_flags: ResourceId,
    definition_prefix: ResourceId,
    definition_scan_local: ResourceId,
    definition_scan_block_sum: ResourceId,
    definition_scan_block_prefix: ResourceId,
    definition_scan_hierarchy: ResourceId,
    definition_total: ResourceId,
    relocations: ResourceId,
    functions: ResourceId,
    definitions: ResourceId,
    type_bytes: ResourceId,
    body_bytes: ResourceId,
    data_bytes: ResourceId,
    metadata_readback: ResourceId,
}

#[derive(Clone, Copy)]
struct X86ObjectGraphResources {
    relocation_flags: ResourceId,
    relocation_prefix: ResourceId,
    relocation_scan_local: ResourceId,
    relocation_scan_block_sum: ResourceId,
    relocation_scan_block_prefix: ResourceId,
    relocation_scan_hierarchy: ResourceId,
    relocation_total: ResourceId,
    symbol_flags: ResourceId,
    symbol_prefix: ResourceId,
    symbol_scan_local: ResourceId,
    symbol_scan_block_sum: ResourceId,
    symbol_scan_block_prefix: ResourceId,
    symbol_scan_hierarchy: ResourceId,
    symbol_total: ResourceId,
    definition_flags: ResourceId,
    definition_prefix: ResourceId,
    definition_scan_local: ResourceId,
    definition_scan_block_sum: ResourceId,
    definition_scan_block_prefix: ResourceId,
    definition_scan_hierarchy: ResourceId,
    definition_total: ResourceId,
    relocations: ResourceId,
    undefined_symbols: ResourceId,
    definitions: ResourceId,
    text_bytes: ResourceId,
    rodata_bytes: ResourceId,
    metadata_readback: ResourceId,
}

#[derive(Clone, Copy)]
struct X86ArtifactGraphResources {
    body_length: ResourceId,
    entrypoint_state: ResourceId,
    layout: ResourceId,
    artifact_length: ResourceId,
    artifact_bytes: ResourceId,
    artifact_length_readback: Option<ResourceId>,
}

#[derive(Clone, Copy)]
struct ScheduleGraphResources {
    total: ResourceId,
    keys: ResourceId,
    order: ResourceId,
    order_tmp: ResourceId,
    slot_count: ResourceId,
    histogram: ResourceId,
    global_prefix: ResourceId,
    scan_local: ResourceId,
    scan_block_sum: ResourceId,
    scan_block_prefix: ResourceId,
    scan_hierarchy: ResourceId,
    scan_total: ResourceId,
}

fn add_schedule_graph_passes(
    graph: &mut CompilerGraphBuilder,
    phase: CompilerPhase,
    domain: ResourceDomain,
    resources: ScheduleGraphResources,
    radix_steps: u32,
) -> Result<(), String> {
    let names = [
        "lir.semantic.schedule.histogram.even",
        "lir.semantic.schedule.scan.local.even",
        "lir.semantic.schedule.scan.hierarchy_up.even",
        "lir.semantic.schedule.scan.hierarchy_down.even",
        "lir.semantic.schedule.scan.apply.even",
        "lir.semantic.schedule.scatter.even",
        "lir.semantic.schedule.histogram.odd",
        "lir.semantic.schedule.scan.local.odd",
        "lir.semantic.schedule.scan.hierarchy_up.odd",
        "lir.semantic.schedule.scan.hierarchy_down.odd",
        "lir.semantic.schedule.scan.apply.odd",
        "lir.semantic.schedule.scatter.odd",
    ];
    let mut directions = Vec::with_capacity(2);
    for base in [0usize, 6usize] {
        let (order_in, order_out) = if base == 0 {
            (resources.order, resources.order_tmp)
        } else {
            (resources.order_tmp, resources.order)
        };
        directions.push([
            PassDesc {
                name: names[base],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("target_lir_total", resources.total),
                    PassAccess::read("target_schedule_key", resources.keys),
                    PassAccess::initialize_read_write("target_schedule_order_in", order_in),
                    PassAccess::write("target_schedule_slot_count", resources.slot_count),
                    PassAccess::write("target_schedule_histogram", resources.histogram),
                ],
            },
            PassDesc {
                name: names[base + 1],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read("scan_input", resources.histogram),
                    PassAccess::write("scan_local_prefix", resources.scan_local),
                    PassAccess::write("scan_block_sum", resources.scan_block_sum),
                ],
            },
            PassDesc {
                name: names[base + 2],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read("scan_block_sum", resources.scan_block_sum),
                    PassAccess::write("scan_block_prefix", resources.scan_block_prefix),
                    PassAccess::write("scan_hierarchy", resources.scan_hierarchy),
                ],
            },
            PassDesc {
                name: names[base + 3],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read_write("scan_block_prefix", resources.scan_block_prefix),
                    PassAccess::read_write("scan_hierarchy", resources.scan_hierarchy),
                ],
            },
            PassDesc {
                name: names[base + 4],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("scan_count", resources.slot_count),
                    PassAccess::read("scan_local_prefix", resources.scan_local),
                    PassAccess::read("scan_block_prefix", resources.scan_block_prefix),
                    PassAccess::write("scan_output_prefix", resources.global_prefix),
                    PassAccess::write("scan_total", resources.scan_total),
                ],
            },
            PassDesc {
                name: names[base + 5],
                phase,
                dispatch_domain: domain,
                accesses: vec![
                    PassAccess::read("target_lir_total", resources.total),
                    PassAccess::read("target_schedule_key", resources.keys),
                    PassAccess::read("target_schedule_order_in", order_in),
                    PassAccess::read("target_schedule_global_prefix", resources.global_prefix),
                    PassAccess::write("target_schedule_order_out", order_out),
                ],
            },
        ]);
    }
    let mut body = Vec::with_capacity(12);
    let starts_in_temporary = radix_steps % 2 != 0;
    if starts_in_temporary {
        body.extend(directions[1].clone());
        body.extend(directions[0].clone());
    } else {
        body.extend(directions[0].clone());
        body.extend(directions[1].clone());
    }
    graph.add_repeated_region(radix_steps.div_ceil(2), body)?;
    Ok(())
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirCore {
    pub type_id: u32,
    pub type_ref_payload: u32,
    pub flags: u32,
    pub value_word_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirOperands {
    pub result: u32,
    pub a: u32,
    pub b: u32,
    pub c: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirCallArg {
    pub call_instruction: u32,
    pub value_instruction: u32,
    pub ordinal: u32,
    pub value_metadata: u32,
}

/// One variable-length aggregate member. Array elements and named struct
/// fields share this representation; `name_token` is INVALID for arrays.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirAggregateElement {
    pub aggregate_instruction: u32,
    pub value_instruction: u32,
    pub ordinal: u32,
    pub name_token: u32,
    pub value_metadata: u32,
    pub word_offset: u32,
    pub word_count: u32,
}

/// A decoded string literal retained independently of compact HIR. The byte
/// range addresses `GpuSemanticLirView::string_data_words`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirString {
    pub instruction: u32,
    pub data_offset: u32,
    pub decoded_len: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirFunction {
    pub hir_function: u32,
    pub name_token: u32,
    pub param_start: u32,
    pub param_count: u32,
    pub result_type: u32,
    pub flags: u32,
    pub file_id: u32,
    pub local_start: u32,
    pub local_count: u32,
    /// Number of target-independent 32-bit words in an aggregate result.
    /// Zero denotes a scalar/void result. This is semantic ABI metadata, not
    /// a target-specific stack layout.
    pub result_word_count: u32,
    /// Stable declaration index in this unit's persisted semantic interface,
    /// or `u32::MAX` for a private/non-exported function.
    pub symbol_local_index: u32,
    pub symbol_flags: u32,
    /// Canonical runtime host-service identity, or `u32::MAX`.
    pub host_service: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirParam {
    pub function_id: u32,
    pub declaration_id: u32,
    pub ordinal: u32,
    pub type_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct SemanticLirLocal {
    pub function_id: u32,
    pub declaration_id: u32,
    pub ordinal: u32,
    pub type_id: u32,
}

/// GPU-derived semantic interval needed to produce one target page.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct TargetSemanticPage {
    pub semantic_start: u32,
    pub semantic_count: u32,
    pub target_start: u32,
    pub target_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct LoweringStatus {
    pub flags: u32,
    pub first_unsupported_hir: u32,
    pub required_capacity: u32,
    pub available_capacity: u32,
    pub diagnostic_reason: u32,
    pub diagnostic_detail_kind: u32,
    pub diagnostic_detail: u32,
    pub diagnostic_aux: u32,
}

pub(crate) const LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_PARAMETERS: u32 = 1;
pub(crate) const LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_AGGREGATE_RETURN: u32 = 2;
pub(crate) const LOWERING_DIAGNOSTIC_X86_PARAMETER_REGISTERS: u32 = 3;
pub(crate) const LOWERING_DIAGNOSTIC_X86_CALL_ABI: u32 = 4;
pub(crate) const LOWERING_DIAGNOSTIC_MISSING_ENTRYPOINT: u32 = 5;
pub(crate) const LOWERING_DIAGNOSTIC_MULTIPLE_ENTRYPOINTS: u32 = 6;
pub(crate) const LOWERING_DIAGNOSTIC_X86_FOR_ITERABLE: u32 = 7;
pub(crate) const LOWERING_DIAGNOSTIC_X86_ZERO_DIVISOR: u32 = 8;
pub(crate) const LOWERING_DIAGNOSTIC_X86_ARRAY_INDEX_BOUNDS: u32 = 9;
pub(crate) const LOWERING_DIAGNOSTIC_X86_DYNAMIC_ARRAY_INDEX: u32 = 10;
pub(crate) const LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_CALL: u32 = 11;
pub(crate) const LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_TRAP: u32 = 12;
pub(crate) const LOWERING_DIAGNOSTIC_X86_MATCH_EXPRESSION: u32 = 13;
pub(crate) const LOWERING_DIAGNOSTIC_DETAIL_TOKEN: u32 = 1;
pub(crate) const LOWERING_DIAGNOSTIC_DETAIL_HIR: u32 = 2;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct TargetScheduleKey {
    pub word0: u32,
    pub word1: u32,
    pub word2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct TargetLirFunction {
    pub function_id: u32,
    pub instruction_start: u32,
    pub instruction_count: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86LirCore {
    pub source_hir: u32,
    pub local_ordinal: u32,
    pub op: u32,
    pub result_or_target: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86LirOperands {
    pub a: u32,
    pub b: u32,
    pub c: u32,
    pub metadata: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86LirLocations {
    pub result: u32,
    pub a: u32,
    pub b: u32,
    pub c: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86SelectInfo {
    pub condition: u32,
    pub true_value: u32,
    pub false_value: u32,
    pub declaration: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86DeclarationAnalysis {
    pub last_read: u32,
    pub last_access: u32,
    pub definition: u32,
    pub read_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86FunctionRegisterAnalysis {
    pub first_call: u32,
    pub first_rdx_clobber: u32,
    pub first_rcx_clobber: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86ValueAnalysis {
    pub value: u32,
    pub known: u32,
    pub replacement: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmLirInstruction {
    pub opcode: u32,
    pub immediate: u32,
    pub semantic_instruction: u32,
    pub flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmLirOperands {
    pub a: u32,
    pub b: u32,
    pub c: u32,
    pub metadata: u32,
}

/// Target-specialized function record. Source-level parameters and locals
/// remain addressable through the semantic family ranges while the value
/// counts reflect Wasm ABI expansion (for example, strings occupy two i32s).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmLirFunction {
    pub semantic_function: u32,
    pub type_index: u32,
    pub param_value_count: u32,
    pub local_value_count: u32,
    pub body_instruction_start: u32,
    pub body_instruction_count: u32,
    pub body_byte_start: u32,
    pub body_byte_count: u32,
    pub flags: u32,
    pub result_type: u32,
    pub param_start: u32,
    pub param_count: u32,
    pub local_start: u32,
    pub local_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmModuleLayout {
    pub function_count: u32,
    pub entrypoint_count: u32,
    pub entrypoint_id: u32,
    pub status: u32,
    pub module_length: u32,
    pub type_section_start: u32,
    pub type_entries_start: u32,
    pub type_entries_length: u32,
    pub function_section_start: u32,
    pub function_entries_start: u32,
    pub export_section_start: u32,
    pub code_section_start: u32,
    pub code_entries_start: u32,
    pub code_entries_length: u32,
    pub reserved0: u32,
    pub reserved1: u32,
}

/// One compact relocation emitted by the graph-native Wasm object projector.
/// The final three identity words are meaningful only for `target_kind == 2`;
/// keeping them in the row makes every relocation self-contained until symbol
/// table serialization.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmObjectRelocationRow {
    pub body_byte_offset: u32,
    pub target_kind: u32,
    pub target_index: u32,
    pub addend: u32,
    pub library_id: u32,
    pub unit_id: u32,
    pub local_index: u32,
    pub reserved: u32,
}

/// Directly serializable per-function columns for a relocatable Wasm object.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmObjectFunctionRow {
    pub type_byte_start: u32,
    pub type_byte_len: u32,
    pub body_byte_start: u32,
    pub body_byte_len: u32,
    pub symbol_index: u32,
    pub flags: u32,
}

/// One compact definition. Identity is an exact source-pack coordinate rather
/// than a token/name recovered by the host after lowering.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct WasmObjectDefinitionRow {
    pub library_id: u32,
    pub unit_id: u32,
    pub local_index: u32,
    pub function_index: u32,
    pub size: u32,
    pub flags: u32,
    pub reserved0: u32,
    pub reserved1: u32,
}

/// One normalized x86 object relocation. The row matches the durable object
/// contract directly, including the signed 64-bit addend split into words.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86ObjectRelocationRow {
    pub kind: u32,
    pub site_section: u32,
    pub site_offset: u32,
    pub target_kind: u32,
    pub target_index: u32,
    pub target_offset: u32,
    pub addend_lo: u32,
    pub addend_hi: u32,
}

/// One compact x86 definition. Undefined call symbols are represented by the
/// corresponding relocation row identity; this table contains definitions
/// owned by the current compilation unit.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86ObjectDefinitionRow {
    pub library_id: u32,
    pub unit_id: u32,
    pub local_index: u32,
    pub section: u32,
    pub offset: u32,
    pub size: u32,
    pub flags: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86ObjectUndefinedRow {
    pub library_id: u32,
    pub unit_id: u32,
    pub local_index: u32,
    pub reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, ShaderType)]
pub struct X86ArtifactLayout {
    pub body_length: u32,
    pub file_length: u32,
    pub entrypoint_count: u32,
    pub entrypoint_function: u32,
    pub entrypoint_body_offset: u32,
    pub text_offset: u32,
    pub body_offset: u32,
    pub status: u32,
    pub runtime_offset: u32,
    pub runtime_length: u32,
    pub rodata_offset: u32,
    pub rodata_length: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LoweringTarget {
    X86_64,
    Wasm,
}

/// Artifact boundary requested from one lowering job.
///
/// Executable and relocatable-object projection share semantic and target LIR,
/// but their retained output tables are mutually exclusive. Keeping this in
/// the graph key prevents an executable request from reserving object storage.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum LoweringArtifactKind {
    Executable,
    Object,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LoweringCapacities {
    pub source_bytes: u32,
    pub tokens: u32,
    pub hir_nodes: u32,
    pub semantic_instructions: u32,
    pub call_arguments: u32,
    pub parameters: u32,
    pub aggregate_elements: u32,
    pub target_instructions: u32,
    pub artifact_bytes: u32,
}

impl LoweringCapacities {
    const REUSE_GRANULARITY: u32 = 4 * 1024;

    fn capacity_bucket(value: u32) -> u32 {
        value
            .max(1)
            .div_ceil(Self::REUSE_GRANULARITY)
            .saturating_mul(Self::REUSE_GRANULARITY)
    }

    pub(crate) fn bucketed(self) -> Self {
        Self {
            source_bytes: Self::capacity_bucket(self.source_bytes),
            tokens: Self::capacity_bucket(self.tokens),
            hir_nodes: Self::capacity_bucket(self.hir_nodes),
            semantic_instructions: Self::capacity_bucket(self.semantic_instructions),
            call_arguments: Self::capacity_bucket(self.call_arguments),
            parameters: Self::capacity_bucket(self.parameters),
            aggregate_elements: Self::capacity_bucket(self.aggregate_elements),
            target_instructions: Self::capacity_bucket(self.target_instructions),
            artifact_bytes: Self::capacity_bucket(self.artifact_bytes),
        }
    }

    fn bytes<T>(count: u32) -> u64 {
        u64::from(count.max(1)) * std::mem::size_of::<T>() as u64
    }

    /// Dense semantic-local rows. A match expression owns three compiler
    /// locals (result, scrutinee, and first-match state), which is the widest
    /// per-HIR local recipe. Keeping this bound in one place prevents target
    /// backends from silently allocating different declaration domains.
    pub(crate) fn local_capacity(self) -> u32 {
        self.hir_nodes.saturating_mul(3).max(1)
    }

    /// Source-token declarations followed by the three disjoint synthetic
    /// declaration bands used by semantic lowering.
    pub(crate) fn declaration_capacity(self) -> u32 {
        self.tokens
            .saturating_add(self.hir_nodes.saturating_mul(3))
            .max(1)
    }

    pub(crate) fn covers(self, required: Self) -> bool {
        self.source_bytes >= required.source_bytes
            && self.tokens >= required.tokens
            && self.hir_nodes >= required.hir_nodes
            && self.semantic_instructions >= required.semantic_instructions
            && self.call_arguments >= required.call_arguments
            && self.parameters >= required.parameters
            && self.aggregate_elements >= required.aggregate_elements
            && self.target_instructions >= required.target_instructions
            && self.artifact_bytes >= required.artifact_bytes
    }

    pub(crate) fn grow_to_cover(self, required: Self) -> Self {
        let grow = |current: u32, needed: u32| Self::capacity_bucket(needed.max(current));
        Self {
            source_bytes: grow(self.source_bytes, required.source_bytes),
            tokens: grow(self.tokens, required.tokens),
            hir_nodes: grow(self.hir_nodes, required.hir_nodes),
            semantic_instructions: grow(self.semantic_instructions, required.semantic_instructions),
            call_arguments: grow(self.call_arguments, required.call_arguments),
            parameters: grow(self.parameters, required.parameters),
            aggregate_elements: grow(self.aggregate_elements, required.aggregate_elements),
            target_instructions: grow(self.target_instructions, required.target_instructions),
            artifact_bytes: grow(self.artifact_bytes, required.artifact_bytes),
        }
    }

    /// Derives lossless lowering capacities from the bounded frontend unit.
    /// These factors are structural upper bounds of the current IR contracts,
    /// not workload guesses. Although one range-loop owner expands to
    /// seventeen semantic rows, it necessarily owns three distinct compact-HIR
    /// rows: the range expression and its two endpoint roots. Those four rows
    /// produce at most twenty semantic rows together. Other structured control
    /// forms have smaller owner/child ratios. A match with N arms owns at
    /// least its scrutinee plus N distinct pattern rows and N distinct result
    /// roots; its first-match recipe therefore remains below seven semantic
    /// rows per compact-HIR row. Target bounds are likewise
    /// coupled over distinct HIR owners and edges instead of adding mutually
    /// exclusive maxima:
    ///
    /// - x86 match lowering retains at most twelve target rows per arm and
    ///   therefore remains below seven target rows per HIR row;
    /// - Wasm aggregate lowering owns six rows per distinct element edge plus
    ///   five rows per owner. With at most one incoming aggregate edge per HIR
    ///   row and at most two ordinary rows for every non-owner, this is bounded
    ///   by eight target rows per HIR row;
    /// - call-argument and aggregate-element side rows are source-tree edges.
    ///   Every such edge has a distinct child HIR row, so their expansions do
    ///   not add another whole-HIR maximum on top of the range-loop maximum.
    ///
    /// These remain logical stream bounds; converting them to fixed resident
    /// pages is required before large-unit production use.
    pub fn from_frontend_unit(
        source_bytes: u32,
        token_capacity: u32,
        hir_capacity: u32,
        target: LoweringTarget,
    ) -> Result<Self, String> {
        let multiply = |value: u32, factor: u32, label: &str| {
            value.checked_mul(factor).ok_or_else(|| {
                format!("{label} capacity overflows u32 for a {value}-row frontend unit")
            })
        };
        let add = |left: u32, right: u32, label: &str| {
            left.checked_add(right)
                .ok_or_else(|| format!("{label} capacity overflows u32 for this frontend unit"))
        };
        let hir_nodes = hir_capacity.max(1);
        let semantic_instructions = multiply(hir_nodes, 7, "semantic instruction")?;
        let call_arguments = hir_nodes;
        let aggregate_elements = hir_nodes;
        let target_instructions = multiply(
            hir_nodes,
            match target {
                LoweringTarget::X86_64 => 7,
                LoweringTarget::Wasm => 8,
            },
            "target instruction",
        )?;
        let target_bytes = multiply(
            target_instructions,
            match target {
                LoweringTarget::X86_64 => 16,
                LoweringTarget::Wasm => 8,
            },
            "target artifact",
        )?;
        let table_bytes = multiply(hir_nodes, 32, "artifact table")?;
        let artifact_bytes = add(
            add(source_bytes.max(4), target_bytes, "artifact")?,
            add(table_bytes, 4096, "artifact")?,
            "artifact",
        )?;
        Ok(Self {
            source_bytes: source_bytes.max(4),
            tokens: token_capacity.max(1),
            hir_nodes,
            semantic_instructions,
            call_arguments,
            parameters: hir_nodes,
            aggregate_elements,
            target_instructions,
            artifact_bytes,
        })
    }
}

/// Builds the ownership graph for the common and target-specific lowering
/// levels. The graph is target-selected because one daemon job emits one
/// artifact kind; inactive target storage should never become resident.
pub fn lowering_compiler_graph(
    capacities: LoweringCapacities,
    target: LoweringTarget,
) -> Result<CompilerGraph, String> {
    build_lowering_compiler_graph(capacities, Some(target), true)
}

pub(crate) fn lowering_compiler_graph_for_artifact(
    capacities: LoweringCapacities,
    target: LoweringTarget,
    artifact_kind: LoweringArtifactKind,
) -> Result<CompilerGraph, String> {
    build_lowering_compiler_graph(
        capacities,
        Some(target),
        artifact_kind == LoweringArtifactKind::Object,
    )
}

pub fn semantic_lowering_compiler_graph(
    capacities: LoweringCapacities,
) -> Result<CompilerGraph, String> {
    build_lowering_compiler_graph(capacities, None, false)
}

fn build_lowering_compiler_graph(
    capacities: LoweringCapacities,
    target: Option<LoweringTarget>,
    include_object: bool,
) -> Result<CompilerGraph, String> {
    let mut graph = CompilerGraphBuilder::new();
    let value_capacity = capacities.declaration_capacity();
    let local_capacity = capacities.local_capacity();
    let input = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: ResourceClass::Input,
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };
    let workspace = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: ResourceClass::Workspace,
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };
    let artifact = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: ResourceClass::Artifact,
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };
    let retained_semantic = |name, domain, bytes| ResourceDesc {
        name,
        domain,
        class: if target.is_none() {
            ResourceClass::Output
        } else {
            ResourceClass::Artifact
        },
        bytes,
        usage: WorkspaceUsageClass::Storage,
    };

    let hir_core = graph.add_resource(input(
        "hir.core",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirCore>(capacities.hir_nodes),
    ))?;
    let hir_count = graph.add_resource(input(
        "hir.count",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_payload = graph.add_resource(input(
        "hir.payload",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirPayload>(capacities.hir_nodes),
    ))?;
    let hir_fn_return_type = graph.add_resource(input(
        "hir.fn_return_type",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_const_value = graph.add_resource(input(
        "hir.const_value",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_links = graph.add_resource(input(
        "hir.links",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirLinks>(capacities.hir_nodes),
    ))?;
    let hir_expr_root = graph.add_resource(input(
        "hir.expression_roots",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_expr_parent = graph.add_resource(input(
        "hir.expression_parents",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_nearest_loop = graph.add_resource(input(
        "hir.nearest_loop",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_types = graph.add_resource(input(
        "semantic.expression_types",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_expr_ref_tags = graph.add_resource(input(
        "typecheck.semantic_expr_ref_tags_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_expr_ref_payloads = graph.add_resource(input(
        "typecheck.semantic_expr_ref_payloads_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_aggregate_decl_tokens = graph.add_resource(input(
        "typecheck.semantic_aggregate_decl_tokens_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_aggregate_word_counts = graph.add_resource(input(
        "typecheck.semantic_aggregate_word_counts_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_array_lengths = graph.add_resource(input(
        "typecheck.semantic_array_lengths_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_iterable_kinds = graph.add_resource(input(
        "typecheck.semantic_iterable_kinds_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let checked_value_decls = graph.add_resource(input(
        "typecheck.semantic_value_decls_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let checked_value_types = graph.add_resource(input(
        "typecheck.semantic_value_types_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let checked_value_consts = graph.add_resource(input(
        "typecheck.semantic_value_consts_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let checked_value_const_present = graph.add_resource(input(
        "typecheck.semantic_value_const_present_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let checked_param_types = graph.add_resource(input(
        "typecheck.semantic_param_types_by_row",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.parameters),
    ))?;
    let checked_calls = graph.add_resource(input(
        "typecheck.semantic_calls_by_hir",
        ResourceDomain::Calls,
        LoweringCapacities::bytes::<crate::type_checker::GpuCheckedCallArtifact>(
            capacities.hir_nodes,
        ),
    ))?;
    let member_field_ordinals = graph.add_resource(input(
        "typecheck.semantic_member_field_ordinals_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let struct_init_field_ordinals = graph.add_resource(input(
        "typecheck.struct_init_field_ordinals",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.aggregate_elements),
    ))?;
    let semantic_function_return_types_by_hir = graph.add_resource(input(
        "typecheck.semantic_function_return_types_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_result_word_counts_by_hir = graph.add_resource(input(
        "typecheck.semantic_function_result_word_counts_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_entrypoints_by_hir = graph.add_resource(input(
        "typecheck.semantic_function_entrypoints_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_host_services_by_hir = graph.add_resource(input(
        "typecheck.semantic_function_host_services_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let public_decl_index_by_hir = graph.add_resource(input(
        "typecheck.public_decl_index_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let checked_enclosing_functions = graph.add_resource(input(
        "typecheck.semantic_enclosing_functions_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_control_depths = graph.add_resource(input(
        "typecheck.semantic_control_depths_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_value_ids = graph.add_resource(artifact(
        "semantic.value_ids",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_value_types = graph.add_resource(artifact(
        "semantic.value_types",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_targets = graph.add_resource(artifact(
        "semantic.call_targets",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_kinds = graph.add_resource(artifact(
        "semantic.call_kinds",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_result_types = graph.add_resource(artifact(
        "semantic.call_result_types",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_receivers = graph.add_resource(artifact(
        "semantic.call_receivers",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_symbol_library_ids = graph.add_resource(artifact(
        "semantic.call_symbol_library_ids",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_symbol_unit_ids = graph.add_resource(artifact(
        "semantic.call_symbol_unit_ids",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_symbol_local_indices = graph.add_resource(artifact(
        "semantic.call_symbol_local_indices",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_arg_counts_by_hir = graph.add_resource(workspace(
        "lir.semantic.call_arg_counts_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_arg_prefix_by_hir = graph.add_resource(workspace(
        "lir.semantic.call_arg_prefix_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_ids = graph.add_resource(artifact(
        "semantic.function_ids",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_flags = graph.add_resource(workspace(
        "lir.semantic.function_flags",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_prefix = graph.add_resource(workspace(
        "lir.semantic.function_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_id_by_token = graph.add_resource(workspace(
        "lir.semantic.function_id_by_token",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let semantic_const_function_by_root = graph.add_resource(workspace(
        "lir.semantic.const_function_by_root",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_aggregate_hir_by_name_token = graph.add_resource(workspace(
        "lir.semantic.struct_hir_by_name_token",
        ResourceDomain::Tokens,
        LoweringCapacities::bytes::<u32>(capacities.tokens),
    ))?;
    let semantic_struct_field_count_by_hir = graph.add_resource(workspace(
        "lir.semantic.struct_field_count_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_struct_field_start_by_hir = graph.add_resource(workspace(
        "lir.semantic.struct_field_start_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_struct_word_count_by_hir = graph.add_resource(workspace(
        "lir.semantic.struct_word_count_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_struct_field_word_offset_by_row = graph.add_resource(workspace(
        "lir.semantic.struct_field_word_offset_by_row",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_struct_field_word_count_by_row = graph.add_resource(workspace(
        "lir.semantic.struct_field_word_count_by_row",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_local_flags = graph.add_resource(workspace(
        "lir.semantic.local_flags",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_local_prefix = graph.add_resource(workspace(
        "lir.semantic.local_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_call_arg_count = graph.add_resource(input(
        "hir.call_arg_count",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_call_args = graph.add_resource(input(
        "hir.call_args",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<crate::parser::buffers::HirCallArg>(capacities.call_arguments),
    ))?;
    let hir_param_count = graph.add_resource(input(
        "hir.param_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_params = graph.add_resource(input(
        "hir.params",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirParam>(capacities.parameters),
    ))?;
    let hir_param_ranges = graph.add_resource(input(
        "hir.param_ranges",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirRange>(capacities.hir_nodes),
    ))?;
    let hir_method_count = graph.add_resource(input(
        "hir.method_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_method_cores = graph.add_resource(input(
        "hir.method_cores",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirMethodCore>(capacities.hir_nodes),
    ))?;
    let hir_method_signatures = graph.add_resource(input(
        "hir.method_signatures",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirMethodSignature>(
            capacities.hir_nodes,
        ),
    ))?;
    let hir_field_count = graph.add_resource(input(
        "hir.field_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_fields = graph.add_resource(input(
        "hir.fields",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirField>(
            capacities.aggregate_elements,
        ),
    ))?;
    let hir_variant_count = graph.add_resource(input(
        "hir.variant_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_variants = graph.add_resource(input(
        "hir.variants",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirVariant>(capacities.hir_nodes),
    ))?;
    let hir_variant_payload_start = graph.add_resource(input(
        "hir.variant_payload_start",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_variant_payload_count = graph.add_resource(input(
        "hir.variant_payload_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_variant_payload_row_count = graph.add_resource(input(
        "hir.variant_payload_row_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_variant_payloads = graph.add_resource(input(
        "hir.variant_payloads",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirVariantPayload>(
            capacities.hir_nodes,
        ),
    ))?;
    let hir_match_arm_count = graph.add_resource(input(
        "hir.match_arm_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_match_arms = graph.add_resource(input(
        "hir.match_arms",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirMatchArm>(capacities.hir_nodes),
    ))?;
    let hir_match_payload_start = graph.add_resource(input(
        "hir.match_payload_start",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_match_payload_count = graph.add_resource(input(
        "hir.match_payload_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_match_payload_row_count = graph.add_resource(input(
        "hir.match_payload_row_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_match_payloads = graph.add_resource(input(
        "hir.match_payloads",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirMatchPayload>(capacities.hir_nodes),
    ))?;
    let hir_array_element_count = graph.add_resource(input(
        "hir.array_element_row_count",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_array_element_start = graph.add_resource(input(
        "hir.array_element_start",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_array_element_owner_count = graph.add_resource(input(
        "hir.array_element_count",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let hir_array_elements = graph.add_resource(input(
        "hir.array_elements",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<crate::parser::buffers::HirArrayElement>(
            capacities.aggregate_elements,
        ),
    ))?;
    let hir_string_count = graph.add_resource(input(
        "hir.string_count",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_strings = graph.add_resource(input(
        "hir.strings",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<crate::parser::buffers::HirString>(capacities.hir_nodes),
    ))?;
    let hir_string_pool_len = graph.add_resource(input(
        "hir.string_pool_len",
        ResourceDomain::SourceBytes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let hir_string_data = graph.add_resource(input(
        "hir.string_data",
        ResourceDomain::SourceBytes,
        u64::from(capacities.source_bytes.max(4).div_ceil(4)) * 4,
    ))?;
    let semantic_counts = graph.add_resource(workspace(
        "lir.semantic.count_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_link_a = graph.add_resource(workspace(
        "lir.semantic.execution_rank_link_a",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_a = graph.add_resource(workspace(
        "lir.semantic.execution_rank_a",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_link_b = graph.add_resource(workspace(
        "lir.semantic.execution_rank_link_b",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let execution_rank_b = graph.add_resource(workspace(
        "lir.semantic.execution_rank_b",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_offsets = graph.add_resource(workspace(
        "lir.semantic.offset_by_hir",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_scan_local = graph.add_resource(workspace(
        "lir.semantic.scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_scan_blocks = capacities.hir_nodes.max(1).div_ceil(256);
    let semantic_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_function_scan_local = graph.add_resource(workspace(
        "lir.semantic.function_scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_function_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.function_scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_function_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.function_scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_function_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.function_scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_local_scan_local = graph.add_resource(workspace(
        "lir.semantic.local_scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_local_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.local_scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_local_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.local_scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_local_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.local_scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_call_arg_scan_local = graph.add_resource(workspace(
        "lir.semantic.call_arg_scan_local",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let semantic_call_arg_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.call_arg_scan_block_sum",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_call_arg_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.call_arg_scan_block_prefix",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_call_arg_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.call_arg_scan_hierarchy",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(semantic_scan_blocks),
    ))?;
    let semantic_total = graph.add_resource(retained_semantic(
        "lir.semantic.total",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_resident_rows = capacities.semantic_instructions.max(1);
    let semantic_record_class = if target.is_none() {
        ResourceClass::Output
    } else {
        ResourceClass::Workspace
    };
    let semantic_core = graph.add_resource(ResourceDesc {
        name: "lir.semantic.core",
        domain: ResourceDomain::SemanticInstructions,
        class: semantic_record_class,
        bytes: LoweringCapacities::bytes::<SemanticLirCore>(semantic_resident_rows),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_operands = graph.add_resource(ResourceDesc {
        name: "lir.semantic.operands",
        domain: ResourceDomain::SemanticInstructions,
        class: semantic_record_class,
        bytes: LoweringCapacities::bytes::<SemanticLirOperands>(semantic_resident_rows),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_layout_word_offset = graph.add_resource(ResourceDesc {
        name: "lir.semantic.layout_word_offset",
        domain: ResourceDomain::SemanticInstructions,
        class: semantic_record_class,
        bytes: LoweringCapacities::bytes::<u32>(semantic_resident_rows),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_schedule = graph.add_resource(ResourceDesc {
        name: "lir.semantic.schedule",
        domain: ResourceDomain::SemanticInstructions,
        class: if target.is_none() {
            ResourceClass::Output
        } else {
            ResourceClass::Workspace
        },
        bytes: LoweringCapacities::bytes::<TargetScheduleKey>(capacities.semantic_instructions),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let semantic_owner = graph.add_resource(retained_semantic(
        "lir.semantic.owner_by_instruction",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_op = graph.add_resource(retained_semantic(
        "lir.semantic.op_by_instruction",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_call_args = graph.add_resource(retained_semantic(
        "lir.semantic.call_args",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<SemanticLirCallArg>(capacities.call_arguments),
    ))?;
    let semantic_call_arg_total = graph.add_resource(retained_semantic(
        "lir.semantic.call_arg_total",
        ResourceDomain::CallArguments,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_functions = graph.add_resource(retained_semantic(
        "lir.semantic.functions",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirFunction>(capacities.hir_nodes),
    ))?;
    let semantic_function_total = graph.add_resource(retained_semantic(
        "lir.semantic.function_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_params = graph.add_resource(retained_semantic(
        "lir.semantic.params",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirParam>(capacities.parameters),
    ))?;
    let semantic_param_total = graph.add_resource(retained_semantic(
        "lir.semantic.param_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_locals = graph.add_resource(retained_semantic(
        "lir.semantic.locals",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirLocal>(local_capacity),
    ))?;
    let semantic_local_total = graph.add_resource(retained_semantic(
        "lir.semantic.local_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_aggregate_elements = graph.add_resource(retained_semantic(
        "lir.semantic.aggregate_elements",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<SemanticLirAggregateElement>(
            capacities.aggregate_elements.saturating_mul(2),
        ),
    ))?;
    let semantic_aggregate_element_total = graph.add_resource(retained_semantic(
        "lir.semantic.aggregate_element_total",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_strings = graph.add_resource(retained_semantic(
        "lir.semantic.strings",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<SemanticLirString>(capacities.hir_nodes),
    ))?;
    let semantic_string_total = graph.add_resource(retained_semantic(
        "lir.semantic.string_total",
        ResourceDomain::HirNodes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_string_pool_len = graph.add_resource(retained_semantic(
        "lir.semantic.string_pool_len",
        ResourceDomain::SourceBytes,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let semantic_string_data = graph.add_resource(retained_semantic(
        "lir.semantic.string_data",
        ResourceDomain::SourceBytes,
        u64::from(capacities.source_bytes.max(4).div_ceil(4)) * 4,
    ))?;
    let lowering_status = graph.add_resource(ResourceDesc {
        name: "lowering.status",
        domain: ResourceDomain::ArtifactBytes,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<LoweringStatus>(1),
        usage: WorkspaceUsageClass::Storage,
    })?;

    graph.add_pass(PassDesc {
        name: "lir.status.clear",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![PassAccess::write("lowering_status", lowering_status)],
    })?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.mark",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::write("semantic_function_flag", semantic_function_flags),
            PassAccess::write(
                "semantic_const_function_by_root",
                semantic_const_function_by_root,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_function_flags),
            PassAccess::write("scan_local_prefix", semantic_function_scan_local),
            PassAccess::write("scan_block_sum", semantic_function_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_function_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_function_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_function_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.function_scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_function_scan_local),
            PassAccess::read("scan_block_prefix", semantic_function_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_function_prefix),
            PassAccess::write("scan_total", semantic_function_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.locals.mark",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read(
                "compact_match_payload_row_count",
                hir_match_payload_row_count,
            ),
            PassAccess::read("compact_match_payloads", hir_match_payloads),
            PassAccess::read("compact_variant_count", hir_variant_count),
            PassAccess::read("compact_variants", hir_variants),
            PassAccess::read("semantic_value_id", checked_value_decls),
            PassAccess::write("semantic_local_flag", semantic_local_flags),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_local_flags),
            PassAccess::write("scan_local_prefix", semantic_local_scan_local),
            PassAccess::write("scan_block_sum", semantic_local_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_local_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_local_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_local_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_local_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_local_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.local_scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_local_scan_local),
            PassAccess::read("scan_block_prefix", semantic_local_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_local_prefix),
            PassAccess::write("scan_total", semantic_local_total),
        ],
    })?;
    // The runtime records aggregate layout after both declaration scans and
    // before function rows are scattered. Keep the ownership graph in that
    // exact order: layout scratch may otherwise alias the still-live local
    // flags/prefix and corrupt the semantic local table under coloring.
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.layout.clear",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::Tokens,
        accesses: vec![
            PassAccess::write(
                "semantic_aggregate_hir_by_name_token",
                semantic_aggregate_hir_by_name_token,
            ),
            PassAccess::write(
                "semantic_struct_field_count_by_hir",
                semantic_struct_field_count_by_hir,
            ),
            PassAccess::write(
                "semantic_struct_field_start_by_hir",
                semantic_struct_field_start_by_hir,
            ),
            PassAccess::write(
                "semantic_struct_word_count_by_hir",
                semantic_struct_word_count_by_hir,
            ),
            PassAccess::write(
                "semantic_struct_field_word_offset_by_row",
                semantic_struct_field_word_offset_by_row,
            ),
            PassAccess::write(
                "semantic_struct_field_word_count_by_row",
                semantic_struct_field_word_count_by_row,
            ),
            PassAccess::write(
                "semantic_function_id_by_token",
                semantic_function_id_by_token,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.layout.collect",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_field_count", hir_field_count),
            PassAccess::read("compact_fields", hir_fields),
            PassAccess::write(
                "semantic_aggregate_hir_by_name_token",
                semantic_aggregate_hir_by_name_token,
            ),
            PassAccess::write(
                "semantic_struct_field_count_by_hir",
                semantic_struct_field_count_by_hir,
            ),
            PassAccess::write(
                "semantic_struct_field_start_by_hir",
                semantic_struct_field_start_by_hir,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.layout.words",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_fields", hir_fields),
            PassAccess::read("semantic_expr_ref_tag", semantic_expr_ref_tags),
            PassAccess::read("semantic_expr_ref_payload", semantic_expr_ref_payloads),
            PassAccess::read(
                "semantic_aggregate_decl_token",
                semantic_aggregate_decl_tokens,
            ),
            PassAccess::read(
                "semantic_aggregate_hir_by_name_token",
                semantic_aggregate_hir_by_name_token,
            ),
            PassAccess::read(
                "semantic_struct_field_start_by_hir",
                semantic_struct_field_start_by_hir,
            ),
            PassAccess::read(
                "semantic_struct_field_count_by_hir",
                semantic_struct_field_count_by_hir,
            ),
            PassAccess::write(
                "semantic_struct_word_count_by_hir",
                semantic_struct_word_count_by_hir,
            ),
            PassAccess::write(
                "semantic_struct_field_word_offset_by_row",
                semantic_struct_field_word_offset_by_row,
            ),
            PassAccess::write(
                "semantic_struct_field_word_count_by_row",
                semantic_struct_field_word_count_by_row,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.scatter",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_links", hir_links),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_fn_return_type", hir_fn_return_type),
            PassAccess::read("compact_const_value", hir_const_value),
            PassAccess::read("compact_param_ranges", hir_param_ranges),
            PassAccess::read("compact_method_count", hir_method_count),
            PassAccess::read("compact_method_cores", hir_method_cores),
            PassAccess::read("compact_method_signatures", hir_method_signatures),
            PassAccess::read("compact_variant_count", hir_variant_count),
            PassAccess::read("compact_variants", hir_variants),
            PassAccess::read("compact_variant_payload_start", hir_variant_payload_start),
            PassAccess::read("compact_variant_payload_count", hir_variant_payload_count),
            PassAccess::read(
                "compact_variant_payload_row_count",
                hir_variant_payload_row_count,
            ),
            PassAccess::read("compact_variant_payloads", hir_variant_payloads),
            PassAccess::read("semantic_function_flag", semantic_function_flags),
            PassAccess::read("semantic_function_prefix", semantic_function_prefix),
            PassAccess::read("semantic_local_prefix", semantic_local_prefix),
            PassAccess::read("semantic_local_total", semantic_local_total),
            PassAccess::read(
                "semantic_function_return_type_by_hir",
                semantic_function_return_types_by_hir,
            ),
            PassAccess::read(
                "semantic_function_result_word_count_by_hir",
                semantic_function_result_word_counts_by_hir,
            ),
            PassAccess::read(
                "semantic_function_entrypoint_by_hir",
                semantic_function_entrypoints_by_hir,
            ),
            PassAccess::read(
                "semantic_function_host_service_by_hir",
                semantic_function_host_services_by_hir,
            ),
            PassAccess::read("public_decl_index_by_hir", public_decl_index_by_hir),
            PassAccess::read("semantic_value_type_by_hir", checked_value_types),
            PassAccess::read("semantic_expr_ref_tag_by_hir", semantic_expr_ref_tags),
            PassAccess::read(
                "semantic_expr_ref_payload_by_hir",
                semantic_expr_ref_payloads,
            ),
            PassAccess::read(
                "semantic_aggregate_decl_token_by_hir",
                semantic_aggregate_decl_tokens,
            ),
            PassAccess::read(
                "semantic_aggregate_word_count_by_hir",
                semantic_aggregate_word_counts,
            ),
            PassAccess::read("semantic_array_length_by_hir", semantic_array_lengths),
            PassAccess::read(
                "semantic_aggregate_hir_by_name_token",
                semantic_aggregate_hir_by_name_token,
            ),
            PassAccess::read(
                "semantic_struct_word_count_by_hir",
                semantic_struct_word_count_by_hir,
            ),
            PassAccess::write("semantic_lir_functions", semantic_functions),
            PassAccess::write(
                "semantic_function_id_by_token",
                semantic_function_id_by_token,
            ),
            PassAccess::write(
                "semantic_const_function_by_root",
                semantic_const_function_by_root,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.functions.params",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("compact_param_count", hir_param_count),
            PassAccess::read("compact_params", hir_params),
            PassAccess::read("semantic_function_flag", semantic_function_flags),
            PassAccess::read("semantic_function_prefix", semantic_function_prefix),
            PassAccess::read("semantic_param_type_by_row", checked_param_types),
            PassAccess::write("semantic_lir_param_total", semantic_param_total),
            PassAccess::write("semantic_lir_params", semantic_params),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.project",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_expr_root", hir_expr_root),
            PassAccess::read("compact_variant_count", hir_variant_count),
            PassAccess::read("compact_variants", hir_variants),
            PassAccess::read("compact_variant_payload_count", hir_variant_payload_count),
            PassAccess::read("semantic_value_decl_by_hir", checked_value_decls),
            PassAccess::read("semantic_value_type_by_hir", checked_value_types),
            PassAccess::read(
                "semantic_value_const_present_by_hir",
                checked_value_const_present,
            ),
            PassAccess::read("semantic_calls_by_hir", checked_calls),
            PassAccess::read("semantic_enclosing_fn_by_hir", checked_enclosing_functions),
            PassAccess::read("semantic_function_flag", semantic_function_flags),
            PassAccess::read("semantic_function_prefix", semantic_function_prefix),
            PassAccess::read(
                "semantic_function_id_by_token",
                semantic_function_id_by_token,
            ),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read(
                "semantic_const_function_by_root",
                semantic_const_function_by_root,
            ),
            PassAccess::write("semantic_value_id", semantic_value_ids),
            PassAccess::write("semantic_value_type", semantic_value_types),
            PassAccess::write("semantic_call_target", semantic_call_targets),
            PassAccess::write("semantic_call_kind", semantic_call_kinds),
            PassAccess::write("semantic_call_result_type", semantic_call_result_types),
            PassAccess::write("semantic_call_receiver", semantic_call_receivers),
            PassAccess::write(
                "semantic_call_symbol_library_id",
                semantic_call_symbol_library_ids,
            ),
            PassAccess::write(
                "semantic_call_symbol_unit_id",
                semantic_call_symbol_unit_ids,
            ),
            PassAccess::write(
                "semantic_call_symbol_local_index",
                semantic_call_symbol_local_indices,
            ),
            PassAccess::write(
                "semantic_call_arg_count_by_hir",
                semantic_call_arg_counts_by_hir,
            ),
            PassAccess::write("semantic_function_id", semantic_function_ids),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_arg_scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_call_arg_counts_by_hir),
            PassAccess::write("scan_local_prefix", semantic_call_arg_scan_local),
            PassAccess::write("scan_block_sum", semantic_call_arg_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_arg_scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_call_arg_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_call_arg_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_call_arg_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_arg_scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_call_arg_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_call_arg_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_arg_scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_call_arg_scan_local),
            PassAccess::read("scan_block_prefix", semantic_call_arg_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_call_arg_prefix_by_hir),
            PassAccess::write("scan_total", semantic_call_arg_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.locals.scatter",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read(
                "compact_match_payload_row_count",
                hir_match_payload_row_count,
            ),
            PassAccess::read("compact_match_payloads", hir_match_payloads),
            PassAccess::read("compact_variant_count", hir_variant_count),
            PassAccess::read("compact_variants", hir_variants),
            PassAccess::read("semantic_local_flag", semantic_local_flags),
            PassAccess::read("semantic_local_prefix", semantic_local_prefix),
            PassAccess::read("semantic_function_id", semantic_function_ids),
            PassAccess::read("semantic_value_type_by_hir", checked_value_types),
            PassAccess::read("semantic_value_decl_by_hir", checked_value_decls),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::write("semantic_lir_locals", semantic_locals),
        ],
    })?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.execution_rank.init",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_expr_parent", hir_expr_parent),
            PassAccess::write("execution_rank_link", execution_rank_link_a),
            PassAccess::write("execution_rank", execution_rank_a),
        ],
    })?;
    let rank_pairs = (u32::BITS - capacities.hir_nodes.max(1).leading_zeros())
        .max(1)
        .div_ceil(2);
    graph.add_repeated_region(
        rank_pairs,
        vec![
            PassDesc {
                name: "lir.semantic.execution_rank.step_a_to_b",
                phase: CompilerPhase::SemanticLowering,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", hir_count),
                    PassAccess::read("execution_rank_link_in", execution_rank_link_a),
                    PassAccess::read("execution_rank_in", execution_rank_a),
                    PassAccess::write("execution_rank_link_out", execution_rank_link_b),
                    PassAccess::write("execution_rank_out", execution_rank_b),
                ],
            },
            PassDesc {
                name: "lir.semantic.execution_rank.step_b_to_a",
                phase: CompilerPhase::SemanticLowering,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("compact_hir_count", hir_count),
                    PassAccess::read("execution_rank_link_in", execution_rank_link_b),
                    PassAccess::read("execution_rank_in", execution_rank_b),
                    PassAccess::write("execution_rank_link_out", execution_rank_link_a),
                    PassAccess::write("execution_rank_out", execution_rank_a),
                ],
            },
        ],
    )?;

    graph.add_pass(PassDesc {
        name: "lir.semantic.count",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_expr_parent", hir_expr_parent),
            PassAccess::read("compact_match_arm_count", hir_match_arm_count),
            PassAccess::read("compact_match_arms", hir_match_arms),
            PassAccess::read("compact_match_payload_start", hir_match_payload_start),
            PassAccess::read("compact_match_payload_count", hir_match_payload_count),
            PassAccess::read(
                "compact_match_payload_row_count",
                hir_match_payload_row_count,
            ),
            PassAccess::read("compact_match_payloads", hir_match_payloads),
            PassAccess::read("compact_variant_count", hir_variant_count),
            PassAccess::read("compact_variants", hir_variants),
            PassAccess::read("semantic_value_id", checked_value_decls),
            PassAccess::read("semantic_function_id", semantic_function_ids),
            PassAccess::read("semantic_array_length", semantic_array_lengths),
            PassAccess::read("semantic_iterable_kind", semantic_iterable_kinds),
            PassAccess::write("semantic_lir_count", semantic_counts),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.local",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_input", semantic_counts),
            PassAccess::write("scan_local_prefix", semantic_scan_local),
            PassAccess::write("scan_block_sum", semantic_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.hierarchy_up",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_block_sum", semantic_scan_block_sum),
            PassAccess::write("scan_block_prefix", semantic_scan_block_prefix),
            PassAccess::write("scan_hierarchy", semantic_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.hierarchy_down",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read_write("scan_block_prefix", semantic_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", semantic_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scan.apply",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::HirNodes,
        accesses: vec![
            PassAccess::read("scan_count", hir_count),
            PassAccess::read("scan_local_prefix", semantic_scan_local),
            PassAccess::read("scan_block_prefix", semantic_scan_block_prefix),
            PassAccess::write("scan_output_prefix", semantic_offsets),
            PassAccess::write("scan_total", semantic_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.scatter",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_hir_links", hir_links),
            PassAccess::read("compact_hir_payload", hir_payload),
            PassAccess::read("compact_const_value", hir_const_value),
            PassAccess::read("semantic_expr_type", semantic_types),
            PassAccess::read("semantic_expr_ref_tag", semantic_expr_ref_tags),
            PassAccess::read("semantic_expr_ref_payload", semantic_expr_ref_payloads),
            PassAccess::read(
                "semantic_aggregate_decl_token",
                semantic_aggregate_decl_tokens,
            ),
            PassAccess::read(
                "semantic_aggregate_word_count",
                semantic_aggregate_word_counts,
            ),
            PassAccess::read("semantic_array_length", semantic_array_lengths),
            PassAccess::read("semantic_iterable_kind", semantic_iterable_kinds),
            PassAccess::read("semantic_value_id", semantic_value_ids),
            PassAccess::read("semantic_value_type", semantic_value_types),
            PassAccess::read("semantic_value_const_by_hir", checked_value_consts),
            PassAccess::read(
                "semantic_value_const_present_by_hir",
                checked_value_const_present,
            ),
            PassAccess::read("semantic_call_target", semantic_call_targets),
            PassAccess::read("semantic_call_kind", semantic_call_kinds),
            PassAccess::read("semantic_call_result_type", semantic_call_result_types),
            PassAccess::read(
                "semantic_call_symbol_library_id",
                semantic_call_symbol_library_ids,
            ),
            PassAccess::read(
                "semantic_call_symbol_unit_id",
                semantic_call_symbol_unit_ids,
            ),
            PassAccess::read(
                "semantic_call_symbol_local_index",
                semantic_call_symbol_local_indices,
            ),
            PassAccess::read("semantic_function_id", semantic_function_ids),
            PassAccess::read(
                "semantic_function_id_by_token",
                semantic_function_id_by_token,
            ),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read("semantic_control_depth_by_hir", semantic_control_depths),
            PassAccess::read("semantic_member_field_ordinal", member_field_ordinals),
            PassAccess::read(
                "semantic_aggregate_hir_by_name_token",
                semantic_aggregate_hir_by_name_token,
            ),
            PassAccess::read(
                "semantic_struct_word_count_by_hir",
                semantic_struct_word_count_by_hir,
            ),
            PassAccess::read(
                "semantic_struct_field_start_by_hir",
                semantic_struct_field_start_by_hir,
            ),
            PassAccess::read(
                "semantic_struct_field_word_offset_by_row",
                semantic_struct_field_word_offset_by_row,
            ),
            PassAccess::read(
                "semantic_struct_field_word_count_by_row",
                semantic_struct_field_word_count_by_row,
            ),
            PassAccess::read("compact_expr_root", hir_expr_root),
            PassAccess::read("compact_nearest_loop", hir_nearest_loop),
            PassAccess::read("compact_array_element_start", hir_array_element_start),
            PassAccess::read(
                "compact_array_element_owner_count",
                hir_array_element_owner_count,
            ),
            PassAccess::read("compact_array_element_row_count", hir_array_element_count),
            PassAccess::read("compact_field_count", hir_field_count),
            PassAccess::read("compact_call_arg_count", hir_call_arg_count),
            PassAccess::read("compact_call_args", hir_call_args),
            PassAccess::read("compact_variant_count", hir_variant_count),
            PassAccess::read("compact_variants", hir_variants),
            PassAccess::read("compact_match_arm_count", hir_match_arm_count),
            PassAccess::read("compact_match_arms", hir_match_arms),
            PassAccess::read("compact_match_payload_start", hir_match_payload_start),
            PassAccess::read("compact_match_payload_count", hir_match_payload_count),
            PassAccess::read(
                "compact_match_payload_row_count",
                hir_match_payload_row_count,
            ),
            PassAccess::read("compact_match_payloads", hir_match_payloads),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_execution_rank", execution_rank_a),
            PassAccess::write("semantic_lir_schedule", semantic_schedule),
            PassAccess::write("semantic_owner_by_instruction", semantic_owner),
            PassAccess::write("semantic_op_by_instruction", semantic_op),
            PassAccess::write("semantic_lir_core", semantic_core),
            PassAccess::write("semantic_lir_operands", semantic_operands),
            PassAccess::write(
                "semantic_lir_layout_word_offset",
                semantic_layout_word_offset,
            ),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.call_args",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::CallArguments,
        accesses: vec![
            PassAccess::read("compact_call_arg_count", hir_call_arg_count),
            PassAccess::read("compact_call_args", hir_call_args),
            PassAccess::read("semantic_call_receiver", semantic_call_receivers),
            PassAccess::read(
                "semantic_call_arg_count_by_hir",
                semantic_call_arg_counts_by_hir,
            ),
            PassAccess::read(
                "semantic_call_arg_prefix_by_hir",
                semantic_call_arg_prefix_by_hir,
            ),
            PassAccess::read("semantic_expr_type", semantic_types),
            PassAccess::read("semantic_expr_ref_tag", semantic_expr_ref_tags),
            PassAccess::read("semantic_expr_ref_payload", semantic_expr_ref_payloads),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::write("semantic_lir_call_args", semantic_call_args),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.aggregate_elements",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("compact_hir_count", hir_count),
            PassAccess::read("compact_hir_core", hir_core),
            PassAccess::read("compact_field_count", hir_field_count),
            PassAccess::read("compact_fields", hir_fields),
            PassAccess::read(
                "struct_init_field_ordinal_by_row",
                struct_init_field_ordinals,
            ),
            PassAccess::read("compact_array_element_count", hir_array_element_count),
            PassAccess::read("compact_array_elements", hir_array_elements),
            PassAccess::read("compact_call_arg_count", hir_call_arg_count),
            PassAccess::read("compact_call_args", hir_call_args),
            PassAccess::read("semantic_call_kind", semantic_call_kinds),
            PassAccess::read("semantic_expr_type", semantic_types),
            PassAccess::read("semantic_expr_ref_tag", semantic_expr_ref_tags),
            PassAccess::read("semantic_expr_ref_payload", semantic_expr_ref_payloads),
            PassAccess::read(
                "semantic_aggregate_decl_token",
                semantic_aggregate_decl_tokens,
            ),
            PassAccess::read(
                "semantic_aggregate_word_count",
                semantic_aggregate_word_counts,
            ),
            PassAccess::read("semantic_array_length", semantic_array_lengths),
            PassAccess::read(
                "semantic_aggregate_hir_by_name_token",
                semantic_aggregate_hir_by_name_token,
            ),
            PassAccess::read(
                "semantic_struct_word_count_by_hir",
                semantic_struct_word_count_by_hir,
            ),
            PassAccess::read(
                "semantic_struct_field_start_by_hir",
                semantic_struct_field_start_by_hir,
            ),
            PassAccess::read(
                "semantic_struct_field_word_offset_by_row",
                semantic_struct_field_word_offset_by_row,
            ),
            PassAccess::read(
                "semantic_struct_field_word_count_by_row",
                semantic_struct_field_word_count_by_row,
            ),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::write(
                "semantic_lir_aggregate_element_total",
                semantic_aggregate_element_total,
            ),
            PassAccess::write(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.semantic.strings",
        phase: CompilerPhase::SemanticLowering,
        dispatch_domain: ResourceDomain::SourceBytes,
        accesses: vec![
            PassAccess::read("compact_string_count", hir_string_count),
            PassAccess::read("compact_strings", hir_strings),
            PassAccess::read("compact_string_pool_len", hir_string_pool_len),
            PassAccess::read("compact_string_data", hir_string_data),
            PassAccess::read("semantic_lir_count", semantic_counts),
            PassAccess::read("semantic_lir_offset", semantic_offsets),
            PassAccess::write("semantic_lir_string_total", semantic_string_total),
            PassAccess::write("semantic_lir_strings", semantic_strings),
            PassAccess::write("semantic_lir_string_pool_len", semantic_string_pool_len),
            PassAccess::write("semantic_lir_string_data", semantic_string_data),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    })?;

    let Some(target) = target else {
        return graph.build();
    };
    let lowering_status_readback = graph.add_storage(
        "lowering.status_readback",
        ResourceDomain::ArtifactBytes,
        ResourceClass::External,
        LoweringCapacities::bytes::<LoweringStatus>(1),
    )?;
    let target_domain = match target {
        LoweringTarget::X86_64 => ResourceDomain::X86Instructions,
        LoweringTarget::Wasm => ResourceDomain::WasmInstructions,
    };
    let target_phase = match target {
        LoweringTarget::X86_64 => CompilerPhase::X86Lowering,
        LoweringTarget::Wasm => CompilerPhase::WasmLowering,
    };
    let target_counts = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.count_by_semantic",
            LoweringTarget::Wasm => "lir.wasm.count_by_semantic",
        },
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let target_offsets = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.offset_by_semantic",
            LoweringTarget::Wasm => "lir.wasm.offset_by_semantic",
        },
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let semantic_to_target_start = graph.add_resource(workspace(
        "lir.target.semantic_to_target_start",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let target_total = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.total",
            LoweringTarget::Wasm => "lir.wasm.total",
        },
        target_domain,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let target_scan_blocks = capacities.semantic_instructions.max(1).div_ceil(256);
    let target_scan_local = graph.add_resource(workspace(
        "lir.target.count_scan_local",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let target_scan_block_sum = graph.add_resource(workspace(
        "lir.target.count_scan_block_sum",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(target_scan_blocks),
    ))?;
    let target_scan_block_prefix = graph.add_resource(workspace(
        "lir.target.count_scan_block_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(target_scan_blocks),
    ))?;
    let target_scan_hierarchy = graph.add_resource(workspace(
        "lir.target.count_scan_hierarchy",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(target_scan_blocks),
    ))?;
    let target_page_rows = capacities
        .target_instructions
        .max(1)
        .min(TARGET_LIR_PAGE_ROWS);
    let target_page_count = capacities
        .target_instructions
        .max(1)
        .div_ceil(TARGET_LIR_PAGE_ROWS);
    let target_semantic_pages = graph.add_resource(workspace(
        "lir.target.semantic_pages",
        target_domain,
        LoweringCapacities::bytes::<TargetSemanticPage>(target_page_count),
    ))?;
    let target_core_bytes = match target {
        LoweringTarget::X86_64 => LoweringCapacities::bytes::<X86LirCore>(target_page_rows),
        LoweringTarget::Wasm => LoweringCapacities::bytes::<WasmLirInstruction>(target_page_rows),
    };
    let target_core = graph.add_resource(match target {
        // x86 call-argument lanes and semantic-row lanes populate disjoint
        // portions of this unscheduled staging table. The single-producer
        // artifact boundary is the subsequent schedule-materialize pass.
        LoweringTarget::X86_64 => workspace("lir.x86.core", target_domain, target_core_bytes),
        LoweringTarget::Wasm => {
            workspace("lir.wasm.instructions", target_domain, target_core_bytes)
        }
    })?;
    // Both targets retain an explicit operand record. Most Wasm instructions
    // need only the immediate embedded in `WasmLirInstruction`, but symbolic
    // calls must preserve all three words of canonical symbol identity until
    // relocatable-object projection.
    let target_operands = Some(graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.operands",
            LoweringTarget::Wasm => "lir.wasm.operands",
        },
        target_domain,
        LoweringCapacities::bytes::<X86LirOperands>(target_page_rows),
    ))?);
    let x86_target_locations = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.locations",
            target_domain,
            LoweringCapacities::bytes::<X86LirLocations>(target_page_rows),
        ))?)
    } else {
        None
    };
    // Wasm carries this in WasmLirInstruction. x86 preserves the established
    // virtual-instruction layout, so scheduling provenance is a compact side
    // table rather than an overloaded operand word.
    let target_semantic_origins = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.semantic_origins",
            target_domain,
            LoweringCapacities::bytes::<u32>(target_page_rows),
        ))?)
    } else {
        None
    };
    let x86_target_flags = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.flags",
            target_domain,
            LoweringCapacities::bytes::<u32>(target_page_rows),
        ))?)
    } else {
        None
    };
    let x86_decl_location_by_token = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(ResourceDesc {
            name: "lir.x86.decl_location_by_token",
            domain: ResourceDomain::Tokens,
            class: ResourceClass::Output,
            bytes: LoweringCapacities::bytes::<u32>(value_capacity),
            usage: WorkspaceUsageClass::Storage,
        })?)
    } else {
        None
    };
    let x86_saved_gpr_mask_by_function = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(ResourceDesc {
            name: "lir.x86.saved_gpr_mask_by_function",
            domain: ResourceDomain::Declarations,
            class: ResourceClass::Output,
            bytes: LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
            usage: WorkspaceUsageClass::Storage,
        })?)
    } else {
        None
    };
    let x86_position_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.position_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_last_use_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.last_use_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_next_rax_clobber_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.next_rax_clobber_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_decl_analysis_by_token = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.decl_analysis_by_token",
            ResourceDomain::Tokens,
            LoweringCapacities::bytes::<X86DeclarationAnalysis>(value_capacity),
        ))?)
    } else {
        None
    };
    let x86_live_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.live_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_value_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.value_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<X86ValueAnalysis>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_location_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.location_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_select_by_semantic = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.select_by_semantic",
            ResourceDomain::SemanticInstructions,
            LoweringCapacities::bytes::<X86SelectInfo>(capacities.semantic_instructions),
        ))?)
    } else {
        None
    };
    let x86_function_start = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.function_start",
            ResourceDomain::Declarations,
            LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
        ))?)
    } else {
        None
    };
    let x86_function_end = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.function_end",
            ResourceDomain::Declarations,
            LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
        ))?)
    } else {
        None
    };
    let x86_register_analysis_by_function = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.register_analysis_by_function",
            ResourceDomain::Declarations,
            LoweringCapacities::bytes::<X86FunctionRegisterAnalysis>(capacities.hir_nodes),
        ))?)
    } else {
        None
    };
    let x86_stack_slot_count_by_function = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.stack_slot_count_by_function",
            ResourceDomain::Declarations,
            LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
        ))?)
    } else {
        None
    };
    let x86_frame_slot_count_by_function = if target == LoweringTarget::X86_64 {
        Some(graph.add_resource(workspace(
            "lir.x86.frame_slot_count_by_function",
            ResourceDomain::Declarations,
            LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
        ))?)
    } else {
        None
    };
    let wasm_abi = if target == LoweringTarget::Wasm {
        let param_blocks = capacities.parameters.max(1).div_ceil(256);
        let local_blocks = local_capacity.div_ceil(256);
        Some(WasmAbiGraphResources {
            param_widths: graph.add_resource(workspace(
                "lir.wasm.param_widths",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(capacities.parameters),
            ))?,
            param_prefix: graph.add_resource(workspace(
                "lir.wasm.param_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(capacities.parameters),
            ))?,
            param_scan_local: graph.add_resource(workspace(
                "lir.wasm.param_scan_local",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(capacities.parameters),
            ))?,
            param_scan_block_sum: graph.add_resource(workspace(
                "lir.wasm.param_scan_block_sum",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(param_blocks),
            ))?,
            param_scan_block_prefix: graph.add_resource(workspace(
                "lir.wasm.param_scan_block_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(param_blocks),
            ))?,
            param_scan_hierarchy: graph.add_resource(workspace(
                "lir.wasm.param_scan_hierarchy",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(param_blocks),
            ))?,
            param_value_total: graph.add_resource(workspace(
                "lir.wasm.param_value_total",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(1),
            ))?,
            local_widths: graph.add_resource(workspace(
                "lir.wasm.local_widths",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_capacity),
            ))?,
            local_prefix: graph.add_resource(workspace(
                "lir.wasm.local_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_capacity),
            ))?,
            local_scan_local: graph.add_resource(workspace(
                "lir.wasm.local_scan_local",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_capacity),
            ))?,
            local_scan_block_sum: graph.add_resource(workspace(
                "lir.wasm.local_scan_block_sum",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_blocks),
            ))?,
            local_scan_block_prefix: graph.add_resource(workspace(
                "lir.wasm.local_scan_block_prefix",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_blocks),
            ))?,
            local_scan_hierarchy: graph.add_resource(workspace(
                "lir.wasm.local_scan_hierarchy",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(local_blocks),
            ))?,
            local_value_total: graph.add_resource(workspace(
                "lir.wasm.local_value_total",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(1),
            ))?,
            functions: graph.add_resource(ResourceDesc {
                name: "lir.wasm.functions",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<WasmLirFunction>(capacities.hir_nodes),
                usage: WorkspaceUsageClass::Storage,
            })?,
            local_index_by_token: graph.add_resource(workspace(
                "lir.wasm.local_index_by_token",
                ResourceDomain::Tokens,
                LoweringCapacities::bytes::<u32>(value_capacity),
            ))?,
        })
    } else {
        None
    };
    let schedule_capacity = capacities.semantic_instructions;
    let schedule_order = graph.add_resource(workspace(
        "lir.semantic.schedule_order",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_capacity),
    ))?;
    let schedule_order_tmp = graph.add_resource(workspace(
        "lir.semantic.schedule_order_tmp",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_capacity),
    ))?;
    let schedule_blocks = schedule_capacity.max(1).div_ceil(256);
    let schedule_slots = schedule_blocks.saturating_mul(256);
    let schedule_slot_count = graph.add_resource(workspace(
        "lir.semantic.schedule_slot_count",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let schedule_histogram = graph.add_resource(workspace(
        "lir.semantic.schedule_histogram",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots),
    ))?;
    let schedule_global_prefix = graph.add_resource(workspace(
        "lir.semantic.schedule_global_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots),
    ))?;
    let schedule_scan_local = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_local",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots),
    ))?;
    let schedule_scan_block_sum = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_block_sum",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots.div_ceil(256)),
    ))?;
    let schedule_scan_block_prefix = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_block_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots.div_ceil(256)),
    ))?;
    let schedule_scan_hierarchy = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_hierarchy",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(schedule_slots.div_ceil(256)),
    ))?;
    let schedule_scan_total = graph.add_resource(workspace(
        "lir.semantic.schedule_scan_total",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(1),
    ))?;
    let byte_lengths = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.byte_lengths",
            LoweringTarget::Wasm => "lir.wasm.byte_lengths",
        },
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let byte_offsets = graph.add_resource(workspace(
        match target {
            LoweringTarget::X86_64 => "lir.x86.byte_offsets",
            LoweringTarget::Wasm => "lir.wasm.byte_offsets",
        },
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let byte_scan_blocks = capacities.target_instructions.max(1).div_ceil(256);
    let byte_scan_local = graph.add_resource(workspace(
        "lir.target.byte_scan_local",
        target_domain,
        LoweringCapacities::bytes::<u32>(capacities.target_instructions),
    ))?;
    let byte_scan_block_sum = graph.add_resource(workspace(
        "lir.target.byte_scan_block_sum",
        target_domain,
        LoweringCapacities::bytes::<u32>(byte_scan_blocks),
    ))?;
    let byte_scan_block_prefix = graph.add_resource(workspace(
        "lir.target.byte_scan_block_prefix",
        target_domain,
        LoweringCapacities::bytes::<u32>(byte_scan_blocks),
    ))?;
    let byte_scan_hierarchy = graph.add_resource(workspace(
        "lir.target.byte_scan_hierarchy",
        target_domain,
        LoweringCapacities::bytes::<u32>(byte_scan_blocks),
    ))?;
    let body_length = graph.add_resource(ResourceDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.body_length",
            LoweringTarget::Wasm => "lir.wasm.body_length",
        },
        domain: ResourceDomain::ArtifactBytes,
        class: ResourceClass::Workspace,
        bytes: LoweringCapacities::bytes::<u32>(1),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let output = graph.add_resource(ResourceDesc {
        name: match target {
            LoweringTarget::X86_64 => "artifact.x86.bytes",
            LoweringTarget::Wasm => "lir.wasm.body_bytes",
        },
        domain: ResourceDomain::ArtifactBytes,
        class: match target {
            LoweringTarget::X86_64 => ResourceClass::Output,
            LoweringTarget::Wasm => ResourceClass::Workspace,
        },
        // The byte emitter binds this storage as packed `u32` words. Keep the
        // logical capacity in bytes while making the physical binding large
        // enough and aligned even for a one-byte artifact.
        bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let x86_artifact = if target == LoweringTarget::X86_64 {
        Some(X86ArtifactGraphResources {
            body_length,
            entrypoint_state: graph.add_resource(workspace(
                "lir.x86.entrypoint_state",
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(3),
            ))?,
            layout: graph.add_resource(workspace(
                "lir.x86.artifact_layout",
                ResourceDomain::ArtifactBytes,
                LoweringCapacities::bytes::<X86ArtifactLayout>(1),
            ))?,
            artifact_length: graph.add_resource(ResourceDesc {
                name: "artifact.x86.length",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            artifact_bytes: output,
            artifact_length_readback: if include_object {
                None
            } else {
                Some(graph.add_storage(
                    "artifact.x86.length_readback",
                    ResourceDomain::ArtifactBytes,
                    ResourceClass::External,
                    LoweringCapacities::bytes::<u32>(1),
                )?)
            },
        })
    } else {
        None
    };
    let x86_object = if target == LoweringTarget::X86_64 && include_object {
        let relocation_capacity = capacities.semantic_instructions.max(1);
        let function_capacity = capacities.hir_nodes.max(1);
        let relocation_blocks = relocation_capacity.div_ceil(256);
        let function_blocks = function_capacity.div_ceil(256);
        let u32_rows = |graph: &mut CompilerGraphBuilder,
                        name: &'static str,
                        domain: ResourceDomain,
                        rows: u32|
         -> Result<ResourceId, String> {
            graph.add_resource(workspace(
                name,
                domain,
                LoweringCapacities::bytes::<u32>(rows),
            ))
        };
        Some(X86ObjectGraphResources {
            relocation_flags: u32_rows(
                &mut graph,
                "artifact.x86.object.relocation_flags",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            relocation_prefix: u32_rows(
                &mut graph,
                "artifact.x86.object.relocation_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            relocation_scan_local: u32_rows(
                &mut graph,
                "artifact.x86.object.relocation_scan_local",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            relocation_scan_block_sum: u32_rows(
                &mut graph,
                "artifact.x86.object.relocation_scan_block_sum",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            relocation_scan_block_prefix: u32_rows(
                &mut graph,
                "artifact.x86.object.relocation_scan_block_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            relocation_scan_hierarchy: u32_rows(
                &mut graph,
                "artifact.x86.object.relocation_scan_hierarchy",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            relocation_total: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.relocation_total",
                domain: ResourceDomain::SemanticInstructions,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            symbol_flags: u32_rows(
                &mut graph,
                "artifact.x86.object.symbol_flags",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            symbol_prefix: u32_rows(
                &mut graph,
                "artifact.x86.object.symbol_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            symbol_scan_local: u32_rows(
                &mut graph,
                "artifact.x86.object.symbol_scan_local",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            symbol_scan_block_sum: u32_rows(
                &mut graph,
                "artifact.x86.object.symbol_scan_block_sum",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            symbol_scan_block_prefix: u32_rows(
                &mut graph,
                "artifact.x86.object.symbol_scan_block_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            symbol_scan_hierarchy: u32_rows(
                &mut graph,
                "artifact.x86.object.symbol_scan_hierarchy",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            symbol_total: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.symbol_total",
                domain: ResourceDomain::SemanticInstructions,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            definition_flags: u32_rows(
                &mut graph,
                "artifact.x86.object.definition_flags",
                ResourceDomain::Declarations,
                function_capacity,
            )?,
            definition_prefix: u32_rows(
                &mut graph,
                "artifact.x86.object.definition_prefix",
                ResourceDomain::Declarations,
                function_capacity,
            )?,
            definition_scan_local: u32_rows(
                &mut graph,
                "artifact.x86.object.definition_scan_local",
                ResourceDomain::Declarations,
                function_capacity,
            )?,
            definition_scan_block_sum: u32_rows(
                &mut graph,
                "artifact.x86.object.definition_scan_block_sum",
                ResourceDomain::Declarations,
                function_blocks,
            )?,
            definition_scan_block_prefix: u32_rows(
                &mut graph,
                "artifact.x86.object.definition_scan_block_prefix",
                ResourceDomain::Declarations,
                function_blocks,
            )?,
            definition_scan_hierarchy: u32_rows(
                &mut graph,
                "artifact.x86.object.definition_scan_hierarchy",
                ResourceDomain::Declarations,
                function_blocks,
            )?,
            definition_total: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.definition_total",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            relocations: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.relocations",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<X86ObjectRelocationRow>(relocation_capacity),
                usage: WorkspaceUsageClass::Storage,
            })?,
            undefined_symbols: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.undefined_symbols",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<X86ObjectUndefinedRow>(relocation_capacity),
                usage: WorkspaceUsageClass::Storage,
            })?,
            definitions: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.definitions",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<X86ObjectDefinitionRow>(function_capacity),
                usage: WorkspaceUsageClass::Storage,
            })?,
            text_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.text_bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
            rodata_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.x86.object.rodata_bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
            metadata_readback: graph.add_storage(
                "artifact.x86.object.metadata_readback",
                ResourceDomain::ArtifactBytes,
                ResourceClass::External,
                64,
            )?,
        })
    } else {
        None
    };
    let wasm_module = if target == LoweringTarget::Wasm {
        let function_capacity = capacities.hir_nodes.max(1);
        let blocks = function_capacity.div_ceil(256);
        let u32_rows = |graph: &mut CompilerGraphBuilder,
                        name: &'static str,
                        rows: u32|
         -> Result<ResourceId, String> {
            graph.add_resource(workspace(
                name,
                ResourceDomain::Declarations,
                LoweringCapacities::bytes::<u32>(rows),
            ))
        };
        Some(WasmModuleGraphResources {
            type_lengths: u32_rows(
                &mut graph,
                "lir.wasm.module.type_lengths",
                function_capacity,
            )?,
            type_offsets: u32_rows(
                &mut graph,
                "lir.wasm.module.type_offsets",
                function_capacity,
            )?,
            type_scan_local: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_local",
                function_capacity,
            )?,
            type_scan_block_sum: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_block_sum",
                blocks,
            )?,
            type_scan_block_prefix: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_block_prefix",
                blocks,
            )?,
            type_scan_hierarchy: u32_rows(
                &mut graph,
                "lir.wasm.module.type_scan_hierarchy",
                blocks,
            )?,
            type_total: u32_rows(&mut graph, "lir.wasm.module.type_total", 1)?,
            code_lengths: u32_rows(
                &mut graph,
                "lir.wasm.module.code_lengths",
                function_capacity,
            )?,
            code_offsets: u32_rows(
                &mut graph,
                "lir.wasm.module.code_offsets",
                function_capacity,
            )?,
            code_scan_local: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_local",
                function_capacity,
            )?,
            code_scan_block_sum: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_block_sum",
                blocks,
            )?,
            code_scan_block_prefix: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_block_prefix",
                blocks,
            )?,
            code_scan_hierarchy: u32_rows(
                &mut graph,
                "lir.wasm.module.code_scan_hierarchy",
                blocks,
            )?,
            code_total: u32_rows(&mut graph, "lir.wasm.module.code_total", 1)?,
            entrypoint_state: u32_rows(&mut graph, "lir.wasm.module.entrypoint_state", 2)?,
            layout: graph.add_resource(workspace(
                "lir.wasm.module.layout",
                ResourceDomain::ArtifactBytes,
                LoweringCapacities::bytes::<WasmModuleLayout>(1),
            ))?,
            module_length: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.length",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            module_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
            module_length_readback: if include_object {
                None
            } else {
                Some(graph.add_storage(
                    "artifact.wasm.length_readback",
                    ResourceDomain::ArtifactBytes,
                    ResourceClass::External,
                    LoweringCapacities::bytes::<u32>(1),
                )?)
            },
        })
    } else {
        None
    };
    let wasm_object = if target == LoweringTarget::Wasm && include_object {
        let relocation_capacity = capacities.semantic_instructions.max(1);
        let function_capacity = capacities.hir_nodes.max(1);
        let relocation_blocks = relocation_capacity.div_ceil(256);
        let function_blocks = function_capacity.div_ceil(256);
        let u32_rows = |graph: &mut CompilerGraphBuilder,
                        name: &'static str,
                        domain: ResourceDomain,
                        rows: u32|
         -> Result<ResourceId, String> {
            graph.add_resource(workspace(
                name,
                domain,
                LoweringCapacities::bytes::<u32>(rows),
            ))
        };
        Some(WasmObjectGraphResources {
            relocation_flags: u32_rows(
                &mut graph,
                "artifact.wasm.object.relocation_flags",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            relocation_prefix: u32_rows(
                &mut graph,
                "artifact.wasm.object.relocation_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            relocation_scan_local: u32_rows(
                &mut graph,
                "artifact.wasm.object.relocation_scan_local",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            relocation_scan_block_sum: u32_rows(
                &mut graph,
                "artifact.wasm.object.relocation_scan_block_sum",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            relocation_scan_block_prefix: u32_rows(
                &mut graph,
                "artifact.wasm.object.relocation_scan_block_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            relocation_scan_hierarchy: u32_rows(
                &mut graph,
                "artifact.wasm.object.relocation_scan_hierarchy",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            relocation_total: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.relocation_total",
                domain: ResourceDomain::SemanticInstructions,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            symbol_flags: u32_rows(
                &mut graph,
                "artifact.wasm.object.symbol_flags",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            symbol_prefix: u32_rows(
                &mut graph,
                "artifact.wasm.object.symbol_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            symbol_scan_local: u32_rows(
                &mut graph,
                "artifact.wasm.object.symbol_scan_local",
                ResourceDomain::SemanticInstructions,
                relocation_capacity,
            )?,
            symbol_scan_block_sum: u32_rows(
                &mut graph,
                "artifact.wasm.object.symbol_scan_block_sum",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            symbol_scan_block_prefix: u32_rows(
                &mut graph,
                "artifact.wasm.object.symbol_scan_block_prefix",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            symbol_scan_hierarchy: u32_rows(
                &mut graph,
                "artifact.wasm.object.symbol_scan_hierarchy",
                ResourceDomain::SemanticInstructions,
                relocation_blocks,
            )?,
            symbol_total: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.symbol_total",
                domain: ResourceDomain::SemanticInstructions,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            definition_flags: u32_rows(
                &mut graph,
                "artifact.wasm.object.definition_flags",
                ResourceDomain::Declarations,
                function_capacity,
            )?,
            definition_prefix: u32_rows(
                &mut graph,
                "artifact.wasm.object.definition_prefix",
                ResourceDomain::Declarations,
                function_capacity,
            )?,
            definition_scan_local: u32_rows(
                &mut graph,
                "artifact.wasm.object.definition_scan_local",
                ResourceDomain::Declarations,
                function_capacity,
            )?,
            definition_scan_block_sum: u32_rows(
                &mut graph,
                "artifact.wasm.object.definition_scan_block_sum",
                ResourceDomain::Declarations,
                function_blocks,
            )?,
            definition_scan_block_prefix: u32_rows(
                &mut graph,
                "artifact.wasm.object.definition_scan_block_prefix",
                ResourceDomain::Declarations,
                function_blocks,
            )?,
            definition_scan_hierarchy: u32_rows(
                &mut graph,
                "artifact.wasm.object.definition_scan_hierarchy",
                ResourceDomain::Declarations,
                function_blocks,
            )?,
            definition_total: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.definition_total",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<u32>(1),
                usage: WorkspaceUsageClass::Storage,
            })?,
            relocations: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.relocations",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<WasmObjectRelocationRow>(relocation_capacity),
                usage: WorkspaceUsageClass::Storage,
            })?,
            functions: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.functions",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<WasmObjectFunctionRow>(function_capacity),
                usage: WorkspaceUsageClass::Storage,
            })?,
            definitions: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.definitions",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: LoweringCapacities::bytes::<WasmObjectDefinitionRow>(function_capacity),
                usage: WorkspaceUsageClass::Storage,
            })?,
            type_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.type_bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
            body_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.body_bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
            data_bytes: graph.add_resource(ResourceDesc {
                name: "artifact.wasm.object.data_bytes",
                domain: ResourceDomain::ArtifactBytes,
                class: ResourceClass::Output,
                bytes: u64::from(capacities.artifact_bytes.max(1).div_ceil(4) * 4),
                usage: WorkspaceUsageClass::Storage,
            })?,
            metadata_readback: graph.add_storage(
                "artifact.wasm.object.metadata_readback",
                ResourceDomain::ArtifactBytes,
                ResourceClass::External,
                96,
            )?,
        })
    } else {
        None
    };

    let schedule_radix_layout = TargetScheduleRadixLayout::for_capacities(capacities);
    if schedule_radix_layout.steps > TARGET_SCHEDULE_MAX_RADIX_STEPS {
        return Err(format!(
            "semantic schedule requires {} packed bits, exceeding the {}-bit resident key capacity",
            schedule_radix_layout.total_bits,
            TARGET_SCHEDULE_MAX_RADIX_STEPS * 8,
        ));
    }
    let schedule_resources = ScheduleGraphResources {
        total: semantic_total,
        keys: semantic_schedule,
        order: schedule_order,
        order_tmp: schedule_order_tmp,
        slot_count: schedule_slot_count,
        histogram: schedule_histogram,
        global_prefix: schedule_global_prefix,
        scan_local: schedule_scan_local,
        scan_block_sum: schedule_scan_block_sum,
        scan_block_prefix: schedule_scan_block_prefix,
        scan_hierarchy: schedule_scan_hierarchy,
        scan_total: schedule_scan_total,
    };
    add_schedule_graph_passes(
        &mut graph,
        CompilerPhase::SemanticLowering,
        ResourceDomain::SemanticInstructions,
        schedule_resources,
        schedule_radix_layout.steps,
    )?;
    if target == LoweringTarget::X86_64 {
        graph.add_pass(PassDesc {
            name: "lir.x86.analysis.clear",
            phase: target_phase,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::write(
                    "x86_position_by_semantic",
                    x86_position_by_semantic.unwrap(),
                ),
                PassAccess::write(
                    "x86_last_use_by_semantic",
                    x86_last_use_by_semantic.unwrap(),
                ),
                PassAccess::write(
                    "x86_next_rax_clobber_by_semantic",
                    x86_next_rax_clobber_by_semantic.unwrap(),
                ),
                PassAccess::write("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
                PassAccess::write("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
                PassAccess::write(
                    "x86_location_by_semantic",
                    x86_location_by_semantic.unwrap(),
                ),
                PassAccess::write("x86_function_start", x86_function_start.unwrap()),
                PassAccess::write("x86_function_end", x86_function_end.unwrap()),
                PassAccess::write(
                    "x86_register_analysis_by_function",
                    x86_register_analysis_by_function.unwrap(),
                ),
                PassAccess::write(
                    "x86_decl_analysis_by_token",
                    x86_decl_analysis_by_token.unwrap(),
                ),
                PassAccess::write(
                    "x86_stack_slot_count_by_function",
                    x86_stack_slot_count_by_function.unwrap(),
                ),
                PassAccess::write(
                    "x86_frame_slot_count_by_function",
                    x86_frame_slot_count_by_function.unwrap(),
                ),
                PassAccess::write(
                    "x86_saved_gpr_mask_by_function",
                    x86_saved_gpr_mask_by_function.unwrap(),
                ),
                PassAccess::write(
                    "x86_decl_location_by_token",
                    x86_decl_location_by_token.unwrap(),
                ),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.analysis.index",
            phase: target_phase,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::read("semantic_lir_total", semantic_total),
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("semantic_schedule_order", schedule_order),
                PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::write(
                    "x86_position_by_semantic",
                    x86_position_by_semantic.unwrap(),
                ),
                PassAccess::write(
                    "x86_last_use_by_semantic",
                    x86_last_use_by_semantic.unwrap(),
                ),
                PassAccess::read_write("x86_function_start", x86_function_start.unwrap()),
                PassAccess::read_write("x86_function_end", x86_function_end.unwrap()),
                PassAccess::read_write(
                    "x86_decl_analysis_by_token",
                    x86_decl_analysis_by_token.unwrap(),
                ),
            ],
        })?;
        let x86_function_accesses = vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read("semantic_owner_by_instruction", semantic_owner),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::read(
                "semantic_lir_call_arg_count_by_hir",
                semantic_call_arg_counts_by_hir,
            ),
            PassAccess::read(
                "semantic_lir_call_arg_start_by_hir",
                semantic_call_arg_prefix_by_hir,
            ),
            PassAccess::read("semantic_lir_call_args", semantic_call_args),
            PassAccess::read(
                "semantic_lir_aggregate_element_total",
                semantic_aggregate_element_total,
            ),
            PassAccess::read(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read("semantic_lir_function_total", semantic_function_total),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read("semantic_lir_params", semantic_params),
            PassAccess::read("semantic_lir_locals", semantic_locals),
            PassAccess::read_write(
                "x86_position_by_semantic",
                x86_position_by_semantic.unwrap(),
            ),
            PassAccess::read_write(
                "x86_last_use_by_semantic",
                x86_last_use_by_semantic.unwrap(),
            ),
            PassAccess::write(
                "x86_next_rax_clobber_by_semantic",
                x86_next_rax_clobber_by_semantic.unwrap(),
            ),
            PassAccess::read_write("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
            PassAccess::read_write("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
            PassAccess::write(
                "x86_location_by_semantic",
                x86_location_by_semantic.unwrap(),
            ),
            PassAccess::read("x86_function_start", x86_function_start.unwrap()),
            PassAccess::read("x86_function_end", x86_function_end.unwrap()),
            PassAccess::read_write(
                "x86_decl_analysis_by_token",
                x86_decl_analysis_by_token.unwrap(),
            ),
            PassAccess::write("x86_select_by_semantic", x86_select_by_semantic.unwrap()),
            PassAccess::write(
                "x86_register_analysis_by_function",
                x86_register_analysis_by_function.unwrap(),
            ),
            PassAccess::write(
                "x86_stack_slot_count_by_function",
                x86_stack_slot_count_by_function.unwrap(),
            ),
            PassAccess::write(
                "x86_frame_slot_count_by_function",
                x86_frame_slot_count_by_function.unwrap(),
            ),
            PassAccess::write(
                "x86_saved_gpr_mask_by_function",
                x86_saved_gpr_mask_by_function.unwrap(),
            ),
        ];
        graph.add_pass(PassDesc {
            name: "lir.x86.optimize.functions",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: x86_function_accesses.clone(),
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.if_convert",
            phase: target_phase,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::read("semantic_lir_total", semantic_total),
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("semantic_schedule_order", schedule_order),
                PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::read(
                    "x86_position_by_semantic",
                    x86_position_by_semantic.unwrap(),
                ),
                PassAccess::read_write(
                    "x86_last_use_by_semantic",
                    x86_last_use_by_semantic.unwrap(),
                ),
                PassAccess::read_write("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
                PassAccess::read("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
                PassAccess::read(
                    "x86_decl_analysis_by_token",
                    x86_decl_analysis_by_token.unwrap(),
                ),
                PassAccess::write("x86_select_by_semantic", x86_select_by_semantic.unwrap()),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.allocate.functions",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: x86_function_accesses,
        })?;
    }
    let target_count_accesses = match target {
        LoweringTarget::Wasm => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::write("target_lir_count", target_counts),
        ],
        LoweringTarget::X86_64 => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read(
                "semantic_lir_layout_word_offset",
                semantic_layout_word_offset,
            ),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read("semantic_owner_by_instruction", semantic_owner),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::read(
                "semantic_lir_call_arg_count_by_hir",
                semantic_call_arg_counts_by_hir,
            ),
            PassAccess::read(
                "semantic_lir_call_arg_start_by_hir",
                semantic_call_arg_prefix_by_hir,
            ),
            PassAccess::read("semantic_lir_call_args", semantic_call_args),
            PassAccess::read("semantic_lir_function_total", semantic_function_total),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read("semantic_lir_params", semantic_params),
            PassAccess::read("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
            PassAccess::read(
                "semantic_lir_aggregate_element_total",
                semantic_aggregate_element_total,
            ),
            PassAccess::read(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::write("target_lir_count", target_counts),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    };
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.count",
            LoweringTarget::Wasm => "lir.wasm.count",
        },
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: target_count_accesses,
    })?;
    let target_scatter_accesses = match target {
        LoweringTarget::Wasm => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read(
                "semantic_lir_layout_word_offset",
                semantic_layout_word_offset,
            ),
            PassAccess::read("semantic_owner_by_instruction", semantic_owner),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read("semantic_lir_string_total", semantic_string_total),
            PassAccess::read("semantic_lir_strings", semantic_strings),
            PassAccess::read("target_lir_offset", target_offsets),
            PassAccess::read("target_lir_total", target_total),
            PassAccess::write("semantic_to_target_start", semantic_to_target_start),
            PassAccess::write("target_lir_core", target_core),
            PassAccess::write(
                "target_lir_operands",
                target_operands.expect("Wasm operand resource"),
            ),
        ],
        LoweringTarget::X86_64 => vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_lir_core", semantic_core),
            PassAccess::read("semantic_lir_operands", semantic_operands),
            PassAccess::read(
                "semantic_lir_layout_word_offset",
                semantic_layout_word_offset,
            ),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read("semantic_owner_by_instruction", semantic_owner),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::read(
                "semantic_lir_call_arg_count_by_hir",
                semantic_call_arg_counts_by_hir,
            ),
            PassAccess::read(
                "semantic_lir_call_arg_start_by_hir",
                semantic_call_arg_prefix_by_hir,
            ),
            PassAccess::read("semantic_lir_call_args", semantic_call_args),
            PassAccess::read(
                "semantic_lir_aggregate_element_total",
                semantic_aggregate_element_total,
            ),
            PassAccess::read(
                "semantic_lir_aggregate_elements",
                semantic_aggregate_elements,
            ),
            PassAccess::read("semantic_lir_string_total", semantic_string_total),
            PassAccess::read("semantic_lir_function_total", semantic_function_total),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
            PassAccess::read("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
            PassAccess::read("x86_select_by_semantic", x86_select_by_semantic.unwrap()),
            PassAccess::read("target_lir_offset", target_offsets),
            PassAccess::read("target_lir_total", target_total),
            PassAccess::write("semantic_to_target_start", semantic_to_target_start),
            PassAccess::write("target_lir_core", target_core),
            PassAccess::write(
                "target_lir_operands",
                target_operands.expect("x86 operand resource"),
            ),
            PassAccess::write(
                "target_semantic_origin",
                target_semantic_origins.expect("x86 semantic origin resource"),
            ),
            PassAccess::write(
                "target_lir_flags",
                x86_target_flags.expect("x86 target flag resource"),
            ),
        ],
    };
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.local",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_input", target_counts),
            PassAccess::write("scan_local_prefix", target_scan_local),
            PassAccess::write("scan_block_sum", target_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.hierarchy_up",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_block_sum", target_scan_block_sum),
            PassAccess::write("scan_block_prefix", target_scan_block_prefix),
            PassAccess::write("scan_hierarchy", target_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.hierarchy_down",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read_write("scan_block_prefix", target_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", target_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.count_scan.apply",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_local_prefix", target_scan_local),
            PassAccess::read("scan_block_prefix", target_scan_block_prefix),
            PassAccess::write("scan_output_prefix", target_offsets),
            PassAccess::write("scan_total", target_total),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.semantic_page_plan",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("target_lir_offset", target_offsets),
            PassAccess::read("target_lir_total", target_total),
            PassAccess::write("target_semantic_pages", target_semantic_pages),
        ],
    })?;
    if let Some(wasm) = wasm_abi {
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_widths",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::write("wasm_param_width", wasm.param_widths),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.local",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read("scan_input", wasm.param_widths),
                PassAccess::write("scan_local_prefix", wasm.param_scan_local),
                PassAccess::write("scan_block_sum", wasm.param_scan_block_sum),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.hierarchy_up",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read("scan_block_sum", wasm.param_scan_block_sum),
                PassAccess::write("scan_block_prefix", wasm.param_scan_block_prefix),
                PassAccess::write("scan_hierarchy", wasm.param_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.hierarchy_down",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read_write("scan_block_prefix", wasm.param_scan_block_prefix),
                PassAccess::read_write("scan_hierarchy", wasm.param_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.param_scan.apply",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_param_total),
                PassAccess::read("scan_local_prefix", wasm.param_scan_local),
                PassAccess::read("scan_block_prefix", wasm.param_scan_block_prefix),
                PassAccess::write("scan_output_prefix", wasm.param_prefix),
                PassAccess::write("scan_total", wasm.param_value_total),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_widths",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::write("wasm_local_width", wasm.local_widths),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.local",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read("scan_input", wasm.local_widths),
                PassAccess::write("scan_local_prefix", wasm.local_scan_local),
                PassAccess::write("scan_block_sum", wasm.local_scan_block_sum),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.hierarchy_up",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read("scan_block_sum", wasm.local_scan_block_sum),
                PassAccess::write("scan_block_prefix", wasm.local_scan_block_prefix),
                PassAccess::write("scan_hierarchy", wasm.local_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.hierarchy_down",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read_write("scan_block_prefix", wasm.local_scan_block_prefix),
                PassAccess::read_write("scan_hierarchy", wasm.local_scan_hierarchy),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.local_scan.apply",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("scan_count", semantic_local_total),
                PassAccess::read("scan_local_prefix", wasm.local_scan_local),
                PassAccess::read("scan_block_prefix", wasm.local_scan_block_prefix),
                PassAccess::write("scan_output_prefix", wasm.local_prefix),
                PassAccess::write("scan_total", wasm.local_value_total),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.functions",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("wasm_param_prefix", wasm.param_prefix),
                PassAccess::read("wasm_param_value_total", wasm.param_value_total),
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("wasm_local_prefix", wasm.local_prefix),
                PassAccess::read("wasm_local_value_total", wasm.local_value_total),
                PassAccess::write("wasm_lir_functions", wasm.functions),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.declaration_indices",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("wasm_param_prefix", wasm.param_prefix),
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::read("wasm_local_prefix", wasm.local_prefix),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::write("wasm_local_index_by_decl_token", wasm.local_index_by_token),
            ],
        })?;
    }
    let function_flags = graph.add_resource(workspace(
        "lir.target.function_flags",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let function_prefix = graph.add_resource(workspace(
        "lir.target.function_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let function_scan_local = graph.add_resource(workspace(
        "lir.target.function_scan_local",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(capacities.semantic_instructions),
    ))?;
    let function_scan_blocks = capacities.semantic_instructions.max(1).div_ceil(256);
    let function_scan_block_sum = graph.add_resource(workspace(
        "lir.target.function_scan_block_sum",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(function_scan_blocks),
    ))?;
    let function_scan_block_prefix = graph.add_resource(workspace(
        "lir.target.function_scan_block_prefix",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(function_scan_blocks),
    ))?;
    let function_scan_hierarchy = graph.add_resource(workspace(
        "lir.target.function_scan_hierarchy",
        ResourceDomain::SemanticInstructions,
        LoweringCapacities::bytes::<u32>(function_scan_blocks),
    ))?;
    let function_count = graph.add_resource(ResourceDesc {
        name: "lir.target.function_count",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<u32>(1),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let function_starts = graph.add_resource(workspace(
        "lir.target.function_starts",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let compact_function_ids = graph.add_resource(workspace(
        "lir.target.compact_function_ids",
        ResourceDomain::Declarations,
        LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
    ))?;
    let functions = graph.add_resource(ResourceDesc {
        name: "lir.target.functions",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<TargetLirFunction>(capacities.hir_nodes),
        usage: WorkspaceUsageClass::Storage,
    })?;
    let function_index_by_semantic = graph.add_resource(ResourceDesc {
        name: "lir.target.function_index_by_semantic",
        domain: ResourceDomain::Declarations,
        class: ResourceClass::Output,
        bytes: LoweringCapacities::bytes::<u32>(capacities.hir_nodes),
        usage: WorkspaceUsageClass::Storage,
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.functions.mark",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read("semantic_owner_by_instruction", semantic_owner),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::write("function_start_flag", function_flags),
            PassAccess::write("function_index_by_semantic", function_index_by_semantic),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.local",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_input", function_flags),
            PassAccess::write("scan_local_prefix", function_scan_local),
            PassAccess::write("scan_block_sum", function_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.hierarchy_up",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_block_sum", function_scan_block_sum),
            PassAccess::write("scan_block_prefix", function_scan_block_prefix),
            PassAccess::write("scan_hierarchy", function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.hierarchy_down",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read_write("scan_block_prefix", function_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", function_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.function_scan.apply",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("scan_count", semantic_total),
            PassAccess::read("scan_local_prefix", function_scan_local),
            PassAccess::read("scan_block_prefix", function_scan_block_prefix),
            PassAccess::write("scan_output_prefix", function_prefix),
            PassAccess::write("scan_total", function_count),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.functions.scatter_starts",
        phase: target_phase,
        dispatch_domain: ResourceDomain::SemanticInstructions,
        accesses: vec![
            PassAccess::read("semantic_lir_total", semantic_total),
            PassAccess::read("semantic_schedule_order", schedule_order),
            PassAccess::read("semantic_owner_by_instruction", semantic_owner),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::read("target_lir_offset", target_offsets),
            PassAccess::read("function_start_flag", function_flags),
            PassAccess::read("function_prefix", function_prefix),
            PassAccess::write("function_start", function_starts),
            PassAccess::write("compact_function_id", compact_function_ids),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.functions.finalize",
        phase: target_phase,
        dispatch_domain: ResourceDomain::Declarations,
        accesses: vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("function_count", function_count),
            PassAccess::read("function_start", function_starts),
            PassAccess::read("compact_function_id", compact_function_ids),
            PassAccess::write("target_function", functions),
            PassAccess::write("function_index_by_semantic", function_index_by_semantic),
        ],
    })?;
    if target == LoweringTarget::X86_64 {
        graph.add_pass(PassDesc {
            name: "lir.x86.decl_slots.scatter",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_param_total", semantic_param_total),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("semantic_lir_local_total", semantic_local_total),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read_write(
                    "x86_decl_location_by_token",
                    x86_decl_location_by_token.expect("x86 declaration location resource"),
                ),
                PassAccess::read_write(
                    "x86_saved_gpr_mask_by_function",
                    x86_saved_gpr_mask_by_function.expect("x86 saved-register resource"),
                ),
                PassAccess::read(
                    "x86_register_analysis_by_function",
                    x86_register_analysis_by_function
                        .expect("x86 function register analysis resource"),
                ),
                PassAccess::read(
                    "x86_decl_analysis_by_token",
                    x86_decl_analysis_by_token.expect("x86 declaration analysis resource"),
                ),
                PassAccess::read(
                    "x86_live_by_semantic",
                    x86_live_by_semantic.expect("x86 semantic liveness resource"),
                ),
                PassAccess::read(
                    "x86_stack_slot_count_by_function",
                    x86_stack_slot_count_by_function.expect("x86 stack-slot count resource"),
                ),
                PassAccess::read_write(
                    "x86_frame_slot_count_by_function",
                    x86_frame_slot_count_by_function.expect("x86 frame-slot count resource"),
                ),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.frame.finalize",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("target_function_count", function_count),
                PassAccess::read_write("target_functions", functions),
                PassAccess::read(
                    "x86_frame_slot_count_by_function",
                    x86_frame_slot_count_by_function.expect("x86 frame-slot count resource"),
                ),
                PassAccess::read(
                    "x86_saved_gpr_mask_by_function",
                    x86_saved_gpr_mask_by_function.expect("x86 saved-register resource"),
                ),
                PassAccess::read(
                    "x86_register_analysis_by_function",
                    x86_register_analysis_by_function
                        .expect("x86 function register analysis resource"),
                ),
            ],
        })?;
    }
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.scatter",
            LoweringTarget::Wasm => "lir.wasm.scatter",
        },
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: target_scatter_accesses.clone(),
    })?;
    if target == LoweringTarget::X86_64 {
        graph.add_pass(PassDesc {
            name: "lir.x86.locations",
            phase: target_phase,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("target_lir_operands", target_operands.unwrap()),
                PassAccess::read("target_semantic_origin", target_semantic_origins.unwrap()),
                PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                PassAccess::read(
                    "x86_location_by_semantic",
                    x86_location_by_semantic.unwrap(),
                ),
                PassAccess::read("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
                PassAccess::read("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
                PassAccess::read(
                    "x86_decl_analysis_by_token",
                    x86_decl_analysis_by_token.expect("x86 declaration analysis resource"),
                ),
                PassAccess::read(
                    "x86_decl_location_by_token",
                    x86_decl_location_by_token.expect("x86 declaration location resource"),
                ),
                PassAccess::read(
                    "x86_select_by_semantic",
                    x86_select_by_semantic.expect("x86 select resource"),
                ),
                PassAccess::write("target_lir_locations", x86_target_locations.unwrap()),
            ],
        })?;
    }
    match target {
        LoweringTarget::Wasm => {
            let wasm = wasm_abi.expect("Wasm ABI resources");
            graph.add_pass(PassDesc {
                name: "lir.wasm.resolve_indices",
                phase: target_phase,
                dispatch_domain: target_domain,
                accesses: vec![
                    PassAccess::read("target_lir_total", target_total),
                    PassAccess::read("wasm_local_index_by_decl_token", wasm.local_index_by_token),
                    PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                    PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                    PassAccess::read("wasm_lir_functions", wasm.functions),
                    PassAccess::read("target_lir_operands", target_operands.unwrap()),
                    PassAccess::read_write("target_lir_core", target_core),
                ],
            })?;
        }
        LoweringTarget::X86_64 => {
            graph.add_pass(PassDesc {
                name: "lir.x86.resolve",
                phase: target_phase,
                dispatch_domain: target_domain,
                accesses: vec![
                    PassAccess::read("target_lir_total", target_total),
                    PassAccess::read_write("target_lir_core", target_core),
                    PassAccess::read_write(
                        "target_lir_operands",
                        target_operands.expect("x86 operand resource"),
                    ),
                    PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                    PassAccess::read("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
                    PassAccess::read(
                        "target_semantic_origin",
                        target_semantic_origins.expect("x86 semantic origin resource"),
                    ),
                ],
            })?;
        }
    }
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.validate",
            LoweringTarget::Wasm => "lir.wasm.validate",
        },
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: match target {
            LoweringTarget::Wasm => vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
            LoweringTarget::X86_64 => vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read(
                    "target_lir_flags",
                    x86_target_flags.expect("x86 target flag resource"),
                ),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
        },
    })?;
    let byte_count_accesses = match target {
        LoweringTarget::Wasm => vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("target_lir_core", target_core),
            PassAccess::write("target_byte_length", byte_lengths),
        ],
        LoweringTarget::X86_64 => vec![
            PassAccess::read("target_lir_total", target_total),
            PassAccess::read("target_lir_core", target_core),
            // x86 encoding size depends on virtual operands and register/
            // addressing forms, unlike Wasm's opcode/immediate record.
            PassAccess::read(
                "target_lir_operands",
                target_operands.expect("x86 operand resource"),
            ),
            PassAccess::read(
                "target_lir_locations",
                x86_target_locations.expect("x86 location resource"),
            ),
            PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
            PassAccess::read("target_function_count", function_count),
            PassAccess::read("target_functions", functions),
            PassAccess::read(
                "target_function_index_by_semantic",
                function_index_by_semantic,
            ),
            PassAccess::read("semantic_lir_function_total", semantic_function_total),
            PassAccess::read("semantic_lir_functions", semantic_functions),
            PassAccess::read("semantic_lir_params", semantic_params),
            PassAccess::read(
                "x86_decl_location_by_token",
                x86_decl_location_by_token.expect("x86 declaration location resource"),
            ),
            PassAccess::read(
                "x86_saved_gpr_mask_by_function",
                x86_saved_gpr_mask_by_function.expect("x86 saved-register resource"),
            ),
            PassAccess::write("target_byte_length", byte_lengths),
            PassAccess::read_write("lowering_status", lowering_status),
        ],
    };
    graph.add_pass(PassDesc {
        name: match target {
            LoweringTarget::X86_64 => "lir.x86.byte_count",
            LoweringTarget::Wasm => "lir.wasm.byte_count",
        },
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: byte_count_accesses,
    })?;
    graph.repeat_pass_range(
        target_page_count,
        match target {
            LoweringTarget::X86_64 => "lir.x86.scatter",
            LoweringTarget::Wasm => "lir.wasm.scatter",
        },
        match target {
            LoweringTarget::X86_64 => "lir.x86.byte_count",
            LoweringTarget::Wasm => "lir.wasm.byte_count",
        },
    )?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.local",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_input", byte_lengths),
            PassAccess::write("scan_local_prefix", byte_scan_local),
            PassAccess::write("scan_block_sum", byte_scan_block_sum),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.hierarchy_up",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_block_sum", byte_scan_block_sum),
            PassAccess::write("scan_block_prefix", byte_scan_block_prefix),
            PassAccess::write("scan_hierarchy", byte_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.hierarchy_down",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read_write("scan_block_prefix", byte_scan_block_prefix),
            PassAccess::read_write("scan_hierarchy", byte_scan_hierarchy),
        ],
    })?;
    graph.add_pass(PassDesc {
        name: "lir.target.byte_scan.apply",
        phase: target_phase,
        dispatch_domain: target_domain,
        accesses: vec![
            PassAccess::read("scan_count", target_total),
            PassAccess::read("scan_local_prefix", byte_scan_local),
            PassAccess::read("scan_block_prefix", byte_scan_block_prefix),
            PassAccess::write("scan_output_prefix", byte_offsets),
            PassAccess::write("scan_total", body_length),
        ],
    })?;
    if let Some(wasm) = wasm_abi {
        graph.add_pass(PassDesc {
            name: "lir.wasm.abi.attach_bodies",
            phase: target_phase,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read_write("wasm_lir_functions", wasm.functions),
            ],
        })?;
    }
    if target == LoweringTarget::Wasm {
        graph.add_pass(PassDesc {
            name: "lir.wasm.scatter.replay",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: target_scatter_accesses.clone(),
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.resolve_indices.replay",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read(
                    "wasm_local_index_by_decl_token",
                    wasm_abi.expect("Wasm ABI resources").local_index_by_token,
                ),
                PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::read(
                    "wasm_lir_functions",
                    wasm_abi.expect("Wasm ABI resources").functions,
                ),
                PassAccess::read(
                    "target_lir_operands",
                    target_operands.expect("Wasm operand resource"),
                ),
                PassAccess::read_write("target_lir_core", target_core),
            ],
        })?;
    }
    if let Some(x86) = x86_artifact {
        graph.add_pass(PassDesc {
            name: "lir.x86.entrypoint.clear",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![PassAccess::write(
                "x86_entrypoint_state",
                x86.entrypoint_state,
            )],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.entrypoint.reduce",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read_write("x86_entrypoint_state", x86.entrypoint_state),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.artifact.layout",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("x86_body_length", x86.body_length),
                PassAccess::read("x86_entrypoint_state", x86.entrypoint_state),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("semantic_lir_string_pool_len", semantic_string_pool_len),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::write("x86_artifact_layout", x86.layout),
                PassAccess::write("x86_artifact_length", x86.artifact_length),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
        })?;
        if x86_object.is_some() {
            graph.add_pass(PassDesc {
                name: "artifact.x86.object.normalize_status",
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::ArtifactBytes,
                accesses: vec![
                    PassAccess::read("x86_entrypoint_state", x86.entrypoint_state),
                    PassAccess::read_write("x86_artifact_layout", x86.layout),
                    PassAccess::read_write("lowering_status", lowering_status),
                ],
            })?;
        }
        graph.add_pass(PassDesc {
            name: "lir.x86.artifact.clear",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![PassAccess::write("artifact_bytes", x86.artifact_bytes)],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.scatter.replay",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: target_scatter_accesses,
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.locations.replay",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("target_lir_operands", target_operands.unwrap()),
                PassAccess::read("target_semantic_origin", target_semantic_origins.unwrap()),
                PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                PassAccess::read(
                    "x86_location_by_semantic",
                    x86_location_by_semantic.unwrap(),
                ),
                PassAccess::read("x86_live_by_semantic", x86_live_by_semantic.unwrap()),
                PassAccess::read("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
                PassAccess::read(
                    "x86_decl_analysis_by_token",
                    x86_decl_analysis_by_token.expect("x86 declaration analysis resource"),
                ),
                PassAccess::read(
                    "x86_decl_location_by_token",
                    x86_decl_location_by_token.expect("x86 declaration location resource"),
                ),
                PassAccess::read(
                    "x86_select_by_semantic",
                    x86_select_by_semantic.expect("x86 select resource"),
                ),
                PassAccess::write("target_lir_locations", x86_target_locations.unwrap()),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.resolve.replay",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read_write("target_lir_core", target_core),
                PassAccess::read_write(
                    "target_lir_operands",
                    target_operands.expect("x86 operand resource"),
                ),
                PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                PassAccess::read("x86_value_by_semantic", x86_value_by_semantic.unwrap()),
                PassAccess::read(
                    "target_semantic_origin",
                    target_semantic_origins.expect("x86 semantic origin resource"),
                ),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.safety.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("target_lir_operands", target_operands.unwrap()),
                PassAccess::read("target_lir_locations", x86_target_locations.unwrap()),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read(
                    "x86_decl_location_by_token",
                    x86_decl_location_by_token.expect("x86 declaration location resource"),
                ),
                PassAccess::read(
                    "x86_saved_gpr_mask_by_function",
                    x86_saved_gpr_mask_by_function.expect("x86 saved-register resource"),
                ),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("x86_artifact_layout", x86.layout),
                PassAccess::write("artifact_bytes", x86.artifact_bytes),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.x86.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read(
                    "target_lir_operands",
                    target_operands.expect("x86 operand resource"),
                ),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("semantic_lir_string_total", semantic_string_total),
                PassAccess::read("semantic_lir_strings", semantic_strings),
                PassAccess::read("semantic_lir_string_pool_len", semantic_string_pool_len),
                PassAccess::read("semantic_lir_string_data", semantic_string_data),
                PassAccess::read(
                    "x86_decl_location_by_token",
                    x86_decl_location_by_token.expect("x86 declaration location resource"),
                ),
                PassAccess::read(
                    "x86_saved_gpr_mask_by_function",
                    x86_saved_gpr_mask_by_function.expect("x86 saved-register resource"),
                ),
                PassAccess::read("target_lir_locations", x86_target_locations.unwrap()),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("x86_artifact_layout", x86.layout),
                PassAccess::write("artifact_bytes", x86.artifact_bytes),
            ],
        })?;
        graph.repeat_pass_range(target_page_count, "lir.x86.scatter.replay", "lir.x86.emit")?;
        graph.add_pass(PassDesc {
            name: "lir.x86.runtime.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("x86_artifact_layout", x86.layout),
                PassAccess::write("artifact_bytes", x86.artifact_bytes),
            ],
        })?;
    } else {
        graph.add_pass(PassDesc {
            name: "lir.wasm.emit",
            phase: CompilerPhase::Artifact,
            dispatch_domain: target_domain,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("target_lir_core", target_core),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("artifact_length", body_length),
                PassAccess::write("artifact_bytes", output),
            ],
        })?;
        graph.repeat_pass_range(
            target_page_count,
            "lir.wasm.scatter.replay",
            "lir.wasm.emit",
        )?;
    }

    if let (Some(artifact), Some(object)) = (x86_artifact, x86_object) {
        graph.add_pass(PassDesc {
            name: "artifact.x86.object.relocation_flags",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::read("semantic_lir_total", semantic_total),
                PassAccess::read("semantic_schedule_order", schedule_order),
                PassAccess::read("semantic_op_by_instruction", semantic_op),
                PassAccess::write("x86_object_relocation_flag", object.relocation_flags),
                PassAccess::write("x86_object_symbol_flag", object.symbol_flags),
            ],
        })?;
        for (name, accesses) in [
            (
                "artifact.x86.object.relocation_scan.local",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_input", object.relocation_flags),
                    PassAccess::write("scan_local_prefix", object.relocation_scan_local),
                    PassAccess::write("scan_block_sum", object.relocation_scan_block_sum),
                ],
            ),
            (
                "artifact.x86.object.relocation_scan.hierarchy_up",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_block_sum", object.relocation_scan_block_sum),
                    PassAccess::write("scan_block_prefix", object.relocation_scan_block_prefix),
                    PassAccess::write("scan_hierarchy", object.relocation_scan_hierarchy),
                ],
            ),
            (
                "artifact.x86.object.relocation_scan.hierarchy_down",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read_write(
                        "scan_block_prefix",
                        object.relocation_scan_block_prefix,
                    ),
                    PassAccess::read_write("scan_hierarchy", object.relocation_scan_hierarchy),
                ],
            ),
            (
                "artifact.x86.object.relocation_scan.apply",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_local_prefix", object.relocation_scan_local),
                    PassAccess::read("scan_block_prefix", object.relocation_scan_block_prefix),
                    PassAccess::write("scan_output_prefix", object.relocation_prefix),
                    PassAccess::write("scan_total", object.relocation_total),
                ],
            ),
            (
                "artifact.x86.object.symbol_scan.local",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_input", object.symbol_flags),
                    PassAccess::write("scan_local_prefix", object.symbol_scan_local),
                    PassAccess::write("scan_block_sum", object.symbol_scan_block_sum),
                ],
            ),
            (
                "artifact.x86.object.symbol_scan.hierarchy_up",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_block_sum", object.symbol_scan_block_sum),
                    PassAccess::write("scan_block_prefix", object.symbol_scan_block_prefix),
                    PassAccess::write("scan_hierarchy", object.symbol_scan_hierarchy),
                ],
            ),
            (
                "artifact.x86.object.symbol_scan.hierarchy_down",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read_write("scan_block_prefix", object.symbol_scan_block_prefix),
                    PassAccess::read_write("scan_hierarchy", object.symbol_scan_hierarchy),
                ],
            ),
            (
                "artifact.x86.object.symbol_scan.apply",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_local_prefix", object.symbol_scan_local),
                    PassAccess::read("scan_block_prefix", object.symbol_scan_block_prefix),
                    PassAccess::write("scan_output_prefix", object.symbol_prefix),
                    PassAccess::write("scan_total", object.symbol_total),
                ],
            ),
        ] {
            graph.add_pass(PassDesc {
                name,
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::SemanticInstructions,
                accesses,
            })?;
        }
        graph.add_pass(PassDesc {
            name: "artifact.x86.object.definition_flags",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::write("x86_object_definition_flag", object.definition_flags),
            ],
        })?;
        for (name, accesses) in [
            (
                "artifact.x86.object.definition_scan.local",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_input", object.definition_flags),
                    PassAccess::write("scan_local_prefix", object.definition_scan_local),
                    PassAccess::write("scan_block_sum", object.definition_scan_block_sum),
                ],
            ),
            (
                "artifact.x86.object.definition_scan.hierarchy_up",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_block_sum", object.definition_scan_block_sum),
                    PassAccess::write("scan_block_prefix", object.definition_scan_block_prefix),
                    PassAccess::write("scan_hierarchy", object.definition_scan_hierarchy),
                ],
            ),
            (
                "artifact.x86.object.definition_scan.hierarchy_down",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read_write(
                        "scan_block_prefix",
                        object.definition_scan_block_prefix,
                    ),
                    PassAccess::read_write("scan_hierarchy", object.definition_scan_hierarchy),
                ],
            ),
            (
                "artifact.x86.object.definition_scan.apply",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_local_prefix", object.definition_scan_local),
                    PassAccess::read("scan_block_prefix", object.definition_scan_block_prefix),
                    PassAccess::write("scan_output_prefix", object.definition_prefix),
                    PassAccess::write("scan_total", object.definition_total),
                ],
            ),
        ] {
            graph.add_pass(PassDesc {
                name,
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses,
            })?;
        }
        graph.add_pass(PassDesc {
            name: "artifact.x86.object.relocations",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("semantic_lir_total", semantic_total),
                PassAccess::read("semantic_schedule_order", schedule_order),
                PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("x86_artifact_layout", artifact.layout),
                PassAccess::read("semantic_lir_string_total", semantic_string_total),
                PassAccess::read("semantic_lir_strings", semantic_strings),
                PassAccess::read("x86_object_relocation_flag", object.relocation_flags),
                PassAccess::read("x86_object_relocation_prefix", object.relocation_prefix),
                PassAccess::read("x86_object_symbol_prefix", object.symbol_prefix),
                PassAccess::write("x86_object_relocations", object.relocations),
                PassAccess::write("x86_object_undefined_symbols", object.undefined_symbols),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "artifact.x86.object.definitions",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("target_function_count", function_count),
                PassAccess::read("target_functions", functions),
                PassAccess::read(
                    "target_function_index_by_semantic",
                    function_index_by_semantic,
                ),
                PassAccess::read("target_byte_length", byte_lengths),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("x86_artifact_layout", artifact.layout),
                PassAccess::read("x86_object_definition_flag", object.definition_flags),
                PassAccess::read("x86_object_definition_prefix", object.definition_prefix),
                PassAccess::write("x86_object_definitions", object.definitions),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "artifact.x86.object.bytes",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("x86_artifact_layout", artifact.layout),
                PassAccess::read("x86_artifact_bytes", artifact.artifact_bytes),
                PassAccess::write("x86_object_text_bytes", object.text_bytes),
                PassAccess::write("x86_object_rodata_bytes", object.rodata_bytes),
            ],
        })?;
    }

    if let (Some(wasm), Some(module)) = (wasm_abi, wasm_module) {
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.state_clear",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![PassAccess::write(
                "wasm_module_entrypoint_state",
                module.entrypoint_state,
            )],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.lengths",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("wasm_lir_function_total", semantic_function_total),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::write("wasm_type_entry_length", module.type_lengths),
                PassAccess::write("wasm_code_entry_length", module.code_lengths),
                PassAccess::read_write("wasm_module_entrypoint_state", module.entrypoint_state),
            ],
        })?;
        for (prefix, lengths, offsets, local, block_sum, block_prefix, hierarchy, total) in [
            (
                "lir.wasm.module.type_scan",
                module.type_lengths,
                module.type_offsets,
                module.type_scan_local,
                module.type_scan_block_sum,
                module.type_scan_block_prefix,
                module.type_scan_hierarchy,
                module.type_total,
            ),
            (
                "lir.wasm.module.code_scan",
                module.code_lengths,
                module.code_offsets,
                module.code_scan_local,
                module.code_scan_block_sum,
                module.code_scan_block_prefix,
                module.code_scan_hierarchy,
                module.code_total,
            ),
        ] {
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.local"
                } else {
                    "lir.wasm.module.code_scan.local"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_input", lengths),
                    PassAccess::write("scan_local_prefix", local),
                    PassAccess::write("scan_block_sum", block_sum),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.hierarchy_up"
                } else {
                    "lir.wasm.module.code_scan.hierarchy_up"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_block_sum", block_sum),
                    PassAccess::write("scan_block_prefix", block_prefix),
                    PassAccess::write("scan_hierarchy", hierarchy),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.hierarchy_down"
                } else {
                    "lir.wasm.module.code_scan.hierarchy_down"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read_write("scan_block_prefix", block_prefix),
                    PassAccess::read_write("scan_hierarchy", hierarchy),
                ],
            })?;
            graph.add_pass(PassDesc {
                name: if prefix.ends_with("type_scan") {
                    "lir.wasm.module.type_scan.apply"
                } else {
                    "lir.wasm.module.code_scan.apply"
                },
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_local_prefix", local),
                    PassAccess::read("scan_block_prefix", block_prefix),
                    PassAccess::write("scan_output_prefix", offsets),
                    PassAccess::write("scan_total", total),
                ],
            })?;
        }
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.layout",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("wasm_lir_function_total", semantic_function_total),
                PassAccess::read("wasm_type_entries_length", module.type_total),
                PassAccess::read("wasm_code_entries_length", module.code_total),
                PassAccess::read("wasm_module_entrypoint_state", module.entrypoint_state),
                PassAccess::read("semantic_lir_string_pool_len", semantic_string_pool_len),
                PassAccess::write("wasm_module_layout", module.layout),
                PassAccess::write("wasm_module_length", module.module_length),
                PassAccess::read_write("lowering_status", lowering_status),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.emit_headers",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("wasm_module_layout", module.layout),
                PassAccess::read("semantic_lir_string_pool_len", semantic_string_pool_len),
                PassAccess::read("semantic_lir_string_data", semantic_string_data),
                PassAccess::write("wasm_module_bytes", module.module_bytes),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "lir.wasm.module.emit_functions",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("wasm_lir_function_total", semantic_function_total),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::read("semantic_lir_params", semantic_params),
                PassAccess::read("semantic_lir_locals", semantic_locals),
                PassAccess::read("wasm_type_entry_offset", module.type_offsets),
                PassAccess::read("wasm_code_entry_offset", module.code_offsets),
                PassAccess::read("wasm_body_bytes", output),
                PassAccess::read("wasm_module_layout", module.layout),
                PassAccess::write("wasm_module_bytes", module.module_bytes),
            ],
        })?;
    }

    if let (Some(wasm), Some(module), Some(object)) = (wasm_abi, wasm_module, wasm_object) {
        graph.add_pass(PassDesc {
            name: "artifact.wasm.object.relocation_flags",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::read("semantic_lir_total", semantic_total),
                PassAccess::read("semantic_schedule_order", schedule_order),
                PassAccess::read("semantic_op_by_instruction", semantic_op),
                PassAccess::write("wasm_object_relocation_flag", object.relocation_flags),
                PassAccess::write("wasm_object_symbol_flag", object.symbol_flags),
            ],
        })?;
        for (name, accesses) in [
            (
                "artifact.wasm.object.relocation_scan.local",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_input", object.relocation_flags),
                    PassAccess::write("scan_local_prefix", object.relocation_scan_local),
                    PassAccess::write("scan_block_sum", object.relocation_scan_block_sum),
                ],
            ),
            (
                "artifact.wasm.object.relocation_scan.hierarchy_up",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_block_sum", object.relocation_scan_block_sum),
                    PassAccess::write("scan_block_prefix", object.relocation_scan_block_prefix),
                    PassAccess::write("scan_hierarchy", object.relocation_scan_hierarchy),
                ],
            ),
            (
                "artifact.wasm.object.relocation_scan.hierarchy_down",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read_write(
                        "scan_block_prefix",
                        object.relocation_scan_block_prefix,
                    ),
                    PassAccess::read_write("scan_hierarchy", object.relocation_scan_hierarchy),
                ],
            ),
            (
                "artifact.wasm.object.relocation_scan.apply",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_local_prefix", object.relocation_scan_local),
                    PassAccess::read("scan_block_prefix", object.relocation_scan_block_prefix),
                    PassAccess::write("scan_output_prefix", object.relocation_prefix),
                    PassAccess::write("scan_total", object.relocation_total),
                ],
            ),
        ] {
            graph.add_pass(PassDesc {
                name,
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::SemanticInstructions,
                accesses,
            })?;
        }
        for (name, accesses) in [
            (
                "artifact.wasm.object.symbol_scan.local",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_input", object.symbol_flags),
                    PassAccess::write("scan_local_prefix", object.symbol_scan_local),
                    PassAccess::write("scan_block_sum", object.symbol_scan_block_sum),
                ],
            ),
            (
                "artifact.wasm.object.symbol_scan.hierarchy_up",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_block_sum", object.symbol_scan_block_sum),
                    PassAccess::write("scan_block_prefix", object.symbol_scan_block_prefix),
                    PassAccess::write("scan_hierarchy", object.symbol_scan_hierarchy),
                ],
            ),
            (
                "artifact.wasm.object.symbol_scan.hierarchy_down",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read_write("scan_block_prefix", object.symbol_scan_block_prefix),
                    PassAccess::read_write("scan_hierarchy", object.symbol_scan_hierarchy),
                ],
            ),
            (
                "artifact.wasm.object.symbol_scan.apply",
                vec![
                    PassAccess::read("scan_count", semantic_total),
                    PassAccess::read("scan_local_prefix", object.symbol_scan_local),
                    PassAccess::read("scan_block_prefix", object.symbol_scan_block_prefix),
                    PassAccess::write("scan_output_prefix", object.symbol_prefix),
                    PassAccess::write("scan_total", object.symbol_total),
                ],
            ),
        ] {
            graph.add_pass(PassDesc {
                name,
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::SemanticInstructions,
                accesses,
            })?;
        }
        graph.add_pass(PassDesc {
            name: "artifact.wasm.object.definition_flags",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::write("wasm_object_definition_flag", object.definition_flags),
            ],
        })?;
        for (name, accesses) in [
            (
                "artifact.wasm.object.definition_scan.local",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_input", object.definition_flags),
                    PassAccess::write("scan_local_prefix", object.definition_scan_local),
                    PassAccess::write("scan_block_sum", object.definition_scan_block_sum),
                ],
            ),
            (
                "artifact.wasm.object.definition_scan.hierarchy_up",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_block_sum", object.definition_scan_block_sum),
                    PassAccess::write("scan_block_prefix", object.definition_scan_block_prefix),
                    PassAccess::write("scan_hierarchy", object.definition_scan_hierarchy),
                ],
            ),
            (
                "artifact.wasm.object.definition_scan.hierarchy_down",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read_write(
                        "scan_block_prefix",
                        object.definition_scan_block_prefix,
                    ),
                    PassAccess::read_write("scan_hierarchy", object.definition_scan_hierarchy),
                ],
            ),
            (
                "artifact.wasm.object.definition_scan.apply",
                vec![
                    PassAccess::read("scan_count", semantic_function_total),
                    PassAccess::read("scan_local_prefix", object.definition_scan_local),
                    PassAccess::read("scan_block_prefix", object.definition_scan_block_prefix),
                    PassAccess::write("scan_output_prefix", object.definition_prefix),
                    PassAccess::write("scan_total", object.definition_total),
                ],
            ),
        ] {
            graph.add_pass(PassDesc {
                name,
                phase: CompilerPhase::Artifact,
                dispatch_domain: ResourceDomain::Declarations,
                accesses,
            })?;
        }
        graph.add_pass(PassDesc {
            name: "artifact.wasm.object.relocations",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::SemanticInstructions,
            accesses: vec![
                PassAccess::read("target_lir_total", target_total),
                PassAccess::read("semantic_lir_core", semantic_core),
                PassAccess::read("semantic_lir_operands", semantic_operands),
                PassAccess::read("semantic_lir_strings", semantic_strings),
                PassAccess::read("semantic_lir_total", semantic_total),
                PassAccess::read("semantic_schedule_order", schedule_order),
                PassAccess::read("semantic_owner_by_instruction", semantic_owner),
                PassAccess::read("semantic_function_id_by_hir", semantic_function_ids),
                PassAccess::read("semantic_to_target_start", semantic_to_target_start),
                PassAccess::read("target_byte_offset", byte_offsets),
                PassAccess::read("wasm_object_relocation_flag", object.relocation_flags),
                PassAccess::read("wasm_object_relocation_prefix", object.relocation_prefix),
                PassAccess::read("wasm_object_symbol_prefix", object.symbol_prefix),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::read("wasm_code_entry_offset", module.code_offsets),
                PassAccess::write("wasm_object_relocations", object.relocations),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "artifact.wasm.object.functions",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::Declarations,
            accesses: vec![
                PassAccess::read("semantic_lir_function_total", semantic_function_total),
                PassAccess::read("semantic_lir_functions", semantic_functions),
                PassAccess::read("wasm_lir_functions", wasm.functions),
                PassAccess::read("wasm_type_entry_length", module.type_lengths),
                PassAccess::read("wasm_type_entry_offset", module.type_offsets),
                PassAccess::read("wasm_code_entry_length", module.code_lengths),
                PassAccess::read("wasm_code_entry_offset", module.code_offsets),
                PassAccess::read("wasm_object_symbol_total", object.symbol_total),
                PassAccess::read("wasm_object_definition_flag", object.definition_flags),
                PassAccess::read("wasm_object_definition_prefix", object.definition_prefix),
                PassAccess::write("wasm_object_functions", object.functions),
                PassAccess::write("wasm_object_definitions", object.definitions),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: "artifact.wasm.object.bytes",
            phase: CompilerPhase::Artifact,
            dispatch_domain: ResourceDomain::ArtifactBytes,
            accesses: vec![
                PassAccess::read("wasm_type_entries_length", module.type_total),
                PassAccess::read("wasm_code_entries_length", module.code_total),
                PassAccess::read("wasm_module_layout", module.layout),
                PassAccess::read("wasm_module_bytes", module.module_bytes),
                PassAccess::read("semantic_lir_string_pool_len", semantic_string_pool_len),
                PassAccess::read("semantic_lir_string_data", semantic_string_data),
                PassAccess::write("wasm_object_type_bytes", object.type_bytes),
                PassAccess::write("wasm_object_body_bytes", object.body_bytes),
                PassAccess::write("wasm_object_data_bytes", object.data_bytes),
            ],
        })?;
    }

    if let Some(x86) = x86_artifact
        && let Some(readback) = x86.artifact_length_readback
    {
        graph.add_buffer_copy_pass(
            "artifact.x86.length.readback",
            CompilerPhase::Artifact,
            "artifact_length",
            x86.artifact_length,
            "artifact_length_readback",
            readback,
        )?;
    }
    if let Some(object) = x86_object {
        for (name, source_binding, source) in [
            (
                "artifact.x86.object.relocation_total.readback",
                "relocation_total",
                object.relocation_total,
            ),
            (
                "artifact.x86.object.symbol_total.readback",
                "symbol_total",
                object.symbol_total,
            ),
            (
                "artifact.x86.object.definition_total.readback",
                "definition_total",
                object.definition_total,
            ),
            (
                "artifact.x86.object.layout.readback",
                "artifact_layout",
                x86_artifact.expect("x86 object has x86 artifact").layout,
            ),
        ] {
            graph.add_buffer_copy_pass(
                name,
                CompilerPhase::Artifact,
                source_binding,
                source,
                "metadata_readback",
                object.metadata_readback,
            )?;
        }
    }
    if let Some(module) = wasm_module
        && let Some(readback) = module.module_length_readback
    {
        graph.add_buffer_copy_pass(
            "artifact.wasm.length.readback",
            CompilerPhase::Artifact,
            "artifact_length",
            module.module_length,
            "artifact_length_readback",
            readback,
        )?;
    }
    if let Some(object) = wasm_object {
        let module = wasm_module.expect("Wasm object has Wasm module");
        for (name, source_binding, source) in [
            (
                "artifact.wasm.object.function_count.readback",
                "function_count",
                semantic_function_total,
            ),
            (
                "artifact.wasm.object.type_total.readback",
                "type_total",
                module.type_total,
            ),
            (
                "artifact.wasm.object.code_total.readback",
                "code_total",
                module.code_total,
            ),
            (
                "artifact.wasm.object.relocation_total.readback",
                "relocation_total",
                object.relocation_total,
            ),
            (
                "artifact.wasm.object.symbol_total.readback",
                "symbol_total",
                object.symbol_total,
            ),
            (
                "artifact.wasm.object.definition_total.readback",
                "definition_total",
                object.definition_total,
            ),
            (
                "artifact.wasm.object.string_pool_len.readback",
                "string_pool_len",
                semantic_string_pool_len,
            ),
            (
                "artifact.wasm.object.layout.readback",
                "module_layout",
                module.layout,
            ),
        ] {
            graph.add_buffer_copy_pass(
                name,
                CompilerPhase::Artifact,
                source_binding,
                source,
                "metadata_readback",
                object.metadata_readback,
            )?;
        }
    }
    graph.add_buffer_copy_pass(
        "lowering.status.readback",
        CompilerPhase::Artifact,
        "lowering_status",
        lowering_status,
        "status_readback",
        lowering_status_readback,
    )?;
    graph.build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cyclic_short_lifetime_registers_never_overlap() {
        let lanes = opcode::X86_TEMP_REGISTER_COUNT;
        let intervals: Vec<_> = (0..64)
            .flat_map(|first| (1..lanes).map(move |length| (first, first + length)))
            .collect();
        for (index, &(first_a, last_a)) in intervals.iter().enumerate() {
            for &(first_b, last_b) in &intervals[index + 1..] {
                if first_a == first_b || first_a % lanes != first_b % lanes {
                    continue;
                }
                assert!(
                    last_a < first_b || last_b < first_a,
                    "same-lane lifetimes [{first_a}, {last_a}] and [{first_b}, {last_b}] overlap"
                );
            }
        }
    }

    #[test]
    fn host_service_namespace_round_trips_canonical_symbol_slots() {
        for slot in opcode::HOST_SERVICE_FIRST..opcode::HOST_SERVICE_END {
            if slot == 52 {
                assert_eq!(HostService::from_symbol_slot(slot), None);
            } else {
                assert_eq!(
                    HostService::from_symbol_slot(slot).map(HostService::symbol_slot),
                    Some(slot)
                );
            }
        }
        assert_eq!(
            HostService::from_symbol_slot(opcode::HOST_SERVICE_FIRST - 1),
            None
        );
        assert_eq!(
            HostService::from_symbol_slot(opcode::HOST_SERVICE_END),
            None
        );
    }

    #[test]
    fn frontend_unit_capacity_uses_structural_ir_expansion_bounds() {
        let wasm =
            LoweringCapacities::from_frontend_unit(1_000, 400, 100, LoweringTarget::Wasm).unwrap();
        assert_eq!(wasm.semantic_instructions, 700);
        assert_eq!(wasm.target_instructions, 800);
        assert_eq!(wasm.call_arguments, 100);
        assert_eq!(wasm.local_capacity(), 300);
        assert_eq!(wasm.declaration_capacity(), 700);
        assert!(wasm.artifact_bytes >= 1_000 + 800 * 8 + 100 * 32);

        let x86 = LoweringCapacities::from_frontend_unit(1_000, 400, 100, LoweringTarget::X86_64)
            .unwrap();
        assert_eq!(x86.semantic_instructions, 700);
        assert_eq!(x86.target_instructions, 700);
        assert!(
            LoweringCapacities::from_frontend_unit(
                u32::MAX,
                u32::MAX,
                u32::MAX,
                LoweringTarget::Wasm,
            )
            .unwrap_err()
            .contains("semantic instruction")
        );
    }

    #[test]
    fn lowering_capacity_growth_reuses_covering_workspace_with_bounded_headroom() {
        let initial =
            LoweringCapacities::from_frontend_unit(1_000, 400, 100, LoweringTarget::X86_64)
                .unwrap();
        assert!(initial.covers(initial));

        let required =
            LoweringCapacities::from_frontend_unit(1_001, 401, 101, LoweringTarget::X86_64)
                .unwrap();
        assert!(!initial.covers(required));
        let grown = initial.grow_to_cover(required);
        assert!(grown.covers(required));
        assert_eq!(grown.source_bytes, 4_096);
        assert_eq!(grown.hir_nodes, 4_096);
        assert_eq!(grown.semantic_instructions, 4_096);
        assert!(
            grown.covers(
                LoweringCapacities::from_frontend_unit(1_002, 402, 102, LoweringTarget::X86_64,)
                    .unwrap()
            )
        );
    }

    #[test]
    fn lowering_workspace_footprint_is_physical_slot_sum() {
        for target in [LoweringTarget::X86_64, LoweringTarget::Wasm] {
            let capacities = LoweringCapacities::from_frontend_unit(
                1024 * 1024,
                1024 * 1024,
                1024 * 1024,
                target,
            )
            .unwrap();
            let graph = lowering_compiler_graph(capacities, target).unwrap();
            let expected = graph
                .workspace_plan()
                .slots
                .iter()
                .map(|slot| slot.bytes)
                .sum::<u64>();
            assert_eq!(graph.workspace_bytes(), expected);
            eprintln!("{target:?} 1MiB lowering workspace: {expected} bytes");
            let mut slots = graph.workspace_plan().slots.clone();
            slots.sort_unstable_by_key(|slot| std::cmp::Reverse(slot.bytes));
            for slot in slots.iter().take(12) {
                let owners = graph
                    .workspace_plan()
                    .assignments
                    .iter()
                    .filter(|assignment| assignment.slot == slot.slot)
                    .map(|assignment| assignment.name)
                    .collect::<Vec<_>>();
                eprintln!("  slot {}: {} bytes {owners:?}", slot.slot, slot.bytes);
            }
        }
    }

    #[test]
    fn executable_lowering_does_not_reserve_relocatable_object_storage() {
        for (target, object_output) in [
            (LoweringTarget::X86_64, "artifact.x86.object.relocations"),
            (LoweringTarget::Wasm, "artifact.wasm.object.relocations"),
        ] {
            let capacities = LoweringCapacities::from_frontend_unit(
                1024 * 1024,
                1024 * 1024,
                1024 * 1024,
                target,
            )
            .unwrap();
            let executable = lowering_compiler_graph_for_artifact(
                capacities,
                target,
                LoweringArtifactKind::Executable,
            )
            .unwrap();
            let object = lowering_compiler_graph_for_artifact(
                capacities,
                target,
                LoweringArtifactKind::Object,
            )
            .unwrap();

            assert!(executable.resource_id(object_output).is_none());
            assert!(object.resource_id(object_output).is_some());
            assert!(executable.workspace_bytes() < object.workspace_bytes());
        }
    }

    #[test]
    fn target_records_are_physically_bounded_and_offsets_survive_replay() {
        let target_rows = TARGET_LIR_PAGE_ROWS * 3 + 17;
        for (target, core_name, core_stride, replay_name) in [
            (
                LoweringTarget::X86_64,
                "lir.x86.core",
                std::mem::size_of::<X86LirCore>() as u64,
                "lir.x86.scatter.replay",
            ),
            (
                LoweringTarget::Wasm,
                "lir.wasm.instructions",
                std::mem::size_of::<WasmLirInstruction>() as u64,
                "lir.wasm.scatter.replay",
            ),
        ] {
            let graph = lowering_compiler_graph(
                LoweringCapacities {
                    source_bytes: 1024,
                    tokens: 1024,
                    hir_nodes: 1024,
                    semantic_instructions: 4096,
                    call_arguments: 1024,
                    parameters: 1024,
                    aggregate_elements: 1024,
                    target_instructions: target_rows,
                    artifact_bytes: 4096,
                },
                target,
            )
            .unwrap();
            let core = graph.resource_id(core_name).unwrap();
            assert_eq!(
                graph.resource(core).unwrap().bytes,
                u64::from(TARGET_LIR_PAGE_ROWS) * core_stride,
            );
            let offsets = graph
                .resource_id(match target {
                    LoweringTarget::X86_64 => "lir.x86.offset_by_semantic",
                    LoweringTarget::Wasm => "lir.wasm.offset_by_semantic",
                })
                .unwrap();
            assert!(
                graph.lifetime(offsets).unwrap().last_pass.index()
                    >= graph.pass_id(replay_name).unwrap().index(),
            );
            assert!(graph.repeated_regions().iter().any(|region| {
                region.iterations == 4
                    && graph.passes()[region.first_pass.index()].name == replay_name
            }));
        }
    }

    #[test]
    fn lowering_records_match_shader_storage_layouts() {
        assert_eq!(std::mem::size_of::<SemanticLirCore>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirOperands>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirFunction>(), 52);
        assert_eq!(std::mem::size_of::<SemanticLirParam>(), 16);
        assert_eq!(std::mem::size_of::<SemanticLirLocal>(), 16);
        assert_eq!(std::mem::size_of::<LoweringStatus>(), 32);
        assert_eq!(std::mem::size_of::<TargetScheduleKey>(), 12);
        assert_eq!(std::mem::size_of::<TargetLirFunction>(), 16);
        assert_eq!(std::mem::size_of::<X86LirCore>(), 16);
        assert_eq!(std::mem::size_of::<X86LirOperands>(), 16);
        assert_eq!(std::mem::size_of::<X86LirLocations>(), 16);
        assert_eq!(std::mem::size_of::<X86SelectInfo>(), 16);
        assert_eq!(std::mem::size_of::<X86DeclarationAnalysis>(), 16);
        assert_eq!(std::mem::size_of::<X86FunctionRegisterAnalysis>(), 16);
        assert_eq!(std::mem::size_of::<X86ValueAnalysis>(), 12);
        assert_eq!(std::mem::size_of::<WasmLirInstruction>(), 16);
        assert_eq!(std::mem::size_of::<WasmLirOperands>(), 16);
        assert_eq!(std::mem::size_of::<WasmLirFunction>(), 56);
        assert_eq!(std::mem::size_of::<WasmModuleLayout>(), 64);
        assert_eq!(std::mem::size_of::<X86ArtifactLayout>(), 48);
        assert_eq!(
            std::mem::size_of::<crate::type_checker::GpuCheckedCallArtifact>(),
            56
        );
    }

    #[test]
    fn generated_opcode_contract_uses_wasm_primary_opcode_values() {
        assert_eq!(opcode::SEMANTIC_LIR_OP_CONST_I32, 1);
        assert_eq!(opcode::WASM_LIR_OP_RETURN, 0x0f);
        assert_eq!(opcode::WASM_LIR_OP_I32_CONST, 0x41);
    }

    #[test]
    fn semantic_schedule_radix_bit_packing_tracks_capacity() {
        let layout = TargetScheduleRadixLayout::for_capacities(LoweringCapacities {
            source_bytes: 1_000_000,
            tokens: 100_000,
            hir_nodes: 65_000,
            semantic_instructions: 250_000,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 1,
            artifact_bytes: 1,
        });
        assert_eq!(layout.packed_bits, 0x8001_1453);
        assert_eq!(layout.steps, 7);
        assert_eq!(layout.total_bits, 53);

        let small_capacities = LoweringCapacities {
            source_bytes: 4_096,
            tokens: 4_096,
            hir_nodes: 4_096,
            semantic_instructions: 4_096,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 1,
            artifact_bytes: 1,
        };
        let small = TargetScheduleRadixLayout::for_capacities(small_capacities);
        assert_eq!(small.packed_bits, 0x8000_d34e);
        assert_eq!(small.steps, 5);
        let graph = lowering_compiler_graph(small_capacities, LoweringTarget::Wasm).unwrap();
        assert!(graph.repeated_regions().iter().any(|region| {
            region.iterations == 3
                && region.pass_count == 12
                && graph.passes()[region.first_pass.index()].name
                    == "lir.semantic.schedule.histogram.odd"
        }));

        let odd_capacities = LoweringCapacities {
            source_bytes: 4_096,
            tokens: 128,
            hir_nodes: 128,
            semantic_instructions: 257,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 1,
            artifact_bytes: 1,
        };
        let odd = TargetScheduleRadixLayout::for_capacities(odd_capacities);
        assert_eq!(odd.packed_bits, 0x8000_8209);
        assert_eq!(odd.steps, 4);
        let graph = lowering_compiler_graph(odd_capacities, LoweringTarget::Wasm).unwrap();
        assert!(graph.repeated_regions().iter().any(|region| {
            region.iterations == 2
                && region.pass_count == 12
                && graph.passes()[region.first_pass.index()].name
                    == "lir.semantic.schedule.histogram.even"
        }));
    }

    #[test]
    fn semantic_schedule_key_covers_the_default_frontend_unit() {
        let maximum = (5 * 1024 * 1024) as u32;
        let capacities = LoweringCapacities::from_frontend_unit(
            maximum,
            maximum,
            maximum,
            LoweringTarget::X86_64,
        )
        .unwrap()
        .bucketed();
        let layout = TargetScheduleRadixLayout::for_capacities(capacities);
        assert_eq!(layout.total_bits, 72);
        assert_eq!(layout.steps, TARGET_SCHEDULE_MAX_RADIX_STEPS);
        lowering_compiler_graph(capacities, LoweringTarget::X86_64).unwrap();
    }

    #[test]
    fn semantic_schedule_key_rejects_an_overwide_unit() {
        let capacities = LoweringCapacities {
            source_bytes: 1,
            tokens: 1 << 29,
            hir_nodes: 1 << 29,
            semantic_instructions: 1 << 31,
            call_arguments: 1,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 1,
            artifact_bytes: 1,
        };
        let error = lowering_compiler_graph(capacities, LoweringTarget::X86_64).unwrap_err();
        assert!(error.contains("exceeding the 72-bit resident key capacity"));
    }

    #[test]
    fn both_target_graphs_have_common_semantic_lowering_and_target_output() {
        let capacities = LoweringCapacities {
            source_bytes: 48,
            tokens: 48,
            hir_nodes: 32,
            semantic_instructions: 64,
            call_arguments: 16,
            parameters: 16,
            aggregate_elements: 16,
            target_instructions: 96,
            artifact_bytes: 1024,
        };
        for (target, target_pass, output) in [
            (
                LoweringTarget::X86_64,
                "lir.x86.scatter",
                "artifact.x86.bytes",
            ),
            (
                LoweringTarget::Wasm,
                "lir.wasm.scatter",
                "artifact.wasm.bytes",
            ),
        ] {
            let graph = lowering_compiler_graph(capacities, target).unwrap();
            assert_eq!(graph.repeated_regions().len(), 4);
            assert!(graph.repeated_regions().iter().any(|region| {
                region.iterations == 3
                    && region.pass_count == 2
                    && graph.passes()[region.first_pass.index()].name
                        == "lir.semantic.execution_rank.step_a_to_b"
            }));
            let schedule_layout = TargetScheduleRadixLayout::for_capacities(capacities);
            assert!(graph.repeated_regions().iter().any(|region| {
                region.iterations == schedule_layout.steps.div_ceil(2)
                    && region.pass_count == 12
                    && graph.passes()[region.first_pass.index()].name
                        == if schedule_layout.steps % 2 == 0 {
                            "lir.semantic.schedule.histogram.even"
                        } else {
                            "lir.semantic.schedule.histogram.odd"
                        }
            }));
            assert!(
                graph.repeated_regions().iter().any(|region| {
                    region.iterations == 1
                        && region.pass_count
                            == match target {
                                LoweringTarget::X86_64 => 5,
                                LoweringTarget::Wasm => 3,
                            }
                        && graph.passes()[region.first_pass.index()].name
                            == match target {
                                LoweringTarget::X86_64 => "lir.x86.scatter.replay",
                                LoweringTarget::Wasm => "lir.wasm.scatter.replay",
                            }
                }),
                "target repeated regions: {:?}",
                graph
                    .repeated_regions()
                    .iter()
                    .map(|region| (
                        region.iterations,
                        region.pass_count,
                        graph.passes()[region.first_pass.index()].name
                    ))
                    .collect::<Vec<_>>()
            );
            assert!(
                graph
                    .passes()
                    .iter()
                    .any(|pass| pass.name == "lir.semantic.scatter")
            );
            assert!(graph.passes().iter().any(|pass| pass.name == target_pass));
            assert!(
                graph
                    .resources()
                    .iter()
                    .any(|resource| resource.name == output)
            );
            assert!(graph.resource_id("typecheck.visible_decls").is_none());
            assert!(graph.resource_id("typecheck.visible_types").is_none());
            assert_eq!(
                graph
                    .resource(
                        graph
                            .resource_id("typecheck.semantic_value_decls_by_hir")
                            .unwrap(),
                    )
                    .unwrap()
                    .domain,
                ResourceDomain::HirNodes,
            );
            assert_eq!(
                graph
                    .resource(
                        graph
                            .resource_id("typecheck.semantic_param_types_by_row")
                            .unwrap(),
                    )
                    .unwrap()
                    .domain,
                ResourceDomain::Declarations,
            );
            assert_eq!(
                graph
                    .resource(
                        graph
                            .resource_id("typecheck.semantic_calls_by_hir")
                            .unwrap(),
                    )
                    .unwrap()
                    .domain,
                ResourceDomain::Calls,
            );
            assert!(
                graph
                    .resource_id("typecheck.backend_call_targets")
                    .is_none()
            );
            assert!(
                graph
                    .resource_id("typecheck.call_dependency_decls")
                    .is_none()
            );
            assert!(graph.resource_id("typecheck.call_intrinsic_tags").is_none());
        }
    }

    #[test]
    fn semantic_lowering_entrypoints_match_graph_access_contracts() {
        let graph = lowering_compiler_graph(
            LoweringCapacities {
                source_bytes: 48,
                tokens: 48,
                hir_nodes: 32,
                semantic_instructions: 32,
                call_arguments: 16,
                parameters: 16,
                aggregate_elements: 16,
                target_instructions: 64,
                artifact_bytes: 512,
            },
            LoweringTarget::Wasm,
        )
        .unwrap();
        for (pass_name, artifact) in [
            ("lir.status.clear", "codegen/lir/status_clear"),
            ("lir.semantic.project", "codegen/lir/semantic/project"),
            (
                "lir.semantic.execution_rank.init",
                "codegen/lir/semantic/execution_rank_init",
            ),
            (
                "lir.semantic.execution_rank.step_a_to_b",
                "codegen/lir/semantic/execution_rank_step",
            ),
            (
                "lir.semantic.execution_rank.step_b_to_a",
                "codegen/lir/semantic/execution_rank_step",
            ),
            ("lir.semantic.count", "codegen/lir/semantic/count"),
            ("lir.semantic.scan.local", "scan/counted/00_local"),
            (
                "lir.semantic.scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.semantic.scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.semantic.scan.apply", "scan/counted/02_apply"),
            ("lir.semantic.scatter", "codegen/lir/semantic/scatter"),
            ("lir.semantic.call_args", "codegen/lir/semantic/call_args"),
        ] {
            let reflection = crate::reflection::parse_reflection_from_file(
                crate::shader_artifacts::artifact_path(&format!("{artifact}.reflect.json")),
            )
            .unwrap();
            graph
                .validate_complete_pass_reflection(graph.pass_id(pass_name).unwrap(), &reflection)
                .unwrap();
        }
    }

    #[test]
    fn wasm_target_entrypoints_match_graph_access_contracts() {
        let graph = lowering_compiler_graph(
            LoweringCapacities {
                source_bytes: 48,
                tokens: 48,
                hir_nodes: 32,
                semantic_instructions: 32,
                call_arguments: 16,
                parameters: 16,
                aggregate_elements: 16,
                target_instructions: 64,
                artifact_bytes: 512,
            },
            LoweringTarget::Wasm,
        )
        .unwrap();
        for (pass_name, artifact) in [
            ("lir.wasm.count", "codegen/lir/wasm/count"),
            ("lir.target.count_scan.local", "scan/counted/00_local"),
            (
                "lir.target.count_scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.target.count_scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.target.count_scan.apply", "scan/counted/02_apply"),
            ("lir.wasm.scatter", "codegen/lir/wasm/scatter"),
            ("lir.wasm.scatter.replay", "codegen/lir/wasm/scatter"),
            ("lir.wasm.validate", "codegen/lir/wasm/validate"),
            ("lir.target.functions.mark", "codegen/lir/functions/mark"),
            ("lir.target.function_scan.local", "scan/counted/00_local"),
            (
                "lir.target.function_scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.target.function_scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.target.function_scan.apply", "scan/counted/02_apply"),
            (
                "lir.target.functions.scatter_starts",
                "codegen/lir/functions/scatter_starts",
            ),
            (
                "lir.target.functions.finalize",
                "codegen/lir/functions/finalize",
            ),
            ("lir.wasm.byte_count", "codegen/lir/wasm/byte_count"),
            ("lir.target.byte_scan.local", "scan/counted/00_local"),
            (
                "lir.target.byte_scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.target.byte_scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.target.byte_scan.apply", "scan/counted/02_apply"),
            ("lir.wasm.emit", "codegen/lir/wasm/emit"),
            (
                "lir.wasm.resolve_indices.replay",
                "codegen/lir/wasm/resolve_indices",
            ),
        ] {
            let reflection = crate::reflection::parse_reflection_from_file(
                crate::shader_artifacts::artifact_path(&format!("{artifact}.reflect.json")),
            )
            .unwrap();
            graph
                .validate_complete_pass_reflection(graph.pass_id(pass_name).unwrap(), &reflection)
                .unwrap();
        }
    }

    #[test]
    fn x86_target_lir_entrypoints_match_graph_access_contracts() {
        let graph = lowering_compiler_graph(
            LoweringCapacities {
                source_bytes: 48,
                tokens: 48,
                hir_nodes: 32,
                semantic_instructions: 32,
                call_arguments: 16,
                parameters: 16,
                aggregate_elements: 16,
                target_instructions: 64,
                artifact_bytes: 512,
            },
            LoweringTarget::X86_64,
        )
        .unwrap();
        for (pass_name, artifact) in [
            ("lir.x86.analysis.clear", "codegen/lir/x86/analysis_clear"),
            ("lir.x86.analysis.index", "codegen/lir/x86/analysis_index"),
            (
                "lir.x86.optimize.functions",
                "codegen/lir/x86/optimize_functions",
            ),
            ("lir.x86.if_convert", "codegen/lir/x86/if_convert"),
            (
                "lir.x86.allocate.functions",
                "codegen/lir/x86/optimize_functions",
            ),
            ("lir.x86.count", "codegen/lir/x86/count"),
            ("lir.target.count_scan.local", "scan/counted/00_local"),
            (
                "lir.target.count_scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.target.count_scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.target.count_scan.apply", "scan/counted/02_apply"),
            ("lir.x86.scatter", "codegen/lir/x86/scatter"),
            ("lir.x86.scatter.replay", "codegen/lir/x86/scatter"),
            ("lir.x86.locations", "codegen/lir/x86/locations"),
            ("lir.x86.locations.replay", "codegen/lir/x86/locations"),
            ("lir.x86.validate", "codegen/lir/x86/validate"),
            ("lir.x86.resolve", "codegen/lir/x86/resolve"),
            ("lir.x86.resolve.replay", "codegen/lir/x86/resolve"),
            ("lir.target.functions.mark", "codegen/lir/functions/mark"),
            ("lir.target.function_scan.local", "scan/counted/00_local"),
            (
                "lir.target.function_scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.target.function_scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.target.function_scan.apply", "scan/counted/02_apply"),
            (
                "lir.target.functions.scatter_starts",
                "codegen/lir/functions/scatter_starts",
            ),
            (
                "lir.target.functions.finalize",
                "codegen/lir/functions/finalize",
            ),
            (
                "lir.x86.decl_slots.scatter",
                "codegen/lir/x86/decl_slots_scatter",
            ),
            ("lir.x86.frame.finalize", "codegen/lir/x86/frame_finalize"),
            ("lir.x86.byte_count", "codegen/lir/x86/byte_count"),
            ("lir.target.byte_scan.local", "scan/counted/00_local"),
            (
                "lir.target.byte_scan.hierarchy_up",
                "scan/counted/01_hierarchy_up",
            ),
            (
                "lir.target.byte_scan.hierarchy_down",
                "scan/counted/02_hierarchy_down",
            ),
            ("lir.target.byte_scan.apply", "scan/counted/02_apply"),
            (
                "lir.x86.entrypoint.clear",
                "codegen/lir/x86/entrypoint_clear",
            ),
            (
                "lir.x86.entrypoint.reduce",
                "codegen/lir/x86/entrypoint_reduce",
            ),
            ("lir.x86.artifact.layout", "codegen/lir/x86/artifact_layout"),
            ("lir.x86.artifact.clear", "codegen/lir/x86/artifact_clear"),
            ("lir.x86.emit", "codegen/lir/x86/emit"),
            ("lir.x86.runtime.emit", "codegen/lir/x86/runtime_emit"),
            (
                "artifact.x86.object.normalize_status",
                "codegen/lir/x86/object_normalize_status",
            ),
            (
                "artifact.x86.object.relocation_flags",
                "codegen/lir/x86/object_relocation_flags",
            ),
            (
                "artifact.x86.object.definition_flags",
                "codegen/lir/x86/object_definition_flags",
            ),
            (
                "artifact.x86.object.relocations",
                "codegen/lir/x86/object_relocations",
            ),
            (
                "artifact.x86.object.definitions",
                "codegen/lir/x86/object_definitions",
            ),
            ("artifact.x86.object.bytes", "codegen/lir/x86/object_bytes"),
        ] {
            let reflection = crate::reflection::parse_reflection_from_file(
                crate::shader_artifacts::artifact_path(&format!("{artifact}.reflect.json")),
            )
            .unwrap();
            graph
                .validate_complete_pass_reflection(graph.pass_id(pass_name).unwrap(), &reflection)
                .unwrap();
        }
    }
}
