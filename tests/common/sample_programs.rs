use std::{
    collections::HashMap,
    env,
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
    expected_exit_code: i32,
    input_files: Vec<SampleFileMapping>,
    output_files: Vec<SampleExpectedFile>,
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

    pub fn selected_by_env_filter(&self) -> bool {
        selected_by_env_filter(&self.name)
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

    pub fn assert_exit_code_eq(&self, backend: &str, actual: i32) {
        assert_eq!(
            actual,
            self.expected_exit_code,
            "{}: {backend} exit code mismatch for sample {}",
            self.name,
            self.path.display()
        );
    }

    pub fn stage_input_files(&self, work_dir: &Path) {
        for input in &self.input_files {
            let destination = work_dir.join(&input.runtime_path);
            if let Some(parent) = destination.parent() {
                fs::create_dir_all(parent).unwrap_or_else(|err| {
                    panic!(
                        "{}: create input parent {}: {err}",
                        self.name,
                        parent.display()
                    )
                });
            }
            fs::copy(&input.source_path, &destination).unwrap_or_else(|err| {
                panic!(
                    "{}: copy sample input {} to {}: {err}",
                    self.name,
                    input.source_path.display(),
                    destination.display()
                )
            });
        }
    }

    pub fn wasm_initial_files(&self) -> Vec<(String, Vec<u8>)> {
        self.input_files
            .iter()
            .map(|input| {
                let bytes = fs::read(&input.source_path).unwrap_or_else(|err| {
                    panic!(
                        "{}: read sample input {}: {err}",
                        self.name,
                        input.source_path.display()
                    )
                });
                (input.runtime_path.clone(), bytes)
            })
            .collect()
    }

    pub fn assert_output_files_eq_dir(&self, backend: &str, work_dir: &Path) {
        for expected in &self.output_files {
            let actual_path = work_dir.join(&expected.runtime_path);
            let actual = fs::read(&actual_path).unwrap_or_else(|err| {
                panic!(
                    "{}: read {backend} output file {}: {err}",
                    self.name,
                    actual_path.display()
                )
            });
            expected.assert_eq(&self.name, backend, &actual);
        }
    }

    pub fn assert_output_files_eq_virtual<'a>(
        &self,
        backend: &str,
        files: impl IntoIterator<Item = (&'a str, &'a [u8])>,
    ) {
        let files = files.into_iter().collect::<HashMap<_, _>>();
        for expected in &self.output_files {
            let actual = files
                .get(expected.runtime_path.as_str())
                .unwrap_or_else(|| {
                    panic!(
                        "{}: {backend} virtual filesystem did not contain expected output {}",
                        self.name, expected.runtime_path
                    )
                });
            expected.assert_eq(&self.name, backend, actual);
        }
    }
}

#[derive(Debug, Clone)]
struct SampleFileMapping {
    runtime_path: String,
    source_path: PathBuf,
}

#[derive(Debug, Clone)]
struct SampleExpectedFile {
    runtime_path: String,
    expected_path: PathBuf,
    expected: Vec<u8>,
}

impl SampleExpectedFile {
    fn assert_eq(&self, sample_name: &str, backend: &str, actual: &[u8]) {
        assert_eq!(
            actual,
            self.expected.as_slice(),
            "{sample_name}: {backend} output file {} mismatch (expected bytes from {})",
            self.runtime_path,
            self.expected_path.display()
        );
    }
}

pub fn load_sample_programs() -> Vec<SampleProgram> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("sample_programs");
    let manifest = load_sample_manifest(&root);
    let mut programs = Vec::new();
    let mut expected_stdout_files = Vec::new();

    for entry in fs::read_dir(&root)
        .unwrap_or_else(|err| panic!("read sample_programs dir {}: {err}", root.display()))
    {
        let path = entry
            .unwrap_or_else(|err| panic!("read sample_programs entry in {}: {err}", root.display()))
            .path();
        match path.extension().and_then(|ext| ext.to_str()) {
            Some("lani") => programs.push(path),
            Some("stdout") => expected_stdout_files.push(path),
            _ => {}
        }
    }

    programs.sort();
    expected_stdout_files.sort();
    assert!(
        !programs.is_empty(),
        "expected at least one sample program (*.lani) in {}",
        root.display()
    );

    assert_no_missing_stdout(&programs);
    assert_no_orphan_stdout(&expected_stdout_files);
    assert_manifest_matches_programs(&programs, &manifest);

    programs
        .into_iter()
        .map(|path| load_sample_program(path, &manifest))
        .collect::<Vec<_>>()
}

fn selected_by_env_filter(name: &str) -> bool {
    let Ok(filter) = env::var("LANIUS_SAMPLE_FILTER") else {
        return true;
    };
    filter
        .split(',')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .any(|entry| entry == name)
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
    let root = path
        .parent()
        .unwrap_or_else(|| panic!("{} has no parent", path.display()))
        .to_path_buf();
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
    let input_files = manifest_entry
        .input_files
        .iter()
        .map(|mapping| mapping.to_sample_file(&root, &name, "input"))
        .collect::<Vec<_>>();
    let output_files = manifest_entry
        .output_files
        .iter()
        .map(|mapping| {
            let file = mapping.to_sample_file(&root, &name, "expected output");
            let expected = fs::read(&file.source_path).unwrap_or_else(|err| {
                panic!(
                    "{name}: read expected output file {}: {err}",
                    file.source_path.display()
                )
            });
            SampleExpectedFile {
                runtime_path: file.runtime_path,
                expected_path: file.source_path,
                expected,
            }
        })
        .collect::<Vec<_>>();

    SampleProgram {
        name,
        path,
        source,
        stdout_path,
        expected_stdout,
        expected_exit_code: manifest_entry.expected_exit_code,
        input_files,
        output_files,
        checked_targets: manifest_entry.checked_targets.clone(),
    }
}

#[derive(Debug, Clone)]
struct SampleManifestEntry {
    stdout: String,
    expected_exit_code: i32,
    input_files: Vec<ManifestFileMapping>,
    output_files: Vec<ManifestFileMapping>,
    checked_targets: Vec<String>,
}

#[derive(Debug, Clone)]
struct ManifestFileMapping {
    runtime_path: String,
    sidecar_path: String,
}

impl ManifestFileMapping {
    fn to_sample_file(&self, root: &Path, sample_name: &str, label: &str) -> SampleFileMapping {
        assert!(
            !Path::new(&self.runtime_path).is_absolute(),
            "{sample_name}: sample {label} runtime path must be relative: {}",
            self.runtime_path
        );
        assert!(
            !self.runtime_path.contains(".."),
            "{sample_name}: sample {label} runtime path must not contain '..': {}",
            self.runtime_path
        );
        let source_path = root.join(&self.sidecar_path);
        assert!(
            source_path.is_file(),
            "{sample_name}: sample {label} sidecar file missing: {}",
            source_path.display()
        );
        SampleFileMapping {
            runtime_path: self.runtime_path.clone(),
            source_path,
        }
    }
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
        header,
        "sample\tstdout\texit_code\tinput_files\toutput_files\tslice\tchecked_targets\tevidence_policy",
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
            8,
            "sample manifest line {line_no} should have 8 tab-separated fields"
        );
        let checked_targets = parse_checked_targets(fields[6], line_no);
        let previous = entries.insert(
            fields[0].to_string(),
            SampleManifestEntry {
                stdout: fields[1].to_string(),
                expected_exit_code: parse_exit_code(fields[2], line_no),
                input_files: parse_file_mappings(fields[3], line_no, "input_files"),
                output_files: parse_file_mappings(fields[4], line_no, "output_files"),
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

fn parse_exit_code(raw: &str, line_no: usize) -> i32 {
    let value = raw.parse::<i32>().unwrap_or_else(|err| {
        panic!("sample manifest line {line_no} exit_code should be an i32: {err}")
    });
    assert!(
        (0..=255).contains(&value),
        "sample manifest line {line_no} exit_code should fit a process status byte: {value}"
    );
    value
}

fn parse_file_mappings(raw: &str, line_no: usize, column: &str) -> Vec<ManifestFileMapping> {
    if raw == "-" {
        return Vec::new();
    }

    raw.split(';')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .map(|entry| {
            let (runtime_path, sidecar_path) = entry.split_once('=').unwrap_or_else(|| {
                panic!(
                    "sample manifest line {line_no} {column} entry should be runtime=sidecar: {entry}"
                )
            });
            assert!(
                !runtime_path.is_empty() && !sidecar_path.is_empty(),
                "sample manifest line {line_no} {column} entry has an empty side: {entry}"
            );
            ManifestFileMapping {
                runtime_path: runtime_path.to_string(),
                sidecar_path: sidecar_path.to_string(),
            }
        })
        .collect()
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
