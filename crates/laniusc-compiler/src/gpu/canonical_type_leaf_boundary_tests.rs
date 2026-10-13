//! Direct GPU coverage of the canonical type-domain boundary. The host builds
//! rows and checks observations; all type/constant decisions run in production
//! shader helpers. No compiler frontend or host type solver is involved.

use std::collections::BTreeMap;

use super::{
    buffers::{LaniusBuffer, readback_bytes, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

const INVALID: u32 = u32::MAX;
const BOOL: [u32; 2] = [1, 2];
const CONSTANT: u32 = 0x8000_0001;
const EMPTY: [u32; 2] = [0, INVALID];
const TOKENS: u32 = 4;
const T: u32 = 2;
const LITERAL_THREE: u32 = 4;
const ARRAY: u32 = 7;
const ARRAY_T: u32 = 8;
const BOX: u32 = 9;
const BOX_T: u32 = 10;
const PAIR_T_U: u32 = 11;
const ARRAY_PROJECTED: u32 = 12;
const BOX_ARRAY: u32 = 17;
const CONSTANT_N: u32 = 15;
const ARRAY_N: u32 = 16;
const FIRST_N_PROJECTION: u32 = 18;
const N_PROJECTED_63: u32 = FIRST_N_PROJECTION + 62;
const N_PROJECTED_64: u32 = FIRST_N_PROJECTION + 63;
const ARRAY_N_PROJECTED_63: u32 = N_PROJECTED_64 + 1;
const ARRAY_N_PROJECTED_64: u32 = N_PROJECTED_64 + 2;
const BOX_T_N_PROJECTED_63: u32 = N_PROJECTED_64 + 3;
const BOX_T_N_PROJECTED_64: u32 = N_PROJECTED_64 + 4;

#[derive(encase::ShaderType)]
struct Params {
    nodes: u32,
    arguments: u32,
    environments: u32,
    queries: u32,
    tokens: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

struct Case<const N: usize> {
    label: &'static str,
    query: [u32; 8],
    expected: [Option<u32>; N],
}

fn query(pattern: u32, environment: u32, actual: [u32; 2], infer: bool) -> [u32; 8] {
    [pattern, environment, actual[0], actual[1], u32::from(infer), 1, 5, pattern]
}

struct Fixture {
    nodes: Vec<[u32; 11]>,
    arguments: Vec<[u32; 2]>,
    environments: Vec<[u32; 4]>,
    page: Vec<u32>,
    roots: Vec<u32>,
    constant_refs: Vec<u32>,
}

fn flatten<const N: usize>(rows: &[[u32; N]]) -> Vec<u32> {
    rows.iter().flat_map(|row| row.iter().copied()).collect()
}

fn fixture() -> Fixture {
    let mut f = Fixture {
        nodes: Vec::new(), arguments: Vec::new(),
        // Explicitly retain raw/malformed bindings. A fixture-side filter
        // would hide the production boundary this regression exercises.
        environments: vec![
            [1, 2, 1, 2],             // 0: checked bool
            [5, 0, 1, 2],             // 1: canonical bool
            [5, BOX, 1, 2],           // 2: canonical nominal
            [5, ARRAY, 1, 2],         // 3: canonical array
            [5, LITERAL_THREE, 1, 2], // 4: canonical literal in type domain
            [CONSTANT, 3, 1, 2],      // 5: source literal in type domain
            [5, 6, 1, 2],             // 6: canonical projection in type domain
            [5, 15, 1, 2],            // 7: canonical constant parameter
            [5, T, 1, 2],             // 8: one-step canonical type parameter
            [5, 99, 1, 2],            // 9: out-of-range canonical replacement
            [0, INVALID, 1, 2],       // 10: present malformed binding
            [3, 1, 1, 2],             // 11: checked nominal
            [2, 2, 1, 2],             // 12: caller-owned type parameter U
            [0x8000_0002, 3, 1, 2],   // 13: source constant parameter
            [0x8000_0003, 0, 1, 2],   // 14: source projection
            [5, BOX_ARRAY, 1, 2],     // 15: canonical nested constants
        ],
        page: Vec::new(), roots: Vec::new(), constant_refs: Vec::new(),
    };
    // Checked nodes: array<bool,3>, Box<bool,3>, Pair<bool,bool>,
    // malformed Pair<bool,const3>, wrong-value Box/array, malformed raw
    // canonical operand, and Box<array<bool,3>,3>.
    f.nodes.push([2, INVALID, 0, 1, 2, 1, 3, INVALID, INVALID, INVALID, 0]);
    let mut nominal = |declaration, arguments: &[[u32; 2]], types, constants| {
        let start = f.arguments.len() as u32;
        f.arguments.extend_from_slice(arguments);
        f.nodes.push([1, INVALID, arguments.len() as u32, 0, 0, types, constants,
            7, 11, declaration, start]);
    };
    nominal(17, &[BOOL, [CONSTANT, 3]], 1, 2); // node1
    nominal(18, &[BOOL, BOOL], 2, 0);          // node2
    nominal(18, &[BOOL, [CONSTANT, 3]], 2, 0); // node3: deliberately wrong domain
    nominal(17, &[BOOL, [CONSTANT, 4]], 1, 2); // node4
    drop(nominal);
    f.nodes.push([2, INVALID, 0, 1, 2, 1, 4, INVALID, INVALID, INVALID, 0]); // node5
    for (declaration, arguments, types, constants) in [
        (18, [BOOL, [5, LITERAL_THREE]], 2, 0), // node6: raw constant in a type slot
        (17, [[3, 0], [CONSTANT, 3]], 1, 2),   // node7
    ] {
        let start = f.arguments.len() as u32;
        f.arguments.extend_from_slice(&arguments);
        f.nodes.push([1, INVALID, 2, 0, 0, types, constants, 7, 11, declaration, start]);
    }

    // A tiny portable page, using the actual nine-word type and twelve-word
    // member formats. Canonical root IDs intentionally differ from source IDs.
    let mut edges = vec![4, 0, 4, 2, 4, 0, 4, 2, 4, 2, 3, 0, 6, 0, 15, 7, 4];
    let mut types = vec![
        [1, 2, 0, 0, 0, 0, 0, 0, 0],       // 0 bool
        [1, 4, 0, 0, 0, 0, 0, 0, 0],       // 1 u32
        [2, 0, 0, 0, 0, 0, 0, 0, 0],       // 2 T, member0
        [2, 1, 0, 0, 0, 0, 0, 0, 0],       // 3 U, member1
        [9, 4, 0, 0, 0, 0, 3, 0, 0],       // 4 typed literal3
        [9, 4, 0, 0, 0, 0, 4, 0, 0],       // 5 typed literal4
        [10, 4, 0, 0, 1, 0, 0, 0, 0],      // 6 u32 projection(literal3)
        [4, 0, 0, 1, 2, 0, 0, 0, 0],       // 7 array<bool,3>
        [4, 0, 0, 3, 2, 0, 0, 0, 0],       // 8 array<T,3>
        [3, 7, 17, 5, 2, 0, 0, 0, 11],     // 9 Box<bool,3>
        [3, 7, 17, 7, 2, 0, 0, 0, 11],     // 10 Box<T,3>
        [3, 7, 18, 9, 2, 0, 0, 0, 11],     // 11 Pair<T,U>
        [4, 0, 0, 11, 2, 0, 0, 0, 0],      // 12 array<bool,project(3)>
        [1, 0, 0, 0, 0, 0, 0, 0, 0],       // 13 malformed scalar
        [7, 0, 0, 0, 0, 0, 0, 0, 0],       // 14 function is outside leaf domain
        [8, 2, 0, 0, 0, 0, 0, 0, 0],       // 15 N:u32, member2
        [4, 0, 0, 13, 2, 0, 0, 0, 0],      // 16 array<bool,N>
        [3, 7, 17, 15, 2, 0, 0, 0, 11],    // 17 Box<array<bool,3>,3>
    ];
    // Every projection has one edge to an earlier well-formed constant row.
    // The source actual is a single atom, so these cases measure the canonical
    // terminal visit budget rather than the source descriptor's depth limit.
    assert_eq!(types.len() as u32, FIRST_N_PROJECTION);
    let mut child = CONSTANT_N;
    for _ in 0..64 {
        let root = types.len() as u32;
        let edge = edges.len() as u32;
        edges.push(child);
        types.push([10, 4, 0, edge, 1, 0, 0, 0, 0]);
        child = root;
    }
    for (root, length, nominal) in [
        (ARRAY_N_PROJECTED_63, N_PROJECTED_63, false),
        (ARRAY_N_PROJECTED_64, N_PROJECTED_64, false),
        (BOX_T_N_PROJECTED_63, N_PROJECTED_63, true),
        (BOX_T_N_PROJECTED_64, N_PROJECTED_64, true),
    ] {
        assert_eq!(types.len() as u32, root);
        let start = edges.len() as u32;
        edges.extend([if nominal { T } else { 0 }, length]);
        types.push(if nominal {
            [3, 7, 17, start, 2, 0, 0, 0, 11]
        } else {
            [4, 0, 0, start, 2, 0, 0, 0, 0]
        });
    }
    assert!(types.len() < 99, "keep existing invalid canonical row99 out of range");
    let members = [
        [0, 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0],
        [0, 2, 1, 0, 0, 0, 0, 0, 1, 1, 0, 1],
        [0, 3, 2, 0, 0, 0, 0, 1, 0, 1, 0, 2],
    ];
    let mut page = vec![0; 46];
    page[3] = 1; page[4] = types.len() as u32;
    page[5] = edges.len() as u32; page[6] = members.len() as u32;
    page[16] = page.len() as u32;
    page.extend([0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0]);
    page[17] = page.len() as u32; page.extend(flatten(&types));
    page[18] = page.len() as u32; page.extend(edges);
    page[19] = page.len() as u32; page.extend(flatten(&members));
    page[44] = 0; page[45] = types.len() as u32;
    f.page = page;
    f.roots = (0..types.len() as u32).collect();
    f.constant_refs = vec![0; types.len() * 2];
    for (root, reference) in [(4, [1, 3]), (5, [1, 4]), (6, [3, 0])] {
        f.constant_refs[root * 2..root * 2 + 2].copy_from_slice(&reference);
    }
    f
}

type Resources = BTreeMap<&'static str, LaniusBuffer<u32>>;

fn group(device: &wgpu::Device, pass: &PassData, resources: &Resources,
    params: &LaniusBuffer<Params>) -> wgpu::BindGroup {
    // Each entrypoint reflects only its actual storage surface; unknown names
    // fail instead of silently receiving a placeholder buffer.
    let reflection = &pass.reflection;
    let parameters = if let Some(layout) = reflection.entry_points.iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref()) {
        layout.parameters.first().map(|set| set.parameters.as_slice()).unwrap_or_default()
    } else { reflection.parameters.as_slice() };
    let entries: Vec<_> = parameters.iter()
        .filter(|parameter| parameter.binding.index.is_some() && parameter.ty.kind.is_some())
        .map(|parameter| {
            let name = parameter.name.as_str();
            let binding = if name == "boundary_params" { params.as_entire_binding() }
                else { resources.get(name).unwrap_or_else(||
                    panic!("{} requires unknown fixture buffer {name}", pass.shader_id)).as_entire_binding() };
            (name, binding)
        }).collect();
    passes_core::bind_group::validate_exact_binding_names(pass, 0, &entries).unwrap();
    passes_core::bind_group::create_bind_group_from_bindings(
        device, Some(&pass.shader_id), pass, 0, &entries).unwrap()
}

fn run<const N: usize>(key: &str, cases: &[Case<N>]) {
    assert!(!super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU");
    let f = fixture();
    let gpu = device::global();
    let params = uniform_from_val(&gpu.device, key, &Params {
        nodes: f.nodes.len() as u32, arguments: f.arguments.len() as u32,
        environments: f.environments.len() as u32, queries: cases.len() as u32,
        tokens: TOKENS, reserved0: 0, reserved1: 0, reserved2: 0,
    });
    let mut resources = Resources::new();
    for (name, words) in [
        ("boundary_nodes", flatten(&f.nodes)),
        ("boundary_arguments", flatten(&f.arguments)),
        ("boundary_environments", flatten(&f.environments)),
        ("boundary_queries", flatten(&cases.iter().map(|case| case.query).collect::<Vec<_>>())),
        ("boundary_results", vec![0xa5a5_a5a5; cases.len() * N]),
        ("dependency_words", f.page),
        ("canonical_type_roots", f.roots),
        ("dependency_constant_ref_by_type", f.constant_refs),
        ("type_const_param_slot_by_token", vec![INVALID, INVALID, INVALID, 0]),
        ("type_const_param_scalar_by_token", vec![0, 0, 0, 4]),
        ("checked_constant_atoms", flatten(&(0..=4)
            .map(|value| [4, value, 0, 0]).collect::<Vec<_>>())),
        ("checked_constant_projections", vec![4, 1, 3, 0]),
    ] {
        let buffer = storage_rw_for_array::<u32>(&gpu.device, name, words.len());
        let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
        buffer.write(&gpu.queue, 0, &bytes);
        resources.insert(name, buffer);
    }
    let pass = make_pass_data_from_shader_key(&gpu.device, key, "main", key).unwrap();
    assert_eq!(pass.thread_group_size, [32, 1, 1]);
    let group = group(&gpu.device, &pass, &resources, &params);
    let words = cases.len() * N;
    let readback = readback_bytes(&gpu.device, key, words * 4, words);
    let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(key) });
    {
        let mut compute = passes_core::begin_counted_compute_pass(&mut encoder,
            &wgpu::ComputePassDescriptor { label: Some(key), timestamp_writes: None });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        compute.dispatch_workgroups((cases.len() as u32).div_ceil(32), 1, 1);
    }
    resources["boundary_results"].copy_to(&mut encoder, 0, &readback, 0, (words * 4) as u64);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, key).unwrap();
    let mapped = slice.get_mapped_range();
    let actual: Vec<_> = mapped.chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap())).collect();
    drop(mapped); readback.unmap();
    assert_eq!(actual.len(), words);
    for (case, row) in cases.iter().zip(actual.chunks_exact(N)) {
        for (column, expected) in case.expected.iter().enumerate() {
            if let Some(expected) = expected {
                assert_eq!(row[column], *expected, "{} column {column}: {row:?}", case.label);
            }
        }
    }
}

#[test]
fn physical_gpu_canonical_type_leaf_preserves_one_step_and_rejects_constant_bindings() {
    let mut cases = Vec::new();
    for (label, environment, reference) in [
        ("checked scalar", 0, BOOL),
        ("canonical scalar remains one step", 1, [5, 0]),
        ("canonical nominal remains one step", 2, [5, BOX]),
        ("canonical array remains one step", 3, [5, ARRAY]),
        ("canonical parameter is not recursively substituted", 8, [5, T]),
        ("checked nominal", 11, [3, 1]),
        ("caller parameter identity retained", 12, [2, 2]),
        ("canonical nested constants", 15, [5, BOX_ARRAY]),
    ] {
        cases.push(Case { label, query: query(T, environment, BOOL, false),
            expected: [Some(1), Some(reference[0]), Some(reference[1]), Some(0)] });
    }
    for (label, environment) in [
        ("canonical literal cannot bind a type", 4),
        ("source literal cannot bind a type", 5),
        ("canonical projection cannot bind a type", 6),
        ("canonical constant parameter cannot bind a type", 7),
        ("out-of-range canonical replacement", 9),
        ("present invalid binding", 10),
        ("source constant parameter cannot bind a type", 13),
        ("source projection cannot bind a type", 14),
    ] {
        cases.push(Case { label, query: query(T, environment, BOOL, false),
            expected: [Some(0), None, None, Some(0)] });
    }
    for (label, pattern) in [
        ("literal is not a type leaf", LITERAL_THREE),
        ("projection is not a type leaf", 6),
        ("constant parameter is not a type leaf", 15),
        ("invalid scalar payload", 13),
        ("unsupported canonical kind", 14),
        ("out-of-range canonical root", 99),
    ] {
        cases.push(Case { label, query: query(pattern, INVALID, BOOL, false),
            expected: [Some(0), None, None, Some(0)] });
    }
    run("tests/canonical_type_leaf_boundary", &cases);
}

fn constraint(label: &'static str, pattern: u32, environment: u32, actual: [u32; 2],
    infer: bool, accepted: u32, mask: u32, first: [u32; 2], second: [u32; 2]) -> Case<12> {
    Case { label, query: query(pattern, environment, actual, infer),
        expected: [accepted, mask, 0, first[0], first[1], second[0], second[1],
            1, 1, 0, INVALID, 0].map(Some) }
}

#[test]
fn physical_gpu_canonical_type_constraints_reject_cross_domain_bindings_before_publication() {
    let mut cases = vec![
        constraint("canonical scalar replacement normalizes", T, 1, BOOL, false, 1, 0, EMPTY, EMPTY),
        constraint("canonical nominal replacement", T, 2, [3, 1], false, 1, 0, EMPTY, EMPTY),
        constraint("canonical array replacement", T, 3, [3, 0], false, 1, 0, EMPTY, EMPTY),
        constraint("caller parameter substituted once", T, 12, [2, 2], false, 1, 0, EMPTY, EMPTY),
        constraint("unbound type infers checked scalar", T, INVALID, BOOL, true, 1, 1, BOOL, EMPTY),
        constraint("literal in nominal operand is checked", BOX, INVALID, [3, 1], false, 1, 0, EMPTY, EMPTY),
        constraint("wrong nominal constant value rejected", BOX, INVALID, [3, 4], false, 0, 0, EMPTY, EMPTY),
        constraint("array length is checked", ARRAY, INVALID, [3, 0], false, 1, 0, EMPTY, EMPTY),
        constraint("wrong array length rejected", ARRAY, INVALID, [3, 5], false, 0, 0, EMPTY, EMPTY),
        constraint("projected constant length retains value", ARRAY_PROJECTED, INVALID, [3, 0], false, 1, 0, EMPTY, EMPTY),
        constraint("wrong projected length rejected", ARRAY_PROJECTED, INVALID, [3, 5], false, 0, 0, EMPTY, EMPTY),
        constraint("nested array and nominal constants", BOX_ARRAY, INVALID, [3, 7], false, 1, 0, EMPTY, EMPTY),
        constraint("nominal type inference preserves constant operand", BOX_T, INVALID, [3, 1], true, 1, 1, BOOL, EMPTY),
        constraint("array element inference preserves length", ARRAY_T, INVALID, [3, 0], true, 1, 1, BOOL, EMPTY),
        constraint("two type slots infer independently", PAIR_T_U, INVALID, [3, 2], true, 1, 3, BOOL, BOOL),
        constraint("invalid source constant retains rejected inference snapshot", T, INVALID,
            [CONSTANT, 3], true, 0, 1, [CONSTANT, 3], EMPTY),
        constraint("invalid canonical constant retains rejected inference snapshot", T, INVALID,
            [5, LITERAL_THREE], true, 0, 1, [5, LITERAL_THREE], EMPTY),
        constraint("failure in second slot preserves earlier type claim", PAIR_T_U, INVALID,
            [3, 3], true, 0, 3, BOOL, [CONSTANT, 3]),
        constraint("failure in second canonical slot preserves earlier type claim", PAIR_T_U, INVALID,
            [3, 6], true, 0, 3, BOOL, [5, LITERAL_THREE]),
    ];
    for (label, environment) in [
        ("bound canonical literal rejected with no inference", 4),
        ("bound source literal rejected with no inference", 5),
        ("bound canonical projection rejected with no inference", 6),
        ("bound canonical constant parameter rejected with no inference", 7),
        ("bound source constant parameter rejected with no inference", 13),
        ("bound source projection rejected with no inference", 14),
    ] {
        cases.push(constraint(label, T, environment, [CONSTANT, 3], true, 0, 0, EMPTY, EMPTY));
    }
    run("tests/canonical_type_constraint_boundary", &cases);
}

#[test]
fn physical_gpu_canonical_constant_parameter_projection_visit_boundaries() {
    // accepted, type mask, constant mask, T tag/payload, U tag/payload,
    // clear type tail, clear constants, constant0 kind/payload/identity mode.
    let typed_bound = [1, 0, 1, 0, INVALID, 0, INVALID, 1, 0, 1, 3, 0];
    let count_bound = [1, 0, 1, 0, INVALID, 0, INVALID, 1, 0, 1, 3, 1];
    let rejected = [0, 0, 0, 0, INVALID, 0, INVALID, 1, 1, 0, INVALID, 0];
    let partial_bound = [1, 1, 1, 1, 2, 0, INVALID, 1, 0, 1, 3, 0];
    let partial_rejected = [0, 1, 0, 1, 2, 0, INVALID, 1, 1, 0, INVALID, 0];
    let cases: Vec<_> = [
        ("direct kind8 preserves typed identity", CONSTANT_N, [CONSTANT, 3], typed_bound),
        ("direct kind8 array length records count identity", ARRAY_N, [3, 0], count_bound),
        ("63 projected edges visit typed terminal", N_PROJECTED_63, [CONSTANT, 3], typed_bound),
        ("64 projected edges reject before typed terminal", N_PROJECTED_64, [CONSTANT, 3], rejected),
        ("63 projected edges visit array-count terminal", ARRAY_N_PROJECTED_63, [3, 0], count_bound),
        ("64 projected edges reject before array-count terminal", ARRAY_N_PROJECTED_64, [3, 0], rejected),
        ("63 projected edges preserve earlier type inference", BOX_T_N_PROJECTED_63, [3, 1], partial_bound),
        ("64 projected edges preserve rejected inference snapshot", BOX_T_N_PROJECTED_64, [3, 1], partial_rejected),
    ].into_iter().map(|(label, pattern, actual, expected)| Case {
        label, query: query(pattern, INVALID, actual, true), expected: expected.map(Some),
    }).collect();
    run("tests/canonical_type_constraint_boundary", &cases);
}

#[test]
fn physical_gpu_canonical_type_identity_preserves_nested_constant_checks() {
    let mut cases = Vec::new();
    for (label, pattern, environment, candidate) in [
        ("nominal constant identity", BOX, INVALID, 1),
        ("array constant identity", ARRAY, INVALID, 0),
        ("projected array count identity", ARRAY_PROJECTED, INVALID, 0),
        ("nested constants identity", BOX_ARRAY, INVALID, 7),
        ("canonical nominal environment replacement", T, 2, 1),
        ("canonical array environment replacement", T, 3, 0),
        ("canonical nested environment replacement", T, 15, 7),
        ("checked nominal environment replacement", T, 11, 1),
    ] {
        cases.push(Case { label, query: query(pattern, environment, [3, candidate], false),
            expected: [Some(1), Some(1), Some(1), Some(1)] });
    }
    for (label, pattern, candidate) in [
        ("wrong nominal constant must not compare equal", BOX, 4),
        ("wrong array length must not compare equal", ARRAY, 5),
        ("wrong projected count must not compare equal", ARRAY_PROJECTED, 5),
    ] {
        // Hash inequality is not required; full equality remains authoritative.
        cases.push(Case { label, query: query(pattern, INVALID, [3, candidate], false),
            expected: [Some(1), Some(0), Some(1), None] });
    }
    for (label, environment) in [
        ("canonical literal cannot become type identity", 4),
        ("source literal cannot become type identity", 5),
        ("canonical projection cannot become type identity", 6),
        ("canonical constant parameter cannot become type identity", 7),
        ("source constant parameter cannot become type identity", 13),
        ("source projection cannot become type identity", 14),
    ] {
        cases.push(Case { label, query: query(T, environment, [3, 1], false),
            expected: [Some(0), Some(0), Some(1), Some(0)] });
    }
    run("tests/canonical_type_identity_boundary", &cases);
}
