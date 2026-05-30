mod common;

use laniusc::{
    compiler::CompileError,
    lexer::driver::GpuLexer,
    parser::{
        driver::{GpuParser, ResidentParseResult},
        hir_records::INVALID,
        passes::{
            hir_expr_fields::{
                HIR_EXPR_FORM_ADD,
                HIR_EXPR_FORM_AND,
                HIR_EXPR_FORM_FLOAT,
                HIR_EXPR_FORM_FORWARD,
                HIR_EXPR_FORM_INDEX,
                HIR_EXPR_FORM_INT,
                HIR_EXPR_FORM_LE,
                HIR_EXPR_FORM_NAME,
                HIR_EXPR_FORM_NONE,
                HIR_EXPR_FORM_NOT,
                HIR_EXPR_FORM_STRING,
            },
            hir_item_fields::{
                HIR_ITEM_IMPORT_TARGET_NONE,
                HIR_ITEM_IMPORT_TARGET_PATH,
                HIR_ITEM_IMPORT_TARGET_STRING,
                HIR_ITEM_KIND_CONST,
                HIR_ITEM_KIND_ENUM,
                HIR_ITEM_KIND_ENUM_VARIANT,
                HIR_ITEM_KIND_EXTERN_FN,
                HIR_ITEM_KIND_FN,
                HIR_ITEM_KIND_IMPORT,
                HIR_ITEM_KIND_MODULE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_STRUCT,
                HIR_ITEM_KIND_TRAIT,
                HIR_ITEM_KIND_TYPE_ALIAS,
                HIR_ITEM_NAMESPACE_MODULE,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                HIR_ITEM_VIS_PUBLIC,
            },
            hir_method_fields::{
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_REF_SELF,
                HIR_METHOD_RECEIVER_SELF,
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PUBLIC,
            },
            hir_method_signature_status::{
                HIR_METHOD_SIGNATURE_HAS_GENERICS,
                HIR_METHOD_SIGNATURE_HAS_WHERE,
            },
            hir_nodes::{
                HIR_NODE_ARRAY_EXPR,
                HIR_NODE_BINARY_EXPR,
                HIR_NODE_BLOCK,
                HIR_NODE_BREAK_STMT,
                HIR_NODE_CALL_EXPR,
                HIR_NODE_CONST_ITEM,
                HIR_NODE_CONTINUE_STMT,
                HIR_NODE_ENUM_ITEM,
                HIR_NODE_EXPR,
                HIR_NODE_FN,
                HIR_NODE_FOR_STMT,
                HIR_NODE_IF_STMT,
                HIR_NODE_IMPORT_ITEM,
                HIR_NODE_ITEM,
                HIR_NODE_LET_STMT,
                HIR_NODE_LITERAL_EXPR,
                HIR_NODE_MATCH_EXPR,
                HIR_NODE_MEMBER_EXPR,
                HIR_NODE_MODULE_ITEM,
                HIR_NODE_NAME_EXPR,
                HIR_NODE_NONE,
                HIR_NODE_PARAM,
                HIR_NODE_PATH_EXPR,
                HIR_NODE_RETURN_STMT,
                HIR_NODE_STMT,
                HIR_NODE_STRUCT_ITEM,
                HIR_NODE_STRUCT_LITERAL_EXPR,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE_ALIAS_ITEM,
                HIR_NODE_WHILE_STMT,
            },
            hir_stmt_fields::{
                HIR_ASSIGN_OP_SET as ASSIGN_OP_SET,
                HIR_STMT_RECORD_KIND_ASSIGN as STMT_RECORD_KIND_ASSIGN,
                HIR_STMT_RECORD_KIND_BREAK as STMT_RECORD_KIND_BREAK,
                HIR_STMT_RECORD_KIND_CONST as STMT_RECORD_KIND_CONST,
                HIR_STMT_RECORD_KIND_CONTINUE as STMT_RECORD_KIND_CONTINUE,
                HIR_STMT_RECORD_KIND_FOR as STMT_RECORD_KIND_FOR,
                HIR_STMT_RECORD_KIND_IF as STMT_RECORD_KIND_IF,
                HIR_STMT_RECORD_KIND_LET as STMT_RECORD_KIND_LET,
                HIR_STMT_RECORD_KIND_NONE as STMT_RECORD_KIND_NONE,
                HIR_STMT_RECORD_KIND_RETURN as STMT_RECORD_KIND_RETURN,
                HIR_STMT_RECORD_KIND_WHILE as STMT_RECORD_KIND_WHILE,
            },
            hir_type_fields::{
                HIR_TYPE_FORM_ARRAY,
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_REF,
                HIR_TYPE_FORM_SLICE,
            },
        },
        readback::{
            DecodedParserHirFunctionReturnReadbacks,
            DecodedParserHirItemReadbacks,
            ParserHirFunctionReturnReadbacks,
            ParserHirItemReadbacks,
            validate_hir_array_literal_records,
            validate_hir_call_argument_records,
            validate_hir_context_relation_records,
            validate_hir_expression_records,
            validate_hir_function_return_records,
            validate_hir_item_path_records,
            validate_hir_match_records,
            validate_hir_member_records,
            validate_hir_method_records,
            validate_hir_parameter_records,
            validate_hir_source_address_records,
            validate_hir_statement_records,
            validate_hir_struct_literal_field_records,
            validate_hir_type_argument_records,
        },
        tables::PrecomputedParseTables,
    },
};

const VARIANT_PAYLOAD_SLOT_STRIDE: usize = 4;

struct RecordedParserReadback {
    token_capacity: u32,
    tree_capacity: u32,
    readbacks: ParserHirItemReadbacks,
}

struct RecordedFnReturnReadback {
    token_capacity: u32,
    tree_capacity: u32,
    readbacks: ParserHirFunctionReturnReadbacks,
}

const PARSER_STATUS_CONTEXT_SCAN_LIMIT: u32 = 0x8000_0000;
const TK_AMPERSAND: u32 = 25;
const TK_BOUND_TYPE_AMPERSAND: u32 = 179;

fn parser_token_feature_flags_for_source(source: &str) -> u32 {
    let source = source.to_owned();
    common::block_on_gpu_with_timeout("parser token feature flags", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        lexer
            .with_resident_tokens(&source, |_, _, buffers| {
                parser.debug_token_feature_flags_for_resident_tokens(
                    buffers.n,
                    &buffers.tokens_out,
                    &buffers.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex should succeed")
            .expect("parser token feature flag readback should succeed")
    })
}

fn parser_semantic_token_kinds_for_source(source: &str) -> Vec<u32> {
    let source = source.to_owned();
    common::block_on_gpu_with_timeout("parser semantic token kinds", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        lexer
            .with_resident_tokens(&source, |_, _, buffers| {
                parser.debug_semantic_token_kinds_for_resident_tokens(
                    buffers.n,
                    &buffers.tokens_out,
                    &buffers.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex should succeed")
            .expect("parser semantic token kind readback should succeed")
    })
}

fn parse_resident_source(source: &str) -> ResidentParseResult {
    let source = source.to_owned();
    common::block_on_gpu_with_timeout("resident parser HIR records", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        lexer
            .with_resident_tokens(&source, |_, _, buffers| {
                parser.parse_resident_tokens(
                    buffers.n,
                    &buffers.tokens_out,
                    &buffers.token_count,
                    &tables,
                )
            })
            .await
            .expect("resident lex should succeed")
            .expect("resident parse should succeed")
    })
}

fn parse_resident_source_pack(sources: &[&str]) -> DecodedParserHirItemReadbacks {
    let sources = sources
        .iter()
        .map(|source| (*source).to_owned())
        .collect::<Vec<_>>();
    common::block_on_gpu_with_timeout("resident source-pack parser HIR records", async move {
        let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/parse_tables.bin"
        )))
        .expect("load precomputed parse tables");
        let lexer = GpuLexer::new().await.expect("create GPU lexer");
        let parser = GpuParser::new().await.expect("create GPU parser");

        lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                &sources,
                |device, _, buffers, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let tree_capacity = parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &buffers.tokens_out,
                            &buffers.token_count,
                            Some(&buffers.token_file_id),
                            &tables,
                        )
                        .expect("read projected resident tree capacity");
                    let (check, readbacks) = parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &buffers.tokens_out,
                            &buffers.token_count,
                            Some(&buffers.token_file_id),
                            buffers.n,
                            &buffers.in_bytes,
                            &tables,
                            Some(tree_capacity),
                            &mut timer,
                            |parse_buffers, encoder, _| {
                                let readbacks =
                                    ParserHirItemReadbacks::create(device, parse_buffers);
                                readbacks.encode_copies(encoder, parse_buffers);
                                Ok::<_, anyhow::Error>(readbacks)
                            },
                        )
                        .expect("record resident parser HIR readbacks");
                    let readbacks = readbacks.expect("record parser readback copies");
                    Ok::<_, anyhow::Error>((
                        check,
                        RecordedParserReadback {
                            token_capacity,
                            tree_capacity,
                            readbacks,
                        },
                    ))
                },
                |device, _, (_, recorded)| {
                    let decoded = parser.with_current_resident_buffers_with_tree_capacity(
                        recorded.token_capacity,
                        &tables,
                        recorded.tree_capacity,
                        |parse_buffers| recorded.readbacks.map_and_decode(device, parse_buffers),
                    )?;
                    parser.release_current_resident_buffers();
                    Ok::<_, anyhow::Error>(decoded)
                },
            )
            .await
            .expect("resident source-pack lex should succeed")
            .expect("resident source-pack parse readback should succeed")
    })
}

fn parse_resident_source_pack_fn_returns(
    sources: Vec<String>,
) -> DecodedParserHirFunctionReturnReadbacks {
    common::block_on_gpu_with_timeout(
        "resident source-pack parser HIR function return records",
        async move {
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/tables/parse_tables.bin"
            )))
            .expect("load precomputed parse tables");
            let lexer = GpuLexer::new().await.expect("create GPU lexer");
            let parser = GpuParser::new().await.expect("create GPU parser");

            lexer
                .with_recorded_resident_source_pack_tokens_after_count(
                    &sources,
                    |device, _, buffers, token_count, encoder, mut timer| {
                        let token_capacity = token_count.max(1);
                        let tree_capacity = parser
                            .read_resident_projected_tree_capacity(
                                token_capacity,
                                &buffers.tokens_out,
                                &buffers.token_count,
                                Some(&buffers.token_file_id),
                                &tables,
                            )
                            .expect("read projected resident tree capacity");
                        let (check, readbacks) = parser
                            .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                                encoder,
                                token_capacity,
                                &buffers.tokens_out,
                                &buffers.token_count,
                                Some(&buffers.token_file_id),
                                buffers.n,
                                &buffers.in_bytes,
                                &tables,
                                Some(tree_capacity),
                                &mut timer,
                                |parse_buffers, encoder, _| {
                                    let readbacks = ParserHirFunctionReturnReadbacks::create(
                                        device,
                                        parse_buffers,
                                    );
                                    readbacks.encode_copies(encoder, parse_buffers);
                                    Ok::<_, anyhow::Error>(readbacks)
                                },
                            )
                            .expect("record resident parser HIR function-return readbacks");
                        let readbacks = readbacks.expect("record parser readback copies");
                        Ok::<_, anyhow::Error>((
                            check,
                            RecordedFnReturnReadback {
                                token_capacity,
                                tree_capacity,
                                readbacks,
                            },
                        ))
                    },
                    |device, _, (_, recorded)| {
                        let decoded = parser.with_current_resident_buffers_with_tree_capacity(
                            recorded.token_capacity,
                            &tables,
                            recorded.tree_capacity,
                            |parse_buffers| {
                                recorded.readbacks.map_and_decode(device, parse_buffers)
                            },
                        )?;
                        parser.release_current_resident_buffers();
                        Ok::<_, anyhow::Error>(decoded)
                    },
                )
                .await
                .expect("resident source-pack lex should succeed")
                .expect("resident source-pack function-return readback should succeed")
        },
    )
}

fn assert_source_pack_type_checks(sources: &[&str], context: &str) {
    common::type_check_source_pack_with_timeout(sources).expect(context);
}

fn assert_source_pack_type_rejects(sources: &[&str], context: &str) {
    match common::type_check_source_pack_with_timeout(sources) {
        Ok(()) => panic!("{context}"),
        Err(CompileError::Diagnostic(_)) | Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type-check rejection for {context}, got {other:?}"),
    }
}

#[test]
fn parser_token_context_scan_limit_is_reported_as_status_flag() {
    let short_source = "fn f<T: A::B & C>() {}\n";
    let short_flags = parser_token_feature_flags_for_source(short_source);
    assert_eq!(
        short_flags & PARSER_STATUS_CONTEXT_SCAN_LIMIT,
        0,
        "short bound paths should not report the context-scan limit"
    );
    let short_kinds = parser_semantic_token_kinds_for_source(short_source);
    assert!(
        short_kinds.contains(&TK_BOUND_TYPE_AMPERSAND),
        "in-budget bound paths should retag the bound separator"
    );

    let long_source = "fn f<T: A::B::C::D::E::F::G::H::I::J & K>() {}\n";
    let long_flags = parser_token_feature_flags_for_source(long_source);
    assert_ne!(
        long_flags & PARSER_STATUS_CONTEXT_SCAN_LIMIT,
        0,
        "over-budget bound paths should publish the parser retagging limit status"
    );
    let long_kinds = parser_semantic_token_kinds_for_source(long_source);
    assert!(
        !long_kinds.contains(&TK_BOUND_TYPE_AMPERSAND),
        "over-budget bound paths should fail closed instead of guessing the bound separator"
    );
    assert!(
        long_kinds.contains(&TK_AMPERSAND),
        "over-budget bound separators should remain raw tokens behind the status boundary"
    );
}

#[test]
fn parser_hir_call_argument_records_have_contiguous_owners_and_ordinals() {
    let parsed = parse_resident_source(
        r#"
fn choose(a: i32, b: i32, c: i32, d: i32) -> i32 {
    return a;
}

fn main() {
    return choose(1, 2, 3, 4);
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let call_node = parsed
        .hir_call_arg_count
        .iter()
        .position(|&count| count == 4)
        .expect("fixture should contain one four-argument call");
    assert_eq!(
        parsed.hir_kind[call_node], HIR_NODE_CALL_EXPR,
        "argument count should be attached to the call HIR node"
    );

    let mut args = parsed
        .hir_call_arg_parent_call
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == call_node).then_some(node))
        .collect::<Vec<_>>();
    args.sort_unstable_by_key(|&node| parsed.hir_call_arg_ordinal[node]);

    assert_eq!(args.len(), 4, "call should own exactly four argument rows");
    assert_eq!(
        parsed.hir_call_arg_start[call_node] as usize, args[0],
        "call start should point at the ordinal-zero argument"
    );

    for (expected_ordinal, arg_node) in args.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_kind[arg_node], HIR_NODE_EXPR,
            "argument row {arg_node} should be an expression HIR node"
        );
        assert_eq!(
            parsed.hir_call_arg_ordinal[arg_node], expected_ordinal as u32,
            "argument row {arg_node} should have a contiguous ordinal"
        );
        assert_ne!(
            parsed.hir_call_arg_end[arg_node], INVALID,
            "argument row {arg_node} should record an end token"
        );
        assert!(
            parsed.hir_call_arg_end[arg_node] > parsed.hir_token_pos[arg_node],
            "argument end should be after argument start for row {arg_node}"
        );
        assert_eq!(
            parsed.hir_call_arg_end[arg_node], parsed.hir_token_end[arg_node],
            "argument end should come from the parser-owned HIR span end"
        );
    }

    let valid_arg_rows = parsed
        .hir_call_arg_parent_call
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        valid_arg_rows, 4,
        "fixture should not publish extra call-argument owners"
    );
}

#[test]
fn parser_hir_call_argument_records_preserve_counts_beyond_typecheck_cache_width() {
    let parsed = parse_resident_source(
        r#"
fn choose(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
    return a;
}

fn main() {
    return choose(1, 2, 3, 4, 5);
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let call_node = parsed
        .hir_call_arg_count
        .iter()
        .position(|&count| count == 5)
        .expect("fixture should contain one five-argument call");
    assert_eq!(
        parsed.hir_kind[call_node], HIR_NODE_CALL_EXPR,
        "argument count should be attached to the call HIR node"
    );

    let mut args = parsed
        .hir_call_arg_parent_call
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == call_node).then_some(node))
        .collect::<Vec<_>>();
    args.sort_unstable_by_key(|&node| parsed.hir_call_arg_ordinal[node]);

    assert_eq!(args.len(), 5, "call should own exactly five argument rows");
    for (expected_ordinal, arg_node) in args.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_call_arg_ordinal[arg_node], expected_ordinal as u32,
            "argument row {arg_node} should have a contiguous ordinal"
        );
    }
}

#[test]
fn parser_hir_method_call_records_link_callee_member_and_receiver() {
    let parsed = parse_resident_source(
        r#"
struct Pair {
    left: i32,
}

fn main(pair: Pair) -> i32 {
    return pair.project(1, 2);
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let call_node = parsed
        .hir_call_arg_count
        .iter()
        .position(|&count| count == 2)
        .expect("fixture should contain one two-argument method call");
    assert_eq!(
        parsed.hir_kind[call_node], HIR_NODE_CALL_EXPR,
        "argument count should be attached to the call HIR node"
    );

    let callee_node = parsed.hir_call_callee_node[call_node] as usize;
    assert_ne!(
        callee_node as u32, INVALID,
        "method call should publish its callee HIR node"
    );
    assert_eq!(
        parsed.hir_kind[callee_node], HIR_NODE_MEMBER_EXPR,
        "method call callee should be the parser-owned member HIR node"
    );

    let receiver_node = parsed.hir_member_receiver_node[callee_node] as usize;
    assert_ne!(
        receiver_node as u32, INVALID,
        "member callee should publish its receiver HIR node"
    );
    assert_eq!(
        parsed.hir_kind[receiver_node], HIR_NODE_NAME_EXPR,
        "fixture receiver should be the name-expression HIR node"
    );

    let receiver_token = parsed.hir_member_receiver_token[callee_node];
    let member_token = parsed.hir_member_name_token[callee_node];
    assert_ne!(
        receiver_token, INVALID,
        "member callee should publish a receiver token"
    );
    assert_ne!(
        member_token, INVALID,
        "member callee should publish a member-name token"
    );
    assert_eq!(
        receiver_token, parsed.hir_token_pos[receiver_node],
        "receiver token should come from the receiver HIR node, not a source-text rescan"
    );
    assert!(
        parsed.hir_token_pos[callee_node] < member_token,
        "member-name token should be inside the member expression span"
    );
    assert!(
        member_token < parsed.hir_token_end[callee_node],
        "member-name token should remain before the member expression end"
    );

    let mut args = parsed
        .hir_call_arg_parent_call
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == call_node).then_some(node))
        .collect::<Vec<_>>();
    args.sort_unstable_by_key(|&node| parsed.hir_call_arg_ordinal[node]);

    assert_eq!(
        args.len(),
        2,
        "method call should own exactly two argument rows"
    );
    assert_eq!(
        parsed.hir_call_arg_start[call_node] as usize, args[0],
        "method-call arg start should point at ordinal zero"
    );
    for (expected_ordinal, arg_node) in args.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_call_arg_ordinal[arg_node], expected_ordinal as u32,
            "method-call argument {arg_node} should have a contiguous ordinal"
        );
        assert_eq!(
            parsed.hir_kind[arg_node], HIR_NODE_EXPR,
            "method-call argument {arg_node} should be an expression HIR row"
        );
    }
}

#[test]
fn parser_hir_zero_argument_calls_publish_callee_without_argument_rows() {
    let parsed = parse_resident_source(
        r#"
struct Pair {
    left: i32,
}

fn zero() -> i32 {
    return 0;
}

fn main(pair: Pair) -> i32 {
    return zero() + pair.project();
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let zero_arg_calls = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_CALL_EXPR && parsed.hir_call_arg_count[node] == 0).then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        zero_arg_calls.len(),
        2,
        "fixture should publish exactly the plain and method zero-argument call records"
    );

    let mut saw_plain_call = false;
    let mut saw_method_call = false;
    for call_node in zero_arg_calls {
        assert_eq!(
            parsed.hir_call_arg_start[call_node], INVALID,
            "zero-argument call {call_node} should not publish an argument start"
        );
        assert!(
            parsed
                .hir_call_arg_parent_call
                .iter()
                .all(|&parent| parent as usize != call_node),
            "zero-argument call {call_node} should not own argument rows"
        );

        let callee_node = parsed.hir_call_callee_node[call_node] as usize;
        assert_ne!(
            callee_node as u32, INVALID,
            "zero-argument call {call_node} should still publish its callee HIR node"
        );
        assert_hir_node_has_non_empty_span(&parsed, call_node, "zero-argument call");
        assert_hir_node_has_non_empty_span(&parsed, callee_node, "zero-argument call callee");

        match parsed.hir_kind[callee_node] {
            HIR_NODE_NAME_EXPR | HIR_NODE_PATH_EXPR => saw_plain_call = true,
            HIR_NODE_MEMBER_EXPR => {
                saw_method_call = true;
                let receiver_node = parsed.hir_member_receiver_node[callee_node] as usize;
                assert_ne!(
                    receiver_node as u32, INVALID,
                    "zero-argument method call should retain its receiver node"
                );
                assert_eq!(
                    parsed.hir_kind[receiver_node], HIR_NODE_NAME_EXPR,
                    "fixture method receiver should be the name-expression HIR node"
                );
            }
            other => panic!("unexpected zero-argument callee HIR kind {other}"),
        }
    }

    assert!(saw_plain_call, "fixture should publish a plain call callee");
    assert!(
        saw_method_call,
        "fixture should publish a method call callee"
    );
}

#[test]
fn parser_hir_chained_member_records_link_previous_member_as_receiver() {
    let parsed = parse_resident_source(
        r#"
struct Pair {
    left: i32,
}

fn main(pair: Pair) -> i32 {
    return pair.left.right;
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let mut member_nodes = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_NODE_MEMBER_EXPR).then_some(node))
        .collect::<Vec<_>>();
    member_nodes.sort_unstable_by_key(|&node| parsed.hir_member_name_token[node]);
    assert_eq!(
        member_nodes.len(),
        2,
        "fixture should publish exactly the two chained member expression records"
    );

    let first_member = member_nodes[0];
    let second_member = member_nodes[1];
    assert_eq!(
        parsed.hir_member_receiver_node[second_member] as usize, first_member,
        "second member receiver should point at the parser-owned first member row"
    );
    assert_eq!(
        parsed.hir_kind[parsed.hir_member_receiver_node[first_member] as usize], HIR_NODE_NAME_EXPR,
        "first member receiver should be the base name expression"
    );

    for member in [first_member, second_member] {
        let receiver = assert_valid_hir_node_index(
            &parsed,
            parsed.hir_member_receiver_node[member],
            "member receiver",
        );
        let receiver_token = parsed.hir_member_receiver_token[member];
        let member_token = parsed.hir_member_name_token[member];
        assert_ne!(
            receiver_token, INVALID,
            "member row {member} should publish a receiver token"
        );
        assert_ne!(
            member_token, INVALID,
            "member row {member} should publish a member-name token"
        );
        assert!(
            receiver_token < member_token,
            "member row {member} receiver token should precede the member-name token"
        );
        assert!(
            member_token >= parsed.hir_token_pos[member]
                && member_token < parsed.hir_token_end[member],
            "member row {member} name token should stay inside its member expression span"
        );
        assert_hir_node_has_non_empty_span(&parsed, receiver, "member receiver");
    }
}

#[test]
fn parser_hir_member_readback_rejects_orphan_member_metadata() {
    let err = validate_hir_member_records(
        &[HIR_NODE_NAME_EXPR, HIR_NODE_NAME_EXPR],
        &[0, 1],
        &[1, 2],
        &[0, 0],
        &[INVALID, 0],
        &[INVALID, 0],
        &[INVALID, 1],
    )
    .expect_err("member metadata on a non-member row should fail closed");
    assert!(
        err.to_string().contains("without a member-expression"),
        "error should describe orphan parser-owned member metadata"
    );
}

#[test]
fn parser_hir_enum_variant_records_link_variants_and_payload_types() {
    let parsed = parse_resident_source(
        r#"
enum Resultish {
    Ok(i32, bool),
    Empty,
}

fn main(value: Resultish) -> i32 {
    return 0;
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let enum_node = parsed
        .hir_kind
        .iter()
        .position(|&kind| kind == HIR_NODE_ENUM_ITEM)
        .expect("fixture should contain one enum declaration");

    let mut variants = parsed
        .hir_variant_parent_enum
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == enum_node).then_some(node))
        .collect::<Vec<_>>();
    variants.sort_unstable_by_key(|&node| parsed.hir_variant_ordinal[node]);

    assert_eq!(
        variants.len(),
        2,
        "enum declaration should own exactly two variant rows"
    );

    for (expected_ordinal, variant_node) in variants.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_kind[variant_node], HIR_NODE_ITEM,
            "variant row {variant_node} should remain an item HIR node"
        );
        assert_eq!(
            parsed.hir_item_kind[variant_node], HIR_ITEM_KIND_ENUM_VARIANT,
            "variant row {variant_node} should publish enum-variant item kind"
        );
        assert_eq!(
            parsed.hir_variant_ordinal[variant_node], expected_ordinal as u32,
            "variant row {variant_node} should have a contiguous ordinal"
        );
    }

    let ok_variant = variants[0];
    let empty_variant = variants[1];
    assert_eq!(
        parsed.hir_variant_payload_count[ok_variant], 2,
        "tuple variant should publish two payload type rows"
    );
    assert_eq!(
        parsed.hir_variant_payload_count[empty_variant], 0,
        "unit variant should not publish payload type rows"
    );
    let payload_start = parsed.hir_variant_payload_start[ok_variant] as usize;
    assert_ne!(
        payload_start as u32, INVALID,
        "tuple variant should record its first payload type row"
    );
    let payload_slot = ok_variant * VARIANT_PAYLOAD_SLOT_STRIDE;
    let payload_nodes = [
        parsed.hir_variant_payload_node[payload_slot] as usize,
        parsed.hir_variant_payload_node[payload_slot + 1] as usize,
    ];
    assert_eq!(
        payload_start, payload_nodes[0],
        "tuple variant payload start should point at the ordinal-zero payload type"
    );
    assert_ne!(
        payload_nodes[0], payload_nodes[1],
        "distinct payload ordinals should point at distinct type rows"
    );
    for (expected_ordinal, payload_node) in payload_nodes.into_iter().enumerate() {
        assert_eq!(
            parsed.hir_kind[payload_node], HIR_NODE_TYPE,
            "payload row {payload_node} for ordinal {expected_ordinal} should be a type HIR node"
        );
    }
    let empty_payload_slot = empty_variant * VARIANT_PAYLOAD_SLOT_STRIDE;
    assert_eq!(
        parsed.hir_variant_payload_start[empty_variant], INVALID,
        "unit variant should not retain a payload start"
    );
    assert!(
        parsed.hir_variant_payload_node
            [empty_payload_slot..empty_payload_slot + VARIANT_PAYLOAD_SLOT_STRIDE]
            .iter()
            .all(|&node| node == INVALID),
        "unit variant should not publish payload slots"
    );

    let valid_variant_rows = parsed
        .hir_variant_parent_enum
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        valid_variant_rows, 2,
        "fixture should not publish extra enum variant owners"
    );
}

#[test]
fn parser_hir_array_literal_records_link_elements_and_spans() {
    let parsed = parse_resident_source(
        r#"
fn main(values: [i32; 4]) -> i32 {
    let local: [i32; 4] = [3, values[0], 4, 1];
    return local[1];
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let literal_node = parsed
        .hir_array_lit_element_count
        .iter()
        .position(|&count| count == 4)
        .expect("fixture should contain one four-element array literal");
    assert_eq!(
        parsed.hir_kind[literal_node], HIR_NODE_ARRAY_EXPR,
        "element count should be attached to the array literal HIR node"
    );

    let mut elements = parsed
        .hir_array_element_parent_lit
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == literal_node).then_some(node))
        .collect::<Vec<_>>();
    elements.sort_unstable_by_key(|&node| parsed.hir_array_element_ordinal[node]);

    assert_eq!(
        elements.len(),
        4,
        "array literal should own exactly four element rows"
    );
    assert_eq!(
        parsed.hir_array_lit_first_element[literal_node] as usize, elements[0],
        "array literal first-element record should point at ordinal zero"
    );

    for pair in elements.windows(2) {
        assert_eq!(
            parsed.hir_array_element_next[pair[0]] as usize, pair[1],
            "array element next-link should follow source order"
        );
    }
    assert_eq!(
        parsed.hir_array_element_next[*elements.last().unwrap()],
        INVALID,
        "last array element should close the element chain"
    );

    for (expected_ordinal, element_node) in elements.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_array_element_parent_lit[element_node] as usize, literal_node,
            "array element {element_node} should point back to the owning literal"
        );
        assert_eq!(
            parsed.hir_array_element_ordinal[element_node], expected_ordinal as u32,
            "array element {element_node} should have a contiguous ordinal"
        );
        assert_eq!(
            parsed.hir_kind[element_node], HIR_NODE_EXPR,
            "array element {element_node} should be published as an expression HIR row"
        );
        assert_ne!(
            parsed.hir_token_pos[element_node], INVALID,
            "array element {element_node} should record a token start"
        );
        assert_ne!(
            parsed.hir_token_end[element_node], INVALID,
            "array element {element_node} should record a token end"
        );
        assert!(
            parsed.hir_token_end[element_node] > parsed.hir_token_pos[element_node],
            "array element {element_node} span should cover at least one token"
        );
    }

    let valid_element_rows = parsed
        .hir_array_element_parent_lit
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        valid_element_rows, 4,
        "fixture should not publish extra array element owners"
    );
}

#[test]
fn parser_hir_child_records_keep_source_spans_inside_recorded_owners() {
    let parsed = parse_resident_source(
        r#"
enum MaybePair {
    Pair(i32, bool),
    Empty,
}

fn main(value: MaybePair, values: [i32; 3]) -> i32 {
    let local: [i32; 3] = [1, values[0], 2];
    return match (value) {
        Pair(left, flag) -> local[1],
        Empty -> local[0],
    };
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let enum_node = parsed
        .hir_kind
        .iter()
        .position(|&kind| kind == HIR_NODE_ENUM_ITEM)
        .expect("fixture should contain one enum declaration");
    assert_hir_node_has_non_empty_span(&parsed, enum_node, "enum item");

    let variant_node = parsed
        .hir_variant_parent_enum
        .iter()
        .enumerate()
        .find_map(|(node, &parent)| {
            (parent as usize == enum_node && parsed.hir_variant_payload_count[node] == 2)
                .then_some(node)
        })
        .expect("fixture should contain one tuple enum variant");
    assert_hir_child_span_inside_owner(&parsed, enum_node, variant_node, "tuple variant");
    assert_eq!(
        parsed.hir_variant_payload_start[variant_node],
        parsed.hir_variant_payload_node[variant_node * VARIANT_PAYLOAD_SLOT_STRIDE],
        "variant payload start should point at the first payload node"
    );
    for slot in 0..parsed.hir_variant_payload_count[variant_node] as usize {
        let payload_node = assert_valid_hir_node_index(
            &parsed,
            parsed.hir_variant_payload_node[variant_node * VARIANT_PAYLOAD_SLOT_STRIDE + slot],
            "enum variant payload",
        );
        assert_eq!(
            parsed.hir_kind[payload_node], HIR_NODE_TYPE,
            "enum variant payload {payload_node} should be a type HIR row"
        );
        assert_hir_child_span_inside_owner(
            &parsed,
            variant_node,
            payload_node,
            "enum variant payload",
        );
    }

    let array_literal_node = parsed
        .hir_array_lit_element_count
        .iter()
        .position(|&count| count == 3)
        .expect("fixture should contain one three-element array literal");
    assert_eq!(
        parsed.hir_kind[array_literal_node], HIR_NODE_ARRAY_EXPR,
        "array element count should be attached to the literal HIR node"
    );
    assert_hir_node_has_non_empty_span(&parsed, array_literal_node, "array literal");
    let array_elements = parsed
        .hir_array_element_parent_lit
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == array_literal_node).then_some(node))
        .collect::<Vec<_>>();
    assert_eq!(
        array_elements.len(),
        3,
        "array literal should own exactly three element records"
    );
    for element_node in array_elements {
        assert_eq!(
            parsed.hir_kind[element_node], HIR_NODE_EXPR,
            "array element {element_node} should be an expression HIR row"
        );
        assert_hir_child_span_inside_owner(
            &parsed,
            array_literal_node,
            element_node,
            "array element",
        );
    }

    let match_node = parsed
        .hir_match_arm_count
        .iter()
        .position(|&count| count == 2)
        .expect("fixture should contain one two-arm match expression");
    assert_eq!(
        parsed.hir_kind[match_node], HIR_NODE_MATCH_EXPR,
        "match arm count should be attached to the match HIR node"
    );
    assert_hir_node_has_non_empty_span(&parsed, match_node, "match expression");
    let first_arm = assert_valid_hir_node_index(
        &parsed,
        parsed.hir_match_arm_start[match_node],
        "first match arm",
    );
    assert_hir_child_span_inside_owner(&parsed, match_node, first_arm, "match arm");
    assert_eq!(
        parsed.hir_match_arm_payload_count[first_arm], 2,
        "tuple-pattern match arm should publish two payload records"
    );
    let mut match_payloads = parsed
        .hir_match_payload_owner_arm
        .iter()
        .enumerate()
        .filter_map(|(node, &owner)| (owner as usize == first_arm).then_some(node))
        .collect::<Vec<_>>();
    match_payloads.sort_unstable_by_key(|&node| parsed.hir_match_payload_ordinal[node]);
    assert_eq!(
        match_payloads.len(),
        2,
        "tuple-pattern match arm should own exactly two payload records"
    );
    assert_eq!(
        parsed.hir_match_arm_payload_start[first_arm] as usize, match_payloads[0],
        "match arm payload start should point at ordinal zero"
    );
    for payload_node in match_payloads {
        assert_eq!(
            parsed.hir_match_payload_match_node[payload_node] as usize, match_node,
            "match payload {payload_node} should point back to the owning match expression"
        );
        assert_hir_child_span_inside_owner(&parsed, first_arm, payload_node, "match payload");
    }
}

#[test]
fn parser_hir_resident_readback_publishes_expression_roots_and_statement_contexts() {
    let parsed = parse_resident_source(
        r#"
struct Pair {
    left: i32,
    right: i32,
}

fn helper(value: i32) -> i32 {
    return value;
}

fn main(value: i32) -> i32 {
    let local: [i32; 2] = [helper(value), Pair { left: value, right: value + 1 }.left];
    return helper(local[0]);
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let let_node = parsed
        .hir_kind
        .iter()
        .position(|&kind| kind == HIR_NODE_LET_STMT)
        .expect("fixture should publish one local declaration statement");
    let return_node = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_RETURN_STMT
                && parsed.hir_token_pos[node] > parsed.hir_token_end[let_node])
                .then_some(node)
        })
        .min_by_key(|&node| parsed.hir_token_pos[node])
        .expect("fixture should publish the main return statement after the local declaration");
    assert_hir_node_has_non_empty_span(&parsed, let_node, "local declaration statement");
    assert_hir_node_has_non_empty_span(&parsed, return_node, "main return statement");
    let main_block = assert_valid_hir_node_index(
        &parsed,
        parsed.hir_nearest_block_node[let_node],
        "local declaration nearest block",
    );
    assert_eq!(
        parsed.hir_kind[main_block], HIR_NODE_BLOCK,
        "nearest block row should point at the function body block"
    );
    assert_eq!(
        parsed.hir_nearest_block_node[return_node] as usize, main_block,
        "statements in the same function body should agree on nearest block"
    );
    assert_eq!(
        parsed.hir_nearest_enclosing_control_node[let_node], INVALID,
        "top-level local declaration should not have an enclosing control row"
    );

    let array_literal = parsed
        .hir_array_lit_element_count
        .iter()
        .enumerate()
        .find_map(|(node, &count)| {
            (count == 2 && parsed.hir_kind[node] == HIR_NODE_ARRAY_EXPR).then_some(node)
        })
        .expect("fixture should publish one two-element array literal");
    let struct_literal = parsed
        .hir_kind
        .iter()
        .position(|&kind| kind == HIR_NODE_STRUCT_LITERAL_EXPR)
        .expect("fixture should publish one struct literal expression");

    for (node, context, label) in [
        (
            array_literal,
            parsed.hir_array_lit_context_stmt_node[array_literal],
            "array literal",
        ),
        (
            struct_literal,
            parsed.hir_struct_lit_context_stmt_node[struct_literal],
            "struct literal",
        ),
    ] {
        assert_eq!(
            context as usize, let_node,
            "{label} should publish the local declaration as its contextual statement"
        );
        assert_eq!(
            parsed.hir_nearest_stmt_node[node] as usize, let_node,
            "{label} should publish the local declaration as its nearest statement"
        );
        assert_eq!(
            parsed.hir_nearest_block_node[node] as usize, main_block,
            "{label} should publish the function body as its nearest block"
        );
        assert_eq!(
            parsed.hir_nearest_enclosing_control_node[node], INVALID,
            "{label} should not publish an enclosing control outside control flow"
        );
        assert_eq!(
            parsed.hir_expr_result_root_node[node] as usize, node,
            "{label} should publish itself as a direct expression result root"
        );
        assert_hir_child_span_inside_owner(&parsed, let_node, node, label);
    }

    let call_nodes = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_NODE_CALL_EXPR).then_some(node))
        .collect::<Vec<_>>();
    assert_eq!(
        call_nodes.len(),
        2,
        "fixture should publish the local-initializer and return call expressions"
    );

    let mut saw_let_call = false;
    let mut saw_return_call = false;
    for call_node in call_nodes {
        let context = assert_valid_hir_node_index(
            &parsed,
            parsed.hir_call_context_stmt_node[call_node],
            "call contextual statement",
        );
        assert_eq!(
            parsed.hir_nearest_stmt_node[call_node] as usize, context,
            "call row {call_node} should agree between nearest-statement and call-context records"
        );
        assert_eq!(
            parsed.hir_expr_result_root_node[call_node] as usize, call_node,
            "call row {call_node} should publish itself as a direct expression result root"
        );
        assert_eq!(
            parsed.hir_nearest_block_node[call_node] as usize, main_block,
            "call row {call_node} should publish the function body as its nearest block"
        );

        match parsed.hir_kind[context] {
            HIR_NODE_LET_STMT => {
                saw_let_call = true;
                assert_eq!(
                    context, let_node,
                    "initializer call should point at the parser-owned let statement"
                );
                assert_hir_child_span_inside_owner(
                    &parsed,
                    let_node,
                    call_node,
                    "initializer call",
                );
            }
            HIR_NODE_RETURN_STMT => {
                saw_return_call = true;
                assert_eq!(
                    context, return_node,
                    "return call should point at the parser-owned return statement"
                );
                assert_hir_child_span_inside_owner(&parsed, return_node, call_node, "return call");
            }
            other => panic!("unexpected call contextual statement kind {other}"),
        }
    }
    assert!(
        saw_let_call,
        "fixture should exercise a let-context call row"
    );
    assert!(
        saw_return_call,
        "fixture should exercise a return-context call row"
    );

    let array_forwarding_wrappers = parsed
        .hir_expr_result_root_node
        .iter()
        .enumerate()
        .filter(|&(node, &root)| root as usize == array_literal && node != array_literal)
        .count();
    assert!(
        array_forwarding_wrappers > 0,
        "array literal should be reachable through parser-published expression root rows"
    );
}

#[test]
fn parser_hir_resident_readback_publishes_enclosing_control_contexts() {
    let parsed = parse_resident_source(
        r#"
fn main(value: i32) -> i32 {
    if value > 0 {
        let nested: i32 = value;
        return nested;
    }
    return 0;
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let if_node = parsed
        .hir_kind
        .iter()
        .position(|&kind| kind == HIR_NODE_IF_STMT)
        .expect("fixture should publish one if statement");
    let nested_let = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_LET_STMT
                && parsed.hir_token_pos[if_node] < parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[if_node])
                .then_some(node)
        })
        .next()
        .expect("fixture should publish a let statement inside the if branch");
    let nested_return = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_RETURN_STMT
                && parsed.hir_token_pos[if_node] < parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[if_node])
                .then_some(node)
        })
        .next()
        .expect("fixture should publish a return statement inside the if branch");

    let branch_block = assert_valid_hir_node_index(
        &parsed,
        parsed.hir_nearest_block_node[nested_let],
        "branch let nearest block",
    );
    assert_eq!(
        parsed.hir_kind[branch_block], HIR_NODE_BLOCK,
        "branch statement should publish its branch block"
    );
    assert_hir_child_span_inside_owner(&parsed, if_node, branch_block, "branch block");
    for (node, label) in [(nested_let, "branch let"), (nested_return, "branch return")] {
        assert_eq!(
            parsed.hir_nearest_block_node[node] as usize, branch_block,
            "{label} should publish the if branch block"
        );
        assert_eq!(
            parsed.hir_nearest_enclosing_control_node[node] as usize, if_node,
            "{label} should publish the if statement as its nearest enclosing control"
        );
    }
}

#[test]
fn parser_hir_resident_readback_publishes_nearest_function_contexts() {
    let parsed = parse_resident_source(
        r#"
fn helper(seed: i32) -> i32 {
    let folded: i32 = seed + 1;
    return folded;
}

fn main(value: i32) -> i32 {
    let outer: i32 = helper(value);
    if outer > 0 {
        let inner: i32 = helper(outer);
        return inner + outer;
    }
    return helper(0);
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let mut fn_nodes = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_FN && parsed.hir_item_kind[node] == HIR_ITEM_KIND_FN).then_some(node)
        })
        .collect::<Vec<_>>();
    fn_nodes.sort_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        fn_nodes.len(),
        2,
        "fixture should publish exactly two parser-owned function HIR rows"
    );
    let helper_fn = fn_nodes[0];
    let main_fn = fn_nodes[1];

    for fn_node in [helper_fn, main_fn] {
        assert_eq!(
            parsed.hir_nearest_fn_node[fn_node] as usize, fn_node,
            "function row {fn_node} should publish itself as its nearest function"
        );
    }

    let helper_let = node_inside_span(&parsed, HIR_NODE_LET_STMT, helper_fn)
        .expect("helper should publish a local declaration");
    let helper_return = node_inside_span(&parsed, HIR_NODE_RETURN_STMT, helper_fn)
        .expect("helper should publish a return statement");
    for (node, label) in [
        (helper_let, "helper let statement"),
        (helper_return, "helper return statement"),
    ] {
        assert_nearest_fn(&parsed, node, helper_fn, label);
    }

    let main_if = node_inside_span(&parsed, HIR_NODE_IF_STMT, main_fn)
        .expect("main should publish an if statement");
    let nested_let = node_inside_span(&parsed, HIR_NODE_LET_STMT, main_if)
        .expect("if branch should publish a nested local declaration");
    let nested_call = node_inside_span(&parsed, HIR_NODE_CALL_EXPR, nested_let)
        .expect("nested local declaration should publish a call expression");
    let nested_return = node_inside_span(&parsed, HIR_NODE_RETURN_STMT, main_if)
        .expect("if branch should publish a nested return statement");
    let nested_binary = node_inside_span(&parsed, HIR_NODE_BINARY_EXPR, nested_return)
        .expect("nested return should publish a binary expression");
    let trailing_return_call = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_CALL_EXPR
                && parsed.hir_token_pos[main_if] < parsed.hir_token_pos[node]
                && parsed.hir_token_end[main_if] < parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[main_fn])
                .then_some(node)
        })
        .next()
        .expect("main should publish a trailing return call after the if branch");

    for (node, label) in [
        (main_if, "main if statement"),
        (nested_let, "nested let statement"),
        (nested_call, "nested call expression"),
        (nested_return, "nested return statement"),
        (nested_binary, "nested binary expression"),
        (trailing_return_call, "trailing return call expression"),
    ] {
        assert_nearest_fn(&parsed, node, main_fn, label);
    }
}

fn node_inside_span(parsed: &ResidentParseResult, kind: u32, owner_node: usize) -> Option<usize> {
    parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &node_kind)| {
            (node_kind == kind
                && parsed.hir_token_pos[owner_node] < parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[owner_node])
                .then_some(node)
        })
        .min_by_key(|&node| parsed.hir_token_pos[node])
}

fn assert_nearest_fn(parsed: &ResidentParseResult, node: usize, expected_fn: usize, label: &str) {
    assert_eq!(
        parsed.hir_nearest_fn_node[node] as usize, expected_fn,
        "{label} should publish the parser-owned enclosing function"
    );
    assert_hir_child_span_inside_owner(parsed, expected_fn, node, label);
}

fn assert_valid_hir_node_index(parsed: &ResidentParseResult, node: u32, label: &str) -> usize {
    assert_ne!(node, INVALID, "{label} should publish a HIR node");
    let node = node as usize;
    assert!(
        node < parsed.hir_kind.len(),
        "{label} node {node} should be inside the HIR record table"
    );
    node
}

fn assert_hir_node_has_non_empty_span(parsed: &ResidentParseResult, node: usize, label: &str) {
    assert_ne!(
        parsed.hir_token_pos[node], INVALID,
        "{label} node {node} should record a source token start"
    );
    assert_ne!(
        parsed.hir_token_end[node], INVALID,
        "{label} node {node} should record a source token end"
    );
    assert!(
        parsed.hir_token_pos[node] < parsed.hir_token_end[node],
        "{label} node {node} should have a non-empty source span"
    );
}

fn assert_hir_child_span_inside_owner(
    parsed: &ResidentParseResult,
    owner: usize,
    child: usize,
    label: &str,
) {
    assert_hir_node_has_non_empty_span(parsed, owner, "owner");
    assert_hir_node_has_non_empty_span(parsed, child, label);
    assert!(
        parsed.hir_token_pos[owner] <= parsed.hir_token_pos[child],
        "{label} node {child} should start inside owner node {owner}"
    );
    assert!(
        parsed.hir_token_end[child] <= parsed.hir_token_end[owner],
        "{label} node {child} should end inside owner node {owner}"
    );
}

#[test]
fn parser_hir_generic_type_arguments_link_owner_and_argument_chain() {
    let parsed = parse_resident_source(
        r#"
struct Pair<T, U> {
    left: T,
    right: U,
}

fn take(value: Pair<i32, bool>) -> i32 {
    return 0;
}
"#,
    );
    assert!(
        parsed.ll1.accepted,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1.error_pos, parsed.ll1.error_code, parsed.ll1.detail
    );

    let owner = parsed
        .hir_type_arg_count
        .iter()
        .enumerate()
        .find_map(|(node, &count)| (count == 2).then_some(node))
        .expect("fixture should publish one two-argument generic type instance");
    assert_eq!(
        parsed.hir_kind[owner], HIR_NODE_TYPE,
        "generic instance owner should be a type HIR node"
    );
    assert_eq!(
        parsed.hir_type_form[owner], HIR_TYPE_FORM_PATH,
        "generic instance owner should be a path type"
    );

    let first_arg = parsed.hir_type_arg_start[owner] as usize;
    assert_ne!(
        first_arg as u32, INVALID,
        "generic instance should record its first type argument"
    );
    let second_arg = parsed.hir_type_arg_next[first_arg] as usize;
    assert_ne!(
        second_arg as u32, INVALID,
        "first type argument should link to the second"
    );
    assert_eq!(
        parsed.hir_type_arg_next[second_arg], INVALID,
        "last type argument should close the argument chain"
    );

    for arg in [first_arg, second_arg] {
        assert_eq!(
            parsed.hir_kind[arg], HIR_NODE_TYPE,
            "type argument row {arg} should be a type HIR node"
        );
        assert_ne!(
            parsed.hir_token_pos[arg], INVALID,
            "type argument row {arg} should record a token start"
        );
        assert_ne!(
            parsed.hir_token_end[arg], INVALID,
            "type argument row {arg} should record a token end"
        );
        assert!(
            parsed.hir_token_pos[owner] < parsed.hir_token_pos[arg],
            "type argument row {arg} should be inside the owning generic path span"
        );
        assert!(
            parsed.hir_token_end[arg] <= parsed.hir_token_end[owner],
            "type argument row {arg} should end inside the owning generic path span"
        );
    }

    let valid_argument_rows = parsed
        .hir_type_arg_next
        .iter()
        .enumerate()
        .filter(|&(node, _)| node != owner)
        .filter(|&(_, &next)| next != INVALID)
        .count();
    assert_eq!(
        valid_argument_rows, 1,
        "fixture should publish exactly one generic type-argument link"
    );
}

#[test]
fn parser_hir_generic_type_arguments_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::math;
pub fn one() -> i32 {
    return 1;
}
"#,
        r#"
module app::main;
import core::math;

fn take(value: core::math::Pair<i32, bool>) -> i32 {
    return 0;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let generic_owners = parsed
        .hir_type_arg_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 2
                && parsed.hir_kind[node] == HIR_NODE_TYPE
                && parsed.hir_type_form[node] == HIR_TYPE_FORM_PATH)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        generic_owners.len(),
        1,
        "fixture should publish exactly one two-argument generic type owner"
    );

    let owner = generic_owners[0];
    assert_source_pack_hir_node_has_non_empty_span(&parsed, owner, "generic type owner");
    assert_eq!(
        parsed.hir_type_file_id[owner], 1,
        "generic type owner should retain the lexer-provided source-pack file id"
    );
    assert!(
        (parsed.hir_type_file_id[owner] as usize) < source_count,
        "generic type owner should retain a bounded source-pack file id"
    );

    let containing_functions = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == parsed.hir_type_file_id[owner]
                && parsed.hir_token_pos[node] <= parsed.hir_token_pos[owner]
                && parsed.hir_token_end[owner] <= parsed.hir_token_end[node])
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        containing_functions.len(),
        1,
        "generic type owner should stay inside one function item span in its source file"
    );

    let first_arg = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_type_arg_start[owner],
        "first generic type argument",
    );
    let second_arg = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_type_arg_next[first_arg],
        "second generic type argument",
    );
    assert_eq!(
        parsed.hir_type_arg_next[second_arg], INVALID,
        "last generic type argument should close the source-order chain"
    );
    assert!(
        parsed.hir_token_pos[first_arg] < parsed.hir_token_pos[second_arg],
        "generic type-argument chain should be deterministic in source order"
    );

    for (expected_ordinal, arg) in [first_arg, second_arg].into_iter().enumerate() {
        assert_eq!(
            parsed.hir_kind[arg], HIR_NODE_TYPE,
            "generic type argument row {arg} should be a type HIR node"
        );
        assert_eq!(
            parsed.hir_type_form[arg], HIR_TYPE_FORM_PATH,
            "generic type argument row {arg} should be a path type"
        );
        assert_eq!(
            parsed.hir_type_file_id[arg], parsed.hir_type_file_id[owner],
            "generic type argument row {arg} should inherit the owning source-pack file id"
        );
        assert!(
            (parsed.hir_type_file_id[arg] as usize) < source_count,
            "generic type argument row {arg} should retain a bounded source-pack file id"
        );
        assert_eq!(
            parsed.hir_type_arg_count[arg], 0,
            "fixture type argument row {arg} should not own nested type arguments"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            owner,
            arg,
            "generic type argument",
        );

        let expected_next = if expected_ordinal == 0 {
            second_arg as u32
        } else {
            INVALID
        };
        assert_eq!(
            parsed.hir_type_arg_next[arg], expected_next,
            "generic type argument row {arg} should publish its source-order successor"
        );
    }

    let non_empty_generic_owners = parsed
        .hir_type_arg_count
        .iter()
        .filter(|&&count| count != 0)
        .count();
    assert_eq!(
        non_empty_generic_owners, 1,
        "fixture should not publish extra generic type-argument owners"
    );
}

#[test]
fn parser_hir_qualified_type_paths_publish_leaf_records_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::pair;

pub struct Pair<T, U> {
    left: T,
    right: U,
}
"#,
        r#"
module app::main;
import core::pair;

fn mirror(value: core::pair::Pair<i32, bool>) -> core::pair::Pair<i32, bool> {
    return value;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let qualified_generic_type_owners = parsed
        .hir_type_arg_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 2
                && parsed.hir_kind[node] == HIR_NODE_TYPE
                && parsed.hir_type_form[node] == HIR_TYPE_FORM_PATH
                && parsed.hir_type_file_id[node] == 1)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        qualified_generic_type_owners.len(),
        2,
        "fixture should publish one qualified generic parameter type and one qualified generic return type"
    );

    let mut leaf_spans = Vec::new();
    for owner in qualified_generic_type_owners {
        assert_source_pack_hir_node_has_non_empty_span(
            &parsed,
            owner,
            "qualified generic type owner",
        );
        assert!(
            (parsed.hir_type_file_id[owner] as usize) < source_count,
            "qualified generic type owner should retain a bounded source-pack file id"
        );

        let leaf = assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_type_path_leaf_node[owner],
            "qualified generic type leaf",
        );
        assert_eq!(
            parsed.hir_node_file_id[leaf], parsed.hir_type_file_id[owner],
            "qualified type leaf should inherit the owner source-pack file id"
        );
        assert_source_pack_record_span_inside_owner(&parsed, owner, leaf, "qualified type leaf");

        let first_arg = assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_type_arg_start[owner],
            "first qualified generic type argument",
        );
        let second_arg = assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_type_arg_next[first_arg],
            "second qualified generic type argument",
        );
        assert_eq!(
            parsed.hir_type_arg_next[second_arg], INVALID,
            "last qualified generic type argument should close the source-order chain"
        );
        assert!(
            parsed.hir_token_end[leaf] <= parsed.hir_token_pos[first_arg],
            "qualified path leaf should precede the generic argument list in the owner span"
        );

        for arg in [first_arg, second_arg] {
            assert_eq!(
                parsed.hir_kind[arg], HIR_NODE_TYPE,
                "qualified generic argument row {arg} should be a type HIR node"
            );
            assert_eq!(
                parsed.hir_type_file_id[arg], parsed.hir_type_file_id[owner],
                "qualified generic argument row {arg} should inherit the owner source-pack file id"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                owner,
                arg,
                "qualified generic type argument",
            );
        }

        leaf_spans.push((parsed.hir_token_pos[leaf], parsed.hir_token_end[leaf]));
    }

    leaf_spans.sort_unstable();
    leaf_spans.dedup();
    assert_eq!(
        leaf_spans.len(),
        2,
        "parameter and return qualified paths should publish distinct leaf records"
    );
}

#[test]
fn parser_hir_import_records_carry_source_pack_file_ids_and_token_spans() {
    let parsed = parse_resident_source_pack(&[
        "module core::math;\npub fn one() -> i32 { return 1; }\n",
        "module app::main;\nimport core::math;\nfn main() -> i32 { return one(); }\n",
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let import_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_ITEM_KIND_IMPORT).then_some(node))
        .collect::<Vec<_>>();
    assert_eq!(
        import_nodes.len(),
        1,
        "fixture should contain one import item row"
    );
    let import_node = import_nodes[0];

    assert_eq!(
        parsed.hir_kind[import_node], HIR_NODE_IMPORT_ITEM,
        "import item metadata should attach to the import HIR node"
    );
    assert_eq!(
        parsed.hir_item_namespace[import_node], HIR_ITEM_NAMESPACE_MODULE,
        "path imports should publish the module namespace"
    );
    assert_eq!(
        parsed.hir_item_visibility[import_node], HIR_ITEM_VIS_PRIVATE,
        "imports are private parser items until visibility semantics say otherwise"
    );
    assert_eq!(
        parsed.hir_item_import_target_kind[import_node], HIR_ITEM_IMPORT_TARGET_PATH,
        "import should publish a path target rather than requiring source text inspection"
    );
    assert_eq!(
        parsed.hir_item_file_id[import_node], 1,
        "import row should retain the lexer-provided source-pack file id"
    );

    let item_start = parsed.hir_token_pos[import_node];
    let item_end = parsed.hir_token_end[import_node];
    let path_start = parsed.hir_item_path_start[import_node];
    let path_end = parsed.hir_item_path_end[import_node];
    assert_ne!(
        item_start, INVALID,
        "import item should record a token start"
    );
    assert_ne!(item_end, INVALID, "import item should record a token end");
    assert_ne!(
        path_start, INVALID,
        "import path should record a token start"
    );
    assert_ne!(path_end, INVALID, "import path should record a token end");
    assert!(
        item_start < path_start,
        "import path span should begin after the import keyword"
    );
    assert!(
        path_start < path_end,
        "import path should cover at least one token"
    );
    assert!(
        path_end <= item_end,
        "import path span should remain inside the import item span"
    );
}

#[test]
fn parser_hir_module_and_import_records_publish_parser_path_nodes() {
    let parsed = parse_resident_source_pack(&[
        "module core::math;\npub fn one() -> i32 { return 1; }\n",
        "module app::main;\nimport core::math;\nfn main() -> i32 { return one(); }\n",
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut module_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_ITEM_KIND_MODULE).then_some(node))
        .collect::<Vec<_>>();
    module_nodes
        .sort_unstable_by_key(|&node| (parsed.hir_item_file_id[node], parsed.hir_token_pos[node]));
    assert_eq!(
        module_nodes.len(),
        2,
        "fixture should publish one module item row per source-pack file"
    );

    for (expected_file_id, module_node) in module_nodes.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_kind[module_node], HIR_NODE_MODULE_ITEM,
            "module item metadata should attach to the parser-owned module item row"
        );
        assert_eq!(
            parsed.hir_item_file_id[module_node], expected_file_id as u32,
            "module row should retain the source-pack file id"
        );
        assert_eq!(
            parsed.hir_item_import_target_kind[module_node], HIR_ITEM_IMPORT_TARGET_NONE,
            "module rows should not publish import target kinds"
        );

        let path_node = assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_item_path_node[module_node],
            "module path node",
        );
        assert_eq!(
            parsed.hir_node_file_id[path_node], parsed.hir_item_file_id[module_node],
            "module path node should inherit the module source-pack file id"
        );
        assert_eq!(
            parsed.hir_token_pos[path_node], parsed.hir_item_path_start[module_node],
            "module path start should be anchored by the parser-owned path node"
        );
        assert_eq!(
            parsed.hir_token_end[path_node], parsed.hir_item_path_end[module_node],
            "module path end should be anchored by the parser-owned path node"
        );
        assert_source_pack_record_span_inside_owner(
            &parsed,
            module_node,
            path_node,
            "module path node",
        );
        assert!(
            parsed.hir_token_pos[module_node] < parsed.hir_token_pos[path_node],
            "module path node should begin after the module keyword"
        );
    }

    let import_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| (kind == HIR_ITEM_KIND_IMPORT).then_some(node))
        .expect("fixture should publish one import item row");
    assert_eq!(
        parsed.hir_item_file_id[import_node], 1,
        "import row should retain the importing source-pack file id"
    );
    assert_eq!(
        parsed.hir_item_import_target_kind[import_node], HIR_ITEM_IMPORT_TARGET_PATH,
        "path imports should publish a parser path target"
    );

    let import_path_node = assert_valid_source_pack_record_index(
        &parsed,
        parsed.hir_item_path_node[import_node],
        "import path node",
    );
    assert_eq!(
        parsed.hir_node_file_id[import_path_node], parsed.hir_item_file_id[import_node],
        "import path node should inherit the importing source-pack file id"
    );
    assert_eq!(
        parsed.hir_token_pos[import_path_node], parsed.hir_item_path_start[import_node],
        "import path start should be anchored by the parser-owned path node"
    );
    assert_eq!(
        parsed.hir_token_end[import_path_node], parsed.hir_item_path_end[import_node],
        "import path end should be anchored by the parser-owned path node"
    );
    assert_source_pack_record_span_inside_owner(
        &parsed,
        import_node,
        import_path_node,
        "import path node",
    );

    let declaration_path_nodes = parsed
        .hir_item_path_node
        .iter()
        .enumerate()
        .filter(|&(node, &path_node)| {
            path_node != INVALID
                && parsed.hir_item_kind[node] != HIR_ITEM_KIND_MODULE
                && parsed.hir_item_kind[node] != HIR_ITEM_KIND_IMPORT
        })
        .count();
    assert_eq!(
        declaration_path_nodes, 0,
        "declaration item rows should not publish resolver path-node edges"
    );
}

#[test]
fn parser_hir_type_alias_target_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let alias_source = r#"
module core::math;
pub type Count = i32;
"#;
    let positive_app_source = r#"
module app::main;
import core::math;

fn main(value: Count) -> i32 {
    return value;
}
"#;
    let positive_sources = [alias_source, positive_app_source];
    let parsed = parse_resident_source_pack(&positive_sources);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let alias_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_TYPE_ALIAS
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PUBLIC)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        alias_nodes.len(),
        1,
        "fixture should publish exactly one public type-alias item in the first source"
    );
    let alias_node = alias_nodes[0];

    assert_eq!(
        parsed.hir_kind[alias_node], HIR_NODE_TYPE_ALIAS_ITEM,
        "type-alias item metadata should attach to the parser-owned type-alias HIR node"
    );
    assert_eq!(
        parsed.hir_item_namespace[alias_node], HIR_ITEM_NAMESPACE_TYPE,
        "type aliases should publish type-namespace item records"
    );
    assert_eq!(
        parsed.hir_item_import_target_kind[alias_node], HIR_ITEM_IMPORT_TARGET_NONE,
        "type aliases should not look like import targets"
    );
    assert_eq!(
        parsed.hir_node_file_id[alias_node], parsed.hir_item_file_id[alias_node],
        "type-alias HIR row should retain the same source-pack file id as its item record"
    );
    assert!(
        (parsed.hir_item_file_id[alias_node] as usize) < source_count,
        "type-alias item should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, alias_node, "type-alias item");

    let name_token = parsed.hir_item_name_token[alias_node];
    assert_ne!(
        name_token, INVALID,
        "type-alias item should publish its name token"
    );
    assert!(
        parsed.hir_token_pos[alias_node] <= name_token
            && name_token < parsed.hir_token_end[alias_node],
        "type-alias name token should stay inside the item span"
    );

    let target_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_type_alias_target_node[alias_node],
        "type-alias target",
    );
    assert_eq!(
        parsed.hir_kind[target_node], HIR_NODE_TYPE,
        "type-alias target should be a parser-owned type HIR row"
    );
    assert_eq!(
        parsed.hir_type_form[target_node], HIR_TYPE_FORM_PATH,
        "type-alias target should publish a path-type record"
    );
    assert_eq!(
        parsed.hir_node_file_id[target_node], parsed.hir_node_file_id[alias_node],
        "type-alias target should inherit the alias source-pack file id"
    );
    assert_eq!(
        parsed.hir_type_file_id[target_node], parsed.hir_node_file_id[alias_node],
        "type-alias target type record should retain the alias source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        alias_node,
        target_node,
        "type-alias target",
    );
    assert!(
        name_token < parsed.hir_token_pos[target_node],
        "type-alias target should follow the alias name in source order"
    );
    assert_eq!(
        parsed.hir_type_arg_count[target_node], 0,
        "fixture target type should not publish generic type arguments"
    );

    let owned_alias_targets = parsed
        .hir_type_alias_target_node
        .iter()
        .enumerate()
        .filter(|&(node, &target)| {
            target != INVALID && parsed.hir_item_kind[node] == HIR_ITEM_KIND_TYPE_ALIAS
        })
        .count();
    assert_eq!(
        owned_alias_targets, 1,
        "fixture should not publish extra type-alias target records"
    );

    common::type_check_source_pack_with_timeout(&positive_sources)
        .expect("type checking should consume the parser-owned type-alias target record");

    let negative_app_source = r#"
module app::main;
import core::math;

fn main() -> i32 {
    let value: Count = false;
    return value;
}
"#;
    match common::type_check_source_pack_with_timeout(&[alias_source, negative_app_source]) {
        Ok(()) => panic!(
            "type checking should reject a bool value assigned through the i32 alias target record"
        ),
        Err(CompileError::Diagnostic(_)) | Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type-check rejection, got {other:?}"),
    }
}

#[test]
fn parser_hir_const_item_records_are_source_addressable_and_feed_type_checking() {
    let source_count = 3;
    let decoy_source = r#"
module lib::decoy;

pub const LIMIT: bool = true;
"#;
    let const_source = r#"
module core::limits;

pub const LIMIT: i32 = 7;
"#;
    let app_source = r#"
module app::main;
import core::limits;

fn main() -> i32 {
    let value: i32 = LIMIT;
    return value;
}
"#;
    let positive_sources = [decoy_source, const_source, app_source];
    let parsed = parse_resident_source_pack(&positive_sources);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let const_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_CONST
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PUBLIC)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        const_nodes.len(),
        1,
        "fixture should publish exactly one public const item in the imported source"
    );
    let const_node = const_nodes[0];

    assert_eq!(
        parsed.hir_kind[const_node], HIR_NODE_CONST_ITEM,
        "const item metadata should attach to the parser-owned const HIR node"
    );
    assert_eq!(
        parsed.hir_item_namespace[const_node], HIR_ITEM_NAMESPACE_VALUE,
        "const items should publish value-namespace records"
    );
    assert_eq!(
        parsed.hir_item_import_target_kind[const_node], HIR_ITEM_IMPORT_TARGET_NONE,
        "const items should not look like import targets"
    );
    assert_eq!(
        parsed.hir_node_file_id[const_node], parsed.hir_item_file_id[const_node],
        "const HIR row should retain the same source-pack file id as its item record"
    );
    assert!(
        (parsed.hir_item_file_id[const_node] as usize) < source_count,
        "const item should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, const_node, "const item");

    let decl_token = parsed.hir_item_decl_token[const_node];
    let name_token = parsed.hir_item_name_token[const_node];
    assert_ne!(
        decl_token, INVALID,
        "const item should publish its declaration token"
    );
    assert_ne!(
        name_token, INVALID,
        "const item should publish its name token"
    );
    assert_eq!(
        decl_token, parsed.hir_token_pos[const_node],
        "const declaration token should anchor the parser-owned const span"
    );
    assert!(
        decl_token < name_token && name_token < parsed.hir_token_end[const_node],
        "const name token should stay inside the const item span"
    );

    assert_eq!(
        parsed.hir_stmt_record_kind[const_node], STMT_RECORD_KIND_CONST,
        "const item should also publish a statement-style declaration record"
    );
    assert_eq!(
        parsed.hir_stmt_record_operand0[const_node], name_token,
        "const record should reuse the item name token as its declaration identity"
    );

    let value_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand1[const_node],
        "const value expression",
    );
    assert_eq!(
        parsed.hir_kind[value_expr], HIR_NODE_EXPR,
        "const record value edge should point at a parser-owned expression row"
    );
    assert_eq!(
        parsed.hir_node_file_id[value_expr], parsed.hir_node_file_id[const_node],
        "const value expression should inherit the const source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        const_node,
        value_expr,
        "const value expression",
    );

    let value_leaf = resolve_forward_expr_record(&parsed, value_expr, "const value expression");
    assert_eq!(
        parsed.hir_expr_record_form[value_leaf], HIR_EXPR_FORM_INT,
        "const value expression should resolve through parser records to the integer literal"
    );
    assert_expr_record_value_token_inside(&parsed, value_leaf, "const integer value");

    let type_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand2[const_node],
        "const declared type",
    );
    assert_eq!(
        parsed.hir_kind[type_node], HIR_NODE_TYPE,
        "const record type edge should point at a parser-owned type row"
    );
    assert_eq!(
        parsed.hir_type_form[type_node], HIR_TYPE_FORM_PATH,
        "const declared type should publish a path-type record"
    );
    assert_eq!(
        parsed.hir_node_file_id[type_node], parsed.hir_node_file_id[const_node],
        "const declared type should inherit the const source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        const_node,
        type_node,
        "const declared type",
    );
    assert!(
        name_token < parsed.hir_token_pos[type_node],
        "const declared type should follow the const name in source order"
    );
    assert!(
        parsed.hir_token_end[type_node] <= parsed.hir_token_pos[value_expr],
        "const declared type should precede the const value expression"
    );

    let imported_const_records = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter(|&(node, &kind)| {
            kind == STMT_RECORD_KIND_CONST
                && parsed.hir_item_kind[node] == HIR_ITEM_KIND_CONST
                && parsed.hir_item_file_id[node] == 1
        })
        .count();
    assert_eq!(
        imported_const_records, 1,
        "fixture should publish exactly one const record for the imported source"
    );

    common::type_check_source_pack_with_timeout(&positive_sources).expect(
        "type checking should consume the parser-owned imported const record, not the same-spelled bool decoy",
    );

    let negative_app_source = r#"
module app::main;
import core::limits;

fn main() -> i32 {
    let value: bool = LIMIT;
    return 0;
}
"#;
    match common::type_check_source_pack_with_timeout(&[
        decoy_source,
        const_source,
        negative_app_source,
    ]) {
        Ok(()) => panic!(
            "same-spelled bool const in an unimported source must not make the imported i32 const type-check"
        ),
        Err(CompileError::Diagnostic(_)) | Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type-check rejection, got {other:?}"),
    }
}

#[test]
fn parser_hir_extern_item_records_own_signature_return_type() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module std::io;
pub extern "lanius_std" fn flush_stdout() -> i32;
"#,
        r#"
module app::main;
import std::io;

fn main() -> i32 {
    return 0;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let extern_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_ITEM_KIND_EXTERN_FN).then_some(node))
        .collect::<Vec<_>>();
    assert_eq!(
        extern_nodes.len(),
        1,
        "fixture should publish exactly one extern function item row"
    );
    let extern_node = extern_nodes[0];

    assert_eq!(
        parsed.hir_kind[extern_node], HIR_NODE_FN,
        "extern item metadata should attach to the parser-owned function HIR node"
    );
    assert_eq!(
        parsed.hir_item_namespace[extern_node], HIR_ITEM_NAMESPACE_VALUE,
        "extern functions should publish value-namespace item records"
    );
    assert_eq!(
        parsed.hir_item_visibility[extern_node], HIR_ITEM_VIS_PUBLIC,
        "pub extern functions should retain public parser visibility"
    );
    assert_eq!(
        parsed.hir_item_import_target_kind[extern_node], HIR_ITEM_IMPORT_TARGET_NONE,
        "extern function rows should not look like import targets"
    );
    assert_eq!(
        parsed.hir_item_file_id[extern_node], 0,
        "extern function row should retain the source-pack file id"
    );
    assert!(
        (parsed.hir_item_file_id[extern_node] as usize) < source_count,
        "extern function row should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, extern_node, "extern function item");

    let name_token = parsed.hir_item_name_token[extern_node];
    assert_ne!(
        name_token, INVALID,
        "extern function row should publish its name token"
    );

    let return_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_fn_return_type_node[extern_node],
        "extern function return type",
    );
    assert_eq!(
        parsed.hir_kind[return_type], HIR_NODE_TYPE,
        "extern return type should be a parser-owned type HIR row"
    );
    assert_eq!(
        parsed.hir_type_form[return_type], HIR_TYPE_FORM_PATH,
        "extern return type should publish a path-type record"
    );
    assert_eq!(
        parsed.hir_type_file_id[return_type], parsed.hir_item_file_id[extern_node],
        "extern return type should retain the same source-pack file id as its owner"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        extern_node,
        return_type,
        "extern function return type",
    );
    assert!(
        parsed.hir_token_pos[extern_node] < name_token,
        "extern item identifier token should begin after the extern item start"
    );
    assert!(
        name_token < parsed.hir_token_pos[return_type],
        "extern item identifier token should precede the owned return type span"
    );
    assert_eq!(
        parsed.hir_type_arg_count[return_type], 0,
        "fixture return type should not publish generic type arguments"
    );
}

#[test]
fn parser_hir_item_decl_tokens_are_source_addressable_in_source_packs() {
    let parsed = parse_resident_source_pack(&[
        r#"
module core::defs;

pub type Count = i32;

pub struct Pair {
    left: Count,
}

pub enum Maybe {
    Some(Count),
    None,
}

pub extern "lanius_std" fn flush_stdout() -> i32;

pub fn one() -> Count {
    return 1;
}
"#,
        r#"
module app::main;
import core::defs;

fn main() -> i32 {
    return one();
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut saw_type_alias = false;
    let mut saw_struct = false;
    let mut saw_enum = false;
    let mut saw_variant = false;
    let mut saw_extern = false;
    let mut saw_function = false;
    let mut path_item_count = 0usize;
    let mut declaration_count = 0usize;

    for (node, &kind) in parsed.hir_item_kind.iter().enumerate() {
        match kind {
            HIR_ITEM_KIND_FN
            | HIR_ITEM_KIND_EXTERN_FN
            | HIR_ITEM_KIND_STRUCT
            | HIR_ITEM_KIND_ENUM
            | HIR_ITEM_KIND_TYPE_ALIAS
            | HIR_ITEM_KIND_ENUM_VARIANT => {
                declaration_count += 1;
                let decl_token = parsed.hir_item_decl_token[node];
                assert_ne!(
                    decl_token, INVALID,
                    "declaration item row {node} should publish a declaration token"
                );
                assert_eq!(
                    decl_token, parsed.hir_token_pos[node],
                    "declaration token for row {node} should anchor the parser-owned item span"
                );
                assert!(
                    decl_token < parsed.hir_token_end[node],
                    "declaration token for row {node} should stay inside the item span"
                );

                let name_token = parsed.hir_item_name_token[node];
                assert_ne!(
                    name_token, INVALID,
                    "declaration item row {node} should publish a name token"
                );
                assert!(
                    decl_token <= name_token && name_token < parsed.hir_token_end[node],
                    "name token for row {node} should stay inside the declaration span"
                );
                assert_eq!(
                    parsed.hir_item_import_target_kind[node], HIR_ITEM_IMPORT_TARGET_NONE,
                    "declaration item row {node} should not look like an import target"
                );
                assert_eq!(
                    parsed.hir_item_path_start[node], INVALID,
                    "declaration item row {node} should not publish a module/import path"
                );
                assert_eq!(
                    parsed.hir_item_path_end[node], INVALID,
                    "declaration item row {node} should not publish a module/import path end"
                );

                match kind {
                    HIR_ITEM_KIND_FN => saw_function = true,
                    HIR_ITEM_KIND_EXTERN_FN => saw_extern = true,
                    HIR_ITEM_KIND_STRUCT => saw_struct = true,
                    HIR_ITEM_KIND_ENUM => saw_enum = true,
                    HIR_ITEM_KIND_TYPE_ALIAS => saw_type_alias = true,
                    HIR_ITEM_KIND_ENUM_VARIANT => saw_variant = true,
                    _ => {}
                }
            }
            HIR_ITEM_KIND_MODULE | HIR_ITEM_KIND_IMPORT => {
                path_item_count += 1;
                assert_eq!(
                    parsed.hir_item_decl_token[node], INVALID,
                    "module/import item row {node} should not publish a declaration token"
                );
                assert_ne!(
                    parsed.hir_item_path_start[node], INVALID,
                    "module/import item row {node} should publish a path start"
                );
                assert_ne!(
                    parsed.hir_item_path_end[node], INVALID,
                    "module/import item row {node} should publish a path end"
                );
            }
            HIR_ITEM_KIND_NONE => {}
            other => panic!("fixture published unexpected item kind {other} at row {node}"),
        }
    }

    assert!(
        declaration_count >= 7,
        "fixture should publish declaration-token records for functions, externs, types, and enum variants"
    );
    assert!(
        path_item_count >= 3,
        "fixture should publish module/import path records without declaration tokens"
    );
    assert!(
        saw_type_alias,
        "fixture should publish a type-alias declaration"
    );
    assert!(saw_struct, "fixture should publish a struct declaration");
    assert!(saw_enum, "fixture should publish an enum declaration");
    assert!(
        saw_variant,
        "fixture should publish enum-variant declarations"
    );
    assert!(saw_extern, "fixture should publish an extern declaration");
    assert!(saw_function, "fixture should publish function declarations");
}

#[test]
fn parser_hir_trait_item_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::cmp;

pub trait Eq<T> {
    pub fn eq(left: T, right: T) -> bool;
}
"#,
        r#"
module app::main;
import core::cmp;

trait Local<T> {
    fn check(value: T) -> bool;
}

fn main() -> i32 {
    return 0;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut trait_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_ITEM_KIND_TRAIT).then_some(node))
        .collect::<Vec<_>>();
    trait_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        trait_nodes.len(),
        2,
        "fixture should publish one public imported trait and one private local trait"
    );

    let public_trait = trait_nodes[0];
    let private_trait = trait_nodes[1];
    assert_eq!(
        parsed.hir_item_file_id[public_trait], 0,
        "public trait should retain the source-pack file id for its declaration"
    );
    assert_eq!(
        parsed.hir_item_file_id[private_trait], 1,
        "private trait should retain the source-pack file id for its declaration"
    );
    assert_eq!(
        parsed.hir_item_visibility[public_trait], HIR_ITEM_VIS_PUBLIC,
        "pub trait declarations should publish public visibility"
    );
    assert_eq!(
        parsed.hir_item_visibility[private_trait], HIR_ITEM_VIS_PRIVATE,
        "non-pub trait declarations should publish private visibility"
    );

    for trait_node in [public_trait, private_trait] {
        assert_eq!(
            parsed.hir_kind[trait_node], HIR_NODE_ITEM,
            "trait item metadata should attach only to a parser-owned item HIR row"
        );
        assert_eq!(
            parsed.hir_item_namespace[trait_node], HIR_ITEM_NAMESPACE_TYPE,
            "trait declarations should publish type-namespace item records"
        );
        assert_eq!(
            parsed.hir_item_import_target_kind[trait_node], HIR_ITEM_IMPORT_TARGET_NONE,
            "trait declarations should not look like import targets"
        );
        assert_eq!(
            parsed.hir_item_path_start[trait_node], INVALID,
            "trait declarations should not publish module/import path spans"
        );
        assert_eq!(
            parsed.hir_item_path_end[trait_node], INVALID,
            "trait declarations should not publish module/import path ends"
        );
        assert_eq!(
            parsed.hir_node_file_id[trait_node], parsed.hir_item_file_id[trait_node],
            "trait HIR row should retain the same source-pack file id as its item record"
        );
        assert!(
            (parsed.hir_item_file_id[trait_node] as usize) < source_count,
            "trait item should retain a bounded source-pack file id"
        );
        assert_source_pack_hir_node_has_non_empty_span(&parsed, trait_node, "trait item");

        let decl_token = parsed.hir_item_decl_token[trait_node];
        let name_token = parsed.hir_item_name_token[trait_node];
        assert_ne!(
            decl_token, INVALID,
            "trait item should publish its declaration token"
        );
        assert_eq!(
            decl_token, parsed.hir_token_pos[trait_node],
            "trait declaration token should anchor the parser-owned item span"
        );
        assert_ne!(
            name_token, INVALID,
            "trait item should publish its name token"
        );
        assert!(
            decl_token < name_token && name_token < parsed.hir_token_end[trait_node],
            "trait name token should stay inside the parser-owned trait item span"
        );
    }
}

#[test]
fn parser_hir_trait_and_impl_method_declaration_records_are_source_addressable_in_source_packs() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

trait Probe {
    pub fn public_trait(&self, value: i32) -> bool;
    fn private_trait(self: Probe, value: i32) -> i32;
}

struct Probe {
    value: i32,
}

impl Probe {
    pub fn public_impl(&self, value: i32) -> bool {
        return true;
    }

    fn private_impl(self: Probe, value: i32) -> i32 {
        return value;
    }
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut method_nodes = parsed
        .hir_method_name_token
        .iter()
        .enumerate()
        .filter_map(|(node, &name_token)| (name_token != INVALID).then_some(node))
        .collect::<Vec<_>>();
    method_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        method_nodes.len(),
        4,
        "fixture should publish two trait-method and two impl-method declaration records"
    );

    let trait_owner = parsed.hir_method_owner_node[method_nodes[0]];
    assert_ne!(
        trait_owner, INVALID,
        "trait method rows should publish their owning trait row"
    );
    let trait_owner =
        assert_valid_source_pack_hir_node_index(&parsed, trait_owner, "trait method owner");
    assert_eq!(
        parsed.hir_item_kind[trait_owner], HIR_ITEM_KIND_TRAIT,
        "trait method owner should be the parser-owned trait item record"
    );
    assert_eq!(
        parsed.hir_kind[trait_owner], HIR_NODE_ITEM,
        "trait method owner should be an item HIR row"
    );

    assert_eq!(
        parsed.hir_method_impl_node[method_nodes[0]], INVALID,
        "trait method rows should not masquerade as impl-backed methods"
    );

    let impl_owner = parsed.hir_method_owner_node[method_nodes[2]];
    assert_ne!(
        impl_owner, INVALID,
        "impl method rows should publish their owning impl row"
    );
    let impl_owner =
        assert_valid_source_pack_hir_node_index(&parsed, impl_owner, "impl method owner");
    assert_ne!(
        trait_owner, impl_owner,
        "trait and impl method declarations should keep distinct owner rows"
    );
    assert_eq!(
        parsed.hir_method_impl_node[method_nodes[2]] as usize, impl_owner,
        "impl method rows should also publish their impl-specific owner relation"
    );
    let impl_receiver_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_impl_receiver_type_node[impl_owner],
        "impl receiver type",
    );
    assert_eq!(
        parsed.hir_kind[impl_receiver_type], HIR_NODE_TYPE,
        "impl method owner should retain a parser-owned receiver type record"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        impl_owner,
        impl_receiver_type,
        "impl receiver type",
    );

    let expected = [
        (
            trait_owner,
            HIR_METHOD_VIS_PUBLIC,
            HIR_METHOD_RECEIVER_REF_SELF,
            false,
        ),
        (
            trait_owner,
            HIR_METHOD_VIS_PRIVATE,
            HIR_METHOD_RECEIVER_SELF,
            false,
        ),
        (
            impl_owner,
            HIR_METHOD_VIS_PUBLIC,
            HIR_METHOD_RECEIVER_REF_SELF,
            true,
        ),
        (
            impl_owner,
            HIR_METHOD_VIS_PRIVATE,
            HIR_METHOD_RECEIVER_SELF,
            true,
        ),
    ];
    for (method_node, (owner, visibility, receiver_mode, is_impl_method)) in
        method_nodes.iter().copied().zip(expected)
    {
        assert_eq!(
            parsed.hir_kind[method_node], HIR_NODE_FN,
            "method record should attach to a parser-owned function HIR row"
        );
        if is_impl_method {
            assert_eq!(
                parsed.hir_item_kind[method_node], HIR_ITEM_KIND_FN,
                "impl method record should attach to a function item record"
            );
            assert_eq!(
                parsed.hir_method_impl_node[method_node] as usize, owner,
                "impl method row should retain its impl-specific owner"
            );
            assert_eq!(
                parsed.hir_method_name_token[method_node], parsed.hir_item_name_token[method_node],
                "impl method name token should reuse the parser-owned function item name token"
            );
        } else {
            assert_eq!(
                parsed.hir_item_kind[method_node], HIR_ITEM_KIND_NONE,
                "trait method records should not enter the value item namespace"
            );
            assert_eq!(
                parsed.hir_method_impl_node[method_node], INVALID,
                "trait method row should not publish an impl-specific owner"
            );
        }
        assert_eq!(
            parsed.hir_method_owner_node[method_node] as usize, owner,
            "method row should retain its parser-owned declaration owner"
        );
        assert_eq!(
            parsed.hir_node_file_id[method_node], parsed.hir_node_file_id[owner],
            "method row should retain the same source-pack file id as its owner"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            owner,
            method_node,
            "method declaration",
        );
        assert_ne!(
            parsed.hir_method_name_token[method_node], INVALID,
            "method row should publish its source name token"
        );
        assert!(
            parsed.hir_token_pos[method_node] < parsed.hir_method_name_token[method_node]
                && parsed.hir_method_name_token[method_node] < parsed.hir_token_end[method_node],
            "method name token should stay inside the method function span"
        );
        assert_eq!(
            parsed.hir_method_visibility[method_node], visibility,
            "method visibility should be published as method metadata"
        );
        assert_eq!(
            parsed.hir_method_receiver_mode[method_node], receiver_mode,
            "method receiver mode should be published from the ordinal-zero parameter record"
        );

        let mut params = parsed
            .hir_param_owner_fn_node
            .iter()
            .enumerate()
            .filter_map(|(node, &param_owner)| {
                (param_owner as usize == method_node && parsed.hir_kind[node] == HIR_NODE_PARAM)
                    .then_some(node)
            })
            .collect::<Vec<_>>();
        params.sort_unstable_by_key(|&node| parsed.hir_param_ordinal[node]);
        assert_eq!(
            params.len(),
            2,
            "each method declaration should own receiver and value parameter records"
        );
        assert_eq!(
            parsed.hir_method_first_param_token[method_node],
            parsed.hir_param_name_token[params[0]],
            "method first-param token should point at the ordinal-zero parameter record"
        );
        for (ordinal, param_node) in params.iter().copied().enumerate() {
            assert_eq!(
                parsed.hir_param_ordinal[param_node], ordinal as u32,
                "method parameter rows should publish contiguous source-order ordinals"
            );
            assert_eq!(
                parsed.hir_node_file_id[param_node], parsed.hir_node_file_id[method_node],
                "method parameter row should retain the method source-pack file id"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                method_node,
                param_node,
                "method parameter",
            );
        }
    }
}

#[test]
fn parser_hir_trait_impl_method_declaration_records_are_source_addressable_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

trait Describe {
    pub fn by_ref(&self, value: i32) -> bool;
    fn by_value(self: Subject, value: i32) -> i32;
}

struct Subject {
    value: i32,
}

impl Describe for Subject {
    pub fn by_ref(&self, value: i32) -> bool {
        return true;
    }

    fn by_value(self: Subject, value: i32) -> i32 {
        return value;
    }
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut method_nodes = parsed
        .hir_method_name_token
        .iter()
        .enumerate()
        .filter_map(|(node, &name_token)| (name_token != INVALID).then_some(node))
        .collect::<Vec<_>>();
    method_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        method_nodes.len(),
        4,
        "fixture should publish two trait contract rows and two trait-impl method rows"
    );

    let trait_owner = parsed.hir_method_owner_node[method_nodes[0]];
    let trait_owner =
        assert_valid_source_pack_hir_node_index(&parsed, trait_owner, "trait method owner");
    assert_eq!(
        parsed.hir_kind[trait_owner], HIR_NODE_ITEM,
        "trait method owner should be a parser-owned item row"
    );
    assert_eq!(
        parsed.hir_item_kind[trait_owner], HIR_ITEM_KIND_TRAIT,
        "trait method owner should be the declared trait"
    );

    let trait_impl_owner = parsed.hir_method_owner_node[method_nodes[2]];
    let trait_impl_owner = assert_valid_source_pack_hir_node_index(
        &parsed,
        trait_impl_owner,
        "trait impl method owner",
    );
    assert_ne!(
        trait_impl_owner, trait_owner,
        "trait declarations and trait impl declarations should keep distinct owner rows"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, trait_impl_owner, "trait impl owner");
    assert_eq!(
        parsed.hir_node_file_id[trait_impl_owner], 0,
        "trait impl owner should retain the source-pack file id"
    );

    let impl_receiver_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_impl_receiver_type_node[trait_impl_owner],
        "trait impl receiver type",
    );
    assert_eq!(
        parsed.hir_kind[impl_receiver_type], HIR_NODE_TYPE,
        "trait impl owner should retain a parser-owned target receiver type row"
    );
    assert_eq!(
        parsed.hir_type_form[impl_receiver_type], HIR_TYPE_FORM_PATH,
        "trait impl receiver type should be published as a path-type row"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        trait_impl_owner,
        impl_receiver_type,
        "trait impl receiver type",
    );

    let expected = [
        (
            trait_owner,
            HIR_METHOD_VIS_PUBLIC,
            HIR_METHOD_RECEIVER_REF_SELF,
            false,
        ),
        (
            trait_owner,
            HIR_METHOD_VIS_PRIVATE,
            HIR_METHOD_RECEIVER_SELF,
            false,
        ),
        (
            trait_impl_owner,
            HIR_METHOD_VIS_PUBLIC,
            HIR_METHOD_RECEIVER_REF_SELF,
            true,
        ),
        (
            trait_impl_owner,
            HIR_METHOD_VIS_PRIVATE,
            HIR_METHOD_RECEIVER_SELF,
            true,
        ),
    ];
    for (method_node, (owner, visibility, receiver_mode, is_trait_impl_method)) in
        method_nodes.iter().copied().zip(expected)
    {
        assert!(
            (parsed.hir_node_file_id[method_node] as usize) < source_count,
            "method row {method_node} should retain a bounded source-pack file id"
        );
        assert_eq!(
            parsed.hir_node_file_id[method_node], parsed.hir_node_file_id[owner],
            "method row should retain the same source-pack file id as its owner"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            owner,
            method_node,
            "method declaration",
        );
        assert_eq!(
            parsed.hir_method_owner_node[method_node] as usize, owner,
            "method row should retain its parser-owned declaration owner"
        );
        assert_ne!(
            parsed.hir_method_name_token[method_node], INVALID,
            "method row should publish its source name token"
        );
        assert!(
            parsed.hir_token_pos[method_node] < parsed.hir_method_name_token[method_node]
                && parsed.hir_method_name_token[method_node] < parsed.hir_token_end[method_node],
            "method name token should stay inside the method declaration span"
        );
        assert_eq!(
            parsed.hir_method_visibility[method_node], visibility,
            "method visibility should be published from method declaration syntax"
        );
        assert_eq!(
            parsed.hir_method_receiver_mode[method_node], receiver_mode,
            "method receiver mode should be published from the ordinal-zero parameter row"
        );

        if is_trait_impl_method {
            assert_eq!(
                parsed.hir_kind[method_node], HIR_NODE_FN,
                "trait impl method record should attach to a parser-owned function row"
            );
            assert_eq!(
                parsed.hir_item_kind[method_node], HIR_ITEM_KIND_FN,
                "trait impl method record should publish a function item row"
            );
            assert_eq!(
                parsed.hir_method_impl_node[method_node] as usize, owner,
                "trait impl method row should retain its impl-specific owner relation"
            );
            assert_eq!(
                parsed.hir_method_name_token[method_node], parsed.hir_item_name_token[method_node],
                "trait impl method name token should reuse the parser-owned function item name token"
            );
        } else {
            assert_eq!(
                parsed.hir_item_kind[method_node], HIR_ITEM_KIND_NONE,
                "trait contract method rows should not enter the value item namespace"
            );
            assert_eq!(
                parsed.hir_method_impl_node[method_node], INVALID,
                "trait contract method rows should not publish an impl-specific owner"
            );
        }

        let mut params = parsed
            .hir_param_owner_fn_node
            .iter()
            .enumerate()
            .filter_map(|(node, &param_owner)| {
                (param_owner as usize == method_node && parsed.hir_kind[node] == HIR_NODE_PARAM)
                    .then_some(node)
            })
            .collect::<Vec<_>>();
        params.sort_unstable_by_key(|&node| parsed.hir_param_ordinal[node]);
        assert_eq!(
            params.len(),
            2,
            "each trait contract and trait impl method should own receiver and value parameter rows"
        );
        assert_eq!(
            parsed.hir_method_first_param_token[method_node],
            parsed.hir_param_name_token[params[0]],
            "method first-param token should point at the ordinal-zero receiver parameter"
        );

        for (expected_ordinal, param_node) in params.iter().copied().enumerate() {
            assert_eq!(
                parsed.hir_param_ordinal[param_node], expected_ordinal as u32,
                "method parameter rows should publish contiguous source-order ordinals"
            );
            assert_eq!(
                parsed.hir_param_record_node[param_node] as usize, param_node,
                "method parameter row should self-identify its parser-owned record node"
            );
            assert_ne!(
                parsed.hir_param_name_token[param_node], INVALID,
                "method parameter row should publish its source name token"
            );
            assert_eq!(
                parsed.hir_node_file_id[param_node], parsed.hir_node_file_id[method_node],
                "method parameter row should retain the method source-pack file id"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                method_node,
                param_node,
                "method parameter",
            );
        }

        let receiver_param = params[0];
        let value_param = params[1];
        if receiver_mode == HIR_METHOD_RECEIVER_REF_SELF {
            assert_eq!(
                parsed.hir_param_type_node[receiver_param], INVALID,
                "&self receiver rows should not synthesize a receiver type edge"
            );
        } else {
            let typed_receiver = assert_valid_source_pack_hir_node_index(
                &parsed,
                parsed.hir_param_type_node[receiver_param],
                "typed method receiver",
            );
            assert_eq!(
                parsed.hir_kind[typed_receiver], HIR_NODE_TYPE,
                "typed receiver should point at a parser-owned type HIR row"
            );
            assert_eq!(
                parsed.hir_type_form[typed_receiver], HIR_TYPE_FORM_PATH,
                "typed receiver should publish a path-type row"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                receiver_param,
                typed_receiver,
                "typed method receiver",
            );
        }

        let value_type = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_param_type_node[value_param],
            "method value parameter type",
        );
        assert_eq!(
            parsed.hir_kind[value_type], HIR_NODE_TYPE,
            "method value parameter should point at a parser-owned type HIR row"
        );
        assert_eq!(
            parsed.hir_type_form[value_type], HIR_TYPE_FORM_PATH,
            "method value parameter should publish a path-type row"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            value_param,
            value_type,
            "method value parameter type",
        );
    }
}

#[test]
fn parser_hir_method_parameter_records_publish_receiver_type_policy_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

struct Range {
    start: i32,
}

impl Range {
    fn by_ref(&self, value: i32) {
        return;
    }

    fn by_value(self: Range, value: i32) {
        return;
    }
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_owners = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_NODE_FN && parsed.hir_node_file_id[node] == 0).then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_owners.len(),
        2,
        "fixture should publish exactly the two impl method function rows"
    );

    let mut by_ref_method_count = 0usize;
    let mut by_value_method_count = 0usize;
    let mut owned_param_count = 0usize;
    for function_node in function_owners {
        assert!(
            (parsed.hir_node_file_id[function_node] as usize) < source_count,
            "method function row {function_node} should retain a bounded source-pack file id"
        );
        assert_source_pack_hir_node_has_non_empty_span(&parsed, function_node, "method function");

        let mut params = parsed
            .hir_param_owner_fn_node
            .iter()
            .enumerate()
            .filter_map(|(node, &owner)| {
                (owner as usize == function_node && parsed.hir_kind[node] == HIR_NODE_PARAM)
                    .then_some(node)
            })
            .collect::<Vec<_>>();
        params.sort_unstable_by_key(|&node| parsed.hir_param_ordinal[node]);
        assert_eq!(
            params.len(),
            2,
            "each fixture method should own receiver and value parameter rows"
        );
        owned_param_count += params.len();

        let mut previous_start = None;
        for (expected_ordinal, param_node) in params.iter().copied().enumerate() {
            assert_eq!(
                parsed.hir_param_ordinal[param_node], expected_ordinal as u32,
                "parameter row {param_node} should publish a contiguous source-order ordinal"
            );
            assert_eq!(
                parsed.hir_param_record_node[param_node] as usize, param_node,
                "parameter row {param_node} should self-identify its parser-owned record node"
            );
            assert_eq!(
                parsed.hir_param_name_token[param_node], parsed.hir_token_pos[param_node],
                "parameter row {param_node} should publish its token anchor without source-text rediscovery"
            );
            assert_eq!(
                parsed.hir_node_file_id[param_node], parsed.hir_node_file_id[function_node],
                "parameter row {param_node} should inherit its method source-pack file id"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                function_node,
                param_node,
                "method parameter",
            );
            if let Some(previous_start) = previous_start {
                assert!(
                    previous_start < parsed.hir_token_pos[param_node],
                    "method parameter ordinals should follow source order"
                );
            }
            previous_start = Some(parsed.hir_token_pos[param_node]);
        }

        let receiver = params[0];
        let value_param = params[1];
        let value_type = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_param_type_node[value_param],
            "named method parameter type",
        );
        assert_eq!(
            parsed.hir_kind[value_type], HIR_NODE_TYPE,
            "named method parameter should point at a parser-owned type HIR row"
        );
        assert_eq!(
            parsed.hir_type_form[value_type], HIR_TYPE_FORM_PATH,
            "named method parameter type should publish a path-type record"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            value_param,
            value_type,
            "named method parameter type",
        );

        let receiver_type = parsed.hir_param_type_node[receiver];
        if receiver_type == INVALID {
            by_ref_method_count += 1;
        } else {
            by_value_method_count += 1;
            let receiver_type =
                assert_valid_source_pack_hir_node_index(&parsed, receiver_type, "typed receiver");
            assert_eq!(
                parsed.hir_kind[receiver_type], HIR_NODE_TYPE,
                "typed receiver should point at a parser-owned type HIR row"
            );
            assert_eq!(
                parsed.hir_type_form[receiver_type], HIR_TYPE_FORM_PATH,
                "typed receiver should publish a path-type record"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                receiver,
                receiver_type,
                "typed receiver",
            );
        }
    }

    assert_eq!(
        by_ref_method_count, 1,
        "&self receiver rows should not synthesize a type edge"
    );
    assert_eq!(
        by_value_method_count, 1,
        "self: T receiver rows should retain their parser-owned type edge"
    );
    assert_eq!(
        owned_param_count, 4,
        "fixture should publish exactly four method parameter rows"
    );
}

#[test]
fn parser_hir_method_declaration_records_are_source_addressable_in_source_packs() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

struct Range {
    start: i32,
}

impl Range {
    pub fn by_ref(&self, value: i32) {
        return;
    }

    fn by_value(self: Range, value: i32) {
        return;
    }
}

fn free(value: i32) -> i32 {
    return value;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut method_nodes = parsed
        .hir_method_impl_node
        .iter()
        .enumerate()
        .filter_map(|(node, &impl_node)| (impl_node != INVALID).then_some(node))
        .collect::<Vec<_>>();
    method_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        method_nodes.len(),
        2,
        "fixture should publish exactly two parser-owned impl method rows"
    );

    let impl_node = parsed.hir_method_impl_node[method_nodes[0]];
    assert_ne!(
        impl_node, INVALID,
        "method rows should publish their impl owner"
    );
    assert_eq!(
        parsed.hir_method_impl_node[method_nodes[1]], impl_node,
        "methods from the same impl block should share an impl owner row"
    );
    assert!(
        (impl_node as usize) < parsed.hir_kind.len(),
        "method impl owner should be inside the parser tree readback"
    );

    let receiver_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_impl_receiver_type_node[impl_node as usize],
        "impl receiver type",
    );
    assert_eq!(
        parsed.hir_kind[receiver_type], HIR_NODE_TYPE,
        "impl receiver type should be a parser-owned type HIR row"
    );
    assert_eq!(
        parsed.hir_type_form[receiver_type], HIR_TYPE_FORM_PATH,
        "impl receiver type should publish a concrete path-type record"
    );
    assert_eq!(
        parsed.hir_node_file_id[receiver_type], 0,
        "impl receiver type should retain the source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, receiver_type, "impl receiver type");

    let expected = [
        (HIR_METHOD_VIS_PUBLIC, HIR_METHOD_RECEIVER_REF_SELF, true),
        (HIR_METHOD_VIS_PRIVATE, HIR_METHOD_RECEIVER_SELF, false),
    ];
    for (method_node, (visibility, receiver_mode, receiver_type_is_empty)) in
        method_nodes.iter().copied().zip(expected)
    {
        assert_eq!(
            parsed.hir_kind[method_node], HIR_NODE_FN,
            "method record should attach to the parser-owned function HIR row"
        );
        assert_eq!(
            parsed.hir_item_kind[method_node], HIR_ITEM_KIND_FN,
            "method record should attach to a function item record"
        );
        assert_eq!(
            parsed.hir_node_file_id[method_node], 0,
            "method row should retain the source-pack file id"
        );
        assert_source_pack_hir_node_has_non_empty_span(&parsed, method_node, "method row");
        assert_eq!(
            parsed.hir_method_name_token[method_node], parsed.hir_item_name_token[method_node],
            "method name token should reuse the parser-owned function item name token"
        );
        assert!(
            parsed.hir_token_pos[method_node] < parsed.hir_method_name_token[method_node]
                && parsed.hir_method_name_token[method_node] < parsed.hir_token_end[method_node],
            "method name token should stay inside the function item span"
        );
        assert_eq!(
            parsed.hir_method_visibility[method_node], visibility,
            "method visibility should be published from the impl method wrapper"
        );
        assert_eq!(
            parsed.hir_method_receiver_mode[method_node], receiver_mode,
            "method receiver mode should be published from the ordinal-zero parameter row"
        );

        let mut params = parsed
            .hir_param_owner_fn_node
            .iter()
            .enumerate()
            .filter_map(|(node, &owner)| (owner as usize == method_node).then_some(node))
            .collect::<Vec<_>>();
        params.sort_unstable_by_key(|&node| parsed.hir_param_ordinal[node]);
        assert_eq!(
            params.len(),
            2,
            "each fixture method should own receiver and value parameter rows"
        );
        let receiver_param = params[0];
        assert_eq!(
            parsed.hir_method_first_param_token[method_node],
            parsed.hir_param_name_token[receiver_param],
            "method first-param token should point at the ordinal-zero parameter record"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            method_node,
            receiver_param,
            "method receiver parameter",
        );

        if receiver_type_is_empty {
            assert_eq!(
                parsed.hir_param_type_node[receiver_param], INVALID,
                "&self receiver rows should not synthesize a receiver type edge"
            );
        } else {
            let typed_receiver = assert_valid_source_pack_hir_node_index(
                &parsed,
                parsed.hir_param_type_node[receiver_param],
                "typed method receiver",
            );
            assert_eq!(
                parsed.hir_kind[typed_receiver], HIR_NODE_TYPE,
                "typed receiver should point at a parser-owned type HIR row"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                receiver_param,
                typed_receiver,
                "typed method receiver",
            );
        }
    }

    let free_function_count = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter(|&(node, &kind)| {
            kind == HIR_ITEM_KIND_FN
                && parsed.hir_node_file_id[node] == 0
                && parsed.hir_method_impl_node[node] == INVALID
        })
        .count();
    assert_eq!(
        free_function_count, 1,
        "free function rows should not publish impl method metadata"
    );
}

#[test]
fn parser_hir_method_return_records_publish_parser_owned_type_edges() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

trait Measures {
    pub fn contains(&self, value: i32) -> bool;
    fn start(self: Range) -> i32;
}

struct Range {
    start: i32,
}

impl Range {
    fn contains(&self, value: i32) -> bool {
        return true;
    }

    fn start(self: Range) -> i32 {
        return 0;
    }
}

impl Measures for Range {
    pub fn contains(&self, value: i32) -> bool {
        return true;
    }

    fn start(self: Range) -> i32 {
        return 0;
    }
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut method_nodes = parsed
        .hir_method_name_token
        .iter()
        .enumerate()
        .filter_map(|(node, &name_token)| (name_token != INVALID).then_some(node))
        .collect::<Vec<_>>();
    method_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        method_nodes.len(),
        6,
        "fixture should publish two trait, two inherent impl, and two trait-impl method rows"
    );

    let trait_owner = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_owner_node[method_nodes[0]],
        "trait method owner",
    );
    assert_eq!(
        parsed.hir_item_kind[trait_owner], HIR_ITEM_KIND_TRAIT,
        "trait method return rows should be anchored under the parser-owned trait item"
    );

    let inherent_impl_owner = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_owner_node[method_nodes[2]],
        "inherent impl method owner",
    );
    let trait_impl_owner = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_owner_node[method_nodes[4]],
        "trait impl method owner",
    );
    assert_ne!(
        trait_owner, inherent_impl_owner,
        "trait declarations and inherent impl declarations should keep distinct owner rows"
    );
    assert_ne!(
        inherent_impl_owner, trait_impl_owner,
        "inherent impl and trait impl declarations should keep distinct owner rows"
    );

    let expected = [
        (
            "public trait method",
            trait_owner,
            HIR_ITEM_KIND_NONE,
            false,
        ),
        (
            "private trait method",
            trait_owner,
            HIR_ITEM_KIND_NONE,
            false,
        ),
        (
            "public inherent method",
            inherent_impl_owner,
            HIR_ITEM_KIND_FN,
            true,
        ),
        (
            "private inherent method",
            inherent_impl_owner,
            HIR_ITEM_KIND_FN,
            true,
        ),
        (
            "public trait impl method",
            trait_impl_owner,
            HIR_ITEM_KIND_FN,
            true,
        ),
        (
            "private trait impl method",
            trait_impl_owner,
            HIR_ITEM_KIND_FN,
            true,
        ),
    ];
    let mut return_type_nodes = Vec::with_capacity(method_nodes.len());
    for (method_node, (label, owner, item_kind, impl_backed)) in
        method_nodes.iter().copied().zip(expected)
    {
        assert_eq!(
            parsed.hir_kind[method_node], HIR_NODE_FN,
            "{label} should attach return metadata to a function-shaped HIR row"
        );
        assert_eq!(
            parsed.hir_item_kind[method_node], item_kind,
            "{label} should keep its parser-owned item namespace classification"
        );
        assert_eq!(
            parsed.hir_method_owner_node[method_node] as usize, owner,
            "{label} should retain the method-owner row that downstream predicate passes consume"
        );
        if impl_backed {
            assert_eq!(
                parsed.hir_method_impl_node[method_node] as usize, owner,
                "{label} should retain its impl-specific owner row"
            );
        } else {
            assert_eq!(
                parsed.hir_method_impl_node[method_node], INVALID,
                "{label} should not publish an impl-specific owner row"
            );
        }
        assert!(
            (parsed.hir_node_file_id[method_node] as usize) < source_count,
            "{label} should retain a bounded source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            owner,
            method_node,
            "method declaration",
        );

        let return_type_node = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_fn_return_type_node[method_node],
            "method return type",
        );
        assert_eq!(
            parsed.hir_kind[return_type_node], HIR_NODE_TYPE,
            "{label} return edge should point at a parser-owned type HIR row"
        );
        assert_eq!(
            parsed.hir_type_form[return_type_node], HIR_TYPE_FORM_PATH,
            "{label} return edge should point at a path type record"
        );
        assert_eq!(
            parsed.hir_node_file_id[return_type_node], parsed.hir_node_file_id[method_node],
            "{label} return type should inherit the method source-pack file id"
        );
        assert_eq!(
            parsed.hir_type_file_id[return_type_node], parsed.hir_node_file_id[method_node],
            "{label} return type record should retain the method source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            method_node,
            return_type_node,
            "method return type",
        );
        assert!(
            parsed.hir_token_pos[method_node] < parsed.hir_token_pos[return_type_node],
            "{label} declaration token should precede its parser-owned return type node"
        );
        return_type_nodes.push(return_type_node);
    }

    return_type_nodes.sort_unstable();
    return_type_nodes.dedup();
    assert_eq!(
        return_type_nodes.len(),
        6,
        "each trait, inherent impl, and trait-impl method should publish a distinct return type HIR node"
    );
}

#[test]
fn parser_hir_method_signature_flags_reject_free_function_rows() {
    let err = validate_hir_method_records(
        &[HIR_NODE_NONE, HIR_NODE_FN],
        &[INVALID, 10],
        &[INVALID, 20],
        &[INVALID, 0],
        &[HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_FN],
        &[INVALID, 12],
        &[INVALID, 0],
        &[INVALID; 2],
        &[0; 2],
        &[INVALID; 2],
        &[INVALID; 2],
        &[INVALID; 2],
        &[INVALID; 2],
        &[INVALID; 2],
        &[INVALID; 2],
        &[HIR_METHOD_RECEIVER_NONE; 2],
        &[HIR_METHOD_VIS_PRIVATE; 2],
        &[0, HIR_METHOD_SIGNATURE_HAS_GENERICS],
        &[INVALID; 2],
    )
    .expect_err("method signature flags should fail closed on free function rows");
    assert!(
        err.to_string().contains("without a declaration owner"),
        "error should describe the method-record owner contract"
    );
}

#[test]
fn parser_hir_method_signature_flags_publish_parser_owned_method_level_records() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

trait Factory {
    fn make<T>(value: T) -> T where T: Factory;
    fn plain(value: i32) -> i32;
}

struct Maker {
    value: i32,
}

impl Factory for Maker {
    fn make<T>(value: T) -> T where T: Factory {
        return value;
    }

    fn plain(value: i32) -> i32 {
        return value;
    }
}

fn free_generic<T>(value: T) -> T where T: Factory {
    return value;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let mut method_nodes = parsed
        .hir_method_name_token
        .iter()
        .enumerate()
        .filter_map(|(node, &name_token)| (name_token != INVALID).then_some(node))
        .collect::<Vec<_>>();
    method_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        method_nodes.len(),
        4,
        "fixture should publish two trait method rows and two trait-impl method rows"
    );

    let trait_owner = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_owner_node[method_nodes[0]],
        "trait method owner",
    );
    assert_eq!(
        parsed.hir_item_kind[trait_owner], HIR_ITEM_KIND_TRAIT,
        "trait declaration methods should publish flags under a trait owner row"
    );
    let trait_impl_owner = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_method_owner_node[method_nodes[2]],
        "trait impl method owner",
    );
    assert_ne!(
        trait_owner, trait_impl_owner,
        "trait declaration and trait-impl methods should keep distinct owner rows"
    );

    let signature_flag_mask = HIR_METHOD_SIGNATURE_HAS_GENERICS | HIR_METHOD_SIGNATURE_HAS_WHERE;
    let expected = [
        (
            "trait declaration method with method-level generics and where clause",
            trait_owner,
            HIR_ITEM_KIND_NONE,
            INVALID,
            signature_flag_mask,
        ),
        (
            "plain trait declaration method",
            trait_owner,
            HIR_ITEM_KIND_NONE,
            INVALID,
            0,
        ),
        (
            "trait impl method with method-level generics and where clause",
            trait_impl_owner,
            HIR_ITEM_KIND_FN,
            trait_impl_owner as u32,
            signature_flag_mask,
        ),
        (
            "plain trait impl method",
            trait_impl_owner,
            HIR_ITEM_KIND_FN,
            trait_impl_owner as u32,
            0,
        ),
    ];
    for (method_node, (label, owner, item_kind, impl_node, flags)) in
        method_nodes.iter().copied().zip(expected)
    {
        assert_eq!(
            parsed.hir_kind[method_node], HIR_NODE_FN,
            "{label} should attach signature flags to a function-shaped HIR row"
        );
        assert_eq!(
            parsed.hir_method_owner_node[method_node] as usize, owner,
            "{label} should retain the parser-owned method owner consumed by predicates"
        );
        assert_eq!(
            parsed.hir_method_impl_node[method_node], impl_node,
            "{label} should retain the parser-owned impl owner policy"
        );
        assert_eq!(
            parsed.hir_item_kind[method_node], item_kind,
            "{label} should retain its item namespace classification"
        );
        assert_eq!(
            parsed.hir_method_signature_flags[method_node] & signature_flag_mask,
            flags,
            "{label} should publish exactly the method-level signature flags downstream consumers read"
        );
        assert_eq!(
            parsed.hir_method_signature_flags[method_node] & !signature_flag_mask,
            0,
            "{label} should not publish unknown method signature flag bits"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, owner, method_node, label);
    }

    let flagged_non_method_rows = parsed
        .hir_method_signature_flags
        .iter()
        .enumerate()
        .filter(|&(node, &flags)| flags != 0 && parsed.hir_method_name_token[node] == INVALID)
        .count();
    assert_eq!(
        flagged_non_method_rows, 0,
        "parser-owned method signature flags should only attach to method rows, not free generic functions"
    );
}

#[test]
fn parser_hir_function_return_records_scale_as_parser_owned_edges() {
    const SUFFIXES: [&str; 12] = [
        "aa", "ab", "ac", "ad", "ae", "af", "ag", "ah", "ai", "aj", "ak", "al",
    ];
    let mut core_source = String::from("module core::returns;\n");
    for suffix in SUFFIXES {
        core_source.push_str(&format!(
            "pub fn ret_core_{suffix}() -> i32 {{ return 0; }}\n"
        ));
    }
    let mut app_source = String::from("module app::main;\nimport core::returns;\n");
    for suffix in SUFFIXES {
        app_source.push_str(&format!("fn ret_app_{suffix}() -> i32 {{ return 0; }}\n"));
    }

    let parsed = parse_resident_source_pack_fn_returns(vec![core_source, app_source]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == HIR_ITEM_KIND_FN).then_some(node))
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        24,
        "fixture should publish two dozen function item rows"
    );

    let mut functions_by_file = [0usize; 2];
    let mut return_type_nodes = Vec::with_capacity(function_nodes.len());
    for function_node in function_nodes {
        assert_eq!(
            parsed.hir_kind[function_node], HIR_NODE_FN,
            "function item metadata should attach to a parser-owned function HIR node"
        );
        let file_id = parsed.hir_item_file_id[function_node] as usize;
        assert!(
            file_id < functions_by_file.len(),
            "function row {function_node} should retain a bounded source-pack file id"
        );
        functions_by_file[file_id] += 1;
        assert_eq!(
            parsed.hir_node_file_id[function_node], parsed.hir_item_file_id[function_node],
            "function row {function_node} should retain the same node and item file id"
        );
        assert_fn_return_readback_node_has_non_empty_span(&parsed, function_node, "function item");

        let name_token = parsed.hir_item_name_token[function_node];
        assert_ne!(
            name_token, INVALID,
            "function row {function_node} should publish its name token"
        );
        assert!(
            parsed.hir_token_pos[function_node] <= name_token
                && name_token < parsed.hir_token_end[function_node],
            "function row {function_node} should keep its name token inside the item span"
        );

        let return_type_node = assert_valid_fn_return_readback_node(
            &parsed,
            parsed.hir_fn_return_type_node[function_node],
            "function return type",
        );
        assert_eq!(
            parsed.hir_kind[return_type_node], HIR_NODE_TYPE,
            "function {function_node} return edge should point at a parser-owned type HIR node"
        );
        assert_eq!(
            parsed.hir_type_form[return_type_node], HIR_TYPE_FORM_PATH,
            "function {function_node} return edge should point at a path type record"
        );
        assert_eq!(
            parsed.hir_node_file_id[return_type_node], parsed.hir_node_file_id[function_node],
            "function {function_node} return type should inherit the function source-pack file id"
        );
        assert_eq!(
            parsed.hir_type_file_id[return_type_node], parsed.hir_item_file_id[function_node],
            "function {function_node} return type record should retain the function source-pack file id"
        );
        assert_fn_return_readback_child_span_inside_owner(
            &parsed,
            function_node,
            return_type_node,
            "function return type",
        );
        assert!(
            name_token < parsed.hir_token_pos[return_type_node],
            "function {function_node} name token should precede the parser-owned return type node"
        );
        return_type_nodes.push(return_type_node);
    }

    assert_eq!(
        functions_by_file,
        [12, 12],
        "source-pack function return records should preserve both source files"
    );
    return_type_nodes.sort_unstable();
    return_type_nodes.dedup();
    assert_eq!(
        return_type_nodes.len(),
        24,
        "each function should publish a distinct return type HIR node"
    );

    let published_function_return_edges = parsed
        .hir_fn_return_type_node
        .iter()
        .enumerate()
        .filter(|&(node, &return_type)| {
            return_type != INVALID && parsed.hir_item_kind[node] == HIR_ITEM_KIND_FN
        })
        .count();
    assert_eq!(
        published_function_return_edges, 24,
        "fixture should publish exactly one return edge per function item"
    );

    let non_function_return_edges = parsed
        .hir_fn_return_type_node
        .iter()
        .enumerate()
        .filter(|&(node, &return_type)| {
            return_type != INVALID && parsed.hir_item_kind[node] != HIR_ITEM_KIND_FN
        })
        .count();
    assert_eq!(
        non_function_return_edges, 0,
        "non-function item rows should not publish function return type edges"
    );
}

#[test]
fn parser_hir_type_records_publish_composite_operand_edges_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn consume(reference: &i32, values: [i32], fixed: [i32; 3]) -> i32 {
    return values[0];
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private function item");
    assert!(
        (parsed.hir_item_file_id[function_node] as usize) < source_count,
        "function item should retain a bounded source-pack file id"
    );

    let mut params = parsed
        .hir_param_owner_fn_node
        .iter()
        .enumerate()
        .filter_map(|(node, &owner)| {
            (owner as usize == function_node && parsed.hir_kind[node] == HIR_NODE_PARAM)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    params.sort_unstable_by_key(|&node| parsed.hir_param_ordinal[node]);
    assert_eq!(
        params.len(),
        3,
        "fixture should publish reference, slice, and array parameter rows"
    );

    let reference_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_param_type_node[params[0]],
        "reference parameter type",
    );
    let slice_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_param_type_node[params[1]],
        "slice parameter type",
    );
    let array_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_param_type_node[params[2]],
        "array parameter type",
    );

    for (param_node, type_node, expected_form, label) in [
        (
            params[0],
            reference_type,
            HIR_TYPE_FORM_REF,
            "reference parameter type",
        ),
        (
            params[1],
            slice_type,
            HIR_TYPE_FORM_SLICE,
            "slice parameter type",
        ),
        (
            params[2],
            array_type,
            HIR_TYPE_FORM_ARRAY,
            "array parameter type",
        ),
    ] {
        assert_eq!(
            parsed.hir_kind[type_node], HIR_NODE_TYPE,
            "{label} should be a parser-owned type HIR row"
        );
        assert_eq!(
            parsed.hir_type_form[type_node], expected_form,
            "{label} should publish its composite type form"
        );
        assert_eq!(
            parsed.hir_node_file_id[type_node], parsed.hir_node_file_id[param_node],
            "{label} should inherit the parameter source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, param_node, type_node, label);

        let operand_type = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_type_value_node[type_node],
            "composite type operand",
        );
        assert_eq!(
            parsed.hir_kind[operand_type], HIR_NODE_TYPE,
            "{label} should point at a parser-owned operand type row"
        );
        assert_eq!(
            parsed.hir_type_form[operand_type], HIR_TYPE_FORM_PATH,
            "{label} operand should publish the path type form"
        );
        assert_eq!(
            parsed.hir_node_file_id[operand_type], parsed.hir_node_file_id[type_node],
            "{label} operand should inherit the composite type source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            type_node,
            operand_type,
            "composite type operand",
        );
    }

    for type_node in [reference_type, slice_type] {
        assert_eq!(
            parsed.hir_type_len_token[type_node], INVALID,
            "non-array composite type rows should not publish array length tokens"
        );
    }
    let array_len_token = parsed.hir_type_len_token[array_type];
    assert_ne!(
        array_len_token, INVALID,
        "array type row should publish its length token"
    );
    assert!(
        parsed.hir_token_pos[array_type] <= array_len_token
            && array_len_token < parsed.hir_token_end[array_type],
        "array length token should stay inside the parser-owned array type span"
    );
}

#[test]
fn parser_hir_return_statement_records_are_source_addressable_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn main(input: i32) -> i32 {
    return input;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        1,
        "fixture should publish exactly one private function item"
    );
    let function_node = function_nodes[0];

    let return_nodes = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_RETURN && parsed.hir_kind[node] == HIR_NODE_RETURN_STMT)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        return_nodes.len(),
        1,
        "fixture should publish exactly one return statement record"
    );
    let return_node = return_nodes[0];

    assert_eq!(
        parsed.hir_node_file_id[return_node], parsed.hir_node_file_id[function_node],
        "return statement should retain the owning function source-pack file id"
    );
    assert!(
        (parsed.hir_node_file_id[return_node] as usize) < source_count,
        "return statement should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        return_node,
        "return statement",
    );

    let return_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[return_node],
        "return expression",
    );
    assert_eq!(
        parsed.hir_kind[return_expr], HIR_NODE_EXPR,
        "return statement record should point at a parser-owned expression HIR row"
    );
    assert_eq!(
        parsed.hir_node_file_id[return_expr], parsed.hir_node_file_id[return_node],
        "return expression should inherit the return statement source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_node,
        return_expr,
        "return expression",
    );
    assert_eq!(
        parsed.hir_stmt_record_operand1[return_node], INVALID,
        "return statement record should leave the unused operand empty"
    );

    let value_token = parsed.hir_stmt_record_operand2[return_node];
    assert_ne!(
        value_token, INVALID,
        "return statement record should publish the value token for downstream consumers"
    );
    assert!(
        parsed.hir_token_pos[return_expr] <= value_token
            && value_token < parsed.hir_token_end[return_expr],
        "return statement value token should stay inside the return expression span"
    );
}

#[test]
fn parser_hir_return_value_token_uses_expression_result_edge_for_member_values() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

struct Pair {
    left: i32,
}

fn main(pair: Pair) -> i32 {
    return pair.left;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let return_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_RETURN && parsed.hir_kind[node] == HIR_NODE_RETURN_STMT)
                .then_some(node)
        })
        .expect("fixture should publish one return statement record");
    let return_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[return_node],
        "return expression",
    );

    let member_node = parsed
        .hir_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_NODE_MEMBER_EXPR
                && parsed.hir_token_pos[return_expr] <= parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[return_expr])
                .then_some(node)
        })
        .expect("return expression should publish one member result row");
    let member_token = parsed.hir_member_name_token[member_node];
    assert_ne!(
        member_token, INVALID,
        "member result row should publish a member-name token"
    );
    assert_eq!(
        parsed.hir_stmt_record_operand2[return_node], member_token,
        "return value token should come from the parser-owned expression result edge"
    );
}

#[test]
fn parser_hir_return_statement_records_publish_strict_return_rows_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn helper() {
    return;
}

fn main() -> i32 {
    return 7;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let return_nodes = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind == STMT_RECORD_KIND_RETURN).then_some(node))
        .collect::<Vec<_>>();
    assert_eq!(
        return_nodes.len(),
        2,
        "fixture should publish one empty and one valued return statement record"
    );

    let mut empty_returns = 0usize;
    let mut valued_returns = 0usize;
    for return_node in return_nodes {
        assert_eq!(
            parsed.hir_kind[return_node], HIR_NODE_RETURN_STMT,
            "return statement record row {return_node} should have the strict return HIR kind"
        );
        assert!(
            (parsed.hir_node_file_id[return_node] as usize) < source_count,
            "return statement record row {return_node} should retain a bounded source-pack file id"
        );
        assert_source_pack_hir_node_has_non_empty_span(
            &parsed,
            return_node,
            "return statement record",
        );
        assert_eq!(
            parsed.hir_stmt_record_operand1[return_node], INVALID,
            "return statement record row {return_node} should leave its reserved operand empty"
        );

        if parsed.hir_stmt_record_operand0[return_node] == INVALID {
            empty_returns += 1;
            assert_eq!(
                parsed.hir_stmt_record_operand2[return_node], INVALID,
                "empty return row {return_node} should not publish a value token"
            );
        } else {
            valued_returns += 1;
            let return_expr = assert_valid_source_pack_hir_node_index(
                &parsed,
                parsed.hir_stmt_record_operand0[return_node],
                "valued return expression",
            );
            assert_eq!(
                parsed.hir_kind[return_expr], HIR_NODE_EXPR,
                "valued return row {return_node} should point at a parser-owned expression row"
            );
            assert_source_pack_hir_child_span_inside_owner(
                &parsed,
                return_node,
                return_expr,
                "valued return expression",
            );
            assert!(
                parsed.hir_stmt_record_operand2[return_node] != INVALID
                    && parsed.hir_token_pos[return_expr]
                        <= parsed.hir_stmt_record_operand2[return_node]
                    && parsed.hir_stmt_record_operand2[return_node]
                        < parsed.hir_token_end[return_expr],
                "valued return row {return_node} should publish a value token inside the expression span"
            );
        }
    }

    assert_eq!(empty_returns, 1, "fixture should publish one empty return");
    assert_eq!(
        valued_returns, 1,
        "fixture should publish one valued return"
    );
}

#[test]
fn parser_hir_expression_records_publish_operator_operands_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn main(values: [i32; 3], delta: i32) -> i32 {
    return values[1] + delta;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private function item");
    assert_eq!(
        parsed.hir_node_file_id[function_node], 0,
        "function row should retain the lexer-provided source-pack file id"
    );
    assert!(
        (parsed.hir_node_file_id[function_node] as usize) < source_count,
        "function row should retain a bounded source-pack file id"
    );

    let return_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_RETURN && parsed.hir_kind[node] == HIR_NODE_RETURN_STMT)
                .then_some(node)
        })
        .expect("fixture should publish one return statement record");
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        return_node,
        "return statement",
    );

    let return_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[return_node],
        "return expression",
    );
    assert_eq!(
        parsed.hir_kind[return_expr], HIR_NODE_EXPR,
        "return statement should point at a parser-owned expression row"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_node,
        return_expr,
        "return expression",
    );

    let add_nodes = parsed
        .hir_expr_record_form
        .iter()
        .enumerate()
        .filter_map(|(node, &form)| {
            (form == HIR_EXPR_FORM_ADD
                && parsed.hir_node_file_id[node] == 0
                && parsed.hir_token_pos[return_expr] <= parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[return_expr])
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        add_nodes.len(),
        1,
        "return expression should publish exactly one add operator record"
    );
    let add_node = add_nodes[0];

    let add_left = assert_valid_source_pack_record_index(
        &parsed,
        parsed.hir_expr_record_left[add_node],
        "add left operand",
    );
    let add_right = assert_valid_source_pack_record_index(
        &parsed,
        parsed.hir_expr_record_right[add_node],
        "add right operand",
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_expr,
        add_left,
        "add left operand",
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_expr,
        add_right,
        "add right operand",
    );

    let index_node = resolve_forward_expr_record(&parsed, add_left, "add left operand");
    assert_eq!(
        parsed.hir_expr_record_form[index_node], HIR_EXPR_FORM_INDEX,
        "left operand should resolve through expression records to the index operator"
    );

    let delta_node = resolve_forward_expr_record(&parsed, add_right, "add right operand");
    assert_eq!(
        parsed.hir_expr_record_form[delta_node], HIR_EXPR_FORM_NAME,
        "right operand should resolve through expression records to the delta name"
    );
    assert_expr_record_value_token_inside(&parsed, delta_node, "right operand name");

    let index_base = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_left[index_node],
            "index base operand",
        ),
        "index base operand",
    );
    assert_eq!(
        parsed.hir_expr_record_form[index_base], HIR_EXPR_FORM_NAME,
        "index base should resolve through expression records to the values name"
    );
    assert_expr_record_value_token_inside(&parsed, index_base, "index base name");

    let index_value = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_right[index_node],
            "index value operand",
        ),
        "index value operand",
    );
    assert_eq!(
        parsed.hir_expr_record_form[index_value], HIR_EXPR_FORM_INT,
        "index operand should resolve through expression records to the literal index"
    );
    assert_expr_record_value_token_inside(&parsed, index_value, "index literal");

    for node in [add_node, index_node, delta_node, index_base, index_value] {
        assert_eq!(
            parsed.hir_node_file_id[node], parsed.hir_node_file_id[return_expr],
            "expression record row {node} should retain the return expression file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            return_expr,
            node,
            "expression record row",
        );
    }
}

#[test]
fn parser_hir_expression_records_link_qualified_path_binary_operands_in_source_packs() {
    let parsed = parse_resident_source_pack(&[
        r#"
module core::numbers;

pub const LIMIT: i32 = 21;
pub const STEP: i32 = 6;
"#,
        r#"
module app::main;
import core::numbers;

fn main() -> i32 {
    return core::numbers::LIMIT + core::numbers::STEP;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one app function item");
    let return_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_RETURN
                && parsed.hir_kind[node] == HIR_NODE_RETURN_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .expect("fixture should publish one app return statement record");
    let return_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[return_node],
        "return expression",
    );

    let add_node = resolve_forward_expr_record(&parsed, return_expr, "return expression");
    assert_eq!(
        parsed.hir_expr_record_form[add_node], HIR_EXPR_FORM_ADD,
        "qualified path return expression should resolve to the add operator"
    );

    let qualified_operand = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_left[add_node],
            "qualified const operand",
        ),
        "qualified const operand",
    );
    assert!(
        matches!(
            parsed.hir_kind[qualified_operand],
            HIR_NODE_NAME_EXPR | HIR_NODE_PATH_EXPR
        ),
        "left add operand should resolve to a parser-owned qualified-name expression row"
    );
    assert_eq!(
        parsed.hir_expr_record_form[qualified_operand], HIR_EXPR_FORM_NAME,
        "qualified const operand should publish a name-form expression record"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_expr,
        qualified_operand,
        "qualified const operand",
    );
    assert_expr_record_value_token_inside(&parsed, qualified_operand, "qualified const operand");

    let right_qualified_operand = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_right[add_node],
            "right qualified const operand",
        ),
        "right qualified const operand",
    );
    assert!(
        matches!(
            parsed.hir_kind[right_qualified_operand],
            HIR_NODE_NAME_EXPR | HIR_NODE_PATH_EXPR
        ),
        "right add operand should resolve to a parser-owned qualified-name expression row"
    );
    assert_eq!(
        parsed.hir_expr_record_form[right_qualified_operand], HIR_EXPR_FORM_NAME,
        "right qualified const operand should publish a name-form expression record"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_expr,
        right_qualified_operand,
        "right qualified const operand",
    );
    assert_expr_record_value_token_inside(
        &parsed,
        right_qualified_operand,
        "right qualified const operand",
    );
}

#[test]
fn parser_hir_expression_records_publish_float_literals_in_source_packs() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn main() -> f32 {
    return 1.5;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let return_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_RETURN && parsed.hir_kind[node] == HIR_NODE_RETURN_STMT)
                .then_some(node)
        })
        .expect("fixture should publish one return statement record");
    let return_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[return_node],
        "return expression",
    );
    let float_node = resolve_forward_expr_record(&parsed, return_expr, "float return expression");

    assert_eq!(
        parsed.hir_expr_record_form[float_node], HIR_EXPR_FORM_FLOAT,
        "float literal expressions should publish a scalar HIR expression form"
    );
    assert_expr_record_value_token_inside(&parsed, float_node, "float literal");
}

#[test]
fn parser_hir_expression_records_publish_string_literals_in_source_packs() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn main() -> str {
    return "ready";
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let return_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_RETURN && parsed.hir_kind[node] == HIR_NODE_RETURN_STMT)
                .then_some(node)
        })
        .expect("fixture should publish one return statement record");
    assert_eq!(
        parsed.hir_node_file_id[return_node], 0,
        "return statement should retain the lexer-provided source-pack file id"
    );

    let return_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[return_node],
        "return expression",
    );
    let string_node = resolve_forward_expr_record(&parsed, return_expr, "string return expression");

    assert_eq!(
        parsed.hir_expr_record_form[string_node], HIR_EXPR_FORM_STRING,
        "string literal expressions should publish a scalar HIR expression form"
    );
    assert_eq!(
        parsed.hir_node_file_id[string_node], parsed.hir_node_file_id[return_node],
        "string literal expression should retain the return statement source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        return_node,
        string_node,
        "string literal expression",
    );
    assert_expr_record_value_token_inside(&parsed, string_node, "string literal");
}

#[test]
fn parser_hir_boolean_condition_records_feed_type_checking_not_name_decoys() {
    let source_count = 2;
    let decoy = r#"
module lib::decoy;

pub fn same_spelled(flag: bool, value: i32, limit: i32) -> bool {
    return flag;
}
"#;
    let positive_app = r#"
module app::main;

fn main(flag: bool, value: i32, limit: i32) -> i32 {
    if (!flag && (value <= limit)) {
        return value;
    }
    return 0;
}
"#;
    let positive_sources = [decoy, positive_app];
    let parsed = parse_resident_source_pack(&positive_sources);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private app function item");
    assert!(
        (parsed.hir_item_file_id[function_node] as usize) < source_count,
        "function item should retain a bounded source-pack file id"
    );

    let if_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_IF
                && parsed.hir_kind[node] == HIR_NODE_IF_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .expect("fixture should publish one app if-statement record");
    assert_source_pack_hir_child_span_inside_owner(&parsed, function_node, if_node, "if statement");

    let condition_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[if_node],
        "if condition expression",
    );
    assert_eq!(
        parsed.hir_kind[condition_expr], HIR_NODE_EXPR,
        "if statement should point at a parser-owned condition expression row"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        if_node,
        condition_expr,
        "if condition expression",
    );

    let and_node = resolve_forward_expr_record(&parsed, condition_expr, "if condition");
    assert_eq!(
        parsed.hir_expr_record_form[and_node], HIR_EXPR_FORM_AND,
        "condition root should resolve through expression records to the logical-and operator"
    );
    assert_eq!(
        parsed.hir_node_file_id[and_node], parsed.hir_item_file_id[function_node],
        "logical-and expression should retain the app source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        condition_expr,
        and_node,
        "logical-and expression",
    );

    let not_node = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_left[and_node],
            "logical-and left operand",
        ),
        "logical-and left operand",
    );
    assert_eq!(
        parsed.hir_expr_record_form[not_node], HIR_EXPR_FORM_NOT,
        "logical-and left operand should resolve to the parser-owned unary-not record"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        condition_expr,
        not_node,
        "unary-not expression",
    );

    let le_node = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_right[and_node],
            "logical-and right operand",
        ),
        "logical-and right operand",
    );
    assert_eq!(
        parsed.hir_expr_record_form[le_node], HIR_EXPR_FORM_LE,
        "logical-and right operand should resolve to the parser-owned comparison record"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        condition_expr,
        le_node,
        "less-or-equal expression",
    );

    let not_operand = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_left[not_node],
            "unary-not operand",
        ),
        "unary-not operand",
    );
    let le_left = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_left[le_node],
            "comparison left operand",
        ),
        "comparison left operand",
    );
    let le_right = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_right[le_node],
            "comparison right operand",
        ),
        "comparison right operand",
    );

    for (node, label) in [
        (not_operand, "unary-not operand"),
        (le_left, "comparison left operand"),
        (le_right, "comparison right operand"),
    ] {
        assert_eq!(
            parsed.hir_expr_record_form[node], HIR_EXPR_FORM_NAME,
            "{label} should resolve through expression records to a name expression"
        );
        assert_eq!(
            parsed.hir_node_file_id[node], parsed.hir_item_file_id[function_node],
            "{label} should retain the app source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, condition_expr, node, label);
        assert_expr_record_value_token_inside(&parsed, node, label);
    }

    assert_eq!(
        parsed.hir_expr_record_right[not_node], INVALID,
        "unary-not records should leave the unused right operand empty"
    );
    assert_eq!(
        parsed.hir_expr_record_value_token[and_node], INVALID,
        "logical-and records should not publish a literal/name value token"
    );
    assert_eq!(
        parsed.hir_expr_record_value_token[le_node], INVALID,
        "comparison records should not publish a literal/name value token"
    );

    common::type_check_source_pack_with_timeout(&positive_sources)
        .expect("type checking should consume parser-owned boolean condition records");

    let negative_app = r#"
module app::main;

fn main(flag: i32, value: i32, limit: i32) -> i32 {
    if (!flag && (value <= limit)) {
        return value;
    }
    return 0;
}
"#;
    let err = common::type_check_source_pack_with_timeout(&[decoy, negative_app]).expect_err(
        "same-spelled bool parameter in another source must not make an i32 operand type-check",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            assert_eq!(diagnostic.message, "type mismatch");
            let label = diagnostic
                .primary_label
                .expect("type mismatch should carry a primary source label");
            assert_eq!(label.message, "expected a different type here");
            assert!(label.line > 0, "diagnostic should be source-spanned");
            assert!(label.column > 0, "diagnostic should be source-spanned");
            assert!(label.length > 0, "diagnostic span should be non-empty");
        }
        other => panic!("expected stable type-mismatch diagnostic, got {other:?}"),
    }
}

#[test]
fn parser_hir_if_statement_records_distinguish_else_blocks_from_adjacent_blocks() {
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn main(flag: bool) -> i32 {
    if (flag) {
        return 1;
    } else {
        return 2;
    }

    if (flag) {
        return 3;
    }

    {
        return 4;
    }

    return 0;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private function item");

    let mut if_nodes = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_IF
                && parsed.hir_kind[node] == HIR_NODE_IF_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .collect::<Vec<_>>();
    if_nodes.sort_unstable_by_key(|&node| parsed.hir_token_pos[node]);
    assert_eq!(
        if_nodes.len(),
        2,
        "fixture should publish exactly two if-statement records"
    );

    for if_node in if_nodes.iter().copied() {
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            function_node,
            if_node,
            "if statement",
        );
        let condition = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_stmt_record_operand0[if_node],
            "if condition",
        );
        assert_eq!(
            parsed.hir_kind[condition], HIR_NODE_EXPR,
            "if record should point at a parser-owned condition expression"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, if_node, condition, "if condition");

        let then_block = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_stmt_record_operand1[if_node],
            "if then block",
        );
        assert_eq!(
            parsed.hir_kind[then_block], HIR_NODE_BLOCK,
            "if record should point at the parser-owned then block"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, if_node, then_block, "then block");
    }

    let first_if = if_nodes[0];
    let first_else = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand2[first_if],
        "explicit else block",
    );
    assert_eq!(
        parsed.hir_kind[first_else], HIR_NODE_BLOCK,
        "explicit else should publish its parser-owned block edge"
    );
    assert_eq!(
        parsed.hir_node_file_id[first_else], parsed.hir_node_file_id[first_if],
        "else block should inherit the if statement source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        first_else,
        "explicit else block",
    );
    assert!(
        parsed.hir_token_pos[parsed.hir_stmt_record_operand1[first_if] as usize]
            < parsed.hir_token_pos[first_else],
        "explicit else block should follow the then block in source order"
    );

    let second_if = if_nodes[1];
    assert_eq!(
        parsed.hir_stmt_record_operand2[second_if], INVALID,
        "a standalone block after an if statement must not be published as an else edge"
    );
    let standalone_blocks_after_second_if = parsed
        .hir_kind
        .iter()
        .enumerate()
        .filter(|&(node, &kind)| {
            kind == HIR_NODE_BLOCK
                && parsed.hir_node_file_id[node] == parsed.hir_node_file_id[second_if]
                && parsed.hir_token_pos[second_if] < parsed.hir_token_pos[node]
                && parsed.hir_token_end[node] <= parsed.hir_token_end[function_node]
        })
        .count();
    assert!(
        standalone_blocks_after_second_if >= 2,
        "fixture should retain the second then block and following standalone block as \
         source-addressable block records"
    );
}

#[test]
fn parser_hir_method_receiver_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::pair;

pub struct Pair {
    left: i32,
}
"#,
        r#"
module app::main;
import core::pair;

fn main(pair: Pair) -> i32 {
    return pair.project(1, 2);
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        1,
        "fixture should publish exactly one private function item in the second source"
    );
    let function_node = function_nodes[0];

    let call_nodes = parsed
        .hir_call_arg_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 2 && parsed.hir_node_file_id[node] == 1).then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        call_nodes.len(),
        1,
        "fixture should publish exactly one two-argument call in the second source"
    );
    let call_node = call_nodes[0];
    assert_eq!(
        parsed.hir_kind[call_node], HIR_NODE_CALL_EXPR,
        "call argument metadata should attach to the parser-owned call HIR node"
    );
    assert_eq!(
        parsed.hir_node_file_id[call_node], parsed.hir_item_file_id[function_node],
        "call expression should retain the owning source-pack file id"
    );
    assert!(
        (parsed.hir_node_file_id[call_node] as usize) < source_count,
        "call expression should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        call_node,
        "method call expression",
    );

    let callee_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_call_callee_node[call_node],
        "method call callee",
    );
    assert_eq!(
        parsed.hir_kind[callee_node], HIR_NODE_MEMBER_EXPR,
        "method-call callee should be the parser-owned member HIR node"
    );
    assert_eq!(
        parsed.hir_node_file_id[callee_node], parsed.hir_node_file_id[call_node],
        "member callee should retain the call-site source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        callee_node,
        "method callee member",
    );

    let receiver_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_member_receiver_node[callee_node],
        "method receiver",
    );
    assert_eq!(
        parsed.hir_kind[receiver_node], HIR_NODE_NAME_EXPR,
        "fixture receiver should be the parser-owned name expression"
    );
    assert_eq!(
        parsed.hir_node_file_id[receiver_node], parsed.hir_node_file_id[callee_node],
        "receiver row should inherit the member expression source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        receiver_node,
        "method receiver",
    );

    let receiver_token = parsed.hir_member_receiver_token[callee_node];
    let member_token = parsed.hir_member_name_token[callee_node];
    assert_ne!(
        receiver_token, INVALID,
        "member receiver record should publish a receiver token"
    );
    assert_ne!(
        member_token, INVALID,
        "member receiver record should publish the member-name token"
    );
    assert_eq!(
        receiver_token, parsed.hir_token_pos[receiver_node],
        "receiver token should come from the receiver HIR row"
    );
    assert!(
        receiver_token < member_token
            && parsed.hir_token_pos[callee_node] <= member_token
            && member_token < parsed.hir_token_end[callee_node],
        "receiver token should precede the member name, and the member name should stay inside the member expression span"
    );

    let owned_member_receiver_rows = parsed
        .hir_member_receiver_node
        .iter()
        .enumerate()
        .filter(|&(node, &receiver)| {
            receiver != INVALID && parsed.hir_kind[node] == HIR_NODE_MEMBER_EXPR
        })
        .count();
    assert_eq!(
        owned_member_receiver_rows, 1,
        "fixture should not publish extra member receiver records"
    );
}

#[test]
fn parser_hir_method_receiver_record_feeds_type_checking_not_callee_spelling() {
    let positive = [r#"
module app::main;

struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(&self, value: i32) -> bool {
        return value >= self.start && value < self.end;
    }
}

fn contains(value: bool) -> bool {
    return value;
}

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn main() -> i32 {
    if (make_range().contains(2)) {
        return 1;
    }
    return 0;
}
"#];

    assert_source_pack_type_checks(
        &positive,
        "method calls should use the receiver-selected method, not a same-spelled global function",
    );

    let negative = [r#"
module app::main;

struct Range {
    start: i32,
    end: i32,
}

impl Range {
    fn contains(&self, value: bool) -> bool {
        return value;
    }
}

fn contains(value: i32) -> bool {
    return value >= 0;
}

fn make_range() -> Range {
    return Range { start: 1, end: 4 };
}

fn main() -> i32 {
    if (make_range().contains(2)) {
        return 1;
    }
    return 0;
}
"#];

    assert_source_pack_type_rejects(
        &negative,
        "same-spelled global function must not make a receiver-selected method argument type-check",
    );
}

#[test]
fn parser_hir_call_argument_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::math;

pub fn choose(a: i32, b: i32, c: i32) -> i32 {
    return a;
}
"#,
        r#"
module app::main;
import core::math;

fn main(left: i32, right: i32) -> i32 {
    return choose(left, 2, right);
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        1,
        "fixture should publish exactly one private function item in the second source"
    );
    let function_node = function_nodes[0];

    let call_nodes = parsed
        .hir_call_arg_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 3
                && parsed.hir_kind[node] == HIR_NODE_CALL_EXPR
                && parsed.hir_node_file_id[node] == 1)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        call_nodes.len(),
        1,
        "fixture should publish exactly one three-argument call in the second source"
    );
    let call_node = call_nodes[0];
    assert_eq!(
        parsed.hir_node_file_id[call_node], parsed.hir_item_file_id[function_node],
        "call expression should retain the owning source-pack file id"
    );
    assert!(
        (parsed.hir_node_file_id[call_node] as usize) < source_count,
        "call expression should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        call_node,
        "call expression",
    );

    let callee_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_call_callee_node[call_node],
        "call callee",
    );
    assert_eq!(
        parsed.hir_node_file_id[callee_node], parsed.hir_node_file_id[call_node],
        "call callee should inherit the call-site source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, callee_node, "call callee");

    let mut args = parsed
        .hir_call_arg_parent_call
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == call_node).then_some(node))
        .collect::<Vec<_>>();
    args.sort_unstable_by_key(|&node| parsed.hir_call_arg_ordinal[node]);

    assert_eq!(args.len(), 3, "call should own exactly three argument rows");
    assert_eq!(
        parsed.hir_call_arg_start[call_node] as usize, args[0],
        "call argument start should point at ordinal zero"
    );

    let mut previous_start = None;
    for (expected_ordinal, arg_node) in args.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_call_arg_ordinal[arg_node], expected_ordinal as u32,
            "call argument {arg_node} should publish a contiguous source-order ordinal"
        );
        assert_eq!(
            parsed.hir_kind[arg_node], HIR_NODE_EXPR,
            "call argument {arg_node} should be a parser-owned expression HIR row"
        );
        assert_eq!(
            parsed.hir_node_file_id[arg_node], parsed.hir_node_file_id[call_node],
            "call argument {arg_node} should inherit the call-site source-pack file id"
        );
        assert!(
            (parsed.hir_node_file_id[arg_node] as usize) < source_count,
            "call argument {arg_node} should retain a bounded source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            call_node,
            arg_node,
            "call argument",
        );

        let arg_end = parsed.hir_call_arg_end[arg_node];
        assert_ne!(
            arg_end, INVALID,
            "call argument {arg_node} should publish an end token"
        );
        assert!(
            parsed.hir_token_pos[arg_node] < arg_end && arg_end <= parsed.hir_token_end[call_node],
            "call argument {arg_node} end token should stay inside the owning call span"
        );
        assert_eq!(
            arg_end, parsed.hir_token_end[arg_node],
            "call argument {arg_node} end token should reuse the parser-owned HIR span end"
        );
        if let Some(previous_start) = previous_start {
            assert!(
                previous_start < parsed.hir_token_pos[arg_node],
                "call argument ordinals should follow source order"
            );
        }
        previous_start = Some(parsed.hir_token_pos[arg_node]);
    }

    let owned_call_arg_rows = parsed
        .hir_call_arg_parent_call
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        owned_call_arg_rows, 3,
        "fixture should not publish extra call argument owner rows"
    );
}

#[test]
fn parser_hir_array_literal_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        "module core::seed;\npub fn zero() -> i32 { return 0; }\n",
        r#"
module app::main;

fn main(values: [i32; 3]) -> i32 {
    let local: [i32; 3] = [1, values[0], 2];
    return local[1];
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        1,
        "fixture should publish exactly one private function item in the second source"
    );
    let function_node = function_nodes[0];

    let literal_nodes = parsed
        .hir_array_lit_element_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 3
                && parsed.hir_kind[node] == HIR_NODE_ARRAY_EXPR
                && parsed.hir_node_file_id[node] == 1)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        literal_nodes.len(),
        1,
        "fixture should publish exactly one three-element array literal in the second source"
    );
    let literal_node = literal_nodes[0];
    assert_eq!(
        parsed.hir_node_file_id[literal_node], parsed.hir_item_file_id[function_node],
        "array literal should retain the owning source-pack file id"
    );
    assert!(
        (parsed.hir_node_file_id[literal_node] as usize) < source_count,
        "array literal should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        literal_node,
        "array literal",
    );

    let mut elements = parsed
        .hir_array_element_parent_lit
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == literal_node).then_some(node))
        .collect::<Vec<_>>();
    elements.sort_unstable_by_key(|&node| parsed.hir_array_element_ordinal[node]);

    assert_eq!(
        elements.len(),
        3,
        "array literal should own exactly three element rows"
    );
    assert_eq!(
        parsed.hir_array_lit_first_element[literal_node] as usize, elements[0],
        "array literal first-element record should point at ordinal zero"
    );

    let mut previous_start = None;
    for (expected_ordinal, element_node) in elements.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_kind[element_node], HIR_NODE_EXPR,
            "array element {element_node} should be a parser-owned expression HIR row"
        );
        assert_eq!(
            parsed.hir_node_file_id[element_node], parsed.hir_node_file_id[literal_node],
            "array element {element_node} should inherit the literal source-pack file id"
        );
        assert!(
            (parsed.hir_node_file_id[element_node] as usize) < source_count,
            "array element {element_node} should retain a bounded source-pack file id"
        );
        assert_eq!(
            parsed.hir_array_element_ordinal[element_node], expected_ordinal as u32,
            "array element {element_node} should publish a contiguous source-order ordinal"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            literal_node,
            element_node,
            "array element",
        );
        if let Some(previous_start) = previous_start {
            assert!(
                previous_start < parsed.hir_token_pos[element_node],
                "array element ordinals should follow source order"
            );
        }
        previous_start = Some(parsed.hir_token_pos[element_node]);
    }

    for pair in elements.windows(2) {
        assert_eq!(
            parsed.hir_array_element_next[pair[0]] as usize, pair[1],
            "array element next-link should follow source order"
        );
    }
    assert_eq!(
        parsed.hir_array_element_next[*elements.last().unwrap()],
        INVALID,
        "last array element should close the element chain"
    );

    let owned_array_element_rows = parsed
        .hir_array_element_parent_lit
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        owned_array_element_rows, 3,
        "fixture should not publish extra array element owner rows"
    );
}

#[test]
fn parser_hir_array_literal_local_declaration_context_feeds_type_checking() {
    let source_count = 2;
    let decoy = "module core::seed;\npub fn seed(value: i32) -> i32 { return value; }\n";
    let positive_app = r#"
module app::main;

fn main(seed: i32) -> i32 {
    let values: [i32; 3] = [1, seed, 3];
    return values[1];
}
"#;
    let positive_sources = [decoy, positive_app];
    let parsed = parse_resident_source_pack(&positive_sources);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private app function item");
    assert!(
        (parsed.hir_item_file_id[function_node] as usize) < source_count,
        "function item should retain a bounded source-pack file id"
    );

    let let_nodes = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_LET
                && parsed.hir_kind[node] == HIR_NODE_LET_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        let_nodes.len(),
        1,
        "fixture should publish exactly one app local declaration record"
    );
    let let_node = let_nodes[0];
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        let_node,
        "local declaration",
    );

    let local_name_token = parsed.hir_stmt_record_operand0[let_node];
    assert_ne!(
        local_name_token, INVALID,
        "local declaration record should publish the declared name token"
    );
    assert!(
        parsed.hir_token_pos[let_node] <= local_name_token
            && local_name_token < parsed.hir_token_end[let_node],
        "local declaration name token should stay inside the local statement span"
    );

    let init_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand1[let_node],
        "local initializer expression",
    );
    assert_eq!(
        parsed.hir_node_file_id[init_expr], parsed.hir_node_file_id[let_node],
        "local initializer should inherit the local declaration source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        let_node,
        init_expr,
        "local initializer expression",
    );
    let declared_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand2[let_node],
        "local declared type",
    );
    assert_eq!(
        parsed.hir_kind[declared_type], HIR_NODE_TYPE,
        "local declaration record should point at a parser-owned type HIR row"
    );
    assert_eq!(
        parsed.hir_type_form[declared_type], HIR_TYPE_FORM_ARRAY,
        "local declaration type should publish the array type form"
    );
    assert_eq!(
        parsed.hir_node_file_id[declared_type], parsed.hir_node_file_id[let_node],
        "local declared type should inherit the local declaration source-pack file id"
    );
    let element_type = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_type_value_node[declared_type],
        "local array element type",
    );
    assert_eq!(
        parsed.hir_kind[element_type], HIR_NODE_TYPE,
        "local array type record should point at a parser-owned element type row"
    );
    assert_eq!(
        parsed.hir_type_form[element_type], HIR_TYPE_FORM_PATH,
        "local array element type should publish its path-type form"
    );
    assert_eq!(
        parsed.hir_node_file_id[element_type], parsed.hir_node_file_id[declared_type],
        "local array element type should inherit the declaration source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        declared_type,
        element_type,
        "local array element type",
    );
    let len_token = parsed.hir_type_len_token[declared_type];
    assert_ne!(
        len_token, INVALID,
        "array type should publish its length token"
    );
    assert!(
        parsed.hir_token_pos[declared_type] <= len_token
            && len_token < parsed.hir_token_end[declared_type],
        "array length token should stay inside the parser-owned array type span"
    );
    assert_eq!(
        parsed.hir_type_len_value[declared_type], 3,
        "array type should publish the parsed length value for type-check consumers"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        let_node,
        declared_type,
        "local declared type",
    );
    assert!(
        local_name_token < parsed.hir_token_pos[declared_type],
        "local declared type should follow the local name in source order"
    );
    assert!(
        parsed.hir_token_end[declared_type] <= parsed.hir_token_pos[init_expr],
        "local declared type should precede the initializer expression"
    );

    let literal_node = resolve_forward_expr_record(&parsed, init_expr, "local initializer");
    assert_eq!(
        parsed.hir_kind[literal_node], HIR_NODE_ARRAY_EXPR,
        "local initializer should resolve through expression records to the array literal"
    );
    assert_eq!(
        parsed.hir_node_file_id[literal_node], parsed.hir_node_file_id[let_node],
        "array literal should retain the local declaration source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        let_node,
        literal_node,
        "array literal initializer",
    );
    assert_eq!(
        parsed.hir_array_lit_element_count[literal_node], 3,
        "local array literal should publish the annotated declaration length"
    );

    let mut elements = parsed
        .hir_array_element_parent_lit
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == literal_node).then_some(node))
        .collect::<Vec<_>>();
    elements.sort_unstable_by_key(|&node| parsed.hir_array_element_ordinal[node]);
    assert_eq!(
        elements.len(),
        3,
        "local array literal should own exactly three element records"
    );
    assert_eq!(
        parsed.hir_array_lit_first_element[literal_node] as usize, elements[0],
        "local array literal first-element record should point at ordinal zero"
    );
    for (expected_ordinal, element_node) in elements.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_array_element_ordinal[element_node], expected_ordinal as u32,
            "local array literal element {element_node} should publish a source-order ordinal"
        );
        assert_eq!(
            parsed.hir_node_file_id[element_node], parsed.hir_node_file_id[let_node],
            "local array literal element {element_node} should inherit the declaration file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            literal_node,
            element_node,
            "local array literal element",
        );
    }

    common::type_check_source_pack_with_timeout(&positive_sources)
        .expect("type checking should consume the parser-owned local array initializer context");

    let negative_app = r#"
module app::main;

fn main(seed: i32) -> i32 {
    let values: [i32; 4] = [1, seed, 3];
    return values[1];
}
"#;
    let err = common::type_check_source_pack_with_timeout(&[decoy, negative_app]).expect_err(
        "array literal length should be checked through the local declaration initializer record",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            assert_eq!(diagnostic.message, "type mismatch");
            let label = diagnostic
                .primary_label
                .expect("type mismatch should carry a primary source label");
            assert_eq!(label.message, "expected a different type here");
            assert!(label.line > 0, "diagnostic should be source-spanned");
            assert!(label.column > 0, "diagnostic should be source-spanned");
            assert!(label.length > 0, "diagnostic span should be non-empty");
        }
        other => panic!("expected stable type-mismatch diagnostic, got {other:?}"),
    }
}

#[test]
fn parser_hir_assignment_records_publish_target_rhs_and_operator_in_source_packs() {
    let source_count = 2;
    let decoy = r#"
module lib::decoy;

pub fn hold(delta: i32) -> i32 {
    return delta;
}
"#;
    let positive_app = r#"
module app::main;

fn main(seed: i32, delta: i32) -> i32 {
    let value: i32 = seed;
    value = value + delta;
    return value;
}
"#;
    let positive_sources = [decoy, positive_app];
    let parsed = parse_resident_source_pack(&positive_sources);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private app function item");
    assert!(
        (parsed.hir_item_file_id[function_node] as usize) < source_count,
        "function item should retain a bounded source-pack file id"
    );

    let assign_nodes = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_ASSIGN
                && parsed.hir_kind[node] == HIR_NODE_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        assign_nodes.len(),
        1,
        "fixture should publish exactly one app assignment statement record"
    );
    let assign_node = assign_nodes[0];
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        assign_node,
        "assignment statement",
    );
    assert_eq!(
        parsed.hir_stmt_record_operand2[assign_node], ASSIGN_OP_SET,
        "assignment record should publish the assignment operator tag"
    );

    let target_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[assign_node],
        "assignment target expression",
    );
    let rhs_expr = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand1[assign_node],
        "assignment rhs expression",
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        assign_node,
        target_expr,
        "assignment target expression",
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        assign_node,
        rhs_expr,
        "assignment rhs expression",
    );

    let target_name = resolve_forward_expr_record(&parsed, target_expr, "assignment target");
    assert_eq!(
        parsed.hir_expr_record_form[target_name], HIR_EXPR_FORM_NAME,
        "assignment target should resolve through expression records to the local name"
    );
    assert_expr_record_value_token_inside(&parsed, target_name, "assignment target");

    let add_node = resolve_forward_expr_record(&parsed, rhs_expr, "assignment rhs");
    assert_eq!(
        parsed.hir_expr_record_form[add_node], HIR_EXPR_FORM_ADD,
        "assignment rhs should resolve through expression records to the add operator"
    );
    let add_left = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_left[add_node],
            "assignment rhs left operand",
        ),
        "assignment rhs left operand",
    );
    let add_right = resolve_forward_expr_record(
        &parsed,
        assert_valid_source_pack_record_index(
            &parsed,
            parsed.hir_expr_record_right[add_node],
            "assignment rhs right operand",
        ),
        "assignment rhs right operand",
    );
    for (node, label) in [
        (add_left, "assignment rhs left operand"),
        (add_right, "assignment rhs right operand"),
    ] {
        assert_eq!(
            parsed.hir_expr_record_form[node], HIR_EXPR_FORM_NAME,
            "{label} should resolve through expression records to a local name"
        );
        assert_eq!(
            parsed.hir_node_file_id[node], parsed.hir_node_file_id[assign_node],
            "{label} should inherit the assignment source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, assign_node, node, label);
        assert_expr_record_value_token_inside(&parsed, node, label);
    }

    common::type_check_source_pack_with_timeout(&positive_sources)
        .expect("type checking should accept the parser-owned assignment expression records");

    let negative_app = r#"
module app::main;

fn main(seed: i32, delta: bool) -> i32 {
    let value: i32 = seed;
    value = delta;
    return value;
}
"#;
    let err = common::type_check_source_pack_with_timeout(&[decoy, negative_app]).expect_err(
        "same-spelled i32 parameter in another source must not make a bool assignment type-check",
    );
    match err {
        CompileError::Diagnostic(diagnostic) => {
            assert_eq!(diagnostic.code, "LNC0006");
            assert_eq!(diagnostic.message, "type mismatch");
            let label = diagnostic
                .primary_label
                .expect("type mismatch should carry a primary source label");
            assert_eq!(label.message, "expected a different type here");
            assert!(label.line > 0, "diagnostic should be source-spanned");
            assert!(label.column > 0, "diagnostic should be source-spanned");
            assert!(label.length > 0, "diagnostic span should be non-empty");
        }
        other => panic!("expected stable assignment diagnostic, got {other:?}"),
    }
}

#[test]
fn parser_hir_loop_control_statement_records_are_source_addressable_in_source_packs() {
    let source_count = 1;
    let parsed = parse_resident_source_pack(&[r#"
module app::main;

fn main(limit: i32) -> i32 {
    let i: i32 = 0;
    while (i < limit) {
        i += 1;
        if (i == 2) {
            continue;
        }
        if (i == 4) {
            break;
        }
    }
    return i;
}
"#]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private function item");
    assert!(
        (parsed.hir_item_file_id[function_node] as usize) < source_count,
        "function item should retain a bounded source-pack file id"
    );

    let while_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_WHILE
                && parsed.hir_kind[node] == HIR_NODE_WHILE_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .expect("fixture should publish one parser-owned while statement record");
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        while_node,
        "while statement",
    );

    let condition_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand0[while_node],
        "while condition",
    );
    assert_eq!(
        parsed.hir_kind[condition_node], HIR_NODE_EXPR,
        "while record should point at a parser-owned condition expression"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        while_node,
        condition_node,
        "while condition",
    );

    let body_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand1[while_node],
        "while body",
    );
    assert_source_pack_hir_child_span_inside_owner(&parsed, while_node, body_node, "while body");
    assert_eq!(
        parsed.hir_stmt_record_operand2[while_node], INVALID,
        "while record should leave the unused operand empty"
    );

    let continue_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_CONTINUE
                && parsed.hir_kind[node] == HIR_NODE_CONTINUE_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .expect("fixture should publish one continue statement record");
    let break_node = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_BREAK
                && parsed.hir_kind[node] == HIR_NODE_BREAK_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .expect("fixture should publish one break statement record");

    assert!(
        parsed.hir_token_pos[continue_node] < parsed.hir_token_pos[break_node],
        "loop-control statement records should retain source order"
    );
    for (node, expected_kind, label) in [
        (
            continue_node,
            STMT_RECORD_KIND_CONTINUE,
            "continue statement",
        ),
        (break_node, STMT_RECORD_KIND_BREAK, "break statement"),
    ] {
        assert_eq!(
            parsed.hir_stmt_record_kind[node], expected_kind,
            "{label} should publish its stable statement record kind"
        );
        assert_eq!(
            parsed.hir_node_file_id[node], parsed.hir_node_file_id[while_node],
            "{label} should inherit the loop source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, body_node, node, label);
        assert_eq!(
            parsed.hir_stmt_record_operand0[node], INVALID,
            "{label} should not publish a synthetic operand"
        );
        assert_eq!(
            parsed.hir_stmt_record_operand1[node], INVALID,
            "{label} should not publish a synthetic operand"
        );
        assert_eq!(
            parsed.hir_stmt_record_operand2[node], INVALID,
            "{label} should not publish a synthetic operand"
        );
    }

    let loop_control_records = parsed
        .hir_stmt_record_kind
        .iter()
        .filter(|&&kind| kind == STMT_RECORD_KIND_BREAK || kind == STMT_RECORD_KIND_CONTINUE)
        .count();
    assert_eq!(
        loop_control_records, 2,
        "fixture should not publish extra loop-control statement records"
    );
}

#[test]
fn parser_hir_for_statement_records_scope_loop_binding_to_body() {
    let source_count = 2;
    let decoy = r#"
module lib::decoy;

pub fn value() -> i32 {
    return 9;
}
"#;
    let positive_app = r#"
module app::main;

fn main(values: [i32; 3]) -> i32 {
    let total: i32 = 0;
    for value in values {
        total += value;
    }
    return total;
}
"#;
    let positive_sources = [decoy, positive_app];
    let parsed = parse_resident_source_pack(&positive_sources);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_node = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .find_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .expect("fixture should publish one private app function item");
    assert!(
        (parsed.hir_item_file_id[function_node] as usize) < source_count,
        "function item should retain a bounded source-pack file id"
    );

    let for_nodes = parsed
        .hir_stmt_record_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == STMT_RECORD_KIND_FOR
                && parsed.hir_kind[node] == HIR_NODE_FOR_STMT
                && parsed.hir_node_file_id[node] == parsed.hir_item_file_id[function_node])
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        for_nodes.len(),
        1,
        "fixture should publish exactly one app for-statement record"
    );
    let for_node = for_nodes[0];
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        for_node,
        "for statement",
    );

    let binding_token = parsed.hir_stmt_record_operand0[for_node];
    let iterable_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand1[for_node],
        "for iterable path",
    );
    let body_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_stmt_record_operand2[for_node],
        "for body",
    );
    assert_ne!(
        binding_token, INVALID,
        "for statement record should publish the loop binding token"
    );
    assert_eq!(
        parsed.hir_kind[iterable_node], HIR_NODE_PATH_EXPR,
        "for statement record should publish the parser-owned iterable path row"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        for_node,
        iterable_node,
        "for iterable path",
    );
    assert_eq!(
        parsed.hir_kind[body_node], HIR_NODE_BLOCK,
        "for statement record should point at the parser-owned body block"
    );
    assert_eq!(
        parsed.hir_node_file_id[for_node], parsed.hir_item_file_id[function_node],
        "for statement should retain the owning source-pack file id"
    );
    assert_eq!(
        parsed.hir_node_file_id[body_node], parsed.hir_node_file_id[for_node],
        "for body should inherit the for statement source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(&parsed, for_node, body_node, "for body");
    assert!(
        parsed.hir_token_pos[for_node] < binding_token
            && binding_token < parsed.hir_token_pos[iterable_node],
        "for binding token should precede the iterable path token inside the statement span"
    );
    assert!(
        parsed.hir_token_end[iterable_node] <= parsed.hir_token_pos[body_node],
        "for iterable path token should precede the body block"
    );
    assert!(
        parsed.hir_token_pos[for_node] <= binding_token
            && binding_token < parsed.hir_token_end[for_node],
        "for binding token should stay inside the statement span"
    );
    assert!(
        parsed.hir_token_pos[for_node] <= parsed.hir_token_pos[iterable_node]
            && parsed.hir_token_end[iterable_node] <= parsed.hir_token_end[for_node],
        "for iterable path should stay inside the statement span"
    );

    common::type_check_source_pack_with_timeout(&positive_sources).expect(
        "type checking should consume the parser-owned for binding record in the loop body",
    );

    let negative_app = r#"
module app::main;

fn main(values: [i32; 3]) -> i32 {
    for value in values {
        let inside: i32 = value;
    }
    return value;
}
"#;
    match common::type_check_source_pack_with_timeout(&[decoy, negative_app]) {
        Ok(()) => panic!("for loop binding must not remain visible after the parser-owned body"),
        Err(CompileError::Diagnostic(_)) | Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU type-check rejection, got {other:?}"),
    }
}

#[test]
fn parser_hir_array_index_records_feed_type_checking_not_parameter_spelling() {
    let positive_decoy = r#"
module lib::decoy;

pub fn hold(slot: bool) -> bool {
    return slot;
}
"#;
    let positive_app = r#"
module app::main;

fn main(values: [i32; 2], slot: i32) -> i32 {
    return values[slot];
}
"#;
    assert_source_pack_type_checks(
        &[positive_decoy, positive_app],
        "array indexing should use the local index expression type, not same-spelled parameters elsewhere",
    );

    let negative_decoy = r#"
module lib::decoy;

pub fn hold(slot: i32) -> i32 {
    return slot;
}
"#;
    let negative_app = r#"
module app::main;

fn main(values: [i32; 2], slot: bool) -> i32 {
    return values[slot];
}
"#;
    assert_source_pack_type_rejects(
        &[negative_decoy, negative_app],
        "same-spelled i32 parameter in another source must not make a bool index type-check",
    );
}

#[test]
fn parser_hir_match_payload_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::maybe;

pub enum MaybePair {
    Pair(i32, i32),
    Empty,
}
"#,
        r#"
module app::main;
import core::maybe;

fn main(value: MaybePair) -> i32 {
    return match (value) {
        Pair(left, right) -> left,
        Empty -> 0,
    };
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        1,
        "fixture should publish exactly one private function item in the second source"
    );
    let function_node = function_nodes[0];

    let match_nodes = parsed
        .hir_match_arm_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 2
                && parsed.hir_kind[node] == HIR_NODE_MATCH_EXPR
                && parsed.hir_node_file_id[node] == 1)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        match_nodes.len(),
        1,
        "fixture should publish exactly one two-arm match expression in the second source"
    );
    let match_node = match_nodes[0];
    assert_eq!(
        parsed.hir_node_file_id[match_node], parsed.hir_item_file_id[function_node],
        "match expression should retain the owning source-pack file id"
    );
    assert!(
        (parsed.hir_node_file_id[match_node] as usize) < source_count,
        "match expression should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        match_node,
        "match expression",
    );

    let scrutinee_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_match_scrutinee_node[match_node],
        "match scrutinee",
    );
    assert_eq!(
        parsed.hir_kind[scrutinee_node], HIR_NODE_EXPR,
        "match scrutinee should be a parser-owned expression HIR row"
    );
    assert_eq!(
        parsed.hir_node_file_id[scrutinee_node], parsed.hir_node_file_id[match_node],
        "match scrutinee should inherit the match expression source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        match_node,
        scrutinee_node,
        "match scrutinee",
    );

    let first_arm = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_match_arm_start[match_node],
        "first match arm",
    );
    let second_arm = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_match_arm_next[first_arm],
        "second match arm",
    );
    assert_eq!(
        parsed.hir_match_arm_next[second_arm], INVALID,
        "last match arm should close the source-order arm chain"
    );
    assert!(
        parsed.hir_token_pos[first_arm] < parsed.hir_token_pos[second_arm],
        "match arm chain should follow source order"
    );

    for arm in [first_arm, second_arm] {
        assert_eq!(
            parsed.hir_node_file_id[arm], parsed.hir_node_file_id[match_node],
            "match arm {arm} should inherit the match expression source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(&parsed, match_node, arm, "match arm");

        let pattern_node = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_match_arm_pattern_node[arm],
            "match arm pattern",
        );
        let result_node = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_match_arm_result_node[arm],
            "match arm result",
        );
        assert_eq!(
            parsed.hir_node_file_id[pattern_node], parsed.hir_node_file_id[arm],
            "match arm pattern should inherit the arm source-pack file id"
        );
        assert_eq!(
            parsed.hir_node_file_id[result_node], parsed.hir_node_file_id[arm],
            "match arm result should inherit the arm source-pack file id"
        );
        assert_eq!(
            parsed.hir_kind[result_node], HIR_NODE_EXPR,
            "match arm result should be a parser-owned expression HIR row"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            arm,
            pattern_node,
            "match arm pattern",
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            arm,
            result_node,
            "match arm result",
        );
    }

    assert_eq!(
        parsed.hir_match_arm_payload_count[first_arm], 2,
        "tuple-pattern match arm should publish two payload rows"
    );
    assert_eq!(
        parsed.hir_match_arm_payload_count[second_arm], 0,
        "unit-pattern match arm should not publish payload rows"
    );
    assert_eq!(
        parsed.hir_match_arm_payload_start[second_arm], INVALID,
        "unit-pattern match arm should not publish a payload start"
    );

    let mut payloads = parsed
        .hir_match_payload_owner_arm
        .iter()
        .enumerate()
        .filter_map(|(node, &owner)| (owner as usize == first_arm).then_some(node))
        .collect::<Vec<_>>();
    payloads.sort_unstable_by_key(|&node| parsed.hir_match_payload_ordinal[node]);
    assert_eq!(
        payloads.len(),
        2,
        "tuple-pattern match arm should own exactly two payload rows"
    );
    assert_eq!(
        parsed.hir_match_arm_payload_start[first_arm] as usize, payloads[0],
        "match arm payload start should point at ordinal zero"
    );
    assert!(
        parsed.hir_token_pos[payloads[0]] < parsed.hir_token_pos[payloads[1]],
        "match payload rows should be linked in source order"
    );

    for (expected_ordinal, payload_node) in payloads.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_match_payload_ordinal[payload_node], expected_ordinal as u32,
            "match payload {payload_node} should publish a contiguous source-order ordinal"
        );
        assert_eq!(
            parsed.hir_match_payload_match_node[payload_node] as usize, match_node,
            "match payload {payload_node} should point back to the owning match expression"
        );
        assert_eq!(
            parsed.hir_node_file_id[payload_node], parsed.hir_node_file_id[first_arm],
            "match payload {payload_node} should inherit the arm source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            first_arm,
            payload_node,
            "match payload",
        );
    }

    let owned_payload_rows = parsed
        .hir_match_payload_owner_arm
        .iter()
        .filter(|&&owner| owner != INVALID)
        .count();
    assert_eq!(
        owned_payload_rows, 2,
        "fixture should not publish extra match payload owner rows"
    );
}

#[test]
fn parser_hir_match_payload_records_feed_type_checking_not_variant_name_decoys() {
    let positive_decoy = r#"
module lib::decoy;

pub enum Decoy {
    Hit(bool),
    Miss,
}
"#;
    let positive_app = r#"
module app::main;

enum Maybe {
    Hit(i32),
    Miss,
}

fn main(value: Maybe) -> i32 {
    return match (value) {
        Hit(payload) -> payload,
        Miss -> 0,
    };
}
"#;
    assert_source_pack_type_checks(
        &[positive_decoy, positive_app],
        "match payloads should be typed from the matched enum, not an earlier same-name decoy variant",
    );

    let negative_decoy = r#"
module lib::decoy;

pub enum Decoy {
    Hit(i32),
    Miss,
}
"#;
    let negative_app = r#"
module app::main;

enum Maybe {
    Hit(bool),
    Miss,
}

fn main(value: Maybe) -> i32 {
    return match (value) {
        Hit(payload) -> payload,
        Miss -> 0,
    };
}
"#;
    assert_source_pack_type_rejects(
        &[negative_decoy, negative_app],
        "same-name decoy variant must not make a bool match payload type-check as i32",
    );
}

#[test]
fn parser_hir_struct_field_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::pair;

pub struct Pair {
    left: i32,
    flag: bool,
}
"#,
        r#"
module app::main;
import core::pair;

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, flag: true };
    return pair.left;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let struct_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_STRUCT
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PUBLIC)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        struct_nodes.len(),
        1,
        "fixture should publish exactly one public struct item in the first source"
    );
    let struct_node = struct_nodes[0];
    assert_eq!(
        parsed.hir_kind[struct_node], HIR_NODE_STRUCT_ITEM,
        "struct item metadata should attach to the parser-owned struct HIR node"
    );
    assert_eq!(
        parsed.hir_item_namespace[struct_node], HIR_ITEM_NAMESPACE_TYPE,
        "struct items should publish type-namespace records"
    );
    assert_eq!(
        parsed.hir_node_file_id[struct_node], parsed.hir_item_file_id[struct_node],
        "struct HIR row should retain the same source-pack file id as its item record"
    );
    assert!(
        (parsed.hir_item_file_id[struct_node] as usize) < source_count,
        "struct item should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, struct_node, "struct item");

    let mut decl_fields = parsed
        .hir_struct_field_parent_struct
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == struct_node).then_some(node))
        .collect::<Vec<_>>();
    decl_fields.sort_unstable_by_key(|&node| parsed.hir_struct_field_ordinal[node]);
    assert_eq!(
        decl_fields.len(),
        2,
        "struct declaration should own exactly two field records"
    );
    assert_eq!(
        parsed.hir_struct_decl_field_count[struct_node], 2,
        "struct declaration should publish its field count"
    );
    assert_eq!(
        parsed.hir_struct_decl_field_start[struct_node] as usize, decl_fields[0],
        "struct declaration field start should point at ordinal zero"
    );

    let mut previous_decl_start = None;
    for (expected_ordinal, field_node) in decl_fields.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_struct_field_ordinal[field_node], expected_ordinal as u32,
            "struct field {field_node} should publish a contiguous source-order ordinal"
        );
        assert_eq!(
            parsed.hir_node_file_id[field_node], parsed.hir_node_file_id[struct_node],
            "struct field {field_node} should inherit the struct source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            struct_node,
            field_node,
            "struct declaration field",
        );

        let type_node = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_struct_field_type_node[field_node],
            "struct declaration field type",
        );
        assert_eq!(
            parsed.hir_kind[type_node], HIR_NODE_TYPE,
            "struct field {field_node} type should be a parser-owned type HIR row"
        );
        assert_eq!(
            parsed.hir_node_file_id[type_node], parsed.hir_node_file_id[field_node],
            "struct field type {type_node} should inherit the field source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            field_node,
            type_node,
            "struct declaration field type",
        );

        if let Some(previous_start) = previous_decl_start {
            assert!(
                previous_start < parsed.hir_token_pos[field_node],
                "struct declaration field ordinals should follow source order"
            );
        }
        previous_decl_start = Some(parsed.hir_token_pos[field_node]);
    }

    let function_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_FN
                && parsed.hir_item_file_id[node] == 1
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PRIVATE)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        function_nodes.len(),
        1,
        "fixture should publish exactly one private function item in the second source"
    );
    let function_node = function_nodes[0];

    let literal_nodes = parsed
        .hir_struct_lit_field_count
        .iter()
        .enumerate()
        .filter_map(|(node, &count)| {
            (count == 2
                && parsed.hir_kind[node] == HIR_NODE_STRUCT_LITERAL_EXPR
                && parsed.hir_node_file_id[node] == 1)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        literal_nodes.len(),
        1,
        "fixture should publish exactly one two-field struct literal in the second source"
    );
    let literal_node = literal_nodes[0];
    assert_eq!(
        parsed.hir_node_file_id[literal_node], parsed.hir_item_file_id[function_node],
        "struct literal should retain the owning source-pack file id"
    );
    assert_source_pack_hir_child_span_inside_owner(
        &parsed,
        function_node,
        literal_node,
        "struct literal",
    );

    let head_node = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_struct_lit_head_node[literal_node],
        "struct literal head",
    );
    assert_eq!(
        parsed.hir_node_file_id[head_node], parsed.hir_node_file_id[literal_node],
        "struct literal head should inherit the literal source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, head_node, "struct literal head");

    let first_lit_field = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_struct_lit_field_start[literal_node],
        "first struct literal field",
    );
    let second_lit_field = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_struct_lit_field_next[first_lit_field],
        "second struct literal field",
    );
    assert_eq!(
        parsed.hir_struct_lit_field_next[second_lit_field], INVALID,
        "last struct literal field should close the source-order chain"
    );
    assert!(
        parsed.hir_token_pos[first_lit_field] < parsed.hir_token_pos[second_lit_field],
        "struct literal field chain should follow source order"
    );
    assert!(
        parsed.hir_token_end[head_node] <= parsed.hir_token_pos[first_lit_field],
        "struct literal head should precede the first field record in source order"
    );

    for field_node in [first_lit_field, second_lit_field] {
        assert_eq!(
            parsed.hir_struct_lit_field_parent_lit[field_node] as usize, literal_node,
            "struct literal field {field_node} should point back to the owning literal"
        );
        assert_eq!(
            parsed.hir_node_file_id[field_node], parsed.hir_node_file_id[literal_node],
            "struct literal field {field_node} should inherit the literal source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            literal_node,
            field_node,
            "struct literal field",
        );

        let value_node = assert_valid_source_pack_hir_node_index(
            &parsed,
            parsed.hir_struct_lit_field_value_node[field_node],
            "struct literal field value",
        );
        assert_eq!(
            parsed.hir_kind[value_node], HIR_NODE_EXPR,
            "struct literal field {field_node} value should be a parser-owned expression HIR row"
        );
        assert_eq!(
            parsed.hir_node_file_id[value_node], parsed.hir_node_file_id[field_node],
            "struct literal field value {value_node} should inherit the field source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            field_node,
            value_node,
            "struct literal field value",
        );
    }

    let owned_decl_rows = parsed
        .hir_struct_field_parent_struct
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        owned_decl_rows, 2,
        "fixture should not publish extra struct declaration field owners"
    );
    let owned_literal_rows = parsed
        .hir_struct_lit_field_parent_lit
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        owned_literal_rows, 2,
        "fixture should not publish extra struct literal field owners"
    );
}

#[test]
fn parser_hir_struct_literal_readback_accepts_contiguous_field_chain() {
    validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 10, 15, 25, 20, 30],
        &[1, 40, 24, 35, 23, 34],
        &[0, 0, 0, 0, 0, 0],
        &[INVALID, 0, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID, INVALID],
        &[0, 2, 0, 0, 0, 0],
        &[INVALID, INVALID, 1, 1, INVALID, INVALID],
        &[INVALID, INVALID, 4, 5, INVALID, INVALID],
        &[INVALID, INVALID, 3, INVALID, INVALID, INVALID],
    )
    .expect("contiguous struct literal field records should decode");
}

#[test]
fn parser_hir_struct_literal_readback_rejects_missing_head_node() {
    let err = validate_hir_struct_literal_field_records(
        &[HIR_NODE_PATH_EXPR, HIR_NODE_STRUCT_LITERAL_EXPR],
        &[0, 10],
        &[1, 20],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("struct literal rows without parser-owned head nodes should fail closed");
    assert!(
        err.to_string().contains("head path node"),
        "error should describe the parser-owned struct literal head contract"
    );
}

#[test]
fn parser_hir_struct_literal_readback_rejects_missing_owned_field_rows() {
    let err = validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 10, 15, 25, 20, 30],
        &[1, 40, 24, 35, 23, 34],
        &[0, 0, 0, 0, 0, 0],
        &[INVALID, 0, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID, INVALID],
        &[0, 2, 0, 0, 0, 0],
        &[INVALID, INVALID, 1, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 4, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("missing owned struct literal field rows should fail closed");
    assert!(
        err.to_string().contains("owned field rows"),
        "error should describe the missing parser-owned struct literal field record"
    );
}

#[test]
fn parser_hir_struct_literal_readback_rejects_broken_next_chain() {
    let err = validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 10, 15, 25, 20, 30],
        &[1, 40, 24, 35, 23, 34],
        &[0, 0, 0, 0, 0, 0],
        &[INVALID, 0, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID, INVALID],
        &[0, 2, 0, 0, 0, 0],
        &[INVALID, INVALID, 1, 1, INVALID, INVALID],
        &[INVALID, INVALID, 4, 5, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("broken struct literal field next links should fail closed");
    assert!(
        err.to_string().contains("field chain ended"),
        "error should describe the broken parser-owned struct literal field chain"
    );
}

#[test]
fn parser_hir_struct_literal_readback_rejects_missing_value_edge() {
    let err = validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 10, 15, 25, 20, 30],
        &[1, 40, 24, 35, 23, 34],
        &[0, 0, 0, 0, 0, 0],
        &[INVALID, 0, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID, INVALID],
        &[0, 2, 0, 0, 0, 0],
        &[INVALID, INVALID, 1, 1, INVALID, INVALID],
        &[INVALID, INVALID, 4, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 3, INVALID, INVALID, INVALID],
    )
    .expect_err("struct literal field rows without value expressions should fail closed");
    assert!(
        err.to_string().contains("value expression"),
        "error should describe the missing parser-owned field value edge"
    );
}

#[test]
fn parser_hir_struct_literal_readback_rejects_orphan_value_edge() {
    validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 10, 15, 20, 18],
        &[1, 30, 19, 24, 19],
        &[0, 0, 0, 0, 0],
        &[INVALID, 0, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[0, 0, 0, 0, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 4, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("unowned struct literal field value edges should fail closed");
}

#[test]
fn parser_hir_struct_literal_readback_rejects_value_outside_field_span() {
    let err = validate_hir_struct_literal_field_records(
        &[
            HIR_NODE_PATH_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 10, 15, 20, 12],
        &[1, 30, 18, 25, 14],
        &[0, 0, 0, 0, 0],
        &[INVALID, 0, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID],
        &[0, 1, 0, 0, 0],
        &[INVALID, INVALID, 1, INVALID, INVALID],
        &[INVALID, INVALID, 4, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("struct literal field values outside the field span should fail closed");
    assert!(
        err.to_string().contains("falls outside the field span"),
        "error should describe the parser-owned field/value span contract"
    );
}

#[test]
fn parser_hir_item_path_readback_rejects_non_path_node_anchor() {
    let err = validate_hir_item_path_records(
        &[HIR_NODE_MODULE_ITEM, HIR_NODE_NAME_EXPR],
        &[0, 1],
        &[3, 3],
        &[0, 0],
        &[HIR_ITEM_KIND_MODULE, HIR_ITEM_KIND_NONE],
        &[0, INVALID],
        &[1, INVALID],
        &[3, INVALID],
        &[1, INVALID],
        &[HIR_ITEM_IMPORT_TARGET_NONE, HIR_ITEM_IMPORT_TARGET_NONE],
    )
    .expect_err("module/import path records should fail closed on non-path HIR anchors");
    assert!(
        err.to_string().contains("path HIR row"),
        "error should describe the parser-owned item path node-kind contract"
    );
}

#[test]
fn parser_hir_item_path_readback_rejects_import_without_supported_target_record() {
    let err = validate_hir_item_path_records(
        &[HIR_NODE_IMPORT_ITEM],
        &[0],
        &[2],
        &[0],
        &[HIR_ITEM_KIND_IMPORT],
        &[0],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[HIR_ITEM_IMPORT_TARGET_NONE],
    )
    .expect_err("import rows without parser-owned target metadata should fail closed");
    assert!(
        err.to_string().contains("no import target record"),
        "error should describe the missing parser-owned import target"
    );

    let err = validate_hir_item_path_records(
        &[HIR_NODE_IMPORT_ITEM],
        &[0],
        &[2],
        &[0],
        &[HIR_ITEM_KIND_IMPORT],
        &[0],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[HIR_ITEM_IMPORT_TARGET_STRING],
    )
    .expect_err("unsupported import target kinds should fail before source rediscovery");
    assert!(
        err.to_string().contains("unsupported string import target"),
        "error should describe the unsupported import target boundary"
    );
}

#[test]
fn parser_hir_item_path_readback_rejects_shared_path_node_anchor() {
    let err = validate_hir_item_path_records(
        &[
            HIR_NODE_MODULE_ITEM,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_IMPORT_ITEM,
        ],
        &[0, 1, 0],
        &[4, 3, 4],
        &[0, 0, 0],
        &[
            HIR_ITEM_KIND_MODULE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_IMPORT,
        ],
        &[0, INVALID, 0],
        &[1, INVALID, 1],
        &[3, INVALID, 3],
        &[1, INVALID, 1],
        &[
            HIR_ITEM_IMPORT_TARGET_NONE,
            HIR_ITEM_IMPORT_TARGET_NONE,
            HIR_ITEM_IMPORT_TARGET_PATH,
        ],
    )
    .expect_err("module/import path rows must not share parser-owned path anchors");
    assert!(
        err.to_string().contains("shares path node"),
        "error should describe ambiguous parser-owned path anchor ownership"
    );
}

#[test]
fn parser_hir_source_address_readback_rejects_public_records_out_of_flat_source_order() {
    let err = validate_hir_source_address_records(
        &[HIR_NODE_TYPE, HIR_NODE_TYPE],
        &[10, 9],
        &[11, 10],
        &[0, 0],
        &[HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_PATH],
        &[0, 0],
        &[HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_NONE],
        &[INVALID, INVALID],
    )
    .expect_err("public HIR records must stay in flat source order");
    assert!(
        err.to_string().contains("flat source order"),
        "error should describe the parser-owned flat source-order contract"
    );
}

#[test]
fn parser_hir_function_return_readback_accepts_function_extern_and_impl_method_edges() {
    validate_hir_function_return_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_TYPE,
            HIR_NODE_FN,
            HIR_NODE_TYPE,
            HIR_NODE_FN,
            HIR_NODE_TYPE,
            HIR_NODE_ITEM,
        ],
        &[0, 3, 6, 9, 12, 15, 18],
        &[5, 4, 11, 10, 17, 16, 19],
        &[0, 0, 1, 1, 2, 2, 2],
        &[
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_NONE,
        ],
        &[INVALID, 0, INVALID, 1, INVALID, 2, INVALID],
        &[1, INVALID, 3, INVALID, 5, INVALID, INVALID],
        &[
            HIR_ITEM_KIND_FN,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_EXTERN_FN,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_STRUCT,
        ],
        &[0, INVALID, 1, INVALID, INVALID, INVALID, 2],
    )
    .expect("function, extern function, and impl method return edges should decode");
}

#[test]
fn parser_hir_function_return_readback_rejects_non_function_owner() {
    let err = validate_hir_function_return_records(
        &[HIR_NODE_ITEM, HIR_NODE_TYPE],
        &[0, 1],
        &[3, 2],
        &[0, 0],
        &[HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_PATH],
        &[INVALID, 0],
        &[1, INVALID],
        &[HIR_ITEM_KIND_STRUCT, HIR_ITEM_KIND_NONE],
        &[0, INVALID],
    )
    .expect_err("return type edges from non-function item rows should fail closed");
    assert!(
        err.to_string()
            .contains("without a function or method owner"),
        "error should describe the parser-owned function return owner contract"
    );
}

#[test]
fn parser_hir_function_return_readback_rejects_shared_return_type_node() {
    let err = validate_hir_function_return_records(
        &[HIR_NODE_FN, HIR_NODE_TYPE, HIR_NODE_FN],
        &[0, 2, 0],
        &[5, 3, 6],
        &[0, 0, 0],
        &[HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_NONE],
        &[INVALID, 0, INVALID],
        &[1, INVALID, 1],
        &[HIR_ITEM_KIND_FN, HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_FN],
        &[0, INVALID, 0],
    )
    .expect_err("function return type rows must have a single parser-owned function owner");
    assert!(
        err.to_string().contains("shares return type row"),
        "error should describe the parser-owned return type ownership contract"
    );
}

#[test]
fn parser_hir_type_argument_readback_rejects_generic_args_on_non_path_type_owner() {
    let err = validate_hir_type_argument_records(
        &[HIR_NODE_NONE, HIR_NODE_TYPE, HIR_NODE_TYPE],
        &[HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_ARRAY, HIR_TYPE_FORM_PATH],
        &[INVALID, 2, INVALID],
        &[0, 1, 0],
        &[INVALID, INVALID, INVALID],
    )
    .expect_err("generic type-argument ownership must stay on path type records");
    assert!(
        err.to_string().contains("non-path type record"),
        "error should describe the parser-owned generic type owner contract"
    );
}

#[test]
fn parser_hir_expression_readback_rejects_non_expression_child_edges() {
    let err = validate_hir_expression_records(
        &[HIR_NODE_EXPR, HIR_NODE_TYPE, HIR_NODE_EXPR],
        &[0, 1, 2],
        &[5, 2, 3],
        &[0, 0, 0],
        &[HIR_EXPR_FORM_ADD, HIR_EXPR_FORM_NONE, HIR_EXPR_FORM_INT],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, INVALID, 2],
    )
    .expect_err("expression records must point at parser-owned expression rows");
    assert!(
        err.to_string().contains("non-expression HIR kind"),
        "error should describe the parser-owned expression child edge contract"
    );
}

#[test]
fn parser_hir_expression_readback_rejects_literal_forms_on_name_rows() {
    let err = validate_hir_expression_records(
        &[HIR_NODE_NAME_EXPR],
        &[0],
        &[1],
        &[0],
        &[HIR_EXPR_FORM_INT],
        &[INVALID],
        &[INVALID],
        &[0],
    )
    .expect_err("literal expression forms must stay on parser-owned literal rows");
    assert!(
        err.to_string().contains("literal value form"),
        "error should describe the parser-owned literal form owner contract"
    );
}

#[test]
fn parser_hir_expression_readback_rejects_name_forms_on_literal_rows() {
    let err = validate_hir_expression_records(
        &[HIR_NODE_LITERAL_EXPR],
        &[0],
        &[1],
        &[0],
        &[HIR_EXPR_FORM_NAME],
        &[INVALID],
        &[INVALID],
        &[0],
    )
    .expect_err("name expression forms must stay on parser-owned name/path rows");
    assert!(
        err.to_string().contains("name value form"),
        "error should describe the parser-owned name form owner contract"
    );
}

#[test]
fn parser_hir_parameter_readback_accepts_contiguous_source_addressed_records() {
    validate_hir_parameter_records(
        &[HIR_NODE_FN, HIR_NODE_PARAM, HIR_NODE_PARAM, HIR_NODE_TYPE],
        &[0, 1, 4, 6],
        &[10, 3, 8, 7],
        &[0, 0, 0, 0],
        &[
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
        ],
        &[INVALID, INVALID, INVALID, 0],
        &[INVALID, 0, 0, INVALID],
        &[INVALID, 0, 1, INVALID],
        &[INVALID, 1, 4, INVALID],
        &[INVALID, 1, 2, INVALID],
        &[INVALID, INVALID, 3, INVALID],
    )
    .expect("source-addressed parameter rows with contiguous ordinals should decode");
}

#[test]
fn parser_hir_parameter_readback_rejects_missing_record_on_param_row() {
    let err = validate_hir_parameter_records(
        &[HIR_NODE_PARAM],
        &[0],
        &[1],
        &[0],
        &[HIR_TYPE_FORM_NONE],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("parameter HIR rows without parser-owned parameter records should fail closed");
    assert!(
        err.to_string().contains("no parser-owned parameter record"),
        "error should describe the required parser-owned parameter record contract"
    );
}

#[test]
fn parser_hir_parameter_readback_rejects_duplicate_ordinals() {
    let err = validate_hir_parameter_records(
        &[HIR_NODE_FN, HIR_NODE_PARAM, HIR_NODE_PARAM],
        &[0, 1, 4],
        &[10, 2, 5],
        &[0, 0, 0],
        &[HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_NONE],
        &[INVALID, INVALID, INVALID],
        &[INVALID, 0, 0],
        &[INVALID, 0, 0],
        &[INVALID, 1, 4],
        &[INVALID, 1, 2],
        &[INVALID, INVALID, INVALID],
    )
    .expect_err("duplicate parameter ordinals should fail closed");
    assert!(
        err.to_string().contains("contiguous from zero"),
        "error should describe the parser-owned parameter ordinal contract"
    );
}

#[test]
fn parser_hir_parameter_readback_rejects_cross_file_type_edge() {
    let err = validate_hir_parameter_records(
        &[HIR_NODE_FN, HIR_NODE_PARAM, HIR_NODE_TYPE],
        &[0, 1, 3],
        &[8, 6, 5],
        &[0, 0, 1],
        &[HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_PATH],
        &[INVALID, INVALID, 1],
        &[INVALID, 0, INVALID],
        &[INVALID, 0, INVALID],
        &[INVALID, 1, INVALID],
        &[INVALID, 1, INVALID],
        &[INVALID, 2, INVALID],
    )
    .expect_err("parameter type edges crossing source-pack file ids should fail closed");
    assert!(
        err.to_string().contains("different file id"),
        "error should describe the parser-owned parameter source-file contract"
    );
}

#[test]
fn parser_hir_call_readback_rejects_zero_argument_call_without_callee() {
    let err = validate_hir_call_argument_records(
        &[HIR_NODE_CALL_EXPR],
        &[INVALID],
        &[INVALID],
        &[0],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("zero-argument call records without a callee should fail closed");
    assert!(
        err.to_string().contains("without an in-table callee"),
        "error should describe the parser-owned call callee contract"
    );
}

#[test]
fn parser_hir_array_literal_readback_rejects_count_on_non_array_owner() {
    let err = validate_hir_array_literal_records(
        &[HIR_NODE_ITEM, HIR_NODE_EXPR, HIR_NODE_EXPR],
        &[INVALID, 10, 12],
        &[INVALID, 20, 13],
        &[INVALID, 2, INVALID],
        &[0, 1, 0],
        &[INVALID, INVALID, 1],
        &[INVALID, INVALID, 0],
        &[INVALID, INVALID, INVALID],
    )
    .expect_err("array element counts on non-array HIR owners should fail closed");
    assert!(
        err.to_string().contains("array-literal HIR owner"),
        "error should describe the parser-owned array literal owner-kind contract"
    );
}

#[test]
fn parser_hir_array_literal_readback_rejects_next_chain_out_of_source_order() {
    let err = validate_hir_array_literal_records(
        &[
            HIR_NODE_NONE,
            HIR_NODE_ARRAY_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[INVALID, 10, 20, 12],
        &[INVALID, 30, 21, 13],
        &[INVALID, 2, INVALID, INVALID],
        &[0, 2, 0, 0],
        &[INVALID, INVALID, 1, 1],
        &[INVALID, INVALID, 0, 1],
        &[INVALID, INVALID, 3, INVALID],
    )
    .expect_err("array element next chains that move backward in source should fail closed");
    assert!(
        err.to_string().contains("source order"),
        "error should describe the parser-owned array element next/source-span contract"
    );
}

#[test]
fn parser_hir_match_readback_rejects_scrutinee_without_match_owner() {
    let err = validate_hir_match_records(
        &[HIR_NODE_ITEM, HIR_NODE_EXPR],
        &[0, 1],
        &[1, 2],
        &[0, 0],
        &[1, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[0, 0],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("match scrutinee edges without match owners should fail closed");
    assert!(
        err.to_string().contains("scrutinee"),
        "error should describe the orphan parser-owned match scrutinee edge"
    );
}

#[test]
fn parser_hir_match_readback_rejects_non_pattern_rows_for_match_patterns() {
    let err = validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_TYPE,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 2, 3, 6, 1],
        &[10, 9, 4, 7, 2],
        &[0; 5],
        &[4, INVALID, INVALID, INVALID, INVALID],
        &[1, INVALID, INVALID, INVALID, INVALID],
        &[1, 0, 0, 0, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[0, 0, 0, 0, 0],
        &[INVALID, 3, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("match arm pattern edges to non-pattern rows should fail closed");
    assert!(
        err.to_string().contains("non-pattern HIR kind"),
        "error should describe the parser-owned match arm pattern kind contract"
    );

    let err = validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_TYPE,
        ],
        &[0, 2, 3, 7, 1, 4],
        &[10, 9, 4, 8, 2, 5],
        &[0; 6],
        &[4, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[1, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[1, 0, 0, 0, 0, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 2, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, 5, INVALID, INVALID, INVALID, INVALID],
        &[0, 1, 0, 0, 0, 0],
        &[INVALID, 3, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 1],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID, 0],
    )
    .expect_err("match payload pattern rows with non-pattern kinds should fail closed");
    assert!(
        err.to_string().contains("payload row 5 has non-pattern"),
        "error should describe the parser-owned match payload pattern kind contract"
    );
}

#[test]
fn parser_hir_match_readback_rejects_cross_file_result_edge() {
    let err = validate_hir_match_records(
        &[
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_EXPR,
        ],
        &[0, 1, 2, 3, 6],
        &[10, 2, 9, 4, 7],
        &[0, 0, 0, 0, 1],
        &[1, INVALID, INVALID, INVALID, INVALID],
        &[2, INVALID, INVALID, INVALID, INVALID],
        &[1, 0, 0, 0, 0],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, 3, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[0, 0, 0, 0, 0],
        &[INVALID, INVALID, 4, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("match arm result edges must stay in the owning source file");
    assert!(
        err.to_string().contains("different file id"),
        "error should describe the parser-owned match source-file contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_if_then_edge_without_block_row() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_IF_STMT, HIR_NODE_EXPR, HIR_NODE_EXPR],
        &[0, 1, 3],
        &[5, 2, 4],
        &[0, 0, 0],
        &[
            STMT_RECORD_KIND_IF,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
        ],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID],
    )
    .expect_err("if statement then edges must point at parser-owned block rows");
    assert!(
        err.to_string().contains("if then arm"),
        "error should describe the parser-owned if then-arm block contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_if_else_alias_or_overlap() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_IF_STMT, HIR_NODE_EXPR, HIR_NODE_BLOCK],
        &[0, 1, 2],
        &[8, 2, 5],
        &[0, 0, 0],
        &[
            STMT_RECORD_KIND_IF,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
        ],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[INVALID, INVALID, INVALID],
    )
    .expect_err("if records must not alias one block as both then and else arms");
    assert!(
        err.to_string().contains("same block row"),
        "error should describe the parser-owned if arm aliasing contract"
    );

    let err = validate_hir_statement_records(
        &[
            HIR_NODE_IF_STMT,
            HIR_NODE_EXPR,
            HIR_NODE_BLOCK,
            HIR_NODE_BLOCK,
        ],
        &[0, 1, 4, 3],
        &[8, 2, 7, 5],
        &[0, 0, 0, 0],
        &[
            STMT_RECORD_KIND_IF,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
        ],
        &[1, INVALID, INVALID, INVALID],
        &[2, INVALID, INVALID, INVALID],
        &[3, INVALID, INVALID, INVALID],
        &[INVALID, INVALID, INVALID, INVALID],
    )
    .expect_err("if else block records must not overlap the then block");
    assert!(
        err.to_string().contains("before the then arm ended"),
        "error should describe the parser-owned if arm source-order contract"
    );
}

#[test]
fn parser_hir_statement_readback_accepts_for_path_anchor_and_body_edge() {
    validate_hir_statement_records(
        &[HIR_NODE_FOR_STMT, HIR_NODE_PATH_EXPR, HIR_NODE_BLOCK],
        &[0, 2, 3],
        &[6, 3, 6],
        &[0, 0, 0],
        &[
            STMT_RECORD_KIND_FOR,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
        ],
        &[1, INVALID, INVALID],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[6, INVALID, INVALID],
    )
    .expect("for statement records should decode when iterable path and body edges are owned");
}

#[test]
fn parser_hir_statement_readback_rejects_missing_local_declaration_scope_end() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_LET_STMT],
        &[0],
        &[3],
        &[0],
        &[STMT_RECORD_KIND_LET],
        &[1],
        &[INVALID],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("local declaration rows without parser-owned scope ends should fail closed");
    assert!(
        err.to_string().contains("declaration scope end"),
        "error should describe the parser-owned declaration scope-end contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_for_iterable_without_path_anchor() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_FOR_STMT, HIR_NODE_EXPR, HIR_NODE_BLOCK],
        &[0, 2, 3],
        &[6, 3, 6],
        &[0, 0, 0],
        &[
            STMT_RECORD_KIND_FOR,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
        ],
        &[1, INVALID, INVALID],
        &[1, INVALID, INVALID],
        &[2, INVALID, INVALID],
        &[6, INVALID, INVALID],
    )
    .expect_err("for iterable nodes without parser-owned path rows should fail closed");
    assert!(
        err.to_string().contains("for iterable path"),
        "error should describe the missing parser-owned iterable path record"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_missing_record_on_concrete_statement_row() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_RETURN_STMT],
        &[0],
        &[2],
        &[0],
        &[STMT_RECORD_KIND_NONE],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("concrete statement HIR rows without statement records should fail closed");
    assert!(
        err.to_string().contains("no parser-owned statement record"),
        "error should describe the required parser-owned statement record contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_declaration_token_outside_owner_span() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_LET_STMT],
        &[10],
        &[12],
        &[0],
        &[STMT_RECORD_KIND_LET],
        &[12],
        &[INVALID],
        &[INVALID],
        &[12],
    )
    .expect_err("statement declaration tokens outside the owner span should fail closed");
    assert!(
        err.to_string()
            .contains("let declaration token outside its statement span"),
        "error should describe the parser-owned declaration-token span contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_return_without_span() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_RETURN_STMT],
        &[INVALID],
        &[INVALID],
        &[0],
        &[STMT_RECORD_KIND_RETURN],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("return statement records without source spans should fail closed");
    assert!(
        err.to_string().contains("without a non-empty token span"),
        "error should describe the parser-owned return statement span contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_return_record_on_non_return_row() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_EXPR],
        &[0],
        &[2],
        &[0],
        &[STMT_RECORD_KIND_RETURN],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("return statement records on non-return HIR rows should fail closed");
    assert!(
        err.to_string().contains("expected"),
        "error should describe the strict parser-owned return row kind contract"
    );
}

#[test]
fn parser_hir_statement_readback_rejects_break_without_span() {
    let err = validate_hir_statement_records(
        &[HIR_NODE_BREAK_STMT],
        &[INVALID],
        &[INVALID],
        &[0],
        &[STMT_RECORD_KIND_BREAK],
        &[INVALID],
        &[INVALID],
        &[INVALID],
        &[INVALID],
    )
    .expect_err("break statement records without source spans should fail closed");
    assert!(
        err.to_string().contains("without a non-empty token span"),
        "error should describe the parser-owned break statement span contract"
    );
}

#[test]
fn parser_hir_context_relation_readback_accepts_compact_context_rows() {
    validate_hir_context_relation_records(
        &[
            HIR_NODE_FN,
            HIR_NODE_BLOCK,
            HIR_NODE_LET_STMT,
            HIR_NODE_CALL_EXPR,
            HIR_NODE_ARRAY_EXPR,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_IF_STMT,
            HIR_NODE_EXPR,
            HIR_NODE_CONST_ITEM,
        ],
        &[0, 1, 2, 3, 4, 5, 6, 7, 10],
        &[12, 9, 8, 4, 5, 6, 9, 8, 11],
        &[0; 9],
        &[
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_LET,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_IF,
            STMT_RECORD_KIND_NONE,
            STMT_RECORD_KIND_CONST,
        ],
        &[INVALID, INVALID, 2, 2, 2, 2, 6, 6, 8],
        &[INVALID, 1, 1, 1, 1, 1, 1, 1, INVALID],
        &[
            INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 6, INVALID,
        ],
        &[0, 0, 0, 0, 0, 0, 0, 0, INVALID],
        &[
            INVALID, INVALID, INVALID, 2, INVALID, INVALID, INVALID, INVALID, INVALID,
        ],
        &[
            INVALID, INVALID, INVALID, INVALID, 2, INVALID, INVALID, INVALID, INVALID,
        ],
        &[
            INVALID, INVALID, INVALID, INVALID, INVALID, 2, INVALID, INVALID, INVALID,
        ],
    )
    .expect("parser-owned context relation rows should decode when spans and owner kinds agree");
}

#[test]
fn parser_hir_context_relation_readback_rejects_malformed_context_rows() {
    validate_hir_context_relation_records(
        &[HIR_NODE_EXPR, HIR_NODE_LET_STMT],
        &[2, 0],
        &[3, 4],
        &[0, 0],
        &[STMT_RECORD_KIND_NONE, STMT_RECORD_KIND_LET],
        &[1, 1],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[1, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("context statement rows on non-call owners should fail closed");

    validate_hir_context_relation_records(
        &[HIR_NODE_CALL_EXPR, HIR_NODE_LET_STMT],
        &[2, 0],
        &[3, 4],
        &[0, 1],
        &[STMT_RECORD_KIND_NONE, STMT_RECORD_KIND_LET],
        &[1, 1],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[1, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("context statement rows crossing source-pack file ids should fail closed");
}

#[test]
fn parser_hir_context_relation_readback_rejects_stale_statement_records() {
    validate_hir_context_relation_records(
        &[HIR_NODE_CALL_EXPR, HIR_NODE_LET_STMT],
        &[2, 0],
        &[3, 4],
        &[0, 0],
        &[STMT_RECORD_KIND_NONE, STMT_RECORD_KIND_NONE],
        &[1, 1],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
        &[1, INVALID],
        &[INVALID, INVALID],
        &[INVALID, INVALID],
    )
    .expect_err("context relations to concrete statement HIR rows without statement records should fail closed");
}

#[test]
fn parser_hir_struct_literal_field_records_feed_type_checking_not_field_spelling() {
    let declarations = r#"
module core::records;

pub struct Pair {
    left: i32,
    flag: bool,
}

pub struct Decoy {
    left: i32,
    flag: i32,
}
"#;
    let positive_app = r#"
module app::main;
import core::records;

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, flag: true };
    let decoy: Decoy = Decoy { left: 8, flag: 1 };
    return pair.left + decoy.flag;
}
"#;
    assert_source_pack_type_checks(
        &[declarations, positive_app],
        "struct literal fields should be typed by their selected struct, not by same-spelled fields",
    );

    let negative_app = r#"
module app::main;
import core::records;

fn main() -> i32 {
    let pair: Pair = Pair { left: 7, flag: 1 };
    let decoy: Decoy = Decoy { left: 8, flag: 1 };
    return pair.left + decoy.flag;
}
"#;
    assert_source_pack_type_rejects(
        &[declarations, negative_app],
        "same-spelled Decoy.flag: i32 must not make Pair.flag accept an i32 field value",
    );
}

#[test]
fn parser_hir_enum_variant_payload_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::maybe;

pub enum Maybe {
    Some(i32, bool),
    None,
}
"#,
        r#"
module app::main;
import core::maybe;

fn main(value: Maybe) -> i32 {
    return 0;
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );

    let enum_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| {
            (kind == HIR_ITEM_KIND_ENUM
                && parsed.hir_item_file_id[node] == 0
                && parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PUBLIC)
                .then_some(node)
        })
        .collect::<Vec<_>>();
    assert_eq!(
        enum_nodes.len(),
        1,
        "fixture should publish exactly one public enum item in the first source"
    );
    let enum_node = enum_nodes[0];
    assert_eq!(
        parsed.hir_kind[enum_node], HIR_NODE_ENUM_ITEM,
        "enum item metadata should attach to the parser-owned enum HIR node"
    );
    assert_eq!(
        parsed.hir_item_namespace[enum_node], HIR_ITEM_NAMESPACE_TYPE,
        "enum items should publish type-namespace records"
    );
    assert_eq!(
        parsed.hir_node_file_id[enum_node], parsed.hir_item_file_id[enum_node],
        "enum HIR row should retain the same source-pack file id as its item record"
    );
    assert!(
        (parsed.hir_node_file_id[enum_node] as usize) < source_count,
        "enum HIR row should retain a bounded source-pack file id"
    );
    assert_source_pack_hir_node_has_non_empty_span(&parsed, enum_node, "enum item");

    let mut variants = parsed
        .hir_variant_parent_enum
        .iter()
        .enumerate()
        .filter_map(|(node, &parent)| (parent as usize == enum_node).then_some(node))
        .collect::<Vec<_>>();
    variants.sort_unstable_by_key(|&node| parsed.hir_variant_ordinal[node]);
    assert_eq!(
        variants.len(),
        2,
        "enum declaration should own exactly two variant records"
    );

    for (expected_ordinal, variant_node) in variants.iter().copied().enumerate() {
        assert_eq!(
            parsed.hir_kind[variant_node], HIR_NODE_ITEM,
            "variant row {variant_node} should remain an item HIR row"
        );
        assert_eq!(
            parsed.hir_item_kind[variant_node], HIR_ITEM_KIND_ENUM_VARIANT,
            "variant row {variant_node} should publish enum-variant item kind"
        );
        assert_eq!(
            parsed.hir_variant_ordinal[variant_node], expected_ordinal as u32,
            "variant row {variant_node} should publish a contiguous source-order ordinal"
        );
        assert_eq!(
            parsed.hir_node_file_id[variant_node], parsed.hir_node_file_id[enum_node],
            "variant row {variant_node} should inherit the enum source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            enum_node,
            variant_node,
            "enum variant",
        );
    }

    let tuple_variant = variants[0];
    let unit_variant = variants[1];
    assert_eq!(
        parsed.hir_variant_payload_count[tuple_variant], 2,
        "tuple variant should publish two payload type records"
    );
    assert_eq!(
        parsed.hir_variant_payload_count[unit_variant], 0,
        "unit variant should not publish payload type records"
    );
    assert_eq!(
        parsed.hir_variant_payload_start[tuple_variant],
        parsed.hir_variant_payload_node[tuple_variant * VARIANT_PAYLOAD_SLOT_STRIDE],
        "tuple variant payload start should point at the ordinal-zero payload type"
    );
    assert_eq!(
        parsed.hir_variant_payload_start[unit_variant], INVALID,
        "unit variant should not publish a payload start"
    );

    let tuple_payload_slot = tuple_variant * VARIANT_PAYLOAD_SLOT_STRIDE;
    let first_payload = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_variant_payload_node[tuple_payload_slot],
        "first enum variant payload",
    );
    let second_payload = assert_valid_source_pack_hir_node_index(
        &parsed,
        parsed.hir_variant_payload_node[tuple_payload_slot + 1],
        "second enum variant payload",
    );
    assert!(
        parsed.hir_token_pos[first_payload] < parsed.hir_token_pos[second_payload],
        "enum variant payload slots should follow source order"
    );

    for payload_node in [first_payload, second_payload] {
        assert_eq!(
            parsed.hir_kind[payload_node], HIR_NODE_TYPE,
            "variant payload {payload_node} should be a parser-owned type HIR row"
        );
        assert_eq!(
            parsed.hir_type_form[payload_node], HIR_TYPE_FORM_PATH,
            "variant payload {payload_node} should publish a path-type record"
        );
        assert_eq!(
            parsed.hir_node_file_id[payload_node], parsed.hir_node_file_id[tuple_variant],
            "variant payload {payload_node} should inherit the variant source-pack file id"
        );
        assert_eq!(
            parsed.hir_type_file_id[payload_node], parsed.hir_node_file_id[tuple_variant],
            "variant payload {payload_node} type record should retain the variant source-pack file id"
        );
        assert!(
            (parsed.hir_type_file_id[payload_node] as usize) < source_count,
            "variant payload {payload_node} should retain a bounded source-pack file id"
        );
        assert_source_pack_hir_child_span_inside_owner(
            &parsed,
            tuple_variant,
            payload_node,
            "enum variant payload",
        );
    }

    let unit_payload_slot = unit_variant * VARIANT_PAYLOAD_SLOT_STRIDE;
    assert!(
        parsed.hir_variant_payload_node
            [unit_payload_slot..unit_payload_slot + VARIANT_PAYLOAD_SLOT_STRIDE]
            .iter()
            .all(|&node| node == INVALID),
        "unit variant should not publish payload slots"
    );

    let owned_variant_rows = parsed
        .hir_variant_parent_enum
        .iter()
        .filter(|&&parent| parent != INVALID)
        .count();
    assert_eq!(
        owned_variant_rows, 2,
        "fixture should not publish extra enum variant owner rows"
    );
}

#[test]
fn parser_hir_item_records_are_source_addressable_in_source_packs() {
    let source_count = 2;
    let parsed = parse_resident_source_pack(&[
        r#"
module core::math;
pub type Count = i32;

pub struct Pair {
    left: Count,
}

pub enum Maybe {
    Some(Count),
    None,
}

pub fn one() -> Count {
    return 1;
}
"#,
        r#"
module app::main;
import core::math;

fn main() -> i32 {
    return one();
}
"#,
    ]);
    assert!(
        parsed.ll1_status[0] != 0,
        "resident parser should accept the fixture: error_pos={} code={} detail={}",
        parsed.ll1_status[1],
        parsed.ll1_status[2],
        parsed.ll1_status[3]
    );
    assert_flat_item_type_records_follow_source_order(&parsed, source_count);

    let item_nodes = parsed
        .hir_item_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind != HIR_ITEM_KIND_NONE).then_some(node))
        .collect::<Vec<_>>();
    assert!(
        item_nodes.len() >= 9,
        "fixture should publish module, import, declaration, and enum-variant item rows"
    );

    let mut saw_module = false;
    let mut saw_import = false;
    let mut saw_pub_fn = false;
    let mut saw_private_fn = false;
    let mut saw_struct = false;
    let mut saw_enum = false;
    let mut saw_type_alias = false;
    let mut saw_variant = false;
    let mut items_by_file = [0usize; 2];

    for node in item_nodes {
        let kind = parsed.hir_item_kind[node];
        let item_start = parsed.hir_token_pos[node];
        let item_end = parsed.hir_token_end[node];
        assert_ne!(
            item_start, INVALID,
            "published item row {node} should record a source token start"
        );
        assert_ne!(
            item_end, INVALID,
            "published item row {node} should record a source token end"
        );
        assert!(
            item_start < item_end,
            "published item row {node} should have a non-empty source span"
        );

        let file_id = parsed.hir_item_file_id[node] as usize;
        assert!(
            file_id < source_count,
            "published item row {node} should retain a bounded source-pack file id"
        );
        items_by_file[file_id] += 1;

        match kind {
            HIR_ITEM_KIND_MODULE => {
                saw_module = true;
                assert_eq!(
                    parsed.hir_item_visibility[node], HIR_ITEM_VIS_PRIVATE,
                    "module item row {node} should retain parser-private visibility"
                );
                assert_source_span_inside_item(
                    &parsed,
                    node,
                    parsed.hir_item_path_start[node],
                    parsed.hir_item_path_end[node],
                    "module path",
                );
            }
            HIR_ITEM_KIND_IMPORT => {
                saw_import = true;
                assert_eq!(
                    parsed.hir_item_visibility[node], HIR_ITEM_VIS_PRIVATE,
                    "import item row {node} should retain parser-private visibility"
                );
                assert_eq!(
                    parsed.hir_item_import_target_kind[node], HIR_ITEM_IMPORT_TARGET_PATH,
                    "path import row {node} should publish its target kind"
                );
                assert_source_span_inside_item(
                    &parsed,
                    node,
                    parsed.hir_item_path_start[node],
                    parsed.hir_item_path_end[node],
                    "import path",
                );
            }
            _ => {
                assert_eq!(
                    parsed.hir_item_import_target_kind[node], HIR_ITEM_IMPORT_TARGET_NONE,
                    "declaration item row {node} should not look like an import target"
                );
                assert_eq!(
                    parsed.hir_item_path_start[node], INVALID,
                    "declaration item row {node} should not publish a module/import path start"
                );
                assert_eq!(
                    parsed.hir_item_path_end[node], INVALID,
                    "declaration item row {node} should not publish a module/import path end"
                );
                let name_token = parsed.hir_item_name_token[node];
                assert_ne!(
                    name_token, INVALID,
                    "declaration item row {node} should publish a source name token"
                );
                assert!(
                    item_start <= name_token && name_token < item_end,
                    "declaration item row {node} should keep its name token inside the item span"
                );
            }
        }

        match kind {
            HIR_ITEM_KIND_FN if parsed.hir_item_visibility[node] == HIR_ITEM_VIS_PUBLIC => {
                saw_pub_fn = true;
            }
            HIR_ITEM_KIND_FN => saw_private_fn = true,
            HIR_ITEM_KIND_STRUCT => saw_struct = true,
            HIR_ITEM_KIND_ENUM => saw_enum = true,
            HIR_ITEM_KIND_TYPE_ALIAS => saw_type_alias = true,
            HIR_ITEM_KIND_ENUM_VARIANT => saw_variant = true,
            _ => {}
        }
    }

    assert!(
        items_by_file.iter().all(|&count| count > 0),
        "source-pack readback should retain item rows for every fixture file"
    );
    assert!(saw_module, "fixture should publish module item rows");
    assert!(saw_import, "fixture should publish an import item row");
    assert!(
        saw_pub_fn,
        "fixture should publish a public function item row"
    );
    assert!(
        saw_private_fn,
        "fixture should publish a private function item row"
    );
    assert!(saw_struct, "fixture should publish a struct item row");
    assert!(saw_enum, "fixture should publish an enum item row");
    assert!(
        saw_type_alias,
        "fixture should publish a type-alias item row"
    );
    assert!(saw_variant, "fixture should publish enum-variant item rows");
}

fn assert_flat_item_type_records_follow_source_order(
    parsed: &DecodedParserHirItemReadbacks,
    source_count: usize,
) {
    let mut previous_public_record: Option<(usize, u32, u32)> = None;
    let mut saw_item_record = false;
    let mut saw_type_record = false;

    for row in 0..parsed.hir_kind.len() {
        let has_item_record = parsed.hir_item_kind[row] != HIR_ITEM_KIND_NONE;
        let has_type_record = parsed.hir_type_form[row] != HIR_TYPE_FORM_NONE;
        if !has_item_record && !has_type_record {
            continue;
        }

        let file_id = parsed.hir_node_file_id[row];
        let token_start = parsed.hir_token_pos[row];
        let token_end = parsed.hir_token_end[row];
        assert_ne!(
            token_start, INVALID,
            "public HIR record row {row} should publish a token start"
        );
        assert_ne!(
            token_end, INVALID,
            "public HIR record row {row} should publish a token end"
        );
        assert!(
            token_start < token_end,
            "public HIR record row {row} should publish a non-empty source span"
        );
        assert!(
            (file_id as usize) < source_count,
            "public HIR record row {row} should retain a bounded source-pack file id"
        );

        if has_item_record {
            saw_item_record = true;
            assert_eq!(
                parsed.hir_item_file_id[row], file_id,
                "item record row {row} should use the already-published HIR node file id"
            );
        }
        if has_type_record {
            saw_type_record = true;
            assert_eq!(
                parsed.hir_type_file_id[row], file_id,
                "type record row {row} should use the already-published HIR node file id"
            );
        }

        if let Some((previous_row, previous_file_id, previous_token_start)) = previous_public_record
        {
            assert!(
                file_id > previous_file_id
                    || (file_id == previous_file_id && token_start >= previous_token_start),
                "public HIR record row {row} should follow flat source order after row {previous_row}"
            );
        }
        previous_public_record = Some((row, file_id, token_start));
    }

    assert!(
        saw_item_record,
        "fixture should publish item records in the flat source-address stream"
    );
    assert!(
        saw_type_record,
        "fixture should publish type records in the flat source-address stream"
    );
}

fn assert_source_span_inside_item(
    parsed: &DecodedParserHirItemReadbacks,
    node: usize,
    start: u32,
    end: u32,
    label: &str,
) {
    assert_ne!(
        start, INVALID,
        "{label} for item row {node} should record a token start"
    );
    assert_ne!(
        end, INVALID,
        "{label} for item row {node} should record a token end"
    );
    assert!(
        parsed.hir_token_pos[node] < start,
        "{label} for item row {node} should begin after the declaration keyword"
    );
    assert!(
        start < end,
        "{label} for item row {node} should cover at least one token"
    );
    assert!(
        end <= parsed.hir_token_end[node],
        "{label} for item row {node} should stay inside the item span"
    );
}

fn assert_valid_source_pack_record_index(
    parsed: &DecodedParserHirItemReadbacks,
    node: u32,
    label: &str,
) -> usize {
    assert_ne!(node, INVALID, "{label} should publish a record row");
    let node = node as usize;
    assert!(
        node < parsed.hir_kind.len(),
        "{label} row {node} should be inside the parser record table"
    );
    node
}

fn assert_valid_source_pack_hir_node_index(
    parsed: &DecodedParserHirItemReadbacks,
    node: u32,
    label: &str,
) -> usize {
    assert_ne!(node, INVALID, "{label} should publish a HIR node");
    let node = node as usize;
    assert!(
        node < parsed.hir_kind.len(),
        "{label} node {node} should be inside the HIR record table"
    );
    node
}

fn assert_source_pack_hir_node_has_non_empty_span(
    parsed: &DecodedParserHirItemReadbacks,
    node: usize,
    label: &str,
) {
    assert_ne!(
        parsed.hir_token_pos[node], INVALID,
        "{label} node {node} should record a source token start"
    );
    assert_ne!(
        parsed.hir_token_end[node], INVALID,
        "{label} node {node} should record a source token end"
    );
    assert!(
        parsed.hir_token_pos[node] < parsed.hir_token_end[node],
        "{label} node {node} should have a non-empty source span"
    );
}

fn assert_source_pack_record_span_inside_owner(
    parsed: &DecodedParserHirItemReadbacks,
    owner: usize,
    child: usize,
    label: &str,
) {
    assert_source_pack_hir_node_has_non_empty_span(parsed, owner, "owner");
    assert_ne!(
        parsed.hir_token_pos[child], INVALID,
        "{label} row {child} should record a source token start"
    );
    assert_ne!(
        parsed.hir_token_end[child], INVALID,
        "{label} row {child} should record a source token end"
    );
    assert!(
        parsed.hir_token_pos[child] < parsed.hir_token_end[child],
        "{label} row {child} should have a non-empty source span"
    );
    assert!(
        parsed.hir_token_pos[owner] <= parsed.hir_token_pos[child],
        "{label} row {child} should start inside owner node {owner}"
    );
    assert!(
        parsed.hir_token_end[child] <= parsed.hir_token_end[owner],
        "{label} row {child} should end inside owner node {owner}"
    );
}

fn assert_source_pack_hir_child_span_inside_owner(
    parsed: &DecodedParserHirItemReadbacks,
    owner: usize,
    child: usize,
    label: &str,
) {
    assert_source_pack_hir_node_has_non_empty_span(parsed, owner, "owner");
    assert_source_pack_hir_node_has_non_empty_span(parsed, child, label);
    assert!(
        parsed.hir_token_pos[owner] <= parsed.hir_token_pos[child],
        "{label} node {child} should start inside owner node {owner}"
    );
    assert!(
        parsed.hir_token_end[child] <= parsed.hir_token_end[owner],
        "{label} node {child} should end inside owner node {owner}"
    );
}

fn resolve_forward_expr_record(
    parsed: &DecodedParserHirItemReadbacks,
    node: usize,
    label: &str,
) -> usize {
    let mut current = node;
    for _ in 0..32 {
        assert!(
            current < parsed.hir_expr_record_form.len(),
            "{label} expression row {current} should be inside the expression record table"
        );
        if parsed.hir_expr_record_form[current] != HIR_EXPR_FORM_FORWARD {
            return current;
        }
        current = assert_valid_source_pack_record_index(
            parsed,
            parsed.hir_expr_record_left[current],
            label,
        );
    }
    panic!("{label} expression record chain should resolve within 32 parser-owned rows");
}

fn assert_expr_record_value_token_inside(
    parsed: &DecodedParserHirItemReadbacks,
    node: usize,
    label: &str,
) {
    let value_token = parsed.hir_expr_record_value_token[node];
    assert_ne!(
        value_token, INVALID,
        "{label} row {node} should publish a value token"
    );
    assert!(
        parsed.hir_token_pos[node] <= value_token && value_token < parsed.hir_token_end[node],
        "{label} value token should stay inside expression row {node}"
    );
}

fn assert_valid_fn_return_readback_node(
    parsed: &DecodedParserHirFunctionReturnReadbacks,
    node: u32,
    label: &str,
) -> usize {
    assert_ne!(node, INVALID, "{label} should publish a HIR node");
    let node = node as usize;
    assert!(
        node < parsed.hir_kind.len(),
        "{label} node {node} should be inside the HIR return-record table"
    );
    node
}

fn assert_fn_return_readback_node_has_non_empty_span(
    parsed: &DecodedParserHirFunctionReturnReadbacks,
    node: usize,
    label: &str,
) {
    assert_ne!(
        parsed.hir_token_pos[node], INVALID,
        "{label} node {node} should record a source token start"
    );
    assert_ne!(
        parsed.hir_token_end[node], INVALID,
        "{label} node {node} should record a source token end"
    );
    assert!(
        parsed.hir_token_pos[node] < parsed.hir_token_end[node],
        "{label} node {node} should have a non-empty source span"
    );
}

fn assert_fn_return_readback_child_span_inside_owner(
    parsed: &DecodedParserHirFunctionReturnReadbacks,
    owner: usize,
    child: usize,
    label: &str,
) {
    assert_fn_return_readback_node_has_non_empty_span(parsed, owner, "owner");
    assert_fn_return_readback_node_has_non_empty_span(parsed, child, label);
    assert!(
        parsed.hir_token_pos[owner] <= parsed.hir_token_pos[child],
        "{label} node {child} should start inside owner node {owner}"
    );
    assert!(
        parsed.hir_token_end[child] <= parsed.hir_token_end[owner],
        "{label} node {child} should end inside owner node {owner}"
    );
}

#[test]
fn source_pack_import_visibility_resolves_public_declarations_only() {
    let imported_module = r#"
module lib::api;

pub fn exposed() -> i32 {
    return 1;
}

fn hidden() -> i32 {
    return 2;
}
"#;
    let unimported_decoy = r#"
module lib::decoy;

pub fn hidden() -> i32 {
    return 3;
}
"#;
    let importing_public = r#"
module app::main;
import lib::api;

fn main() -> i32 {
    return exposed();
}
"#;
    let positive_sources = [imported_module, unimported_decoy, importing_public];
    common::type_check_source_pack_with_timeout(&positive_sources)
        .expect("public declaration should resolve through the imported module");

    let importing_private = r#"
module app::main;
import lib::api;

fn main() -> i32 {
    return hidden();
}
"#;
    match common::type_check_source_pack_with_timeout(&[
        imported_module,
        unimported_decoy,
        importing_private,
    ]) {
        Ok(()) => panic!(
            "private declarations from the imported module must not resolve, \
             even when an unimported module exports the same leaf name"
        ),
        Err(CompileError::Diagnostic(_)) | Err(CompileError::GpuTypeCheck(_)) => {}
        Err(other) => panic!("expected GPU resolver/type-check rejection, got {other:?}"),
    }
}
