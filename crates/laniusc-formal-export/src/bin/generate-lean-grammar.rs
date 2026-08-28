use std::{env, path::PathBuf};

use anyhow::{Context, Result, bail};
use laniusc_formal_export::parser::render_lean_grammar;

fn main() -> Result<()> {
    let mut arguments = env::args_os().skip(1);
    let output = arguments
        .next()
        .map(PathBuf::from)
        .context("usage: generate-lean-grammar <GeneratedGrammar.lean>")?;
    if arguments.next().is_some() {
        bail!("usage: generate-lean-grammar <GeneratedGrammar.lean>");
    }
    std::fs::write(&output, render_lean_grammar()?)
        .with_context(|| format!("write generated Lean grammar {}", output.display()))?;
    Ok(())
}
