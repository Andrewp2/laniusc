use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

pub(crate) enum CliEmission {
    Bytes(Vec<u8>),
    File(PathBuf),
}

pub(crate) fn write_cli_emission(
    emitted: CliEmission,
    output: Option<PathBuf>,
    emit: &str,
) -> Result<(), String> {
    match emitted {
        CliEmission::Bytes(bytes) => {
            if let Some(output) = output {
                fs::write(&output, bytes)
                    .map_err(|err| format!("write {}: {err}", output.display()))?;
                mark_output_executable_if_needed(&output, emit)?;
            } else {
                std::io::stdout()
                    .write_all(&bytes)
                    .map_err(|err| format!("write stdout: {err}"))?;
            }
        }
        CliEmission::File(path) => {
            if let Some(output) = output {
                fs::copy(&path, &output).map_err(|err| {
                    format!(
                        "copy linked output {} to {}: {err}",
                        path.display(),
                        output.display()
                    )
                })?;
                mark_output_executable_if_needed(&output, emit)?;
            } else {
                let mut file = fs::File::open(&path)
                    .map_err(|err| format!("open linked output {}: {err}", path.display()))?;
                std::io::copy(&mut file, &mut std::io::stdout()).map_err(|err| {
                    format!("stream linked output {} to stdout: {err}", path.display())
                })?;
            }
        }
    }
    Ok(())
}

fn mark_output_executable_if_needed(output: &Path, emit: &str) -> Result<(), String> {
    #[cfg(unix)]
    if emit != "wasm" {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(output)
            .map_err(|err| format!("stat {}: {err}", output.display()))?
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(output, permissions)
            .map_err(|err| format!("chmod {}: {err}", output.display()))?;
    }
    #[cfg(not(unix))]
    let _ = (output, emit);
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{
        env,
        fs,
        time::{SystemTime, UNIX_EPOCH},
    };

    use super::*;

    #[test]
    fn file_emission_copies_linked_output_without_byte_vec() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        let root = env::temp_dir().join(format!(
            "laniusc-cli-file-emission-test-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir_all(&root).expect("create file emission root");
        let linked_output = root.join("linked-output.bin");
        let output = root.join("out.bin");
        fs::write(&linked_output, b"linked bytes").expect("write linked output");

        write_cli_emission(
            CliEmission::File(linked_output.clone()),
            Some(output.clone()),
            "wasm",
        )
        .expect("copy file emission");

        assert_eq!(
            fs::read(&output).expect("read copied output"),
            b"linked bytes"
        );
        assert!(linked_output.is_file());

        fs::remove_dir_all(&root).expect("remove temp file emission root");
    }
}
