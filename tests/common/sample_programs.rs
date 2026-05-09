use std::{
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

    programs
        .into_iter()
        .map(load_sample_program)
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

fn load_sample_program(path: PathBuf) -> SampleProgram {
    let name = sample_name(&path);
    let stdout_path = path.with_extension("stdout");
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
