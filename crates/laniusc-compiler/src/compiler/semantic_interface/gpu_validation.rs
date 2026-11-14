//! Validates an encoded semantic-interface artifact on the GPU
//! (shaders/type_checker/interface/validate).
//!
//! The kernels read the exact persisted byte stream where it already is: an
//! export validates the artifact its materialize pass wrote, in the same
//! submission. A plan kernel checks the framing and writes the indirect
//! dispatch arguments of seven record kernels, which check record ranges,
//! canonical names, the typed graph, lexical ownership, implementations and
//! predicates. Each kernel reports a failure as one key; the smallest key is
//! the first failure in check order, and the host reads only that word.

use anyhow::{Result, anyhow};

use crate::gpu::{
    buffers::{CapacityBufferCache, LaniusBuffer},
    passes_core::{self, bind_group::create_bind_group_from_bindings},
};

use super::GPU_SEMANTIC_INTERFACE_VERSION;

const LABEL: &str = "type_check.interface.validate";
const PLAN_SHADER: &str = "type_checker/interface/validate/00_plan";
/// The record kernels in dispatch order. Kernel `k` reads its indirect
/// arguments at words `3k..3k + 3` of the arguments the plan wrote.
const RECORD_SHADERS: [(&str, &str); 7] = [
    ("type_checker/interface/validate/01_clear", "type_check.interface.validate.clear"),
    ("type_checker/interface/validate/02_owners", "type_check.interface.validate.owners"),
    ("type_checker/interface/validate/03_records", "type_check.interface.validate.records"),
    ("type_checker/interface/validate/04_scopes", "type_check.interface.validate.scopes"),
    ("type_checker/interface/validate/04a_implementation_rows", "type_check.interface.validate.implementation_rows"),
    ("type_checker/interface/validate/05_implementations", "type_check.interface.validate.implementations"),
    ("type_checker/interface/validate/06_predicates", "type_check.interface.validate.predicates"),
];
const STATE_WORDS: usize = 40;
const ARGS_WORDS: usize = 3 * RECORD_SHADERS.len();
/// The failure key's state word: INVALID when the artifact passed.
pub(crate) const FAILURE_KEY_BYTE_OFFSET: u64 = 0;
const PASSED: u32 = u32::MAX;

#[derive(encase::ShaderType)]
struct PlanParams {
    version: u32,
    scratch_capacity: u32,
    word_capacity: u32,
    check_export_status: u32,
}

/// Records the validation of the artifact in `artifact_words` (its byte
/// length in `artifact_length[0]`) after the commands already in `encoder`,
/// and returns the state words: word 0 holds the failure key once they ran.
/// With `export_status`, nothing is checked when that export failed.
/// Storage comes from `buffers`, so warm jobs reuse it.
#[allow(clippy::too_many_arguments)]
pub(crate) fn record_validation(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    buffers: &CapacityBufferCache,
    artifact_words: &LaniusBuffer<u32>,
    artifact_length: &LaniusBuffer<u32>,
    export_status: Option<&LaniusBuffer<u32>>,
) -> Result<LaniusBuffer<u32>> {
    let word_capacity = u32::try_from(artifact_words.byte_size / 4)
        .map_err(|_| anyhow!("semantic-interface artifact capacity exceeds u32 words"))?;
    // Each scratch table (00_plan.slang) has fewer words per row than the
    // row's record has in the artifact; the symbol table's power-of-two
    // slack is at most eight more.
    let scratch_words = word_capacity as usize + 64;
    let state = buffers.storage_u32(device, "type_check.interface.validate.state", STATE_WORDS,
        wgpu::BufferUsages::empty());
    let dispatch_args = buffers.storage_u32(device, "type_check.interface.validate.dispatch_args",
        ARGS_WORDS, wgpu::BufferUsages::INDIRECT);
    let scratch: LaniusBuffer<u32> = buffers.binding_capacity(
        device,
        "type_check.interface.validate.scratch",
        scratch_words * 4,
        wgpu::BufferUsages::STORAGE,
    );
    let params = buffers.uniform(device, queue, "type_check.interface.validate.params", &PlanParams {
        version: GPU_SEMANTIC_INTERFACE_VERSION,
        scratch_capacity: u32::try_from(scratch.count).unwrap_or(u32::MAX),
        word_capacity,
        check_export_status: u32::from(export_status.is_some()),
    });
    let status = export_status.unwrap_or(artifact_length);
    let plan = passes_core::make_pass_data_from_shader_key(device, LABEL, "main", PLAN_SHADER)?;
    let plan_group = create_bind_group_from_bindings(
        device,
        Some(LABEL),
        &plan,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("validate_export_status", status.as_entire_binding()),
            ("validate_artifact_words", artifact_words.as_entire_binding()),
            ("validate_artifact_length", artifact_length.as_entire_binding()),
            ("validate_state", state.as_entire_binding()),
            ("validate_scratch", scratch.as_entire_binding()),
            ("validate_dispatch_args", dispatch_args.as_entire_binding()),
        ],
    )?;
    let bindings = [
        ("validate_artifact_words", artifact_words.as_entire_binding()),
        ("validate_artifact_length", artifact_length.as_entire_binding()),
        ("validate_state", state.as_entire_binding()),
        ("validate_scratch", scratch.as_entire_binding()),
    ];
    let mut kernels = vec![(plan, plan_group, None)];
    for (index, (shader, label)) in RECORD_SHADERS.iter().enumerate() {
        let pass = passes_core::make_pass_data_from_shader_key(device, label, "main", shader)?;
        let group = create_bind_group_from_bindings(device, Some(label), &pass, 0, &bindings)?;
        kernels.push((pass, group, Some(dispatch_args.absolute_offset(3 * index as u64 * 4))));
    }
    // The kernels form their own pass, never part of a deferred batch, so
    // a caller outside any export may record them too.
    let descriptor = wgpu::ComputePassDescriptor { label: Some(LABEL), timestamp_writes: None };
    let dispatch = |compute: &mut wgpu::ComputePass<'_>, (pass, group, indirect): &(_, _, Option<u64>)| {
        let (pass, group): (&passes_core::PassData, &wgpu::BindGroup) = (pass, group);
        passes_core::record_compiler_operation(LABEL);
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(group), &[]);
        passes_core::record_compute_dispatch();
        match indirect {
            Some(offset) => compute.dispatch_workgroups_indirect(&dispatch_args.buffer, *offset),
            None => compute.dispatch_workgroups(1, 1, 1),
        }
    };
    if crate::gpu::timer::operation_capture_requires_split_passes() {
        for kernel in &kernels {
            dispatch(&mut passes_core::begin_counted_compute_pass(encoder, &descriptor), kernel);
            crate::gpu::timer::stamp_active_operation(encoder, LABEL);
        }
    } else {
        let timed = crate::gpu::timer::operation_capture_active();
        let mut compute = passes_core::begin_counted_compute_pass(encoder, &descriptor);
        for kernel in &kernels {
            dispatch(&mut compute, kernel);
            if timed {
                crate::gpu::timer::stamp_active_operation_in_pass(&mut compute, LABEL);
            }
        }
    }
    Ok(state)
}

/// The validation's verdict from its failure key.
pub(crate) fn verdict(key: u32) -> std::result::Result<(), String> {
    match key {
        PASSED => Ok(()),
        key => Err(failure_message(key)),
    }
}

/// Validates encoded artifact bytes that no export of this process left on
/// the GPU (stored dependency interfaces, or a test's artifacts) in one GPU
/// job: one submission uploads and validates every artifact, and one
/// readback reads every failure key. Returns one verdict per artifact; the
/// error is a device or transport failure.
pub(crate) fn validate_encoded_artifacts(
    artifacts: &[&[u8]],
) -> std::result::Result<Vec<std::result::Result<(), String>>, String> {
    if artifacts.is_empty() {
        return Ok(Vec::new());
    }
    let gpu = crate::gpu::device::global_result().map_err(|error| error.to_string())?;
    let (device, queue) = (&gpu.device, &gpu.queue);
    let readback = crate::gpu::buffers::readback_bytes(
        device,
        "type_check.interface.validate.readback",
        4 * artifacts.len(),
        4 * artifacts.len(),
    );
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(LABEL) });
    // An artifact longer than u32 bytes has its verdict without a GPU check.
    let mut verdicts = vec![Ok(()); artifacts.len()];
    // Each artifact's buffers are its own, so the validations may share one
    // submission; they live until it completes.
    let mut retained = Vec::with_capacity(artifacts.len());
    for (index, bytes) in artifacts.iter().enumerate() {
        let Ok(length) = u32::try_from(bytes.len()) else {
            verdicts[index] = Err("semantic-interface artifact exceeds u32 bytes".to_string());
            continue;
        };
        let mut padded = bytes.to_vec();
        padded.resize(bytes.len().next_multiple_of(4).max(4), 0);
        let artifact = crate::gpu::buffers::storage_ro_from_bytes::<u32>(
            device,
            "type_check.interface.validate.upload",
            &padded,
            padded.len() / 4,
        );
        let length = crate::gpu::buffers::storage_ro_from_u32s(device, "type_check.interface.validate.length", &[length]);
        let buffers = CapacityBufferCache::default();
        let state = record_validation(device, queue, &mut encoder, &buffers, &artifact, &length, None)
            .map_err(|error| format!("{error:#}"))?;
        passes_core::flush_deferred_compute(&mut encoder);
        encoder.copy_buffer_to_buffer(
            &state.buffer,
            state.absolute_offset(FAILURE_KEY_BYTE_OFFSET),
            &readback.buffer,
            4 * index as u64,
            4,
        );
        retained.push((artifact, length, buffers, state));
    }
    queue.submit(Some(encoder.finish()));
    let slice = readback.buffer.slice(0..4 * artifacts.len() as u64);
    passes_core::map_readback_blocking(device, &slice, "semantic-interface validation")
        .map_err(|error| format!("{error:#}"))?;
    let keys = slice.get_mapped_range()
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().expect("four bytes")))
        .collect::<Vec<_>>();
    readback.buffer.unmap();
    drop(retained);
    Ok(verdicts
        .into_iter()
        .zip(keys)
        .map(|(verdict, key)| verdict.and_then(|()| self::verdict(key)))
        .collect())
}

/// The message of one failure key (phase << 27 | row << 7 | code).
pub(crate) fn failure_message(key: u32) -> String {
    let phase = key >> 27;
    let row = (key >> 7) & 0xf_ffff;
    let code = key & 0x7f;
    let what = failure_text(phase, code);
    format!("semantic-interface {what} (check {phase}.{code}, record {row})")
}

fn failure_text(phase: u32, code: u32) -> &'static str {
    if code == 127 {
        return "graph exceeds the validation walk limit";
    }
    match (phase, code) {
        (1, 1) => "artifact has an invalid or truncated header or length",
        (1, 5) => "artifact version is unsupported",
        (1, 2) => "declaration count exceeds contract owner domain",
        (1, 3) => "implementation count exceeds contract owner domain",
        (1, 4) => "artifact exceeds the validation scratch capacity",
        (2, _) => "module segment range is outside the segment table",
        (3, 1) | (4, 2) | (9, 5) => "name range is outside the name bytes",
        (3, 2) | (4, 3) | (9, 6) => "record has an empty, oversized, or non-UTF-8 canonical name",
        (3, 3) | (4, 4) | (9, 7) => "record canonical-name hash does not match its bytes",
        (4, 1) => "declaration module is outside the module table",
        (4, 5) => "declaration owner is outside the declaration table",
        (5, 1) => "declaration has invalid native ABI metadata",
        (5, 2) => "declaration signature type is outside the type table",
        (5, 3) => "declaration record has no typed signature",
        (5, 4) => "declaration signature uses a constant operand as a value type",
        (5, 5) => "declaration member range is outside the member table",
        (5, 6) => "declaration record member range contains a foreign owner",
        (6, 1) => "implementation module is outside the module table",
        (6, 2) => "implementation subject is outside the type table",
        (6, 3) => "contract owner member range is outside the member table",
        (6, 4) => "implementation contains a foreign member owner",
        (6, 5) => "implementation argument range is outside the argument table",
        (6, 6) => "implementation argument root is outside the type table",
        (6, 7) => "implementation prerequisite range is outside the predicate table",
        (6, 8) => "implementation method binding range is outside the binding table",
        (7, 1) => "method binding implementation is outside the implementation table",
        (7, 2) => "method binding callable member is outside the member table",
        (8, 1) => "type record has unknown kind",
        (8, 2) => "type edge range is outside the edge table",
        (8, 3) => "type edge target is outside the type table",
        (8, 4) => "type record uses a constant operand as a value type",
        (8, 5) => "type record edge target is not in prior topological order",
        (8, 6) => "type record has a child before the start of its reverse-preorder subtree",
        (8, 7) => "type record child is not contiguous reverse preorder",
        (8, 8) => "type record has an unknown scalar identity",
        (8, 9) => "leaf type record has child edges",
        (8, 10) => "array type record must have element and length edges",
        (8, 11) => "unary type record has the wrong number of child edges",
        (8, 12) => "function type record has no return-type edge",
        (8, 13) => "constant operand has an invalid typed scalar value",
        (8, 14) => "count projection has an invalid target or reserved payload",
        (8, 15) => "count projection has a noninteger constant source",
        (8, 16) => "nominal type declaration is outside the declaration table",
        (8, 17) => "generic type member is outside the member table",
        (8, 18) => "type names the wrong parameter member kind",
        (8, 19) => "array type has an invalid length representation",
        (8, 20) => "array type has a noninteger constant length",
        (9, 1) => "member record has unknown kind",
        (9, 2) => "contract owner is invalid",
        (9, 3) => "contract owner member range is outside the member table",
        (9, 4) => "member is outside its owner's member range",
        (9, 8) => "member type is outside the type table",
        (9, 9) => "member signature uses a constant operand as a value type",
        (9, 10) => "member has an invalid implementation member kind",
        (9, 11) => "constant parameter lacks a supported declared scalar leaf",
        (9, 12) => "implementation method has a declaration owner",
        (9, 13) => "implementation method receiver type is outside the type table",
        (9, 14) => "implementation method receiver uses a constant operand as a value type",
        (9, 15) => "member record has a receiver type without an implementation method",
        (9, 16) => "trait method has a non-trait owner",
        (9, 17) => "member has invalid generic declaration order",
        (9, 18) => "member record has no typed signature",
        (10, 1) => "nominal parameter range is outside the member table",
        (10, 2) => "nominal application arity disagrees with its header",
        (10, 3) => "nominal application operand has the wrong declared domain",
        (11, 1) => "trait has an incomplete header",
        (11, 2) => "trait has an invalid ordered parameter",
        (12, _) => "method has invalid or duplicate requirements/identity",
        (13, _) => "declaration has a parameter without its method",
        (14, 1) => "parameter has no implementation owner",
        (14, _) => "parameter has invalid or duplicate lexical ownership",
        (15, _) => "declaration scope has incomplete or duplicate generic declaration order",
        (16, 1) => "method parameter count disagrees with its records",
        (16, 2) => "method parameter ordinals are not a complete signature",
        (16, 3) => "method declared parameter requirements disagree with its lexical slots",
        (16, 4) => "method uses a foreign or out-of-range parameter",
        (16, 5) => "method mixes different impl parameter scopes",
        (17, 0) => "implementation has an unresolved defining unit",
        (17, 1) => "implementation has unknown kind",
        (17, 2) => "implementation has invalid visibility or trait identity",
        (17, 3) => "implementation exceeds 32 ordered operands",
        (17, 4) => "implementation subject uses a constant operand as a value type",
        (17, 5) => "implementation argument has multiple owners",
        (17, 6) => "trait implementation has a foreign header scope",
        (17, 7) => "trait implementation has an incomplete lexical binding scope",
        (17, 8) => "trait implementation has an unconstrained implementation parameter",
        (17, 9) => "implementation parameter has no owning method",
        (17, 10) => "inherent implementation has invalid visibility or trait fields",
        (17, 11) => "implementation subject uses a constant operand as a value type",
        (17, 12) => "inherent implementation has no public methods",
        (17, 13) => "implementation prerequisite has a foreign lexical owner",
        (17, 14) => "implementation mixes different impl parameter scopes",
        (17, 15) => "implementation has an unresolved type identity",
        (17, 16) => "implementation uses a foreign lexical parameter",
        (17, 17) => "inherent implementation has a foreign header scope",
        (17, 18) => "inherent implementation has an incomplete lexical binding scope",
        (17, 20) => "inherent callable has an invalid public target contract",
        (17, 21) => "implementation method receiver disagrees with its full subject",
        (17, 22) => "inherent method has an incomplete composed header",
        (17, 23) => "implementation prerequisite is outside its implementation range",
        (17, 24) => "implementation method has an incomplete inherited header",
        (17, 25) => "trait implementation method own prerequisites are unsupported",
        (17, 26) => "implementation trait declaration is outside the declaration table",
        (17, 27) => "implementation does not name a trait",
        (17, 28) => "implementation trait arity disagrees with its operands",
        (17, 29) => "implementation operand has the wrong declared domain",
        (17, 30) => "implementation method binding has multiple owners",
        (17, 31) => "implementation method binding has invalid or duplicate ownership",
        (17, 32) => "implementation method binding has an invalid executable target",
        (17, 33) => "implementation method binding names no required method",
        (17, 34) => "implementation method binding signature disagrees with its trait",
        (17, 35) => "implementation method binding lacks a required parameter",
        (17, 36) => "implementation method binding parameter disagrees with its trait",
        (17, 37) => "implementation has an incomplete required-method binding set",
        (17, 38) => "implementation arguments or method bindings have no owner",
        (18, 1) => "contract owner is invalid",
        (18, 2) => "predicate has a non-callable owner",
        (18, 3) => "predicate has no owning trait method",
        (18, 7) => "predicate is outside its implementation prerequisite range",
        (18, 8) => "predicate requires unsupported trait implementation method predicates",
        (18, 9) => "predicate has no owning inherent method",
        (18, 10) => "predicate has an incomplete lexical binding scope",
        (18, 11) => "predicate subject is outside the type table",
        (18, 12) => "predicate subject uses a constant operand as a value type",
        (18, 13) => "predicate has an unresolved trait identity",
        (18, 14) => "predicate exceeds 32 ordered operands",
        (18, 15) => "predicate argument range is outside the argument table",
        (18, 16) => "predicate argument has multiple owners",
        (18, 17) => "predicate argument root is outside the type table",
        (18, 18) => "predicate trait declaration is outside the declaration table",
        (18, 19) => "predicate does not name a trait",
        (18, 20) => "predicate trait arity disagrees with its operands",
        (18, 21) => "predicate operand has the wrong declared domain",
        (18, 22) => "predicate has an unresolved type identity",
        (18, 23) => "predicate uses a foreign lexical parameter",
        (18, 24) => "predicate argument has no owner",
        (19, _) => "declaration has an unsupported native C signature",
        _ => "artifact failed validation",
    }
}
