use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};

#[derive(Debug)]
pub struct SampleProgram {
    name: String,
    path: PathBuf,
    source: String,
    stdout_path: PathBuf,
    expected_stdout: String,
    checked_targets: Vec<String>,
}

impl SampleProgram {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn source(&self) -> &str {
        &self.source
    }

    pub fn checked_for_target(&self, target: &str) -> bool {
        self.checked_targets.iter().any(|checked| checked == target)
    }

    pub fn assert_stdout_eq(&self, backend: &str, actual: &str) {
        assert_eq!(
            actual,
            self.expected_stdout.as_str(),
            "{}: {backend} stdout mismatch for sample {} (expected output from {})",
            self.name,
            self.path.display(),
            self.stdout_path.display()
        );
    }
}

pub fn load_sample_programs() -> Vec<SampleProgram> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("sample_programs");
    let manifest = load_sample_manifest(&root);
    let mut programs = Vec::new();
    let mut expected_outputs = Vec::new();

    for entry in fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("read sample_programs dir {}: {err}", root.display()))
    {
        let path = entry
            .unwrap_or_else(|err| panic!("read sample_programs entry in {}: {err}", root.display()))
            .path();
        match path.extension().and_then(|ext| ext.to_str()) {
            Some("lani") => programs.push(path),
            Some("stdout") => expected_outputs.push(path),
            _ => {}
        }
    }

    programs.sort();
    expected_outputs.sort();
    assert!(
        !programs.is_empty(),
        "expected at least one sample program (*.lani) in {}",
        root.display()
    );

    assert_no_missing_stdout(&programs);
    assert_no_orphan_stdout(&expected_outputs);
    assert_manifest_matches_programs(&programs, &manifest);

    programs
        .into_iter()
        .map(|path| load_sample_program(path, &manifest))
        .collect::<Vec<_>>()
}

fn assert_no_missing_stdout(programs: &[PathBuf]) {
    let missing_stdout = programs
        .iter()
        .filter_map(|program| {
            let stdout_path = program.with_extension("stdout");
            (!stdout_path.is_file()).then(|| sample_path_message(program, &stdout_path))
        })
        .collect::<Vec<_>>();

    if !missing_stdout.is_empty() {
        panic!(
            "sample programs missing .stdout files:\n{}",
            bullet_list(&missing_stdout)
        );
    }
}

fn assert_no_orphan_stdout(expected_outputs: &[PathBuf]) {
    let orphan_stdout = expected_outputs
        .iter()
        .filter_map(|expected| {
            let source_path = expected.with_extension("lani");
            (!source_path.is_file()).then(|| sample_path_message(expected, &source_path))
        })
        .collect::<Vec<_>>();

    if !orphan_stdout.is_empty() {
        panic!(
            "sample stdout files missing .lani programs:\n{}",
            bullet_list(&orphan_stdout)
        );
    }
}

fn load_sample_program(
    path: PathBuf,
    manifest: &HashMap<String, SampleManifestEntry>,
) -> SampleProgram {
    let name = sample_name(&path);
    let stdout_path = path.with_extension("stdout");
    let manifest_entry = manifest
        .get(&name)
        .unwrap_or_else(|| panic!("{name}: missing row in sample_programs/MANIFEST.tsv"));
    let stdout_file_name = stdout_path
        .file_name()
        .and_then(|file| file.to_str())
        .unwrap_or_else(|| panic!("{name}: invalid stdout path {}", stdout_path.display()));
    assert_eq!(
        manifest_entry.stdout, stdout_file_name,
        "{name}: manifest stdout should match sibling stdout file"
    );
    let source = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("{name}: read sample source {}: {err}", path.display()));
    let expected_stdout = fs::read_to_string(&stdout_path).unwrap_or_else(|err| {
        panic!(
            "{name}: read expected stdout {} for sample {}: {err}",
            stdout_path.display(),
            path.display()
        )
    });

    SampleProgram {
        name,
        path,
        source,
        stdout_path,
        expected_stdout,
        checked_targets: manifest_entry.checked_targets.clone(),
    }
}

#[derive(Debug, Clone)]
struct SampleManifestEntry {
    stdout: String,
    checked_targets: Vec<String>,
}

fn load_sample_manifest(root: &Path) -> HashMap<String, SampleManifestEntry> {
    let path = root.join("MANIFEST.tsv");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("read sample manifest {}: {err}", path.display()));
    let mut lines = text.lines();
    let header = lines
        .next()
        .unwrap_or_else(|| panic!("sample manifest {} is empty", path.display()));
    assert_eq!(
        header, "sample\tstdout\tslice\tchecked_targets\tevidence_policy",
        "sample manifest header changed unexpectedly"
    );

    let mut entries = HashMap::new();
    for (line_i, line) in lines.enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        let line_no = line_i + 2;
        let fields = line.split('\t').collect::<Vec<_>>();
        assert_eq!(
            fields.len(),
            5,
            "sample manifest line {line_no} should have 5 tab-separated fields"
        );
        let checked_targets = parse_checked_targets(fields[3], line_no);
        let previous = entries.insert(
            fields[0].to_string(),
            SampleManifestEntry {
                stdout: fields[1].to_string(),
                checked_targets,
            },
        );
        assert!(
            previous.is_none(),
            "duplicate sample manifest row for {}",
            fields[0]
        );
    }
    entries
}

fn parse_checked_targets(raw: &str, line_no: usize) -> Vec<String> {
    if raw == "-" {
        return Vec::new();
    }

    raw.split(',')
        .map(str::trim)
        .filter(|target| !target.is_empty())
        .map(|target| {
            assert!(
                matches!(target, "x86_64" | "wasm"),
                "sample manifest line {line_no} has unknown checked target {target}"
            );
            target.to_string()
        })
        .collect()
}

fn assert_manifest_matches_programs(
    programs: &[PathBuf],
    manifest: &HashMap<String, SampleManifestEntry>,
) {
    let program_names = programs
        .iter()
        .map(|path| sample_name(path))
        .collect::<Vec<_>>();
    let missing_rows = program_names
        .iter()
        .filter(|name| !manifest.contains_key(name.as_str()))
        .map(|name| format!("{name}: sample_programs/MANIFEST.tsv needs a row"))
        .collect::<Vec<_>>();
    if !missing_rows.is_empty() {
        panic!(
            "sample programs missing manifest rows:\n{}",
            bullet_list(&missing_rows)
        );
    }

    let extra_rows = manifest
        .keys()
        .filter(|name| !program_names.iter().any(|program| program == *name))
        .map(|name| format!("{name}: manifest row has no matching sample source"))
        .collect::<Vec<_>>();
    if !extra_rows.is_empty() {
        panic!(
            "sample manifest rows missing .lani programs:\n{}",
            bullet_list(&extra_rows)
        );
    }
}

fn sample_name(path: &Path) -> String {
    path.file_stem()
        .and_then(|stem| stem.to_str())
        .map(str::to_owned)
        .unwrap_or_else(|| path.display().to_string())
}

fn sample_path_message(path: &Path, counterpart: &Path) -> String {
    format!(
        "{}: {} needs {}",
        sample_name(path),
        path.display(),
        counterpart.display()
    )
}

fn bullet_list(items: &[String]) -> String {
    items
        .iter()
        .map(|item| format!("  - {item}"))
        .collect::<Vec<_>>()
        .join("\n")
}
