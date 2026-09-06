mod common;

#[test]
fn lanius_surface_literals_preserve_spelling() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("verified_compiler/tests/surface_atoms.lani");
    let roots = EntrySourceRoots {
        user_roots: vec![root.join("verified_compiler/src")],
        stdlib_root: Some(root.join("stdlib")),
    };
    let elf = common::run_gpu_codegen_with_timeout("Lanius Surface atoms", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(entry, &roots))
    })
    .expect("compile Surface atom extraction");
    let result = common::run_x86_64_elf_output("Lanius Surface atoms", "surface_atoms", &elf);
    assert!(
        result.status.success(),
        "Surface atom contract failed: {result:?}"
    );
    let stdout = String::from_utf8(result.stdout).expect("native Surface output is UTF-8");
    let lean = common::TempArtifact::new("extraction", "surface_atoms", Some("lean"));
    let source = format!(
        r#"import Lanius.Extraction.SurfaceReconstruct
import Lanius.Extraction.KernelReduction
open Lanius.Extraction
noncomputable def emitted : List SurfaceLiteral := {}
example : emitted = [.integer 0 "42", .float 1 "1.0", .string 2 "\"\\n\"",
    .character 3 "'x'", .boolean true, .boolean false] := by kernel_rfl
private def artifact : Artifact := {{ Artifact.empty with
  sources := [⟨"atoms", [52,50,32,49,46,48,32,34,92,110,34,32,39,120,39]⟩]
  tokens := [⟨2,⟨0,0,2⟩⟩,⟨5,⟨0,3,6⟩⟩,⟨6,⟨0,7,11⟩⟩,⟨7,⟨0,12,15⟩⟩]
  parse_nodes := [⟨175,0,0,2,[.token 0]⟩,⟨176,0,2,4,[.token 1]⟩,
    ⟨177,0,4,6,[.token 2]⟩,⟨178,0,6,8,[.token 3]⟩]
}}
example : (List.range 4).map (fun i => reconstructTokenLiteral artifact i (175+i)) =
    (emitted.take 4).map some := by kernel_rfl
"#,
        stdout
    );
    std::fs::write(lean.path(), source).unwrap();
    let checked = std::process::Command::new("lake")
        .current_dir(root.join("formal"))
        .args(["env", "lean", "-M", "12000"])
        .arg(lean.path())
        .output()
        .expect("check actual Surface literal output");
    assert!(
        checked.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&checked.stdout),
        String::from_utf8_lossy(&checked.stderr)
    );
}

use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};

#[test]
fn lanius_extractor_uses_full_language_grammar() {
    let started = std::time::Instant::now();
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let grammar: Vec<i32> =
        serde_json::from_str(include_str!("../verified_compiler/data/grammar.json"))
            .expect("packed grammar data");
    let sources: [&[u8]; 16] = [
        b"module app::main;fn main() -> i32 { return -1 + 2 * 3 - 4; }",
        b"module app::main;fn main() -> i32 { return -a::b::c + 2 * x - 4; }",
        b"module app::main;fn main() -> i32 { return a = b = 4; }",
        b"module app::main;fn main() -> i32 { return a.b[1+2].c[3] + 4; }",
        b"module app::main;fn main() -> i32 { return a[1][2].b = 4; }",
        b"module app::main;fn main() -> i32 { return f()(1,g(2,3),).x[4] + 5; }",
        b"module app::main;fn main() -> i32 { return f(a[1], b.x, 2+3) + 4; }",
        b"module app::main;fn main()->i32{return f([])+4;}",
        b"module app::main;fn main()->i32{return [[],[1,2,],f(3)][1]+4;}",
        b"module app::main;fn main(value: [i32;4]) { return 0; }",
        b"module app::main;fn main(value: [i32]) { return 0; }",
        b"module app::main;fn main(value: &app::Thing) { return 0; }",
        b"module app::main;fn main(value: app::Thing<i32,[u8;4]>) { return 0; }",
        b"module app::main;struct Point { x:i32,y:i32 } fn main(){ return Point { x:1,y:2 }; }",
        b"module app::main;fn main(v:i32)->i32{let a:i32=1;let b=2;let c:i32;let d;if(v){a=3;}else{{b=4;}}while(v){break;continue;}v;return a;}",
        b"module app::main;type A=i32;pub type B=u8;const C:i32=1;pub const D:i32=2;fn main()->i32{return C;}",
    ];
    let list = |values: &[i32]| {
        values
            .iter()
            .map(i32::to_string)
            .collect::<Vec<_>>()
            .join(",")
    };
    let temporary = common::TempArtifact::new("extraction", "full_grammar", Some("lani"));
    let input = common::TempArtifact::new("extraction", "input", Some("lani"));
    let path_bytes = input.path().to_str().unwrap().as_bytes();
    let packed_path: Vec<i32> = path_bytes
        .chunks(4)
        .map(|chunk| {
            let mut bytes = [0; 4];
            bytes[..chunk.len()].copy_from_slice(chunk);
            i32::from_le_bytes(bytes)
        })
        .collect();
    let artifact_path: Vec<i32> = path_bytes.iter().map(|byte| i32::from(*byte)).collect();
    let encoded_grammar = grammar
        .iter()
        .map(|word| format!("{word:04x}"))
        .collect::<String>();
    let entry = temporary.path().to_path_buf();
    let program = format!(
        r#"module app::main;
import verified::extraction;
import verified::byte_io;
import verified::semantic_tokens;
import verified::artifact_output;
import verified::source_output;
import verified::parse_output;
import verified::surface_literal;
import verified::surface_expr;
import verified::surface_expr_output;
import verified::surface_type;
import verified::surface_type_output;
import verified::surface_stmt_output;
import verified::surface_function_output;
import verified::surface_item_output;
import verified::surface_path_output;
import verified::surface_file_output;
import verified::output;
import alloc::allocator;
import core::mem;
import std::fs;

fn hex_nibble(byte: i32) -> i32 {{
    if (byte >= 48 && byte <= 57) {{ return byte - 48; }}
    return byte - 87;
}}

fn main() -> i32 {{
    let grammar: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc({grammar_bytes}, 4), {grammar_len});
    let encoded_grammar: str = "{encoded_grammar}";
    let encoded_words: [i32] = core::mem::i32_slice_from_raw_parts(
        core::mem::string_data_ptr(encoded_grammar), {grammar_len});
    let grammar_index: i32 = 0;
    while (grammar_index != {grammar_len}) {{
        let encoded_word: i32 = encoded_words[grammar_index];
        grammar[grammar_index] =
            (hex_nibble(encoded_word & 255) << 12)
            | (hex_nibble((encoded_word >> 8) & 255) << 8)
            | (hex_nibble((encoded_word >> 16) & 255) << 4)
            | hex_nibble((encoded_word >> 24) & 255);
        grammar_index += 1;
    }}
    let source: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(1024, 4), 256);
    let packed_path: [i32; {path_words}] = [{packed_path}];
    let path: [i32; {path_length}] = [{path}];
    let handle: i32 = std::fs::open_read(core::mem::i32_array_data_ptr(packed_path), {path_length});
    if (handle <= -1) {{ return 30; }}
    let source_length: i32 = verified::byte_io::read_file(handle, source, 256);
    let closed: i32 = std::fs::close(handle);
    if (source_length <= -1 || closed <= -1) {{ return 31; }}
    let raw: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(2048, 4), 512);
    let canonical: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(2048, 4), 512);
    let kinds: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(1024, 4), 256);
    let workspace: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(131072, 4), 32768);
    let records: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(16384, 4), 4096);
    let offsets: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(2048, 4), 512);
    let arena: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(1024, 4), 256);
    let semantic: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(1024, 4), 256);
    let output: [i32] = core::mem::i32_slice_from_raw_parts(
        alloc::allocator::alloc(131072, 4), 32768);
    let extracted = verified::extraction::extract_syntax(source, source_length,
        grammar, {grammar_len}, raw, 512, canonical, 512, kinds, 256,
        workspace, 32768, records, 4096, offsets, 512, 128);
    if (verified::extraction::extraction_stage(extracted) != verified::extraction::EXTRACT_SUCCESS) {{
        return 10 + verified::extraction::extraction_stage(extracted);
    }}
    let nodes: i32 = verified::extraction::node_count(extracted);
    if (nodes <= 0) {{ return 20; }}
    let root: i32 = offsets[nodes - 1];
    if (records[root] != 0 || records[root + 1] != 0
        || records[root + 2] != verified::extraction::token_count(extracted) * 2) {{ return 21; }}
    let count: i32 = verified::extraction::token_count(extracted);
    if (verified::semantic_tokens::collect(grammar, {grammar_len}, kinds, count,
        records, 4096, offsets, nodes, semantic, 256) != 0) {{ return 32; }}
    let written: i32 = verified::artifact_output::emit_surface(path, {path_length}, source, source_length,
        grammar, {grammar_len}, raw, 512, verified::extraction::raw_count(extracted),
        canonical, 512, count, semantic, 256, records, 4096, offsets, nodes,
        arena, 256, kinds, 256, 512, output, 32768);
    if (written <= -1) {{
        if (verified::source_output::emit_bytes(path, {path_length}, output, 16384, 0) <= -1) {{ return 51; }}
        if (verified::source_output::emit_bytes(source, source_length, output, 16384, 0) <= -1) {{ return 52; }}
        if (verified::source_output::emit_tokens(raw, 512,
            verified::extraction::raw_count(extracted), source_length, 0,
            output, 16384, 0) <= -1) {{ return 53; }}
        if (verified::source_output::emit_tokens(canonical, 512, count,
            source_length, 0, output, 16384, 0) <= -1) {{ return 54; }}
        if (verified::semantic_tokens::emit(semantic, 256, count,
            output, 16384, 0) <= -1) {{ return 55; }}
        if (verified::parse_output::emit_nodes(grammar, {grammar_len}, records,
            4096, offsets, nodes, count, output, 16384, 0) <= -1) {{ return 56; }}
        return 33;
    }}
    if (verified::byte_io::write_stdout(output, written) != written) {{ return 34; }}
    if (verified::artifact_output::emit_surface(path, {path_length}, source,
        source_length, grammar, {grammar_len}, raw, 512,
        verified::extraction::raw_count(extracted), canonical, 512, count,
        semantic, 256, records, 4096, offsets, nodes, arena, 256, kinds, 256,
        512, output, 1) != -1) {{ return 68; }}
    if (verified::artifact_output::emit_surface(path, {path_length}, source,
        source_length, grammar, {grammar_len}, raw, 512,
        verified::extraction::raw_count(extracted), canonical, 512, count,
        semantic, 256, records, 4096, offsets, nodes, arena, 256, kinds, 256,
        1, output, 32768) != -1) {{ return 69; }}
    output[0] = 10;
    if (verified::byte_io::write_stdout(output, 1) != 1) {{ return 35; }}
    let primary: i32 = -1;
    let candidate: i32 = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 175) {{ primary = candidate; }}
        candidate += 1;
    }}
    let literal_length: i32 = verified::surface_literal::emit(source, source_length,
        canonical, count, records, 4096, offsets, nodes, primary, 7, output, 16384, 0);
    if (literal_length <= -1 || verified::byte_io::write_stdout(output, literal_length) != literal_length) {{ return 35; }}
    if (verified::surface_literal::emit(source, source_length, canonical, count,
        records, 4096, offsets, nodes, primary, 2147483647, output, 16384, 0) != -1) {{ return 36; }}
    let primary_offset: i32 = offsets[primary];
    records[primary_offset + 4] = 2;
    if (verified::surface_literal::emit(source, source_length, canonical, count,
        records, 4096, offsets, nodes, primary, 7, output, 16384, 0) != -1) {{ return 37; }}
    records[primary_offset + 4] = 1;
    offsets[primary] = 1023;
    if (verified::surface_literal::emit(source, source_length, canonical, count,
        records, 4096, offsets, nodes, primary, 7, output, 16384, 0) != -1) {{ return 38; }}
    offsets[primary] = primary_offset;
    let expression: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 104) {{ expression = candidate; }}
        candidate += 1;
    }}
    let expression_root: i32 = verified::surface_expr::extract(records, 4096,
        offsets, nodes, count, expression, arena, 256, 512);
    if (expression_root <= -1) {{ return 3900 + arena[0]; }}
    output[0] = 10; output[1] = 40;
    let expression_length: i32 = verified::output::natural(output, 16384, 2, expression);
    expression_length = verified::output::byte(output, 16384, expression_length, 44);
    expression_length = verified::surface_expr_output::emit(source, source_length,
        canonical, count, records, 4096, offsets, nodes, arena, 256, expression_root,
        7, output, 16384, expression_length);
    expression_length = verified::output::byte(output, 16384, expression_length, 44);
    expression_length = verified::output::natural(output, 16384, expression_length, 7 + arena[0]);
    expression_length = verified::output::byte(output, 16384, expression_length, 41);
    if (expression_length <= -1 || verified::byte_io::write_stdout(output, expression_length) != expression_length) {{ return 40; }}
    let call_argument: i32 = -1;
    candidate = 0;
    while (candidate != arena[0]) {{
        if ((arena[1 + candidate * 7] == 9 || arena[1 + candidate * 7] == 10)
            && arena[1 + candidate * 7 + 4] != -1) {{
            call_argument = arena[1 + candidate * 7 + 4];
        }}
        candidate += 1;
    }}
    if (call_argument != -1) {{
        let link: i32 = arena[1 + call_argument * 7 + 6];
        arena[1 + call_argument * 7 + 6] = call_argument;
        if (verified::surface_expr_output::emit(source, source_length, canonical, count,
            records, 4096, offsets, nodes, arena, 256, expression_root, 7,
            output, 16384, 0) != -1) {{ return 45; }}
        arena[1 + call_argument * 7 + 6] = link;
    }}
    let segment: i32 = -1;
    candidate = 0;
    while (candidate != arena[0]) {{
        if (arena[1 + candidate * 7] == 4) {{ segment = candidate; }}
        candidate += 1;
    }}
    if (segment != -1) {{
        let link: i32 = arena[1 + segment * 7 + 3];
        arena[1 + segment * 7 + 3] = segment;
        if (verified::surface_expr_output::emit(source, source_length, canonical, count,
            records, 4096, offsets, nodes, arena, 256, expression_root, 7,
            output, 16384, 0) != -1) {{ return 44; }}
        arena[1 + segment * 7 + 3] = link;
    }}
    arena[1 + expression_root * 7 + 3] = expression_root;
    if (verified::surface_expr_output::emit(source, source_length, canonical, count,
        records, 4096, offsets, nodes, arena, 256, expression_root, 7,
        output, 16384, 0) != -1) {{ return 41; }}
    if (verified::surface_expr::extract(records, 4096, offsets, nodes, count,
        expression, arena, 1, 512) != -1) {{ return 42; }}
    if (verified::surface_expr::extract(records, 4096, offsets, nodes, count,
        expression, arena, 256, 1) != -1) {{ return 43; }}
    let type_expression: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        let type_kind: i32 = records[offsets[candidate]];
        if (type_kind == 69 || type_kind == 70 || type_kind == 285) {{
            type_expression = candidate;
        }}
        candidate += 1;
    }}
    if (type_expression <= -1) {{ return 46; }}
    let type_root: i32 = verified::surface_type::extract(records, 4096,
        offsets, nodes, count, type_expression, arena, 256, 512);
    if (type_root <= -1) {{ return 47; }}
    output[0] = 10; output[1] = 40;
    let type_length: i32 = verified::output::natural(output, 16384, 2, type_expression);
    type_length = verified::output::byte(output, 16384, type_length, 44);
    type_length = verified::surface_type_output::emit(source, source_length,
        canonical, count, arena, 256, type_root, 7, output, 16384, type_length);
    type_length = verified::output::byte(output, 16384, type_length, 44);
    type_length = verified::output::natural(output, 16384, type_length, 7 + arena[0]);
    type_length = verified::output::byte(output, 16384, type_length, 41);
    if (type_length <= -1 || verified::byte_io::write_stdout(output, type_length) != type_length) {{ return 48; }}
    let type_segment: i32 = -1;
    candidate = 0;
    while (candidate != arena[0]) {{
        if (arena[1 + candidate * 8] == 0) {{ type_segment = candidate; }}
        candidate += 1;
    }}
    if (type_segment <= -1) {{ return 49; }}
    let type_link: i32 = arena[1 + type_segment * 8 + 7];
    arena[1 + type_segment * 8 + 7] = type_segment;
    if (verified::surface_type_output::emit(source, source_length, canonical,
        count, arena, 256, type_root, 7, output, 16384, 0) != -1) {{ return 50; }}
    arena[1 + type_segment * 8 + 7] = type_link;
    if (verified::surface_type_output::emit(source, source_length, canonical,
        count, arena, 256, type_root, 7, output, 1, 0) != -1) {{ return 51; }}
    if (verified::surface_type::extract(records, 4096, offsets, nodes, count,
        type_expression, arena, 1, 512) != -1) {{ return 52; }}
    if (verified::surface_type::extract(records, 4096, offsets, nodes, count,
        type_expression, arena, 256, 1) != -1) {{ return 53; }}
    let block: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 12) {{ block = candidate; }}
        candidate += 1;
    }}
    if (block <= -1) {{ return 57; }}
    output[0] = 10; output[1] = 40;
    let statement_length: i32 = verified::output::natural(output, 16384, 2, block);
    statement_length = verified::output::byte(output, 16384, statement_length, 44);
    let statement_result = verified::surface_stmt_output::emit_block(source,
        source_length, canonical, count, records, 4096, offsets, nodes, block,
        arena, 256, semantic, 256, 512, 7, output, 16384, statement_length);
    statement_length = verified::surface_stmt_output::emit_position(statement_result);
    statement_length = verified::output::byte(output, 16384, statement_length, 44);
    statement_length = verified::output::natural(output, 16384, statement_length,
        verified::surface_stmt_output::emit_next_id(statement_result));
    statement_length = verified::output::byte(output, 16384, statement_length, 41);
    if (statement_length <= -1
        || verified::byte_io::write_stdout(output, statement_length) != statement_length) {{ return 58; }}
    let function: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 11) {{ function = candidate; }}
        candidate += 1;
    }}
    if (function <= -1) {{ return 59; }}
    output[0] = 10; output[1] = 40;
    let function_length: i32 = verified::output::natural(output, 16384, 2, function);
    function_length = verified::output::byte(output, 16384, function_length, 44);
    let function_result = verified::surface_function_output::emit(source,
        source_length, canonical, count, records, 4096, offsets, nodes,
        function, false, arena, 256, semantic, 256, 512, 7, output, 16384,
        function_length);
    function_length = verified::surface_function_output::emit_position(function_result);
    function_length = verified::output::byte(output, 16384, function_length, 44);
    function_length = verified::output::natural(output, 16384, function_length,
        verified::surface_function_output::emit_next_id(function_result));
    function_length = verified::output::byte(output, 16384, function_length, 41);
    if (function_length <= -1
        || verified::byte_io::write_stdout(output, function_length) != function_length) {{ return 60; }}
    let function_item: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 4) {{ function_item = candidate; }}
        candidate += 1;
    }}
    if (function_item <= -1) {{ return 61; }}
    output[0] = 10; output[1] = 40;
    let item_length: i32 = verified::output::natural(output, 16384, 2, function_item);
    item_length = verified::output::byte(output, 16384, item_length, 44);
    let item_result = verified::surface_item_output::emit(source,
        source_length, canonical, count, records, 4096, offsets, nodes,
        function_item, arena, 256, semantic, 256, 512, 7, output, 16384,
        item_length);
    item_length = verified::surface_item_output::emit_position(item_result);
    item_length = verified::output::byte(output, 16384, item_length, 44);
    item_length = verified::output::natural(output, 16384, item_length,
        verified::surface_item_output::emit_next_id(item_result));
    item_length = verified::output::byte(output, 16384, item_length, 41);
    if (item_length <= -1
        || verified::byte_io::write_stdout(output, item_length) != item_length) {{ return 62; }}
    let module_item: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 7) {{ module_item = candidate; }}
        candidate += 1;
    }}
    if (module_item <= -1) {{ return 65; }}
    output[0] = 10; output[1] = 40;
    let module_length: i32 = verified::output::natural(output, 16384, 2, module_item);
    module_length = verified::output::byte(output, 16384, module_length, 44);
    let module_result = verified::surface_item_output::emit(source,
        source_length, canonical, count, records, 4096, offsets, nodes,
        module_item, arena, 256, semantic, 256, 512, 7, output, 16384,
        module_length);
    module_length = verified::surface_item_output::emit_position(module_result);
    module_length = verified::output::byte(output, 16384, module_length, 44);
    module_length = verified::output::natural(output, 16384, module_length,
        verified::surface_item_output::emit_next_id(module_result));
    module_length = verified::output::byte(output, 16384, module_length, 41);
    if (module_length <= -1
        || verified::byte_io::write_stdout(output, module_length) != module_length) {{ return 66; }}
    let path_node: i32 = -1;
    candidate = 0;
    while (candidate != nodes) {{
        if (records[offsets[candidate]] == 47) {{ path_node = candidate; }}
        candidate += 1;
    }}
    if (path_node <= -1) {{ return 63; }}
    output[0] = 10; output[1] = 40;
    let path_length_out: i32 = verified::output::natural(output, 16384, 2, path_node);
    path_length_out = verified::output::byte(output, 16384, path_length_out, 44);
    let path_result = verified::surface_path_output::emit(source, source_length,
        canonical, count, records, 4096, offsets, nodes, path_node, semantic,
        256, 512, 7, output, 16384, path_length_out);
    path_length_out = verified::surface_path_output::emit_position(path_result);
    path_length_out = verified::output::byte(output, 16384, path_length_out, 44);
    path_length_out = verified::output::natural(output, 16384, path_length_out,
        verified::surface_path_output::emit_next_id(path_result));
    path_length_out = verified::output::byte(output, 16384, path_length_out, 41);
    if (path_length_out <= -1
        || verified::byte_io::write_stdout(output, path_length_out) != path_length_out) {{ return 64; }}
    let root_node: i32 = nodes - 1;
    output[0] = 10; output[1] = 40;
    let file_length: i32 = verified::output::natural(output, 16384, 2, root_node);
    file_length = verified::output::byte(output, 16384, file_length, 44);
    let file_result = verified::surface_file_output::emit(source,
        source_length, canonical, count, records, 4096, offsets, nodes,
        root_node, arena, 256, semantic, 256, 512, 0, output, 16384,
        file_length);
    file_length = verified::surface_file_output::emit_position(file_result);
    file_length = verified::output::byte(output, 16384, file_length, 44);
    file_length = verified::output::natural(output, 16384, file_length,
        verified::surface_file_output::emit_next_id(file_result));
    file_length = verified::output::byte(output, 16384, file_length, 41);
    if (file_length <= -1
        || verified::byte_io::write_stdout(output, file_length) != file_length) {{ return 67; }}
    source[0] = 96;
    let rejected = verified::extraction::extract_syntax(source, source_length,
        grammar, {grammar_len}, raw, 512, canonical, 512, kinds, 256,
        workspace, 32768, records, 4096, offsets, 512, 128);
    if (verified::extraction::extraction_stage(rejected) != verified::extraction::EXTRACT_LEX) {{ return 22; }}
    return 0;
}}
"#,
        grammar_len = grammar.len(),
        grammar_bytes = grammar.len() * 4,
        encoded_grammar = encoded_grammar,
        path_words = packed_path.len(),
        packed_path = list(&packed_path),
        path = list(&artifact_path),
        path_length = path_bytes.len(),
    );
    std::fs::write(&entry, program).unwrap();
    let source_root = root.join("verified_compiler/src");
    let roots = EntrySourceRoots {
        user_roots: vec![source_root],
        stdlib_root: Some(root.join("stdlib")),
    };
    let elf = common::run_gpu_codegen_with_timeout("full-grammar Lanius extraction", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(entry, &roots))
    })
    .expect("compile full-grammar extraction test");
    eprintln!("full-grammar GPU compilation: {:?}", started.elapsed());
    let native_started = std::time::Instant::now();
    const LEAN_BATCH_COUNT: usize = 4;
    let lean_prefix = "import Lanius.Extraction.ParseChecker\n\
         import Lanius.Extraction.SurfaceReconstruct\n\
         import Lanius.Extraction.KernelReduction\n\
         open Lanius.Extraction\n";
    let mut lean_sources = vec![String::from(lean_prefix); LEAN_BATCH_COUNT];
    for (case_index, source) in sources.into_iter().enumerate() {
        input.write_bytes(source);
        let result = common::run_x86_64_elf_output(
            "full-grammar Lanius extraction",
            "lanius_full_grammar_extraction",
            &elf,
        );
        assert!(
            result.status.success(),
            "source-to-tree extraction failed ({result:?}) for {}",
            String::from_utf8_lossy(source)
        );
        let stdout = String::from_utf8(result.stdout).expect("native extraction output is UTF-8");
        assert!(stdout.starts_with("{ Lanius.Extraction.Artifact.empty with"));
        let (artifact_term, _) = stdout
            .split_once('\n')
            .expect("artifact and diagnostic terms");
        assert!(artifact_term.ends_with(" }"));
        lean_sources[case_index % LEAN_BATCH_COUNT].push_str(&format!(
        "namespace ExtractionCase{}\ndef extracted : Artifact := {}\nexample : checkParseArtifact extracted = true := by kernel_rfl\nexample : extracted.surface = reconstructArtifactSurface extracted := by kernel_rfl\nend ExtractionCase{}\n",
        case_index, artifact_term, case_index
    ));
    }
    eprintln!("full-grammar native batch: {:?}", native_started.elapsed());
    let lean_started = std::time::Instant::now();
    let mut lean_jobs = Vec::with_capacity(LEAN_BATCH_COUNT);
    for (batch, source) in lean_sources.into_iter().enumerate() {
        let artifact = common::TempArtifact::new(
            "extraction",
            &format!("runtime_artifacts_{batch}"),
            Some("lean"),
        );
        std::fs::write(artifact.path(), source).unwrap();
        let child = std::process::Command::new("lake")
            .current_dir(root.join("formal"))
            .args(["env", "lean", "-M", "3000"])
            .arg(artifact.path())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .expect("start batched Lean artifact check");
        lean_jobs.push((artifact, child));
    }
    for (batch, (_artifact, child)) in lean_jobs.into_iter().enumerate() {
        let checked = child
            .wait_with_output()
            .expect("finish batched Lean artifact check");
        assert!(
            checked.status.success(),
            "Lean rejected emitted-artifact batch {batch}:\n{}\n{}",
            String::from_utf8_lossy(&checked.stdout),
            String::from_utf8_lossy(&checked.stderr)
        );
    }
    eprintln!("full-grammar Lean batch: {:?}", lean_started.elapsed());
}

#[test]
fn lanius_extractor_runs_source_to_syntax_evidence() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("verified_compiler/tests/extraction_syntax.lani");
    let roots = EntrySourceRoots {
        user_roots: vec![root.join("verified_compiler/src")],
        stdlib_root: Some(root.join("stdlib")),
    };
    let elf = common::run_gpu_codegen_with_timeout("Lanius syntax extraction", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(entry, &roots))
    })
    .expect("compile the Lanius extraction test");
    let result =
        common::run_x86_64_elf_output("Lanius syntax extraction", "lanius_syntax_extraction", &elf);
    assert!(
        result.status.success(),
        "native extraction failed: {result:?}"
    );
}
