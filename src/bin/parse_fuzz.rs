// src/bin/parse_fuzz.rs
// Runs fixed corpus + always-on random corpus.
// For fixed files, also checks sidecar goldens (<name>.parse.json) when present.
// This is developer test/fuzz tooling, not part of the compiler pipeline; its
// test CPU oracles exist only to validate GPU parser passes.
//
// CLI:
//   cargo run --bin parse_fuzz
//   cargo run --bin parse_fuzz -- parser_tests/tricky_combo.lani
//   cargo run --bin parse_fuzz -- --iters=10 --len=2000000 --seed=123

use std::{
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result};
use laniusc::{
    lexer::gpu::driver::GpuLexer,
    parser::{
        gpu::{
            buffers::ActionHeader,
            driver::{GpuParser, ParseResult},
            passes::ll1_blocks_01::{LL1_BLOCK_STATUS_ACCEPTED, LL1_BLOCK_STATUS_BOUNDARY},
        },
        tables::PrecomputedParseTables,
    },
};
use log::warn;
use rand::{SeedableRng, rngs::StdRng};
use serde::Deserialize;

// ------------------------ helpers: input collection ------------------------

fn collect_inputs_from_dir(dir: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(dir) else {
        warn!("failed to read parser test directory {dir}");
        return out;
    };
    for ent in rd {
        match ent {
            Ok(ent) => {
                let p = ent.path();
                if p.extension().and_then(|e| e.to_str()) == Some("lani") {
                    out.push(p);
                }
            }
            Err(err) => warn!("failed to read parser test directory entry in {dir}: {err}"),
        }
    }
    out.sort();
    out
}

fn load_tables() -> Result<PrecomputedParseTables> {
    let bytes = std::fs::read("tables/parse_tables.bin")
        .context("read generated GPU parser tables from tables/parse_tables.bin")?;
    PrecomputedParseTables::load_bin_bytes(&bytes)
        .map_err(|err| anyhow::anyhow!("load generated GPU parser tables: {err}"))
}

fn env_truthy(name: &str) -> bool {
    match std::env::var(name) {
        Ok(v) => {
            if v == "1" || v.eq_ignore_ascii_case("true") {
                true
            } else if v == "0" || v.eq_ignore_ascii_case("false") {
                false
            } else {
                warn!("{name} has unrecognized value '{v}'; using default false");
                false
            }
        }
        Err(_) => {
            warn!("{name} is unset; using default false");
            false
        }
    }
}

// ------------------------ helpers: test CPU bracket oracle ------------------------

#[derive(Debug, Clone)]
struct TestCpuBrackets {
    valid: bool,
    final_depth: i32,
    min_depth: i32,
    _match_for_index: Vec<u32>,
}

/// Test-only CPU oracle for validating the parallel GPU bracket matcher.
fn test_cpu_brackets(sc_stream: &[u32]) -> TestCpuBrackets {
    let n = sc_stream.len();
    let mut match_for_index = vec![0xFFFF_FFFFu32; n];
    let mut open_stack: Vec<u32> = Vec::with_capacity(n);

    let mut depth: i32 = 0;
    let mut min_depth: i32 = 0;
    let mut valid = true;

    for i in 0..n {
        let code = sc_stream[i];
        let is_push = (code & 1) == 1;
        if is_push {
            open_stack.push(i as u32);
            depth += 1;
            if depth < min_depth {
                min_depth = depth;
            }
        } else {
            if depth <= 0 || open_stack.is_empty() {
                valid = false;
                depth -= 1;
                if depth < min_depth {
                    min_depth = depth;
                }
                continue;
            }
            let push_idx = open_stack.pop().unwrap();
            depth -= 1;
            if depth < min_depth {
                min_depth = depth;
            }
            let push_sym = sc_stream[push_idx as usize] >> 1;
            let pop_sym = code >> 1;
            if push_sym != pop_sym {
                valid = false;
            }
            match_for_index[push_idx as usize] = i as u32;
            match_for_index[i] = push_idx;
        }
    }
    if !open_stack.is_empty() {
        valid = false;
    }
    TestCpuBrackets {
        valid,
        final_depth: depth,
        min_depth,
        _match_for_index: match_for_index,
    }
}

// ------------------------ helpers: additional invariants ------------------------

fn assert_involutive(map: &[u32]) -> Result<()> {
    for (i, &m) in map.iter().enumerate() {
        if m != 0xFFFF_FFFF {
            let back = map.get(m as usize).copied().unwrap_or(0xFFFF_FFFF);
            if back != i as u32 {
                anyhow::bail!(
                    "pair map not involutive at i={i}: match[i]={m}, but match[match[i]]={back}"
                );
            }
        }
    }
    Ok(())
}

fn assert_type_agrees(sc: &[u32], map: &[u32]) -> Result<()> {
    for i in 0..sc.len() {
        let m = *map.get(i).unwrap_or(&0xFFFF_FFFF);
        if m == 0xFFFF_FFFF {
            continue;
        }
        let a = sc[i];
        let b = sc[m as usize];
        if ((a ^ b) & 1) == 0 {
            anyhow::bail!(
                "pair does not connect push<->pop at i={i} <-> {m} (codes {a:#x},{b:#x})"
            );
        }
        let sym_a = a >> 1;
        let sym_b = b >> 1;
        if sym_a != sym_b {
            anyhow::bail!(
                "type mismatch in pair i={i} <-> {m} (sym_a={}, sym_b={})",
                sym_a,
                sym_b
            );
        }
    }
    Ok(())
}

fn assert_stream_lengths_from_headers(
    headers: &[ActionHeader],
    sc_len: usize,
    emit_len: usize,
) -> Result<()> {
    let mut sum_sc: usize = 0;
    let mut sum_emit: usize = 0;
    for h in headers {
        sum_sc += (h.push_len + h.pop_count) as usize;
        sum_emit += h.emit_len as usize;
    }
    if sum_sc != sc_len {
        anyhow::bail!(
            "stack-change length mismatch: headers sum={} vs sc_stream.len()={}",
            sum_sc,
            sc_len
        );
    }
    if sum_emit != emit_len {
        anyhow::bail!(
            "emit length mismatch: headers sum={} vs emit_stream.len()={}",
            sum_emit,
            emit_len
        );
    }
    Ok(())
}

fn assert_tree_forest_shape(node_kind: &[u32], parent: &[u32], prod_arity: &[u32]) -> Result<()> {
    if node_kind.len() != parent.len() {
        anyhow::bail!(
            "tree arrays length mismatch: node_kind.len()={} parent.len()={}",
            node_kind.len(),
            parent.len()
        );
    }
    if node_kind.is_empty() {
        return Ok(());
    }
    for i in 0..node_kind.len() {
        if parent[i] == 0xFFFF_FFFF {
            continue;
        }
        let p = parent[i] as usize;
        if p >= i {
            anyhow::bail!(
                "parent pointer not backward at node {}: parent[i]={}",
                i,
                parent[i]
            );
        }
    }
    let mut child_counts = vec![0usize; node_kind.len()];
    for i in 0..node_kind.len() {
        if parent[i] == 0xFFFF_FFFF {
            continue;
        }
        let p = parent[i] as usize;
        child_counts[p] += 1;
    }
    for i in 0..node_kind.len() {
        let nk = node_kind[i] as usize;
        let want = *prod_arity.get(nk).unwrap_or(&0) as usize;
        if child_counts[i] != want {
            anyhow::bail!(
                "arity mismatch at node {i}: kind={} expected_children={} got={}",
                nk,
                want,
                child_counts[i]
            );
        }
    }
    Ok(())
}

// ------------------------ goldens: sidecar .parse.json ------------------------

#[derive(Deserialize)]
struct GoldenSizes {
    headers: usize,
    sc: usize,
    emit: usize,
    nodes: usize,
}
#[derive(Deserialize)]
struct GoldenBrackets {
    valid: bool,
    final_depth: i32,
    min_depth: i32,
}
#[derive(Deserialize)]
struct GoldenHashes {
    sc: u64,
    emit: u64,
    match_for_index: u64,
    node_kind: u64,
    parent: u64,
}
#[derive(Deserialize)]
struct ParseGolden {
    sizes: GoldenSizes,
    brackets: GoldenBrackets,
    hashes: GoldenHashes,
}

fn sidecar_path_for(p: &Path) -> PathBuf {
    let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or("case");
    let dir = p.parent().unwrap_or_else(|| Path::new("."));
    dir.join(format!("{stem}.parse.json"))
}

fn fnv1a_u32s(xs: &[u32]) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for &x in xs {
        for b in x.to_le_bytes() {
            h ^= b as u64;
            h = h.wrapping_mul(0x100000001b3);
        }
    }
    h ^ (xs.len() as u64)
}

// --- test-oracle-vs-GPU comparison against golden -------------------------

fn types_from_src(src: &str) -> Vec<u32> {
    // 0 for paren, 1 for bracket, in the exact source event order.
    let mut out = Vec::with_capacity(src.len());
    for ch in src.chars() {
        match ch {
            '(' | ')' => out.push(0),
            '[' | ']' => out.push(1),
            _ => {}
        }
    }
    out
}

fn check_against_golden(path: &Path, src: &str, res: &ParseResult) -> Result<()> {
    use serde_json::Value;

    let sidecar = sidecar_path_for(path);
    if !sidecar.exists() {
        return Ok(()); // no golden yet → skip
    }
    let s = std::fs::read_to_string(&sidecar)
        .with_context(|| format!("read golden {}", sidecar.display()))?;

    let v: Value =
        serde_json::from_str(&s).with_context(|| format!("parse golden {}", sidecar.display()))?;

    // If this is a test CPU oracle golden, do a full structural comparison.
    // Older generated sidecars predate the marker but contain `sc_canon`.
    if v.get("test_cpu_oracle_only").and_then(|b| b.as_bool()) == Some(true)
        || v.get("sc_canon").is_some()
    {
        let ty_seq = types_from_src(src);
        let delimiter_shape_matches = ty_seq.len() == res.sc_stream.len();
        if delimiter_shape_matches {
            // 1) bracket summary must match when test CPU oracle and GPU streams describe
            // the same delimiter event surface. Newer parser stack streams also
            // include grammar events, so old test-CPU delimiter goldens are not
            // directly comparable in that case.
            let b = v
                .get("brackets")
                .ok_or_else(|| anyhow::anyhow!("golden missing 'brackets'"))?;
            let g_valid = b
                .get("valid")
                .and_then(|x| x.as_bool())
                .ok_or_else(|| anyhow::anyhow!("golden.brackets.valid"))?;
            let g_final = b
                .get("final_depth")
                .and_then(|x| x.as_i64())
                .ok_or_else(|| anyhow::anyhow!("golden.brackets.final_depth"))?
                as i32;
            let g_min = b
                .get("min_depth")
                .and_then(|x| x.as_i64())
                .ok_or_else(|| anyhow::anyhow!("golden.brackets.min_depth"))?
                as i32;

            if (g_valid, g_final, g_min)
                != (
                    res.brackets.valid,
                    res.brackets.final_depth,
                    res.brackets.min_depth,
                )
            {
                anyhow::bail!(
                    "{}: brackets summary differs from test CPU oracle golden",
                    path.display()
                );
            }
        } else {
            eprintln!(
                "[warn] {}: skipping test-CPU delimiter golden compare (golden events={}, GPU sc={})",
                path.display(),
                ty_seq.len(),
                res.sc_stream.len()
            );
        }

        // 2) canonicalize GPU sc_stream to the test CPU oracle's event typing and compare
        if delimiter_shape_matches
            && let Some(sc_golden) = v.get("sc_canon").and_then(|x| x.as_array())
        {
            let sc_g: Vec<u32> = sc_golden
                .iter()
                .map(|x| x.as_u64().unwrap() as u32)
                .collect();

            let mut sc_gpu_canon = Vec::with_capacity(res.sc_stream.len());
            for (i, &code) in res.sc_stream.iter().enumerate() {
                let push = code & 1;
                let ty = ty_seq[i]; // 0='(', 1='[' by source order
                sc_gpu_canon.push((ty << 1) | push);
            }

            if sc_gpu_canon != sc_g {
                anyhow::bail!(
                    "{}: sc_stream differs from test CPU oracle golden (canonicalized)",
                    path.display()
                );
            }
        }

        // 3) exact pair map must match when provided
        if delimiter_shape_matches
            && let Some(mfi_golden) = v.get("match_for_index").and_then(|x| x.as_array())
        {
            let mfi_g: Vec<u32> = mfi_golden
                .iter()
                .map(|x| x.as_u64().unwrap() as u32)
                .collect();
            if res.brackets.match_for_index != mfi_g {
                anyhow::bail!(
                    "{}: match_for_index differs from test CPU oracle golden",
                    path.display()
                );
            }
        }

        // 4) tree parent array must match if sizes agree (node_kind may be production-IDs on GPU)
        if let Some(tree_v) = v.get("tree") {
            let nk_g: Option<Vec<u32>> = tree_v
                .get("node_kind")
                .and_then(|x| x.as_array())
                .map(|arr| arr.iter().map(|u| u.as_u64().unwrap() as u32).collect());
            let par_g: Option<Vec<u32>> = tree_v
                .get("parent")
                .and_then(|x| x.as_array())
                .map(|arr| arr.iter().map(|u| u.as_u64().unwrap() as u32).collect());

            if let (Some(_nk_g), Some(par_g)) = (nk_g, par_g) {
                if res.parent.len() == par_g.len() {
                    if res.parent != par_g {
                        anyhow::bail!(
                            "{}: parse tree parent array differs from test CPU oracle golden",
                            path.display()
                        );
                    }
                } else {
                    eprintln!(
                        "[warn] {}: skipping tree compare (GPU nodes={}, test CPU oracle nodes={})",
                        path.display(),
                        res.parent.len(),
                        par_g.len()
                    );
                }
            }
        }
        return Ok(());
    }

    // Otherwise: support the older strict format (sizes + hashes).
    let g: ParseGolden = serde_json::from_value(v)
        .with_context(|| format!("parse full golden {}", sidecar.display()))?;

    if g.sizes.headers != res.headers.len()
        || g.sizes.sc != res.sc_stream.len()
        || g.sizes.emit != res.emit_stream.len()
        || g.sizes.nodes != res.node_kind.len()
    {
        anyhow::bail!("{}: size mismatch vs golden", path.display());
    }

    if (
        g.brackets.valid,
        g.brackets.final_depth,
        g.brackets.min_depth,
    ) != (
        res.brackets.valid,
        res.brackets.final_depth,
        res.brackets.min_depth,
    ) {
        anyhow::bail!("{}: brackets summary differs from golden", path.display());
    }

    let h_sc = fnv1a_u32s(&res.sc_stream);
    let h_emit = fnv1a_u32s(&res.emit_stream);
    let h_match = fnv1a_u32s(&res.brackets.match_for_index);
    let h_node = fnv1a_u32s(&res.node_kind);
    let h_parent = fnv1a_u32s(&res.parent);

    if g.hashes.sc != h_sc
        || g.hashes.emit != h_emit
        || g.hashes.match_for_index != h_match
        || g.hashes.node_kind != h_node
        || g.hashes.parent != h_parent
    {
        anyhow::bail!("{}: stream/hash differs from golden", path.display());
    }
    Ok(())
}

// ------------------------ run one source ------------------------

async fn run_source(
    path_opt: Option<&Path>,
    label: &str,
    src: &str,
    lexer: &GpuLexer,
    parser: &GpuParser,
    tables: &PrecomputedParseTables,
) -> Result<()> {
    let toks = lexer
        .lex(src)
        .await
        .with_context(|| format!("lex {}", label))?;
    let mut kinds: Vec<u32> = toks.iter().map(|t| t.kind as u32).collect();
    kinds.insert(0, 0);
    kinds.push(0);

    let res = parser
        .parse(&kinds, tables)
        .await
        .with_context(|| format!("parse {}", label))?;
    let expected_pairs = kinds.len().saturating_sub(1);
    if tables.n_nonterminals > 0 {
        let test_cpu_ll1 = tables.test_cpu_ll1_production_stream(&kinds);

        if path_opt.is_some() && !res.ll1.accepted {
            anyhow::bail!(
                "LL(1) GPU acceptance failed for {} at token pos {} (code={}, detail={}, steps={})",
                label,
                res.ll1.error_pos,
                res.ll1.error_code,
                res.ll1.detail,
                res.ll1.steps
            );
        }
        match (test_cpu_ll1, res.ll1.accepted) {
            (Ok(expected), true) => {
                if res.ll1_emit_stream != expected {
                    anyhow::bail!(
                        "LL(1) production stream mismatch for {}: GPU len={} test CPU oracle len={}",
                        label,
                        res.ll1_emit_stream.len(),
                        expected.len()
                    );
                }
                let projected = tables.test_cpu_projected_production_stream(&kinds);
                if res.emit_stream != projected {
                    anyhow::bail!(
                        "LLP projected stream mismatch for {}: GPU len={} test CPU pair-oracle len={}",
                        label,
                        res.emit_stream.len(),
                        projected.len()
                    );
                }
            }
            (Ok(expected), false) => {
                anyhow::bail!(
                    "GPU rejected a test-CPU-oracle-accepted LL(1) parse for {} (oracle productions={})",
                    label,
                    expected.len()
                );
            }
            (Err(err), true) => {
                anyhow::bail!(
                    "GPU accepted a test-CPU-oracle-rejected LL(1) parse for {}: {}",
                    label,
                    err
                );
            }
            (Err(_), false) => {}
        }
    }
    if tables.n_nonterminals > 0 && res.ll1_block_size > 0 {
        let real_tokens = kinds.len().saturating_sub(2);
        let expected_blocks = real_tokens.div_ceil(res.ll1_block_size as usize).max(1);
        if res.ll1.accepted {
            if !res.ll1_seed_plan.accepted
                || res.ll1_seed_plan.emit_len as usize != res.ll1_emit_stream.len()
                || res.ll1_seed_plan.seed_count as usize != expected_blocks
            {
                anyhow::bail!(
                    "LL(1) seed plan mismatch for {}: accepted={} seeds={} emits={} full_emits={}",
                    label,
                    res.ll1_seed_plan.accepted,
                    res.ll1_seed_plan.seed_count,
                    res.ll1_seed_plan.emit_len,
                    res.ll1_emit_stream.len()
                );
            }
            if res.ll1_seeded_blocks.len() != expected_blocks {
                anyhow::bail!(
                    "LL(1) seeded block count mismatch for {}: got {} want {}",
                    label,
                    res.ll1_seeded_blocks.len(),
                    expected_blocks
                );
            }

            let mut seeded_emit = Vec::with_capacity(res.ll1_emit_stream.len());
            for (i, block) in res.ll1_seeded_blocks.iter().enumerate() {
                let expected_status = if i + 1 == expected_blocks {
                    LL1_BLOCK_STATUS_ACCEPTED
                } else {
                    LL1_BLOCK_STATUS_BOUNDARY
                };
                if block.status != expected_status || block.pos != block.end {
                    anyhow::bail!(
                        "LL(1) seeded block mismatch for {} block {}: status={} want={} pos={} end={}",
                        label,
                        i,
                        block.status,
                        expected_status,
                        block.pos,
                        block.end
                    );
                }
                let base = i * res.ll1_block_emit_stride as usize;
                let len = block.emit_len as usize;
                let Some(chunk) = res.ll1_seeded_emit.get(base..base + len) else {
                    anyhow::bail!("LL(1) seeded emit slice out of range for {}", label);
                };
                seeded_emit.extend_from_slice(chunk);
            }
            if seeded_emit != res.ll1_emit_stream {
                anyhow::bail!(
                    "LL(1) seeded emit mismatch for {}: seeded_len={} full_len={}",
                    label,
                    seeded_emit.len(),
                    res.ll1_emit_stream.len()
                );
            }
        }
    }

    // core invariants on the GPU output itself
    if res.headers.len() != expected_pairs {
        anyhow::bail!(
            "headers.len mismatch: got {} want {}",
            res.headers.len(),
            expected_pairs
        );
    }
    let test_cpu = test_cpu_brackets(&res.sc_stream);
    if (test_cpu.valid, test_cpu.final_depth, test_cpu.min_depth)
        != (
            res.brackets.valid,
            res.brackets.final_depth,
            res.brackets.min_depth,
        )
    {
        anyhow::bail!(
            "test CPU oracle/GPU bracket summary mismatch for {} (gpu v={},f={},m={} vs oracle v={},f={},m={})",
            label,
            res.brackets.valid,
            res.brackets.final_depth,
            res.brackets.min_depth,
            test_cpu.valid,
            test_cpu.final_depth,
            test_cpu.min_depth
        );
    }
    assert_involutive(&res.brackets.match_for_index)?;
    if res.brackets.valid {
        assert_type_agrees(&res.sc_stream, &res.brackets.match_for_index)?;
    }
    assert_stream_lengths_from_headers(&res.headers, res.sc_stream.len(), res.emit_stream.len())?;
    // Random token fuzz usually rejects partway through the grammar, so only
    // run full production-tree arity checks for accepted streams.
    if env_truthy("LANIUS_PARSE_FUZZ_CHECK_TREE") && res.ll1.accepted {
        assert_tree_forest_shape(&res.node_kind, &res.parent, &tables.prod_arity)?;
    }

    // golden (if present) — compare GPU to explicitly named test-oracle truth
    if let Some(p) = path_opt {
        check_against_golden(p, src, &res)?;
    }

    println!(
        "[ok] {} (ll1={}, pairs={}, sc={}, projected_emits={}, ll1_emits={}, nodes={})",
        label,
        res.ll1.accepted,
        res.headers.len(),
        res.sc_stream.len(),
        res.emit_stream.len(),
        res.ll1_emit_stream.len(),
        res.node_kind.len()
    );
    Ok(())
}

// ------------------------ CLI args ------------------------

#[derive(Debug, Clone, Copy)]
struct FuzzCfg {
    iters: usize,
    len: usize,
    seed: u64,
}

fn parse_cli_args(args: &[String]) -> (Vec<PathBuf>, FuzzCfg) {
    let mut paths = Vec::new();
    let mut iters = 3usize;
    let mut len = 1_000_000usize;
    let mut seed = 42u64;

    for a in args {
        if let Some(v) = a.strip_prefix("--iters=") {
            if let Ok(n) = v.parse() {
                iters = n;
            } else {
                warn!("invalid --iters value '{v}'; keeping default {iters}");
            }
        } else if let Some(v) = a.strip_prefix("--len=") {
            if let Ok(n) = v.parse() {
                len = n;
            } else {
                warn!("invalid --len value '{v}'; keeping default {len}");
            }
        } else if let Some(v) = a.strip_prefix("--seed=") {
            if let Ok(n) = v.parse() {
                seed = n;
            } else {
                warn!("invalid --seed value '{v}'; keeping default {seed}");
            }
        } else if a.starts_with("--") {
            eprintln!("[warn] unknown flag '{}'", a);
        } else {
            paths.push(PathBuf::from(a));
        }
    }
    (paths, FuzzCfg { iters, len, seed })
}

// --------------------------------- main ---------------------------------

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (mut paths, fuzz) = parse_cli_args(&args);

    if paths.is_empty() {
        paths = collect_inputs_from_dir("parser_tests");
    }

    if paths.is_empty() {
        eprintln!(
            "[parse_fuzz] no .lani files found in parser_tests/ and no explicit files; continuing with random corpus only."
        );
    }

    let lexer = GpuLexer::new().await.context("init GpuLexer")?;
    let parser = GpuParser::new().await.context("init GpuParser")?;
    let tables = load_tables()?;

    let mut passed = 0usize;
    let mut failed = 0usize;

    // 1) File corpus (goldens checked if present)
    for path in paths {
        let label = path.display().to_string();
        let src =
            std::fs::read_to_string(&path).with_context(|| format!("read input {}", label))?;
        match run_source(Some(&path), &label, &src, &lexer, &parser, &tables).await {
            Ok(()) => passed += 1,
            Err(e) => {
                eprintln!("[fail] {}:\n  {}", label, e);
                failed += 1;
                break; // fail-fast; flip if you want full sweep
            }
        }
    }

    // 2) Random corpus — ALWAYS ON (not env-gated)
    let mut rng = StdRng::seed_from_u64(fuzz.seed);
    println!(
        "[fuzz] random corpus: iters={} len={} seed={}",
        fuzz.iters, fuzz.len, fuzz.seed
    );

    for i in 0..fuzz.iters {
        // Use the repo’s generator to make *valid* sources.
        let src = laniusc::dev::generator::gen_valid_source(&mut rng, fuzz.len);
        let label = format!("fuzz_iter_{}_bytes_{}", i, src.len());
        match run_source(None, &label, &src, &lexer, &parser, &tables).await {
            Ok(()) => passed += 1,
            Err(e) => {
                eprintln!("[fail] {}:\n  {}", label, e);
                // Write a repro case immediately so it’s not lost.
                let ts = match SystemTime::now().duration_since(UNIX_EPOCH) {
                    Ok(elapsed) => elapsed.as_secs(),
                    Err(err) => {
                        warn!("system clock before UNIX_EPOCH: {err}");
                        0
                    }
                };
                let dir = "fuzz-cases";
                if let Err(err) = std::fs::create_dir_all(dir) {
                    warn!("failed to create {dir}: {err}");
                }
                let path = format!("{}/case_{ts}_i{}_n{}.lani", dir, i, src.len());
                if let Err(e) = std::fs::write(&path, src.as_bytes()) {
                    eprintln!("[save] failed to write repro case: {e}");
                } else {
                    eprintln!("[save] wrote repro case: {}", path);
                    eprintln!("[replay] cargo run --bin parse_fuzz -- {}", path);
                }
                failed += 1;
                break;
            }
        }
    }

    println!("[parse_fuzz] summary: passed={} failed={}", passed, failed);
    if failed > 0 {
        std::process::exit(1);
    }
    Ok(())
}
