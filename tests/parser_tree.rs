mod common;

use laniusc::{
    gpu::buffers::storage_ro_from_u32s,
    lexer::{
        driver::GpuLexer,
        tables::tokens::{N_KINDS, TokenKind},
        test_cpu::{TestCpuToken, lex_on_test_cpu},
    },
    parser::{
        driver::{GpuParser, ResidentParseResult},
        passes::{
            hir_item_fields::{
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
                HIR_ITEM_KIND_TYPE_ALIAS,
                HIR_ITEM_NAMESPACE_MODULE,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                HIR_ITEM_VIS_PUBLIC,
            },
            hir_nodes::{
                HIR_NODE_BINARY_EXPR,
                HIR_NODE_CONST_ITEM,
                HIR_NODE_ENUM_ITEM,
                HIR_NODE_FILE,
                HIR_NODE_FN,
                HIR_NODE_IMPORT_ITEM,
                HIR_NODE_LET_STMT,
                HIR_NODE_LITERAL_EXPR,
                HIR_NODE_MATCH_EXPR,
                HIR_NODE_MODULE_ITEM,
                HIR_NODE_PATH_EXPR,
                HIR_NODE_RETURN_STMT,
                HIR_NODE_STRUCT_ITEM,
                HIR_NODE_STRUCT_LITERAL_EXPR,
                HIR_NODE_TYPE,
            },
            hir_type_fields::HIR_TYPE_FORM_NONE,
            ll1_blocks_01::LL1_BLOCK_STATUS_DISABLED,
        },
        syntax::{
            check_token_buffer_on_gpu,
            check_token_buffer_on_gpu_with_file_ids,
            check_tokens_on_gpu,
        },
        tables::{PrecomputedParseTables, encode_pop, encode_push},
    },
};

struct ProductionTreeReadbacks {
    node_kind: wgpu::Buffer,
    parent: wgpu::Buffer,
    first_child: wgpu::Buffer,
    next_sibling: wgpu::Buffer,
    subtree_end: wgpu::Buffer,
}

struct ProductionTreeSnapshot {
    token_capacity: u32,
    tree_capacity: u32,
    emit_len: u32,
    node_kind: Vec<u32>,
    parent: Vec<u32>,
    first_child: Vec<u32>,
    next_sibling: Vec<u32>,
    subtree_end: Vec<u32>,
}

fn parser_tree_readback(device: &wgpu::Device, label: &str, words: u32) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: u64::from(words.max(1)).saturating_mul(4),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn copy_production_tree_readbacks(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    parse_bufs: &laniusc::parser::buffers::ParserBuffers,
) -> ProductionTreeReadbacks {
    let words = parse_bufs.tree_capacity.max(1);
    let bytes = u64::from(words).saturating_mul(4);
    let node_kind = parser_tree_readback(device, "rb.test.parser.node_kind", words);
    let parent = parser_tree_readback(device, "rb.test.parser.parent", words);
    let first_child = parser_tree_readback(device, "rb.test.parser.first_child", words);
    let next_sibling = parser_tree_readback(device, "rb.test.parser.next_sibling", words);
    let subtree_end = parser_tree_readback(device, "rb.test.parser.subtree_end", words);

    encoder.copy_buffer_to_buffer(&parse_bufs.node_kind, 0, &node_kind, 0, bytes);
    encoder.copy_buffer_to_buffer(&parse_bufs.parent, 0, &parent, 0, bytes);
    encoder.copy_buffer_to_buffer(&parse_bufs.first_child, 0, &first_child, 0, bytes);
    encoder.copy_buffer_to_buffer(&parse_bufs.next_sibling, 0, &next_sibling, 0, bytes);
    encoder.copy_buffer_to_buffer(&parse_bufs.subtree_end, 0, &subtree_end, 0, bytes);

    ProductionTreeReadbacks {
        node_kind,
        parent,
        first_child,
        next_sibling,
        subtree_end,
    }
}

fn read_u32s(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let byte_len = count.saturating_mul(4) as u64;
    let slice = buffer.slice(0..byte_len);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::wait_indefinitely());
    let bytes = slice.get_mapped_range();
    let words = bytes
        .chunks_exact(4)
        .map(|chunk| u32::from_le_bytes(chunk.try_into().expect("u32 readback word")))
        .collect::<Vec<_>>();
    drop(bytes);
    buffer.unmap();
    words
}

const PROD_RET_TYPE: u32 = 34;
const PROD_FN: u32 = 11;
const PROD_IMPL_FN: u32 = 13;
const PROD_EXTERN_FN: u32 = 15;

fn test_cpu_raw_kinds_with_sentinels(src: &str) -> Vec<u32> {
    let mut kinds = lex_on_test_cpu(src)
        .expect("test CPU oracle lex fixture")
        .into_iter()
        .map(|token| token.kind as u32)
        .collect::<Vec<_>>();
    kinds.insert(0, 0);
    kinds.push(0);
    kinds
}

fn gpu_semantic_kinds_with_sentinels(src: &str) -> Vec<u32> {
    let src = src.to_owned();
    common::block_on_gpu_with_timeout(
        "GPU semantic token kinds for LL(1) table oracle",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");

            lexer
                .with_resident_tokens(&src, |_, _, bufs| {
                    parser.debug_semantic_token_kinds_for_resident_tokens(
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &tables,
                    )
                })
                .await
                .expect("resident GPU lex for semantic token table oracle")
                .expect("GPU semantic token table oracle")
        },
    )
}

fn llp_pair_emit_total_for_semantic_kinds(
    token_kinds: &[u32],
    tables: &PrecomputedParseTables,
) -> u32 {
    token_kinds
        .windows(2)
        .map(|pair| {
            let prev = pair[0] as usize;
            let this = pair[1] as usize;
            let idx = prev * tables.n_kinds as usize + this;
            tables.pp_len[idx]
        })
        .sum::<u32>()
        .max(1)
}

fn assert_resident_gpu_parser_accepts(label: &str, src: &str) {
    assert_resident_gpu_parser_accepts_all(label, vec![(label.to_string(), src.to_string())]);
}

fn assert_resident_gpu_parser_accepts_all(label: &str, fixtures: Vec<(String, String)>) {
    common::block_on_gpu_with_timeout(label, async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");

        for (fixture_label, src) in fixtures {
            let res = lexer
                .with_resident_tokens(&src, |_, _, bufs| {
                    parser.parse_resident_tokens(
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &tables,
                    )
                })
                .await
                .unwrap_or_else(|err| panic!("resident GPU lex {fixture_label}: {err}"))
                .unwrap_or_else(|err| panic!("resident GPU parse {fixture_label}: {err}"));

            assert!(
                res.ll1.accepted,
                "{fixture_label} rejected by resident GPU parser: pos={} code={} detail={}",
                res.ll1.error_pos, res.ll1.error_code, res.ll1.detail
            );
            assert_eq!(
                res.node_kind.len(),
                res.ll1.emit_len as usize,
                "{fixture_label} resident tree length must match production-stream length"
            );
            assert_eq!(
                res.hir_kind.len(),
                res.node_kind.len(),
                "{fixture_label} HIR records must align with parse-tree records"
            );
            assert_pareas_parent_vector(&res.node_kind, &res.parent, &tables.prod_arity);
            assert_semantic_dense_subtree_ranges(&res);
        }
    });
}

#[test]
#[ignore]
fn debug_parser_hir_positions_for_generic_return() {
    common::block_on_gpu_with_timeout("GPU parser generic return token spans", async move {
        let src = r#"
struct Range<T> {
    start: T,
    end: T,
}

fn make_range(start: i32, end: i32) -> Range<i32> {
    return Range { start: start, end: end };
}
"#;

        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");

        let parsed = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        println!(
            "hir_kind count={} token span count={}",
            parsed.hir_kind.len(),
            parsed.hir_token_pos.len()
        );
        for (i, (&kind, &pos)) in parsed
            .hir_kind
            .iter()
            .zip(parsed.hir_token_pos.iter())
            .enumerate()
        {
            if kind == HIR_NODE_RETURN_STMT {
                println!(
                    "hir node {} => kind={} pos={} token_text={:?}",
                    i,
                    kind,
                    pos,
                    tokens
                        .get(pos as usize)
                        .map(|t| &src[t.start..t.start + t.len])
                );
            }
        }

        for (i, &kind) in parsed.hir_kind.iter().enumerate() {
            if kind == 0 {
                continue;
            }
            let pos = parsed.hir_token_pos.get(i).copied().unwrap_or(u32::MAX);
            let end = parsed.hir_token_end.get(i).copied().unwrap_or(u32::MAX);
            if pos == u32::MAX || end == u32::MAX || pos >= end {
                continue;
            }
            if pos >= tokens.len() as u32 || end > tokens.len() as u32 {
                continue;
            }
            println!(
                "node {i}: kind={kind} span=({pos},{end}) text={:?}",
                &src[tokens[pos as usize].start
                    ..tokens[(end - 1u32) as usize].start + tokens[(end - 1u32) as usize].len]
            );
        }
    });
}

fn assert_tree_forest_shape(node_kind: &[u32], parent: &[u32], prod_arity: &[u32]) {
    assert_eq!(node_kind.len(), parent.len());
    let mut child_counts = vec![0usize; node_kind.len()];
    for (i, &parent_id) in parent.iter().enumerate() {
        if parent_id == u32::MAX {
            continue;
        }
        let parent_idx = parent_id as usize;
        assert!(
            parent_idx < i,
            "parent pointer must point backward at node {i}"
        );
        child_counts[parent_idx] += 1;
    }
    for (i, &kind) in node_kind.iter().enumerate() {
        let want = *prod_arity.get(kind as usize).unwrap_or(&0) as usize;
        assert_eq!(
            child_counts[i], want,
            "production arity mismatch at node {i}, production {kind}"
        );
    }
}

fn assert_pareas_parent_vector(node_kind: &[u32], parent: &[u32], prod_arity: &[u32]) {
    assert_eq!(node_kind.len(), parent.len());
    let mut depth_before = Vec::with_capacity(node_kind.len());
    let mut depth = 0i32;
    for &kind in node_kind {
        depth_before.push(depth);
        let arity = *prod_arity
            .get(kind as usize)
            .unwrap_or_else(|| panic!("missing production arity for production {kind}"));
        depth += arity as i32 - 1;
    }

    for i in 0..node_kind.len() {
        let expected = (0..i)
            .rev()
            .find(|&candidate| depth_before[candidate] <= depth_before[i])
            .map(|candidate| candidate as u32)
            .unwrap_or(u32::MAX);
        assert_eq!(
            parent[i], expected,
            "Pareas parent-vector mismatch at node {i}, production {}",
            node_kind[i]
        );
    }
}

fn expected_subtree_end(i: usize, node_kind: &[u32], prod_arity: &[u32]) -> u32 {
    let mut need = prod_arity[node_kind[i] as usize] as usize;
    let mut j = i + 1;
    while j < node_kind.len() && need > 0 {
        need = need - 1 + prod_arity[node_kind[j] as usize] as usize;
        j += 1;
    }
    j as u32
}

fn nearest_function_owner_node(res: &ResidentParseResult, start: usize) -> u32 {
    let mut node = start as u32;
    while (node as usize) < res.node_kind.len() {
        let idx = node as usize;
        let prod = res.node_kind[idx];
        if res.hir_kind[idx] == HIR_NODE_FN
            && (prod == PROD_FN || prod == PROD_EXTERN_FN || prod == PROD_IMPL_FN)
        {
            return node;
        }
        node = res.parent[idx];
    }
    u32::MAX
}

fn nearest_return_type_owner_node(res: &ResidentParseResult, start: usize) -> u32 {
    let mut node = start as u32;
    while (node as usize) < res.node_kind.len() {
        let idx = node as usize;
        if res.node_kind[idx] == PROD_RET_TYPE {
            return node;
        }
        node = res.parent[idx];
    }
    u32::MAX
}

fn assert_tree_navigation_shape(
    node_kind: &[u32],
    parent: &[u32],
    first_child: &[u32],
    next_sibling: &[u32],
    subtree_end: &[u32],
    prod_arity: &[u32],
) {
    assert_eq!(node_kind.len(), first_child.len());
    assert_eq!(node_kind.len(), next_sibling.len());
    assert_eq!(node_kind.len(), subtree_end.len());
    for (i, &kind) in node_kind.iter().enumerate() {
        let arity = prod_arity[kind as usize] as usize;
        let want_first = if arity > 0 && i + 1 < node_kind.len() {
            (i + 1) as u32
        } else {
            u32::MAX
        };
        let want_end = expected_subtree_end(i, node_kind, prod_arity);
        let want_next =
            if (want_end as usize) < node_kind.len() && parent[want_end as usize] == parent[i] {
                want_end
            } else {
                u32::MAX
            };
        assert_eq!(first_child[i], want_first, "first child at node {i}");
        assert_eq!(subtree_end[i], want_end, "subtree end at node {i}");
        assert_eq!(next_sibling[i], want_next, "next sibling at node {i}");
    }
}

fn assert_semantic_dense_subtree_ranges(res: &ResidentParseResult) {
    assert_eq!(
        res.hir_semantic_prefix_before_node.len(),
        res.node_kind.len()
    );
    assert_eq!(res.hir_semantic_dense_node.len(), res.node_kind.len());
    assert_eq!(res.hir_semantic_subtree_end.len(), res.node_kind.len());
    assert_eq!(res.hir_semantic_parent.len(), res.node_kind.len());
    assert_eq!(res.hir_semantic_first_child.len(), res.node_kind.len());
    assert_eq!(res.hir_semantic_next_sibling.len(), res.node_kind.len());
    assert_eq!(res.hir_semantic_depth.len(), res.node_kind.len());
    assert_eq!(res.hir_semantic_child_index.len(), res.node_kind.len());
    assert_eq!(res.hir_type_alias_target_node.len(), res.node_kind.len());
    assert_eq!(res.hir_fn_return_type_node.len(), res.node_kind.len());

    let semantic_nodes = res
        .hir_kind
        .iter()
        .enumerate()
        .filter_map(|(node, &kind)| (kind != 0).then_some(node))
        .collect::<Vec<_>>();

    for node in 0..res.node_kind.len() {
        let expected_prefix = semantic_nodes.partition_point(|&semantic| semantic < node) as u32;
        assert_eq!(
            res.hir_semantic_prefix_before_node[node], expected_prefix,
            "semantic prefix before original node {node}",
        );
    }

    for (row, &original_node) in semantic_nodes.iter().enumerate() {
        assert_eq!(
            res.hir_semantic_dense_node[row], original_node as u32,
            "dense semantic row {row} maps to original node",
        );
        let original_end = res.subtree_end[original_node] as usize;
        let expected_dense_end = semantic_nodes
            .partition_point(|&semantic| semantic < original_end)
            .max(row + 1) as u32;
        assert_eq!(
            res.hir_semantic_subtree_end[row], expected_dense_end,
            "dense semantic subtree end for row {row} original node {original_node}",
        );

        let mut parent = res.parent[original_node];
        let expected_parent = loop {
            if parent == u32::MAX {
                break u32::MAX;
            }
            let parent_idx = parent as usize;
            assert!(
                parent_idx < original_node,
                "parse parent should point backward for semantic row {row}",
            );
            if res.hir_kind[parent_idx] != 0 {
                break semantic_nodes.partition_point(|&semantic| semantic < parent_idx) as u32;
            }
            parent = res.parent[parent_idx];
        };
        assert_eq!(
            res.hir_semantic_parent[row], expected_parent,
            "dense semantic parent for row {row} original node {original_node}",
        );
        let expected_depth = if expected_parent == u32::MAX {
            0
        } else {
            res.hir_semantic_depth[expected_parent as usize] + 1
        };
        assert_eq!(
            res.hir_semantic_depth[row], expected_depth,
            "dense semantic depth for row {row} original node {original_node}",
        );
        let expected_child_index = res.hir_semantic_parent[..row]
            .iter()
            .filter(|&&parent| parent == expected_parent)
            .count() as u32;
        assert_eq!(
            res.hir_semantic_child_index[row], expected_child_index,
            "dense semantic child index for row {row} original node {original_node}",
        );

        let row_u32 = row as u32;
        let expected_first_child =
            if row + 1 < semantic_nodes.len() && res.hir_semantic_parent[row + 1] == row_u32 {
                row_u32 + 1
            } else {
                u32::MAX
            };
        assert_eq!(
            res.hir_semantic_first_child[row], expected_first_child,
            "dense semantic first child for row {row} original node {original_node}",
        );

        let sibling = res.hir_semantic_subtree_end[row] as usize;
        let expected_next_sibling = if sibling < semantic_nodes.len()
            && res.hir_semantic_parent[sibling] == res.hir_semantic_parent[row]
        {
            sibling as u32
        } else {
            u32::MAX
        };
        assert_eq!(
            res.hir_semantic_next_sibling[row], expected_next_sibling,
            "dense semantic next sibling for row {row} original node {original_node}",
        );
    }

    for (row, &original_node) in semantic_nodes.iter().enumerate() {
        if res.hir_item_kind[original_node] != HIR_ITEM_KIND_TYPE_ALIAS {
            continue;
        }
        let expected_target = semantic_nodes
            .iter()
            .enumerate()
            .filter_map(|(child_row, &child_node)| {
                if res.hir_kind[child_node] != HIR_NODE_TYPE
                    || res.hir_type_form[child_node] == HIR_TYPE_FORM_NONE
                {
                    return None;
                }
                let mut parent = res.hir_semantic_parent[child_row];
                while parent != u32::MAX {
                    let parent_node = semantic_nodes[parent as usize];
                    if res.hir_item_kind[parent_node] != HIR_ITEM_KIND_NONE {
                        return (parent == row as u32).then_some(child_node as u32);
                    }
                    if parent == row as u32 {
                        return Some(child_node as u32);
                    }
                    parent = res.hir_semantic_parent[parent as usize];
                }
                None
            })
            .min()
            .unwrap_or(u32::MAX);
        assert_eq!(
            res.hir_type_alias_target_node[original_node], expected_target,
            "type alias target type node for semantic row {row} original node {original_node}",
        );
    }

    for (row, &original_node) in semantic_nodes.iter().enumerate() {
        if res.hir_kind[original_node] != HIR_NODE_FN
            || (res.hir_item_kind[original_node] != HIR_ITEM_KIND_FN
                && res.hir_item_kind[original_node] != HIR_ITEM_KIND_EXTERN_FN)
        {
            continue;
        }
        let expected_return_type = semantic_nodes
            .iter()
            .filter_map(|&child_node| {
                if res.hir_kind[child_node] != HIR_NODE_TYPE
                    || res.hir_type_form[child_node] == HIR_TYPE_FORM_NONE
                    || nearest_return_type_owner_node(res, child_node) == u32::MAX
                    || nearest_function_owner_node(res, child_node) != original_node as u32
                {
                    return None;
                }
                Some(child_node as u32)
            })
            .min()
            .unwrap_or(u32::MAX);
        assert_eq!(
            res.hir_fn_return_type_node[original_node], expected_return_type,
            "function return type node for semantic row {row} original node {original_node}",
        );
    }
}

fn assert_hir_token_spans(name: &str, hir_token_pos: &[u32], hir_token_end: &[u32], n_tokens: u32) {
    assert_eq!(
        hir_token_pos.len(),
        hir_token_end.len(),
        "{name} HIR span length"
    );
    assert_eq!(
        hir_token_end.first().copied(),
        Some(n_tokens),
        "{name} root HIR span end"
    );
    for (i, (&start, &end)) in hir_token_pos.iter().zip(hir_token_end).enumerate() {
        if start == u32::MAX {
            assert_eq!(end, u32::MAX, "{name} invalid HIR span end at node {i}");
            continue;
        }
        assert!(
            start <= end && end <= n_tokens,
            "{name} invalid HIR span at node {i}: {start}..{end} for {n_tokens} tokens"
        );
    }
}

fn assert_hir_kind_points_to_token(
    name: &str,
    hir_kind: &[u32],
    hir_token_pos: &[u32],
    tokens: &[TestCpuToken],
    kind: u32,
    token_kind: TokenKind,
) {
    let found = hir_kind
        .iter()
        .zip(hir_token_pos)
        .filter(|&(&hir, _)| hir == kind)
        .any(|(_, &pos)| {
            let pos = pos as usize;
            pos < tokens.len() && tokens[pos].kind == token_kind
        });
    assert!(
        found,
        "{name} should contain HIR kind {kind} pointing at {token_kind:?}"
    );
}

fn assert_hir_kind_points_to_semantic_token(
    name: &str,
    hir_kind: &[u32],
    hir_token_pos: &[u32],
    semantic_token_kinds_with_sentinels: &[u32],
    kind: u32,
    token_kind: TokenKind,
) {
    let found = hir_kind
        .iter()
        .zip(hir_token_pos)
        .filter(|&(&hir, _)| hir == kind)
        .any(|(_, &pos)| {
            let semantic_pos = pos as usize + 1;
            semantic_pos < semantic_token_kinds_with_sentinels.len()
                && semantic_token_kinds_with_sentinels[semantic_pos] == token_kind as u32
        });
    assert!(
        found,
        "{name} should contain HIR kind {kind} pointing at semantic {token_kind:?}"
    );
}

fn hir_span_snippets_for_kind(
    src: &str,
    hir_kind: &[u32],
    hir_token_pos: &[u32],
    hir_token_end: &[u32],
    tokens: &[TestCpuToken],
    kind: u32,
) -> Vec<String> {
    hir_kind
        .iter()
        .zip(hir_token_pos)
        .zip(hir_token_end)
        .filter_map(|((&hir, &start), &end)| {
            if hir != kind || start == u32::MAX || end == u32::MAX {
                return None;
            }
            let start = start as usize;
            let end = end as usize;
            if start >= end || end > tokens.len() {
                return None;
            }
            let byte_start = tokens[start].start;
            let last = tokens[end - 1];
            let byte_end = last.start + last.len;
            Some(src[byte_start..byte_end].to_string())
        })
        .collect()
}

fn token_snippet(src: &str, tokens: &[TestCpuToken], token: u32) -> Option<String> {
    let token = token as usize;
    let t = tokens.get(token)?;
    Some(src[t.start..t.start + t.len].to_string())
}

fn token_span_snippet(src: &str, tokens: &[TestCpuToken], start: u32, end: u32) -> Option<String> {
    if start == u32::MAX || end == u32::MAX || start >= end {
        return None;
    }
    let start = start as usize;
    let end = end as usize;
    if end > tokens.len() {
        return None;
    }
    let byte_start = tokens[start].start;
    let last = tokens[end - 1];
    Some(src[byte_start..last.start + last.len].to_string())
}

fn hir_node_snippet(
    src: &str,
    tokens: &[TestCpuToken],
    hir_token_pos: &[u32],
    hir_token_end: &[u32],
    node: u32,
) -> Option<String> {
    let node = node as usize;
    token_span_snippet(
        src,
        tokens,
        *hir_token_pos.get(node)?,
        *hir_token_end.get(node)?,
    )
}

fn hir_item_names_for_kind(
    src: &str,
    tokens: &[TestCpuToken],
    hir_item_kind: &[u32],
    hir_item_name_token: &[u32],
    item_kind: u32,
) -> Vec<String> {
    hir_item_kind
        .iter()
        .zip(hir_item_name_token)
        .filter_map(|(&kind, &name)| {
            if kind == item_kind {
                token_snippet(src, tokens, name)
            } else {
                None
            }
        })
        .collect()
}

#[test]
fn gpu_parser_builds_tree_from_resident_lexer_tokens() {
    common::block_on_gpu_with_timeout("GPU parser resident lexer tokens", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = include_str!("../parser_tests/function.lani");
        let token_kinds = test_cpu_raw_kinds_with_sentinels(src);

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident GPU parser rejected fixture");
        assert_eq!(res.node_kind.len(), res.ll1.emit_len as usize);
        assert_eq!(res.hir_kind.len(), res.node_kind.len());
        assert_hir_token_spans(
            "resident",
            &res.hir_token_pos,
            &res.hir_token_end,
            token_kinds.len().saturating_sub(2) as u32,
        );
        assert_eq!(res.hir_kind.first().copied(), Some(HIR_NODE_FILE));
        assert!(res.hir_kind.contains(&HIR_NODE_FN));
        assert!(res.hir_kind.contains(&HIR_NODE_LET_STMT));
        assert!(res.hir_kind.contains(&HIR_NODE_RETURN_STMT));
        assert!(res.hir_kind.contains(&HIR_NODE_BINARY_EXPR));
        assert!(res.hir_kind.contains(&HIR_NODE_LITERAL_EXPR));
        assert_pareas_parent_vector(&res.node_kind, &res.parent, &tables.prod_arity);
        assert_semantic_dense_subtree_ranges(&res);
    });
}

#[test]
fn gpu_parser_builds_valid_root_span_for_compound_assignment_statements() {
    common::block_on_gpu_with_timeout("GPU parser compound assignment root span", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = include_str!("../sample_programs/compound_assignments.lani");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "compound assignment fixture should parse");
        assert_eq!(
            res.subtree_end.first().copied(),
            Some(res.node_kind.len() as u32),
            "root parse-tree span must cover the active parse stream for backend tree projection"
        );
        assert_pareas_parent_vector(&res.node_kind, &res.parent, &tables.prod_arity);
        assert_semantic_dense_subtree_ranges(&res);
    });
}

#[test]
fn gpu_parser_production_capacity_builds_valid_root_span_for_compound_assignment_statements() {
    common::block_on_gpu_with_timeout(
        "GPU production parser compound assignment root span",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let src = include_str!("../sample_programs/compound_assignments.lani");

            let snapshot = lexer
                .with_recorded_resident_tokens_after_count(
                    src,
                    |device, _queue, bufs, token_count, encoder, mut timer| {
                        let token_capacity = token_count.max(1);
                        let tree_capacity =
                            parser.projected_resident_tree_capacity(token_capacity, &tables);
                        let (parser_check, readbacks) = parser
                            .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                                encoder,
                                token_capacity,
                                &bufs.tokens_out,
                                &bufs.token_count,
                                Some(&bufs.token_file_id),
                                bufs.n,
                                &bufs.in_bytes,
                                &tables,
                                Some(tree_capacity),
                                &mut timer,
                                |parse_bufs, encoder, _timer| {
                                    Ok::<_, String>(copy_production_tree_readbacks(
                                        device, encoder, parse_bufs,
                                    ))
                                },
                            )
                            .map_err(|err| err.to_string())?;
                        let readbacks = readbacks?;
                        Ok::<_, String>((parser_check, readbacks, token_capacity, tree_capacity))
                    },
                    |device,
                     _queue,
                     _bufs,
                     (parser_check, readbacks, token_capacity, tree_capacity)| {
                        let ll1 = parser
                            .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                            .map_err(|err| err.to_string())?;
                        let active = (ll1.emit_len as usize).min(tree_capacity as usize);
                        Ok::<_, String>(ProductionTreeSnapshot {
                            token_capacity,
                            tree_capacity,
                            emit_len: ll1.emit_len,
                            node_kind: read_u32s(device, &readbacks.node_kind, active),
                            parent: read_u32s(device, &readbacks.parent, active),
                            first_child: read_u32s(device, &readbacks.first_child, active),
                            next_sibling: read_u32s(device, &readbacks.next_sibling, active),
                            subtree_end: read_u32s(device, &readbacks.subtree_end, active),
                        })
                    },
                )
                .await
                .expect("resident GPU lex")
                .expect("production parser snapshot");

            assert!(
                snapshot.emit_len <= snapshot.tree_capacity,
                "production parser tree capacity must cover emit_len: token_capacity={} tree_capacity={} emit_len={}",
                snapshot.token_capacity,
                snapshot.tree_capacity,
                snapshot.emit_len
            );
            assert_eq!(
                snapshot.subtree_end.first().copied(),
                Some(snapshot.emit_len),
                "production root span must cover the active parse stream for backend tree projection"
            );
            assert_pareas_parent_vector(&snapshot.node_kind, &snapshot.parent, &tables.prod_arity);
            assert_tree_navigation_shape(
                &snapshot.node_kind,
                &snapshot.parent,
                &snapshot.first_child,
                &snapshot.next_sibling,
                &snapshot.subtree_end,
                &tables.prod_arity,
            );
        },
    );
}

#[test]
fn gpu_parser_projected_capacity_reduces_llp_headers_without_spelling_dependency() {
    common::block_on_gpu_with_timeout(
        "GPU parser projected capacity header reduction",
        async move {
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let parser = GpuParser::new().await.expect("GPU parser init");
            let tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(
                "../tables/parse_tables.bin"
            ))
            .expect("load generated parse tables");
            let fixtures = [
                "fn alpha(a: i32) -> i32 { let temp: i32 = a + 1; return temp; }",
                "fn wildly_different_identifier_name(input_value: i32) -> i32 { let unrelated_local_name: i32 = input_value + 1; return unrelated_local_name; }",
            ];

            let mut projected = Vec::new();
            let mut expected = Vec::new();
            for src in fixtures {
                let semantic_kinds = lexer
                    .with_resident_tokens(src, |_, _, bufs| {
                        parser.debug_semantic_token_kinds_for_resident_tokens(
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            &tables,
                        )
                    })
                    .await
                    .expect("resident GPU lex for semantic token table oracle")
                    .expect("GPU semantic token table oracle");
                expected.push(llp_pair_emit_total_for_semantic_kinds(
                    &semantic_kinds,
                    &tables,
                ));
                let capacity = lexer
                    .with_recorded_resident_tokens_after_count(
                        src,
                        |_device, _queue, bufs, token_count, _encoder, _timer| {
                            parser
                                .read_resident_projected_tree_capacity(
                                    token_count.max(1),
                                    &bufs.tokens_out,
                                    &bufs.token_count,
                                    Some(&bufs.token_file_id),
                                    &tables,
                                )
                                .map_err(|err| err.to_string())
                        },
                        |_device, _queue, _bufs, capacity| Ok::<_, String>(capacity),
                    )
                    .await
                    .expect("resident GPU lex")
                    .expect("GPU projected tree capacity");
                projected.push(capacity);
            }

            assert_eq!(
                projected, expected,
                "projected capacity must equal the LLP pair-table emit total"
            );
            assert_eq!(
                projected[0], projected[1],
                "identifier spelling changes must not affect parser projected capacity"
            );
        },
    );
}

#[test]
fn gpu_parser_ll1_hir_classifies_current_item_and_struct_literal_productions() {
    common::block_on_gpu_with_timeout("GPU parser current HIR production ids", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "const LIMIT: i32 = 7; enum Maybe { Some(i32), None } struct Point { x: i32, y: i32 } fn make() { let p = Point { x: 1, y: 2 }; let out = match (1) { _ -> 1 }; return; }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");
        let (semantic_token_kinds, res) = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                let semantic_token_kinds = parser.debug_semantic_token_kinds_for_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )?;
                let parsed = parser.parse_resident_tokens(
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &tables,
                )?;
                Ok::<_, anyhow::Error>((semantic_token_kinds, parsed))
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_CONST_ITEM,
            TokenKind::Const,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_ENUM_ITEM,
            TokenKind::Enum,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_STRUCT_ITEM,
            TokenKind::Struct,
        );
        assert_hir_kind_points_to_semantic_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &semantic_token_kinds,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            TokenKind::StructLitLBrace,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_MATCH_EXPR,
            TokenKind::Match,
        );
    });
}

#[test]
fn generated_ll1_tables_accept_bool_literals() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "fn main() { let flag: bool = false; if (true) { return 1; } }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("bool literal fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_for_in_statements() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "fn sum(values: [i32]) -> i32 { let total: i32 = 0; for value in values { total += value; } return total; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("for-in fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_extern_function_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        r#"pub extern "wasm" fn host_alloc(size: usize, align: usize,) -> u32; extern fn clock_ms() -> i64;"#,
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("extern function fixture with trailing parameter comma should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_top_level_constants() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "const LIMIT: i32 = 7; pub const PUBLIC_LIMIT: i32 = 9; fn main() { return LIMIT; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("const fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_accepts_public_top_level_constants() {
    common::block_on_gpu_with_timeout("GPU syntax public const", async move {
        let src = "pub const PUBLIC_LIMIT: i32 = 9; fn main() { return PUBLIC_LIMIT; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex public const fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept public const fixture");
    });
}

#[test]
fn gpu_syntax_accepts_for_in_statement_shape() {
    common::block_on_gpu_with_timeout("GPU syntax for-in statement", async move {
        let src = "fn main(values: [i32]) { for value in values { continue; } return; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex for-in fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept for-in fixture");
    });
}

#[test]
fn gpu_syntax_accepts_generated_let_chain_without_import_header_scan() {
    common::block_on_gpu_with_timeout("GPU syntax generated let chain", async move {
        let mut src = String::from("fn main() -> i32 {\n    let v0: i32 = 1;\n");
        for i in 1..80 {
            let prev = i - 1;
            let add = (i * 17 + 3) % 11;
            src.push_str(&format!("    let v{i}: i32 = v{prev} + {add};\n"));
        }
        src.push_str("    return v79;\n}\n");

        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(&src).await.expect("GPU lex generated let chain");
        check_tokens_on_gpu(&tokens).await.expect(
            "GPU syntax should accept generated let chains without whole-file import scans",
        );
        lexer
            .with_resident_tokens(&src, |device, queue, bufs| {
                check_token_buffer_on_gpu(
                    device,
                    queue,
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                )
                .expect("resident GPU syntax should accept generated let chains");
            })
            .await
            .expect("resident GPU lex generated let chain");
    });
}

#[test]
fn gpu_parser_accepts_generated_let_chain_resident_ll1_hir() {
    common::block_on_gpu_with_timeout("GPU parser generated let chain", async move {
        let mut src = String::from("fn main() -> i32 {\n    let v0: i32 = 1;\n");
        for i in 1..80 {
            let prev = i - 1;
            let add = (i * 17 + 3) % 11;
            src.push_str(&format!("    let v{i}: i32 = v{prev} + {add};\n"));
        }
        src.push_str("    return v79;\n}\n");

        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let res = lexer
            .with_resident_tokens(&src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex generated let chain")
            .expect("resident GPU parse generated let chain");

        assert!(res.ll1.accepted, "generated let chain should parse");
        assert!(res.hir_kind.contains(&HIR_NODE_FN));
        assert!(res.hir_kind.contains(&HIR_NODE_LET_STMT));
        assert!(res.hir_kind.contains(&HIR_NODE_RETURN_STMT));
    });
}

#[test]
fn gpu_syntax_accepts_extern_function_declaration_shape() {
    common::block_on_gpu_with_timeout("GPU syntax extern function declaration", async move {
        let src = r#"pub extern "wasm" fn host_alloc(size: usize, align: usize,) -> u32;"#;
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex extern fixture");
        check_tokens_on_gpu(&tokens).await.expect(
            "GPU syntax should accept extern function fixture with trailing parameter comma",
        );
    });
}

#[test]
fn gpu_syntax_rejects_invalid_token_file_ids_from_gpu_metadata() {
    common::block_on_gpu_with_timeout("GPU syntax token file-id validation", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        lexer
            .with_resident_tokens("fn main() { return 0; }", |device, queue, bufs| {
                let invalid_file_ids = vec![u32::MAX; bufs.token_file_id.count.max(1)];
                let invalid_file_id_buf = storage_ro_from_u32s(
                    device,
                    "test.parser.syntax.invalid_token_file_id",
                    &invalid_file_ids,
                );
                let err = check_token_buffer_on_gpu_with_file_ids(
                    device,
                    queue,
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &invalid_file_id_buf,
                )
                .expect_err("invalid token file ids should fail syntax validation");
                let message = err.to_string();
                assert!(
                    message.contains("UnexpectedToken"),
                    "expected invalid file id to be reported as syntax rejection, got {message}"
                );
            })
            .await
            .expect("resident lex");
    });
}

#[test]
fn generated_ll1_tables_accept_module_and_import_items() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "module core::numbers; import core::i32; import \"stdlib/bool.lani\"; fn main() { return; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("module/import fixture should parse with LL(1)");
}

#[test]
fn gpu_ll1_hir_preserves_module_import_and_path_evidence() {
    common::block_on_gpu_with_timeout("GPU parser module/import/path HIR evidence", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "module core::numbers; import core::i32; fn main() { return core::i32::abs(1); }";
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "GPU LL(1) parser rejected fixture");
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_MODULE_ITEM,
            TokenKind::Module,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_IMPORT_ITEM,
            TokenKind::Import,
        );
        assert_hir_kind_points_to_token(
            "resident",
            &res.hir_kind,
            &res.hir_token_pos,
            &tokens,
            HIR_NODE_PATH_EXPR,
            TokenKind::Ident,
        );
        let path_spans = hir_span_snippets_for_kind(
            src,
            &res.hir_kind,
            &res.hir_token_pos,
            &res.hir_token_end,
            &tokens,
            HIR_NODE_PATH_EXPR,
        );
        assert!(
            path_spans.iter().any(|path| path == "core::numbers"),
            "resident HIR should span the full module path, got {path_spans:?}"
        );
        assert!(
            path_spans.iter().any(|path| path == "core::i32"),
            "resident HIR should span the full import path, got {path_spans:?}"
        );
        assert!(
            path_spans.iter().any(|path| path == "core::i32::abs"),
            "resident HIR should span the full qualified value path, got {path_spans:?}"
        );
    });
}

#[test]
fn gpu_ll1_hir_item_fields_are_ast_derived_and_exclude_methods() {
    common::block_on_gpu_with_timeout("GPU parser HIR item field metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = r#"
module core::numbers;
import core::bool;
import "core/bool";

pub const MIN: i32 = 0;
fn private_fn() { return; }
pub fn abs(value: i32) -> i32 { return value; }
pub extern "wasm" fn host_alloc(size: usize,) -> u32;
extern fn clock_ms() -> i64;
pub struct Point { x: i32 }
fn point_x(point: core::numbers::Point) -> i32 { return point.x; }
pub struct Range<T> { start: T, end: T }
enum Maybe { Some(i32), None }
type Alias = i32;

impl Point {
    pub fn method(self: Point) { return; }
}
"#;
        let tokens = lex_on_test_cpu(src).expect("test CPU oracle lex fixture");

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(res.ll1.accepted, "resident LL(1) parser rejected fixture");
        assert_semantic_dense_subtree_ranges(&res);

        let module_paths = res
            .hir_item_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind == HIR_ITEM_KIND_MODULE {
                    token_span_snippet(
                        src,
                        &tokens,
                        res.hir_item_path_start[i],
                        res.hir_item_path_end[i],
                    )
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(module_paths, vec!["core::numbers"]);

        let import_paths = res
            .hir_item_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind == HIR_ITEM_KIND_IMPORT {
                    token_span_snippet(
                        src,
                        &tokens,
                        res.hir_item_path_start[i],
                        res.hir_item_path_end[i],
                    )
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(import_paths, vec!["core::bool", "\"core/bool\""]);

        let import_targets = res
            .hir_item_kind
            .iter()
            .enumerate()
            .filter_map(|(i, &kind)| {
                if kind == HIR_ITEM_KIND_IMPORT {
                    Some(res.hir_item_import_target_kind[i])
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(
            import_targets,
            vec![HIR_ITEM_IMPORT_TARGET_PATH, HIR_ITEM_IMPORT_TARGET_STRING]
        );

        for (item_kind, namespace, visibility, name) in [
            (
                HIR_ITEM_KIND_CONST,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PUBLIC,
                "MIN",
            ),
            (
                HIR_ITEM_KIND_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                "private_fn",
            ),
            (
                HIR_ITEM_KIND_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PUBLIC,
                "abs",
            ),
            (
                HIR_ITEM_KIND_EXTERN_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PUBLIC,
                "host_alloc",
            ),
            (
                HIR_ITEM_KIND_EXTERN_FN,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                "clock_ms",
            ),
            (
                HIR_ITEM_KIND_STRUCT,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PUBLIC,
                "Point",
            ),
            (
                HIR_ITEM_KIND_STRUCT,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PUBLIC,
                "Range",
            ),
            (
                HIR_ITEM_KIND_ENUM,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PRIVATE,
                "Maybe",
            ),
            (
                HIR_ITEM_KIND_ENUM_VARIANT,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                "Some",
            ),
            (
                HIR_ITEM_KIND_ENUM_VARIANT,
                HIR_ITEM_NAMESPACE_VALUE,
                HIR_ITEM_VIS_PRIVATE,
                "None",
            ),
            (
                HIR_ITEM_KIND_TYPE_ALIAS,
                HIR_ITEM_NAMESPACE_TYPE,
                HIR_ITEM_VIS_PRIVATE,
                "Alias",
            ),
        ] {
            let found = res.hir_item_kind.iter().enumerate().any(|(i, &kind)| {
                kind == item_kind
                    && res.hir_item_namespace[i] == namespace
                    && res.hir_item_visibility[i] == visibility
                    && token_snippet(src, &tokens, res.hir_item_name_token[i]).as_deref()
                        == Some(name)
                    && res.hir_item_file_id[i] == 0
            });
            assert!(found, "missing HIR item metadata for {name}");
        }

        let fn_names = hir_item_names_for_kind(
            src,
            &tokens,
            &res.hir_item_kind,
            &res.hir_item_name_token,
            HIR_ITEM_KIND_FN,
        );
        assert!(
            fn_names.contains(&"private_fn".to_string()) && fn_names.contains(&"abs".to_string()),
            "top-level function names should be recorded, got {fn_names:?}"
        );
        assert!(
            !fn_names.contains(&"method".to_string()),
            "impl methods must not be reported as top-level functions"
        );

        for (i, &kind) in res.hir_item_kind.iter().enumerate() {
            if kind == HIR_ITEM_KIND_MODULE || kind == HIR_ITEM_KIND_IMPORT {
                assert_eq!(res.hir_item_namespace[i], HIR_ITEM_NAMESPACE_MODULE);
                assert_eq!(res.hir_item_visibility[i], HIR_ITEM_VIS_PRIVATE);
                assert_eq!(res.hir_item_file_id[i], 0);
            }
        }
    });
}

#[test]
fn gpu_syntax_accepts_leading_module_metadata() {
    common::block_on_gpu_with_timeout("GPU syntax leading module metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let src = "module app::main; fn main() { return 0; }";
        let tokens = lexer.lex(src).await.expect("GPU lex module fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept leading module metadata");
    });
}

#[test]
fn gpu_syntax_accepts_leading_import_metadata_and_rejects_invalid_module_metadata() {
    common::block_on_gpu_with_timeout("GPU syntax module/import metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for src in [
            "import core::i32; fn main() { return 0; }",
            "import \"stdlib/core/i32.lani\"; fn main() { return 0; }",
            "module app::main; import core::i32; import test::assert; fn main() { return 0; }",
        ] {
            let tokens = lexer.lex(src).await.expect("GPU lex import fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect("GPU syntax should accept leading import metadata");
        }
        for src in [
            "fn main() { return 0; } import core::i32;",
            "fn main() { return 0; } module app::late;",
            "module app::main; module app::again; fn main() { return 0; }",
        ] {
            let tokens = lexer.lex(src).await.expect("GPU lex module/import fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect_err("GPU syntax should reject non-leading import/module metadata");
        }
    });
}

#[test]
fn gpu_syntax_treats_source_pack_module_import_metadata_file_locally() {
    common::block_on_gpu_with_timeout("GPU syntax source pack metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let valid = [
            "module first; fn first() { return; } ",
            "module second; import first; fn second() { return; }",
        ];
        lexer
            .with_resident_source_pack_tokens(&valid, |device, queue, bufs| {
                check_token_buffer_on_gpu_with_file_ids(
                    device,
                    queue,
                    bufs.n,
                    &bufs.tokens_out,
                    &bufs.token_count,
                    &bufs.token_file_id,
                )
                .expect("GPU syntax should accept file-local source pack metadata");
            })
            .await
            .expect("resident source pack lex");

        let final_semicolon_before_file_boundary = [
            "module core::count; pub type Count = i32;",
            "module app::main; import core::count; fn main() { return 0; }",
        ];
        lexer
            .with_resident_source_pack_tokens(
                &final_semicolon_before_file_boundary,
                |device, queue, bufs| {
                    check_token_buffer_on_gpu_with_file_ids(
                        device,
                        queue,
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &bufs.token_file_id,
                    )
                    .expect("GPU syntax should preserve final file tokens in source packs");
                },
            )
            .await
            .expect("resident source pack final semicolon lex");

        for invalid in [
            [
                "module first; fn first() { return; } ",
                "fn second() { return; } import first;",
            ],
            [
                "module first; fn first() { return; } ",
                "module second; module duplicate; fn second() { return; }",
            ],
            [
                "module first; fn first() { return; } ",
                "module ; fn second() { return; }",
            ],
        ] {
            lexer
                .with_resident_source_pack_tokens(&invalid, |device, queue, bufs| {
                    check_token_buffer_on_gpu_with_file_ids(
                        device,
                        queue,
                        bufs.n,
                        &bufs.tokens_out,
                        &bufs.token_count,
                        &bufs.token_file_id,
                    )
                    .expect_err(
                        "GPU syntax should reject non-leading module/import metadata per file",
                    );
                })
                .await
                .expect("resident invalid source pack lex");
        }
    });
}

#[test]
fn gpu_syntax_accepts_simple_stdlib_module_seed_files() {
    common::block_on_gpu_with_timeout("GPU syntax stdlib seed module metadata", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for (path, src) in [
            (
                "stdlib/core/i32.lani",
                include_str!("../stdlib/core/i32.lani"),
            ),
            (
                "stdlib/core/bool.lani",
                include_str!("../stdlib/core/bool.lani"),
            ),
            (
                "stdlib/test/assert.lani",
                include_str!("../stdlib/test/assert.lani"),
            ),
        ] {
            let tokens = lexer
                .lex(src)
                .await
                .unwrap_or_else(|err| panic!("GPU lex {path}: {err}"));
            let result = check_tokens_on_gpu(&tokens).await;
            assert!(
                result.is_ok(),
                "{path} should accept leading module metadata: {result:?}"
            );
        }
    });
}

#[test]
fn gpu_parser_accepts_namespaced_paths() {
    assert_resident_gpu_parser_accepts(
        "GPU parser namespaced paths",
        "fn main(value: core::option::Option<i32>, result: core::result::Result<i32, i32>) { let out = core::math::add_one(1); let p = core::point::Point { x: out }; let y = match (out) { core::option::Some(inner) -> inner, _ -> out }; return; }",
    );
}

#[test]
fn gpu_syntax_accepts_qualified_value_paths_as_hir_evidence() {
    common::block_on_gpu_with_timeout("GPU syntax qualified value path evidence", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for accepted in [
            r#"
module app::main;

fn helper() -> i32 {
    return 1;
}

fn main() {
    return app::main::helper();
}
"#,
            "fn main() { let value: i32 = core::i32::MIN; return value; }",
            "fn main() { return core::i32::abs + 1; }",
        ] {
            let tokens = lexer
                .lex(accepted)
                .await
                .expect("GPU lex qualified value path fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect("GPU syntax should preserve qualified value paths for type checking");
        }
    });
}

#[test]
fn gpu_parser_accepts_enum_declarations() {
    assert_resident_gpu_parser_accepts(
        "GPU parser enum declarations",
        "enum ResultI32 { Ok(i32), Err([i32; 4]), Empty }",
    );
}

#[test]
fn generated_ll1_tables_accept_generic_enum_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds =
        gpu_semantic_kinds_with_sentinels("enum Result<T, E> { Ok(T), Err(E), Empty }");

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("generic enum fixture should parse with LL(1)");
}

#[test]
fn generated_ll1_tables_accept_struct_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "pub struct VecHeader<T> { ptr: i32, len: i32, value: Option<T> }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("struct fixture should parse with LL(1)");
}

#[test]
fn gpu_parser_accepts_struct_literal_expressions() {
    assert_resident_gpu_parser_accepts(
        "GPU parser struct literals",
        "fn make() { let p = Point { x: 1, y: 2 }; let q = Point { }; }",
    );
}

#[test]
fn gpu_parser_accepts_match_expressions() {
    assert_resident_gpu_parser_accepts(
        "GPU parser match expressions",
        "fn choose(value: i32, fallback: i32) -> i32 { let out = match (value) { 0 -> fallback, Some(inner) -> inner, _ -> value }; return out; }",
    );
}

#[test]
fn gpu_parser_accepts_trailing_commas_in_stdlib_shapes() {
    assert_resident_gpu_parser_accepts(
        "GPU parser trailing commas",
        "struct Pair { left: i32, right: bool, } enum Maybe<T,> { Some(T,), None, } type Alias<T,> = Maybe<T,>; fn main(values: [i32; 2],) { let xs = [1, 2,]; let p = Pair { left: 1, right: true, }; let out = match (value) { Some(inner,) -> inner, _ -> value, }; take(1, 2,); return; }",
    );
}

#[test]
fn gpu_parser_accepts_slice_type_syntax() {
    assert_resident_gpu_parser_accepts(
        "GPU parser slice type syntax",
        "fn first(values: [i32], nested: [[bool]]) -> i32 { return 0; }",
    );
}

#[test]
fn generated_ll1_tables_accept_reference_type_syntax() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "fn borrow(value: &i32, values: &[i32], nested: & &bool) { return; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("reference type fixture should parse with LL(1)");
}

#[test]
fn gpu_syntax_rejects_general_references_until_borrow_semantics_exist() {
    common::block_on_gpu_with_timeout("GPU syntax general reference rejection", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        for src in [
            "fn read(value: &i32) -> i32 { return 0; }",
            "fn main() { let value: i32 = 7; let ptr: &i32 = &value; return value; }",
        ] {
            let tokens = lexer.lex(src).await.expect("GPU lex reference fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect_err("GPU syntax should reject general references until borrowing exists");
        }
    });
}

#[test]
fn generated_ll1_tables_accept_generic_function_declarations() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "pub fn unwrap_or<T>(value: T, fallback: T) -> T { return fallback; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("generic function fixture should parse with LL(1)");
}

#[test]
fn gpu_parser_accepts_generic_type_parameter_bounds() {
    assert_resident_gpu_parser_accepts(
        "GPU parser generic type parameter bounds",
        "trait Eq<T> { fn eq(left: T, right: T) -> bool; } fn same<T: Eq<T>>(left: T, right: T) -> bool { return left.eq(right); }",
    );
}

#[test]
fn gpu_parser_accepts_multiple_generic_type_parameter_bounds() {
    assert_resident_gpu_parser_accepts(
        "GPU parser multiple generic type parameter bounds",
        "trait Eq<T> { fn eq(left: T, right: T) -> bool; } trait Hash<T> { fn hash(value: T) -> u32; } fn key<T: Eq<T> + Hash<T>>(value: T) -> u32 { return value.hash(); }",
    );
}

#[test]
fn gpu_parser_accepts_where_clause_declarations() {
    assert_resident_gpu_parser_accepts(
        "GPU parser where-clause declarations",
        "pub trait Eq<T> where T: core::cmp::Eq<T> { pub fn eq(left: T, right: T) -> bool where T: core::cmp::Eq<T>; } pub struct Wrapper<T> where T: Eq<T> { value: T } pub enum Maybe<T> where T: Eq<T> { Some(T), None } pub type Wrapped<T> where T: Eq<T> = Wrapper<T>; pub impl<T> Eq<T> for Wrapper<T> where T: Eq<T> { pub fn eq(left: Wrapper<T>, right: Wrapper<T>) -> bool where T: Eq<T> { return true; } } pub fn keep<T>(value: T) -> T where T: Eq<T>, { return value; }",
    );
}

#[test]
fn generated_ll1_tables_accept_self_receiver_methods() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "trait Len { fn len(self) -> i32; fn is_empty(&self) -> bool; } struct Range { start: i32, end: i32 } impl Range { fn start(self) -> i32 { return self.start; } fn end(self: Range) -> i32 { return self.end; } fn is_empty(&self) -> bool { return self.start == self.end; } }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("self receiver fixture should parse with LL(1)");
}

#[test]
fn gpu_parser_accepts_core_range_seed() {
    assert_resident_gpu_parser_accepts(
        "GPU parser core range seed",
        include_str!("../stdlib/core/range.lani"),
    );
}

#[test]
fn gpu_parser_accepts_stdlib_seed_files() {
    let fixtures = [
        (
            "stdlib/core/i32.lani",
            include_str!("../stdlib/core/i32.lani"),
        ),
        (
            "stdlib/core/u8.lani",
            include_str!("../stdlib/core/u8.lani"),
        ),
        (
            "stdlib/core/u32.lani",
            include_str!("../stdlib/core/u32.lani"),
        ),
        (
            "stdlib/core/i64.lani",
            include_str!("../stdlib/core/i64.lani"),
        ),
        (
            "stdlib/core/f32.lani",
            include_str!("../stdlib/core/f32.lani"),
        ),
        (
            "stdlib/core/char.lani",
            include_str!("../stdlib/core/char.lani"),
        ),
        (
            "stdlib/core/bool.lani",
            include_str!("../stdlib/core/bool.lani"),
        ),
        (
            "stdlib/core/array_i32.lani",
            include_str!("../stdlib/core/array_i32.lani"),
        ),
        (
            "stdlib/core/array_i32_4.lani",
            include_str!("../stdlib/core/array_i32_4.lani"),
        ),
        (
            "stdlib/core/option.lani",
            include_str!("../stdlib/core/option.lani"),
        ),
        (
            "stdlib/core/result.lani",
            include_str!("../stdlib/core/result.lani"),
        ),
        (
            "stdlib/core/ordering.lani",
            include_str!("../stdlib/core/ordering.lani"),
        ),
        (
            "stdlib/core/cmp.lani",
            include_str!("../stdlib/core/cmp.lani"),
        ),
        (
            "stdlib/core/hash.lani",
            include_str!("../stdlib/core/hash.lani"),
        ),
        (
            "stdlib/core/range.lani",
            include_str!("../stdlib/core/range.lani"),
        ),
        (
            "stdlib/core/slice.lani",
            include_str!("../stdlib/core/slice.lani"),
        ),
        (
            "stdlib/core/panic.lani",
            include_str!("../stdlib/core/panic.lani"),
        ),
        (
            "stdlib/core/target.lani",
            include_str!("../stdlib/core/target.lani"),
        ),
        (
            "stdlib/alloc/allocator.lani",
            include_str!("../stdlib/alloc/allocator.lani"),
        ),
        ("stdlib/std/io.lani", include_str!("../stdlib/std/io.lani")),
        (
            "stdlib/std/process.lani",
            include_str!("../stdlib/std/process.lani"),
        ),
        (
            "stdlib/std/env.lani",
            include_str!("../stdlib/std/env.lani"),
        ),
        (
            "stdlib/std/time.lani",
            include_str!("../stdlib/std/time.lani"),
        ),
        ("stdlib/std/fs.lani", include_str!("../stdlib/std/fs.lani")),
        (
            "stdlib/std/net.lani",
            include_str!("../stdlib/std/net.lani"),
        ),
        (
            "stdlib/test/assert.lani",
            include_str!("../stdlib/test/assert.lani"),
        ),
        ("stdlib/i32.lani", include_str!("../stdlib/i32.lani")),
        ("stdlib/bool.lani", include_str!("../stdlib/bool.lani")),
        (
            "stdlib/array_i32_4.lani",
            include_str!("../stdlib/array_i32_4.lani"),
        ),
    ];

    assert_resident_gpu_parser_accepts_all(
        "GPU parser stdlib seed files",
        fixtures
            .into_iter()
            .map(|(path, src)| (path.to_string(), src.to_string()))
            .collect(),
    );
}

#[test]
fn gpu_parser_accepts_where_clause_declarations_from_resident_lexer_tokens() {
    common::block_on_gpu_with_timeout("GPU parser where clauses", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "pub trait Eq<T> where T: core::cmp::Eq<T> { pub fn eq(left: T, right: T) -> bool where T: core::cmp::Eq<T>; } pub impl<T> Eq<T> for T where T: core::cmp::Eq<T> { pub fn eq(left: T, right: T) -> bool where T: core::cmp::Eq<T> { return true; } } pub fn keep<T>(value: T) -> T where T: core::cmp::Eq<T>, { return value; }";

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(
            res.ll1.accepted,
            "where-clause fixture rejected by GPU parser"
        );
        assert!(!res.node_kind.is_empty());
    });
}

#[test]
fn gpu_parser_accepts_self_receivers_from_resident_lexer_tokens() {
    common::block_on_gpu_with_timeout("GPU parser self receivers", async move {
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let parser = GpuParser::new().await.expect("GPU parser init");
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("load generated parse tables");
        let src = "trait Len { fn len(self) -> i32; fn is_empty(&self) -> bool; } impl Range { fn start(self) -> i32 { return self.start; } fn end(self: Range) -> i32 { return self.end; } }";

        let res = lexer
            .with_resident_tokens(src, |_, _, bufs| {
                parser.parse_resident_tokens(bufs.n, &bufs.tokens_out, &bufs.token_count, &tables)
            })
            .await
            .expect("resident GPU lex")
            .expect("resident GPU parse");

        assert!(
            res.ll1.accepted,
            "self receiver fixture rejected by GPU parser"
        );
        assert!(!res.node_kind.is_empty());
    });
}

#[test]
fn gpu_syntax_accepts_where_clause_shape() {
    common::block_on_gpu_with_timeout("GPU syntax where clauses", async move {
        let src = "pub fn keep<T>(value: T) -> T where T: core::cmp::Eq<T>, { return value; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex where-clause fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept where-clause fixture");
    });
}

#[test]
fn gpu_syntax_accepts_self_receiver_shape() {
    common::block_on_gpu_with_timeout("GPU syntax self receivers", async move {
        let src = "impl Range { fn start(self) -> i32 { return self.start; } fn end(self: Range) -> i32 { return self.end; } fn is_empty(&self) -> bool { return self.start == self.end; } }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex self receiver fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept self receiver fixture");
    });
}

#[test]
fn gpu_syntax_accepts_generic_type_parameter_bounds() {
    common::block_on_gpu_with_timeout("GPU syntax generic type parameter bounds", async move {
        let src = "trait Eq<T> { fn eq(left: T, right: T) -> bool; } fn same<T: Eq<T> >(left: T, right: T) -> bool { return left.eq(right); }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex generic bound fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept generic type parameter bounds");
    });
}

#[test]
fn gpu_syntax_accepts_multiple_generic_type_parameter_bounds() {
    common::block_on_gpu_with_timeout(
        "GPU syntax multiple generic type parameter bounds",
        async move {
            let src = "trait Eq<T> { fn eq(left: T, right: T) -> bool; } trait Hash<T> { fn hash(value: T) -> u32; } fn key<T: Eq<T> + Hash<T> >(value: T) -> u32 { return value.hash(); }";
            let lexer = GpuLexer::new().await.expect("GPU lexer init");
            let tokens = lexer
                .lex(src)
                .await
                .expect("GPU lex multiple generic bounds fixture");
            check_tokens_on_gpu(&tokens)
                .await
                .expect("GPU syntax should accept multiple generic type parameter bounds");
        },
    );
}

#[test]
fn gpu_parser_accepts_type_alias_declarations() {
    assert_resident_gpu_parser_accepts(
        "GPU parser type alias declarations",
        "pub type Count = i32; type Buffer<T, const N: usize> = [T; N]; fn keep(value: Count) -> Count { return value; }",
    );
}

#[test]
fn gpu_syntax_accepts_type_alias_declarations_for_gpu_semantics() {
    common::block_on_gpu_with_timeout("GPU syntax type alias acceptance", async move {
        let src = "type Count = i32; fn main() { return 0; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex type alias fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept type aliases for GPU semantic resolution");
    });
}

#[test]
fn generated_ll1_tables_accept_const_generic_params_and_named_array_lengths() {
    let tables =
        PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
            .expect("load generated parse tables");
    let token_kinds = gpu_semantic_kinds_with_sentinels(
        "pub struct ArrayVec<T, const N: usize> { values: [T; N], len: usize } fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }",
    );

    tables
        .test_cpu_ll1_production_stream_with_positions(&token_kinds)
        .expect("const generic fixture should parse with LL(1)");
}

#[test]
fn gpu_parser_accepts_impl_and_trait_declarations() {
    assert_resident_gpu_parser_accepts(
        "GPU parser trait impl declarations",
        "pub trait Eq<T> { pub fn eq(left: T, right: T) -> bool; } pub impl Eq<i32> for i32 { pub fn eq(left: i32, right: i32) -> bool { return left == right; } }",
    );
}

#[test]
fn gpu_syntax_accepts_trait_impl_declaration_shape() {
    common::block_on_gpu_with_timeout("GPU syntax trait impl declaration", async move {
        let src = "pub trait Eq<T> { pub fn eq(left: T, right: T) -> bool; } pub impl Eq<i32> for i32 { pub fn eq(left: i32, right: i32) -> bool { return left == right; } }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer.lex(src).await.expect("GPU lex trait impl fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept trait impl fixture");
    });
}

#[test]
fn gpu_syntax_accepts_trailing_commas_in_stdlib_shapes() {
    common::block_on_gpu_with_timeout("GPU syntax trailing commas", async move {
        let src = "struct Pair { left: i32, right: bool, } enum Maybe<T,> { Some(T,), None, } fn main(values: [i32; 2],) { let xs = [1, 2,]; let p = Pair { left: 1, right: true, }; let out = match (value) { Some(inner,) -> inner, _ -> value, }; take(1, 2,); return; }";
        let lexer = GpuLexer::new().await.expect("GPU lexer init");
        let tokens = lexer
            .lex(src)
            .await
            .expect("GPU lex trailing comma fixture");
        check_tokens_on_gpu(&tokens)
            .await
            .expect("GPU syntax should accept trailing comma fixture");
    });
}

#[test]
fn gpu_parser_builds_tree_from_emit_stream() {
    common::block_on_gpu_with_timeout("GPU parser emit stream", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 3);

        tables.prod_arity = vec![2, 0, 0];
        tables.set_pp_for_pair(0, TokenKind::Ident as u32, &[0]);
        tables.set_pp_for_pair(TokenKind::Ident as u32, TokenKind::InfixPlus as u32, &[1]);
        tables.set_pp_for_pair(TokenKind::InfixPlus as u32, TokenKind::Int as u32, &[2]);
        tables.finalize_bit_widths(0);

        let token_kinds = [
            0,
            TokenKind::Ident as u32,
            TokenKind::InfixPlus as u32,
            TokenKind::Int as u32,
        ];
        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert_eq!(res.emit_stream, vec![0, 1, 2]);
        assert_eq!(res.ll1_seeded_blocks[0].status, LL1_BLOCK_STATUS_DISABLED);
        assert_eq!(res.node_kind, vec![0, 1, 2]);
        assert_eq!(res.parent, vec![u32::MAX, 0, 0]);
        assert_eq!(res.first_child, vec![1, u32::MAX, u32::MAX]);
        assert_eq!(res.next_sibling, vec![u32::MAX, 2, u32::MAX]);
        assert_eq!(res.subtree_end, vec![3, 2, 3]);
    });
}

#[test]
#[ignore = "GPU parser stress test; run explicitly with --ignored"]
fn gpu_parser_recovers_large_flat_tree_with_prefix_blocks() {
    common::block_on_gpu_with_timeout("GPU parser large flat tree", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 2);

        let leaf_count = 256 * 256;
        tables.prod_arity = vec![leaf_count as u32, 0];
        tables.set_pp_for_pair(0, TokenKind::Ident as u32, &[0]);
        tables.set_pp_for_pair(TokenKind::Ident as u32, TokenKind::Ident as u32, &[1]);
        tables.finalize_bit_widths(0);

        let mut token_kinds = Vec::with_capacity(leaf_count + 2);
        token_kinds.push(0);
        token_kinds.extend(std::iter::repeat(TokenKind::Ident as u32).take(leaf_count + 1));

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert_eq!(res.emit_stream.len(), leaf_count + 1);
        assert!(
            res.node_kind.len() > 256 * 256,
            "test must exercise tree prefix scans beyond one 256-lane workgroup"
        );
        assert_eq!(res.node_kind[0], 0);
        assert!(res.node_kind[1..].iter().all(|&kind| kind == 1));
        assert_tree_forest_shape(&res.node_kind, &res.parent, &tables.prod_arity);
        assert_tree_navigation_shape(
            &res.node_kind,
            &res.parent,
            &res.first_child,
            &res.next_sibling,
            &res.subtree_end,
            &tables.prod_arity,
        );
    });
}

#[test]
fn gpu_parser_reports_typed_bracket_mismatches() {
    common::block_on_gpu_with_timeout("GPU parser bracket mismatch", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.set_sc_for_pair(0, TokenKind::GroupLParen as u32, &[encode_push(0)]);
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::RBracket as u32,
            &[2],
        );
        tables.finalize_bit_widths(1);

        let token_kinds = [0, TokenKind::GroupLParen as u32, TokenKind::RBracket as u32];
        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(!res.brackets.valid);
        assert_eq!(res.brackets.final_depth, 0);
        assert_eq!(res.brackets.min_depth, 0);
    });
}

#[test]
#[ignore = "GPU parser stress test; run explicitly with --ignored"]
fn gpu_parser_scans_deep_bracket_histogram_offsets() {
    common::block_on_gpu_with_timeout("GPU parser deep bracket scan", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.set_sc_for_pair(0, TokenKind::GroupLParen as u32, &[encode_push(0)]);
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::GroupLParen as u32,
            &[encode_push(0)],
        );
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::GroupRParen as u32,
            &[encode_pop(0)],
        );
        tables.set_sc_for_pair(
            TokenKind::GroupRParen as u32,
            TokenKind::GroupRParen as u32,
            &[encode_pop(0)],
        );
        tables.finalize_bit_widths(0);

        let depth = 33_000usize;
        let mut token_kinds = Vec::with_capacity(depth * 2 + 1);
        token_kinds.push(0);
        token_kinds.extend(std::iter::repeat(TokenKind::GroupLParen as u32).take(depth));
        token_kinds.extend(std::iter::repeat(TokenKind::GroupRParen as u32).take(depth));

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(res.brackets.valid);
        assert_eq!(res.brackets.final_depth, 0);
        assert_eq!(res.brackets.min_depth, 0);
        assert_eq!(res.sc_stream.len(), depth * 2);
        assert!(
            res.sc_stream.len() > 256 * 256,
            "test must exercise block-prefix scan beyond one 256-lane workgroup"
        );
    });
}

#[test]
fn gpu_parser_pairs_many_flat_brackets_in_parallel() {
    common::block_on_gpu_with_timeout("GPU parser flat bracket pairing", async move {
        let parser = GpuParser::new().await.expect("GPU parser init");
        let mut tables = PrecomputedParseTables::new(N_KINDS, 1);

        tables.prod_arity = vec![0];
        tables.set_sc_for_pair(0, TokenKind::GroupLParen as u32, &[encode_push(0)]);
        tables.set_sc_for_pair(
            TokenKind::GroupLParen as u32,
            TokenKind::GroupRParen as u32,
            &[encode_pop(0)],
        );
        tables.set_sc_for_pair(
            TokenKind::GroupRParen as u32,
            TokenKind::GroupLParen as u32,
            &[encode_push(0)],
        );
        tables.finalize_bit_widths(0);

        let pair_count = 1024usize;
        let mut token_kinds = Vec::with_capacity(pair_count * 2 + 1);
        token_kinds.push(0);
        for _ in 0..pair_count {
            token_kinds.push(TokenKind::GroupLParen as u32);
            token_kinds.push(TokenKind::GroupRParen as u32);
        }

        let res = parser
            .parse(&token_kinds, &tables)
            .await
            .expect("GPU parse");

        assert!(res.brackets.valid);
        assert_eq!(res.brackets.final_depth, 0);
        assert_eq!(res.brackets.min_depth, 0);
        assert_eq!(res.sc_stream.len(), pair_count * 2);
    });
}
