// src/bin/token_kinds_dump.rs
// Developer differential tool for the GPU parser token frontend. It writes the
// semantic token kinds of every corpus stream so a shader refactor can be
// checked bit-for-bit against a build of the previous revision.
//
// CLI (run from the workspace root, which holds tables/parse_tables.bin):
//   cargo run --release --bin token_kinds_dump -- OUT.tsv PATH... \
//       [--mutations=N] [--seed=S] [--concat]
//
// Each PATH is a .lani file or a directory searched recursively. Every output
// line is `label<TAB>count<TAB>words...`. `--mutations=N` adds N randomly
// edited copies of every lexed stream (token deletes, inserts and swaps), so
// unbalanced and unusual delimiter structure is covered too. `--concat` adds
// one stream holding every file's tokens back to back, which exercises the
// multi-block delimiter hierarchy. With LANIUS_DEBUG_TOKEN_KINDS_SYMBOLS_ONLY=1
// the frontend stops after `parser.tokens_to_kinds`, so the dump is that
// pass's output rather than the final parser alphabet.

use std::{
    io::Write,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use laniusc_compiler::{
    lexer::driver::GpuLexer,
    parser::{driver::GpuParser, tables::PrecomputedParseTables},
};
use rand::{Rng, SeedableRng, rngs::StdRng};

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

fn mutate(raw: &[u32], alphabet: &[u32], rng: &mut StdRng) -> Vec<u32> {
    let mut stream = raw.to_vec();
    let edits = rng.random_range(1..=8);
    for _ in 0..edits {
        let len = stream.len();
        match rng.random_range(0..3) {
            0 if len > 0 => {
                stream.remove(rng.random_range(0..len));
            }
            1 if len > 1 => {
                let at = rng.random_range(0..len - 1);
                stream.swap(at, at + 1);
            }
            _ => {
                let kind = alphabet[rng.random_range(0..alphabet.len())];
                stream.insert(rng.random_range(0..=len), kind);
            }
        }
    }
    stream
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let mut out_path = None;
    let mut inputs = Vec::new();
    let mut mutations = 0usize;
    let mut seed = 1u64;
    let mut concat = false;
    for arg in std::env::args().skip(1) {
        if let Some(value) = arg.strip_prefix("--mutations=") {
            mutations = value.parse().context("parse --mutations")?;
        } else if let Some(value) = arg.strip_prefix("--seed=") {
            seed = value.parse().context("parse --seed")?;
        } else if arg == "--concat" {
            concat = true;
        } else if out_path.is_none() {
            out_path = Some(PathBuf::from(arg));
        } else {
            collect_lani(Path::new(&arg), &mut inputs)?;
        }
    }
    let out_path = out_path.context("usage: token_kinds_dump OUT.tsv PATH...")?;

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
    let mut write_stream = |label: &str, raw: &[u32]| -> Result<()> {
        let mut kinds = Vec::with_capacity(raw.len() + 2);
        kinds.push(0);
        kinds.extend_from_slice(raw);
        kinds.push(0);
        match parser.debug_semantic_token_kinds_for_raw_token_kinds(&kinds, &tables) {
            Ok(words) => {
                write!(out, "{label}\t{}\t", words.len())?;
                for word in words {
                    write!(out, "{word} ")?;
                }
                writeln!(out)?;
            }
            Err(err) => writeln!(out, "{label}\terror\t{err:#}")?,
        }
        Ok(())
    };

    let mut alphabet = std::collections::BTreeSet::new();
    let mut streams = Vec::new();
    for path in &inputs {
        let label = path.display().to_string();
        let source = match std::fs::read_to_string(path) {
            Ok(source) => source,
            Err(err) => {
                eprintln!("[token_kinds_dump] skip {label}: {err}");
                continue;
            }
        };
        let raw = match lexer.lex(&source).await {
            Ok(tokens) => tokens.iter().map(|token| token.kind as u32).collect::<Vec<_>>(),
            Err(err) => {
                writeln!(std::io::stderr(), "[token_kinds_dump] lex {label}: {err:#}")?;
                continue;
            }
        };
        alphabet.extend(raw.iter().copied());
        write_stream(&label, &raw)?;
        streams.push((label, raw));
    }

    let alphabet = alphabet.into_iter().collect::<Vec<_>>();
    if !alphabet.is_empty() {
        let mut rng = StdRng::seed_from_u64(seed);
        for (label, raw) in &streams {
            for index in 0..mutations {
                let mutated = mutate(raw, &alphabet, &mut rng);
                write_stream(&format!("{label}#m{index}"), &mutated)?;
            }
        }
    }
    if concat {
        let all = streams
            .iter()
            .flat_map(|(_, raw)| raw.iter().copied())
            .collect::<Vec<_>>();
        write_stream("<concat>", &all)?;
    }
    eprintln!(
        "[token_kinds_dump] wrote {} streams ({} files) to {}",
        streams.len() * (1 + mutations) + usize::from(concat),
        streams.len(),
        out_path.display()
    );
    Ok(())
}
