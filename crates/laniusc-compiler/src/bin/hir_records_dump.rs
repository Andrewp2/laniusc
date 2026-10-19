// src/bin/hir_records_dump.rs
// Developer differential tool for the GPU parser's HIR phase. It parses each
// input as a resident source pack, reads back the decoded HIR item records
// (canonical HIR words included) and writes one FNV-1a digest per record
// array, so a HIR shader change can be checked bit-for-bit against a build of
// the previous revision.
//
// CLI (run from the workspace root, which holds tables/parse_tables.bin):
//   hir_records_dump OUT.tsv [--pack=DIR]... [PATH]...
//
// `--pack=DIR` parses every .lani file under DIR as one source pack (large
// tree capacities). Each PATH is a .lani file or a directory whose files are
// each parsed as a one-file pack. Every output line is
// `label<TAB>field<TAB>len<TAB>digest`, or `label<TAB>error<TAB>message`.

use std::{
    io::Write,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use laniusc_compiler::{
    lexer::driver::GpuLexer,
    parser::{
        driver::GpuParser,
        readback::{DecodedParserHirItemReadbacks, ParserHirItemReadbacks},
        tables::PrecomputedParseTables,
    },
};

fn collect_lani(path: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    if path.is_dir() {
        let mut entries = std::fs::read_dir(path)
            .with_context(|| format!("read dir {}", path.display()))?
            .collect::<std::io::Result<Vec<_>>>()?;
        entries.sort_by_key(|entry| entry.path());
        for entry in entries {
            collect_lani(&entry.path(), out)?;
        }
    } else if path.extension().and_then(|e| e.to_str()) == Some("lani") {
        out.push(path.to_path_buf());
    }
    Ok(())
}

fn fnv1a(words: &[u32]) -> u64 {
    let mut hash = 0xcbf2_9ce4_8422_2325u64;
    for word in words {
        for byte in word.to_le_bytes() {
            hash ^= u64::from(byte);
            hash = hash.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }
    hash
}

fn fields(d: &DecodedParserHirItemReadbacks) -> Vec<(&'static str, &Vec<u32>)> {
    vec![
        ("node_kind", &d.node_kind),
        ("hir_kind", &d.hir_kind),
        ("hir_token_pos", &d.hir_token_pos),
        ("hir_token_end", &d.hir_token_end),
        ("hir_node_file_id", &d.hir_node_file_id),
        ("hir_semantic_dense_node", &d.hir_semantic_dense_node),
        ("hir_semantic_parent", &d.hir_semantic_parent),
        ("hir_semantic_first_child", &d.hir_semantic_first_child),
        ("hir_semantic_next_sibling", &d.hir_semantic_next_sibling),
        ("hir_semantic_depth", &d.hir_semantic_depth),
        ("hir_semantic_child_index", &d.hir_semantic_child_index),
        ("hir_canonical_core_words", &d.hir_canonical_core_words),
        ("hir_canonical_payload_words", &d.hir_canonical_payload_words),
        ("hir_canonical_nearest_fn", &d.hir_canonical_nearest_fn),
        ("hir_type_form", &d.hir_type_form),
        ("hir_type_value_node", &d.hir_type_value_node),
        ("hir_type_len_token", &d.hir_type_len_token),
        ("hir_type_len_operand", &d.hir_type_len_operand),
        ("hir_type_file_id", &d.hir_type_file_id),
        ("hir_type_path_leaf_node", &d.hir_type_path_leaf_node),
        ("hir_type_arg_start", &d.hir_type_arg_start),
        ("hir_type_arg_count", &d.hir_type_arg_count),
        ("hir_type_arg_next", &d.hir_type_arg_next),
        ("hir_type_alias_target_node", &d.hir_type_alias_target_node),
        ("hir_fn_return_type_node", &d.hir_fn_return_type_node),
        ("hir_item_kind", &d.hir_item_kind),
        ("hir_item_name_token", &d.hir_item_name_token),
        ("hir_item_decl_token", &d.hir_item_decl_token),
        ("hir_item_namespace", &d.hir_item_namespace),
        ("hir_item_visibility", &d.hir_item_visibility),
        ("hir_item_path_start", &d.hir_item_path_start),
        ("hir_item_path_end", &d.hir_item_path_end),
        ("hir_item_path_node", &d.hir_item_path_node),
        ("hir_item_file_id", &d.hir_item_file_id),
        ("hir_item_import_target_kind", &d.hir_item_import_target_kind),
        ("hir_variant_parent_enum", &d.hir_variant_parent_enum),
        ("hir_variant_ordinal", &d.hir_variant_ordinal),
        ("hir_variant_payload_start", &d.hir_variant_payload_start),
        ("hir_variant_payload_count", &d.hir_variant_payload_count),
        ("hir_variant_payload_node", &d.hir_variant_payload_node),
        ("hir_param_owner_fn_node", &d.hir_param_owner_fn_node),
        ("hir_param_ordinal", &d.hir_param_ordinal),
        ("hir_param_name_token", &d.hir_param_name_token),
        ("hir_param_record_node", &d.hir_param_record_node),
        ("hir_param_type_node", &d.hir_param_type_node),
        ("hir_method_owner_node", &d.hir_method_owner_node),
        ("hir_method_impl_node", &d.hir_method_impl_node),
        ("hir_method_name_token", &d.hir_method_name_token),
        ("hir_method_first_param_token", &d.hir_method_first_param_token),
        ("hir_method_receiver_mode", &d.hir_method_receiver_mode),
        ("hir_method_visibility", &d.hir_method_visibility),
        ("hir_method_signature_flags", &d.hir_method_signature_flags),
        ("hir_method_impl_receiver_type_node", &d.hir_method_impl_receiver_type_node),
        ("hir_expr_record_form", &d.hir_expr_record_form),
        ("hir_expr_record_left", &d.hir_expr_record_left),
        ("hir_expr_record_right", &d.hir_expr_record_right),
        ("hir_expr_record_value_token", &d.hir_expr_record_value_token),
        ("hir_match_scrutinee_node", &d.hir_match_scrutinee_node),
        ("hir_match_arm_start", &d.hir_match_arm_start),
        ("hir_match_arm_count", &d.hir_match_arm_count),
        ("hir_match_arm_next", &d.hir_match_arm_next),
        ("hir_match_arm_pattern_node", &d.hir_match_arm_pattern_node),
        ("hir_match_arm_payload_start", &d.hir_match_arm_payload_start),
        ("hir_match_arm_payload_count", &d.hir_match_arm_payload_count),
        ("hir_match_arm_result_node", &d.hir_match_arm_result_node),
        ("hir_match_payload_owner_arm", &d.hir_match_payload_owner_arm),
        ("hir_match_payload_match_node", &d.hir_match_payload_match_node),
        ("hir_match_payload_ordinal", &d.hir_match_payload_ordinal),
        ("hir_call_callee_node", &d.hir_call_callee_node),
        ("hir_call_context_stmt_node", &d.hir_call_context_stmt_node),
        ("hir_call_arg_start", &d.hir_call_arg_start),
        ("hir_call_arg_end", &d.hir_call_arg_end),
        ("hir_call_arg_count", &d.hir_call_arg_count),
        ("hir_call_arg_parent_call", &d.hir_call_arg_parent_call),
        ("hir_call_arg_ordinal", &d.hir_call_arg_ordinal),
        ("hir_array_lit_first_element", &d.hir_array_lit_first_element),
        ("hir_array_lit_element_count", &d.hir_array_lit_element_count),
        ("hir_array_lit_context_stmt_node", &d.hir_array_lit_context_stmt_node),
        ("hir_array_element_parent_lit", &d.hir_array_element_parent_lit),
        ("hir_array_element_ordinal", &d.hir_array_element_ordinal),
        ("hir_array_element_next", &d.hir_array_element_next),
        ("hir_expr_string_start", &d.hir_expr_string_start),
        ("hir_expr_string_len", &d.hir_expr_string_len),
        ("hir_member_receiver_node", &d.hir_member_receiver_node),
        ("hir_member_receiver_token", &d.hir_member_receiver_token),
        ("hir_member_name_token", &d.hir_member_name_token),
        ("hir_stmt_record_kind", &d.hir_stmt_record_kind),
        ("hir_stmt_record_operand0", &d.hir_stmt_record_operand0),
        ("hir_stmt_record_operand1", &d.hir_stmt_record_operand1),
        ("hir_stmt_record_operand2", &d.hir_stmt_record_operand2),
        ("hir_stmt_scope_end", &d.hir_stmt_scope_end),
        ("hir_nearest_stmt_node", &d.hir_nearest_stmt_node),
        ("hir_nearest_block_node", &d.hir_nearest_block_node),
        ("hir_nearest_enclosing_control_node", &d.hir_nearest_enclosing_control_node),
        ("hir_nearest_loop_node", &d.hir_nearest_loop_node),
        ("hir_nearest_fn_node", &d.hir_nearest_fn_node),
        ("hir_struct_field_parent_struct", &d.hir_struct_field_parent_struct),
        ("hir_struct_field_ordinal", &d.hir_struct_field_ordinal),
        ("hir_struct_field_type_node", &d.hir_struct_field_type_node),
        ("hir_struct_decl_field_start", &d.hir_struct_decl_field_start),
        ("hir_struct_decl_field_count", &d.hir_struct_decl_field_count),
        ("hir_struct_lit_head_node", &d.hir_struct_lit_head_node),
        ("hir_struct_lit_context_stmt_node", &d.hir_struct_lit_context_stmt_node),
        ("hir_struct_lit_field_start", &d.hir_struct_lit_field_start),
        ("hir_struct_lit_field_count", &d.hir_struct_lit_field_count),
        ("hir_struct_lit_field_parent_lit", &d.hir_struct_lit_field_parent_lit),
        ("hir_struct_lit_field_value_node", &d.hir_struct_lit_field_value_node),
        ("hir_struct_lit_field_next", &d.hir_struct_lit_field_next),
    ]
}

struct Recorded {
    token_capacity: u32,
    tree_capacity: u32,
    readbacks: ParserHirItemReadbacks,
}

async fn parse_pack(
    lexer: &GpuLexer,
    parser: &GpuParser,
    tables: &PrecomputedParseTables,
    sources: &[String],
) -> Result<DecodedParserHirItemReadbacks> {
    lexer
        .with_recorded_resident_source_pack_tokens_after_count(
            sources,
            |device, _, buffers, token_count, encoder, mut timer| {
                let token_capacity = token_count.max(1);
                let tree_capacity = parser.read_resident_partial_parse_tree_capacity(
                    token_capacity,
                    &buffers.tokens_out,
                    &buffers.token_count,
                    Some(&buffers.token_file_id),
                    tables,
                )?;
                let (check, readbacks) = parser
                    .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                        encoder,
                        token_capacity,
                        &buffers.tokens_out,
                        &buffers.token_count,
                        Some(&buffers.token_file_id),
                        buffers.n,
                        &buffers.in_bytes,
                        tables,
                        Some(tree_capacity),
                        &mut timer,
                        |parse_buffers, encoder, _| {
                            let readbacks = ParserHirItemReadbacks::create(device, parse_buffers);
                            readbacks.encode_copies(encoder, parse_buffers);
                            Ok::<_, anyhow::Error>(readbacks)
                        },
                    )?;
                Ok::<_, anyhow::Error>((
                    check,
                    Recorded {
                        token_capacity,
                        tree_capacity,
                        readbacks: readbacks?,
                    },
                ))
            },
            |device, _, (_, recorded)| {
                let decoded = parser.with_current_resident_buffers_with_tree_capacity(
                    recorded.token_capacity,
                    tables,
                    recorded.tree_capacity,
                    |parse_buffers| recorded.readbacks.map_and_decode(device, parse_buffers),
                )?;
                parser.release_current_resident_buffers();
                Ok::<_, anyhow::Error>(decoded)
            },
        )
        .await?
}

fn write_record(
    out: &mut impl Write,
    label: &str,
    result: Result<DecodedParserHirItemReadbacks>,
) -> Result<()> {
    match result {
        Ok(decoded) => {
            writeln!(out, "{label}\tll1_status\t6\t{:016x}", fnv1a(&decoded.ll1_status))?;
            for (name, words) in fields(&decoded) {
                writeln!(out, "{label}\t{name}\t{}\t{:016x}", words.len(), fnv1a(words))?;
            }
        }
        Err(err) => writeln!(out, "{label}\terror\t{}", format!("{err:#}").replace('\n', " "))?,
    }
    out.flush()?;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let mut out_path = None;
    let mut packs = Vec::new();
    let mut singles = Vec::new();
    for arg in std::env::args().skip(1) {
        if let Some(dir) = arg.strip_prefix("--pack=") {
            packs.push(PathBuf::from(dir));
        } else if out_path.is_none() {
            out_path = Some(PathBuf::from(arg));
        } else {
            collect_lani(Path::new(&arg), &mut singles)?;
        }
    }
    let out_path =
        out_path.context("usage: hir_records_dump OUT.tsv [--pack=DIR]... [PATH]...")?;
    let lexer = GpuLexer::new().await.context("init GpuLexer")?;
    let parser = GpuParser::new().await.context("init GpuParser")?;
    let tables = PrecomputedParseTables::load_bin_bytes(
        &std::fs::read("tables/parse_tables.bin").context("read tables/parse_tables.bin")?,
    )
    .map_err(|err| anyhow::anyhow!("load parser tables: {err}"))?;
    let mut out = std::io::BufWriter::new(
        std::fs::File::create(&out_path)
            .with_context(|| format!("create {}", out_path.display()))?,
    );
    let mut streams = 0usize;
    for dir in &packs {
        let mut files = Vec::new();
        collect_lani(dir, &mut files)?;
        let sources = files
            .iter()
            .map(std::fs::read_to_string)
            .collect::<std::io::Result<Vec<_>>>()?;
        let label = format!("pack:{}", dir.display());
        let result = parse_pack(&lexer, &parser, &tables, &sources).await;
        write_record(&mut out, &label, result)?;
        streams += 1;
    }
    for path in &singles {
        let label = path.display().to_string();
        let source = match std::fs::read_to_string(path) {
            Ok(source) => source,
            Err(err) => {
                eprintln!("[hir_records_dump] skip {label}: {err}");
                continue;
            }
        };
        let result = parse_pack(&lexer, &parser, &tables, &[source]).await;
        write_record(&mut out, &label, result)?;
        streams += 1;
    }
    eprintln!("[hir_records_dump] wrote {streams} streams to {}", out_path.display());
    Ok(())
}
