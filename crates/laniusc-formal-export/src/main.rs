use std::{env, path::PathBuf};

use anyhow::{Context, Result, bail};
use laniusc_formal_export::{extract_typed_artifact, extract_typed_artifact_pack};

fn main() -> Result<()> {
    let mut arguments = env::args_os().skip(1).collect::<Vec<_>>();
    if arguments
        .first()
        .is_some_and(|argument| argument == "--pack")
    {
        arguments.remove(0);
        let output = arguments
            .first()
            .map(PathBuf::from)
            .context("usage: laniusc-formal-export --pack <artifact.json> <source.lani>...")?;
        let sources = arguments[1..].iter().map(PathBuf::from).collect::<Vec<_>>();
        if sources.is_empty() {
            bail!("usage: laniusc-formal-export --pack <artifact.json> <source.lani>...");
        }
        let artifact = extract_typed_artifact_pack(&sources)?;
        let encoded = serde_json::to_vec(&artifact).context("encode extraction artifact pack")?;
        std::fs::write(&output, encoded)
            .with_context(|| format!("write extraction artifact pack {}", output.display()))?;
        return Ok(());
    }

    let mut arguments = arguments.into_iter();
    let source = arguments
        .next()
        .map(PathBuf::from)
        .context("usage: laniusc-formal-export <source.lani> <artifact.json>")?;
    let output = arguments
        .next()
        .map(PathBuf::from)
        .context("usage: laniusc-formal-export <source.lani> <artifact.json>")?;
    if arguments.next().is_some() {
        bail!("usage: laniusc-formal-export <source.lani> <artifact.json>");
    }

    let artifact = extract_typed_artifact(&source)?;
    let encoded = serde_json::to_vec(&artifact).context("encode extraction artifact")?;
    std::fs::write(&output, encoded)
        .with_context(|| format!("write extraction artifact {}", output.display()))?;
    Ok(())
}
