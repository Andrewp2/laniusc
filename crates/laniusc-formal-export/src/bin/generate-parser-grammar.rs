use anyhow::{Context, Result, ensure};

fn main() -> Result<()> {
    let args = std::env::args_os().skip(1).collect::<Vec<_>>();
    ensure!(
        args.len() == 1,
        "usage: generate-parser-grammar <grammar.json>"
    );
    let words = laniusc_formal_export::parser::packed_lanius_grammar()?;
    std::fs::write(&args[0], serde_json::to_vec(&words)?).context("write packed Lanius grammar")?;
    Ok(())
}
