//! Physical GPU coverage for the production scoped equality/hash capability.
//! Host code constructs fixtures and checks outcomes; it never compares types.

use crate::gpu::{
    buffers::{readback_bytes, storage_ro_from_u32s, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

const INVALID: u32 = u32::MAX;
const CONSTANT_LITERAL: u32 = 0x8000_0001;
const CONSTANT_PARAMETER: u32 = 0x8000_0002;
type Reference = [u32; 2];
type ScopedReference = [u32; 3];
const BOOL: Reference = [1, 2];

fn unbound(reference: Reference) -> ScopedReference {
    [reference[0], reference[1], INVALID]
}

fn bound(reference: Reference, environment: u32) -> ScopedReference {
    [reference[0], reference[1], environment]
}

#[derive(encase::ShaderType)]
struct Params {
    node_count: u32,
    argument_count: u32,
    parameter_count: u32,
    environment_count: u32,
    binding_count: u32,
    query_count: u32,
    reserved0: u32,
    reserved1: u32,
}

struct Case {
    label: String,
    left: ScopedReference,
    right: ScopedReference,
    node_capacity: Option<u32>,
    // admission status, equality, left/right hash success
    expected: [u32; 4],
}

#[derive(Default)]
struct Fixture {
    nodes: Vec<[u32; 11]>,
    arguments: Vec<Reference>,
    parameters: Vec<[u32; 8]>,
    environments: Vec<[u32; 9]>,
    bindings: Vec<[u32; 3]>,
    cases: Vec<Case>,
}

impl Fixture {
    fn parameter(&mut self, owner: [u32; 5], constant: bool, ordinal: u32, slot: u32) -> u32 {
        let id = self.parameters.len() as u32;
        self.parameters.push([
            owner[0], owner[1], owner[2], owner[3], owner[4],
            u32::from(constant), ordinal, slot,
        ]);
        id
    }

    fn environment(
        &mut self,
        owner: [u32; 5],
        types: &[(u32, Reference)],
        constants: &[(u32, Reference)],
    ) -> u32 {
        let id = self.environments.len() as u32;
        let type_start = self.bindings.len() as u32;
        self.bindings.extend(types.iter().map(|(p, r)| [*p, r[0], r[1]]));
        let constant_start = self.bindings.len() as u32;
        self.bindings.extend(constants.iter().map(|(p, r)| [*p, r[0], r[1]]));
        self.environments.push([
            owner[0], owner[1], owner[2], owner[3], owner[4],
            type_start, types.len() as u32, constant_start, constants.len() as u32,
        ]);
        id
    }

    fn nominal(&mut self, declaration: u32, arguments: &[Reference]) -> Reference {
        let id = self.nodes.len() as u32;
        let start = self.arguments.len() as u32;
        self.arguments.extend_from_slice(arguments);
        // External identity avoids conflating declaration identity with a node id.
        self.nodes.push([
            1, INVALID, arguments.len() as u32, 0, 0, 0, 0, 7, 11, declaration, start,
        ]);
        [3, id]
    }

    fn compound(&mut self, kind: u32, element: Reference, length: Reference) -> Reference {
        let id = self.nodes.len() as u32;
        self.nodes.push([
            kind, INVALID, 0, element[0], element[1], length[0], length[1],
            INVALID, INVALID, INVALID, 0,
        ]);
        [3, id]
    }

    fn case(&mut self, label: impl Into<String>, left: ScopedReference, right: ScopedReference, expected: [u32; 4]) {
        self.cases.push(Case { label: label.into(), left, right, node_capacity: None, expected });
    }

    fn equal(&mut self, label: impl Into<String>, left: ScopedReference, right: ScopedReference) {
        self.case(label, left, right, [0, 1, 1, 1]);
    }

    fn rejected(&mut self, label: impl Into<String>, reference: ScopedReference) {
        self.case(label, reference, reference, [0, 0, 0, 0]);
    }
}

fn fixture() -> Fixture {
    let mut f = Fixture::default();
    let scalar_arguments: Vec<_> = (0..32).map(|i| [1, 1 + i % 8]).collect();
    let nominal32 = f.nominal(17, &scalar_arguments);
    assert_eq!(nominal32, [3, 0]);
    f.equal("one node admits 32 inline scalar operands", unbound(nominal32), unbound(nominal32));
    f.cases.last_mut().unwrap().node_capacity = Some(1);
    let nominal33 = f.nominal(17, &[BOOL; 33]);
    f.rejected("33 ordered operands are unsupported", unbound(nominal33));

    let owner_a = [2, 3, 0, 41, 0];
    let owner_b = [2, 3, 0, 42, 0];
    let a_t = f.parameter(owner_a, false, 0, 0);
    let a_n = f.parameter(owner_a, true, 1, 0);
    let b_t = f.parameter(owner_b, false, 0, 0);
    let b_n = f.parameter(owner_b, true, 1, 0);
    let unknown = f.parameters.len() as u32;
    f.parameters.push([INVALID; 8]); // In range, but no declaration identity.
    let env_a = f.environment(owner_a, &[(a_t, [2, b_t])], &[(a_n, [2, b_n])]);
    f.case("distinct owners retain distinct slot zero leaves", unbound([2, a_t]), unbound([2, b_t]), [0, 0, 1, 1]);
    f.equal("type substitution A to B happens once", bound([2, a_t], env_a), unbound([2, b_t]));
    f.equal("right type substitution A to B happens once", unbound([2, b_t]), bound([2, a_t], env_a));
    f.equal("constant substitution A to B happens once", bound([CONSTANT_PARAMETER, a_n], env_a), unbound([CONSTANT_PARAMETER, b_n]));
    f.equal("right constant substitution A to B happens once", unbound([CONSTANT_PARAMETER, b_n]), bound([CONSTANT_PARAMETER, a_n], env_a));
    f.case("B cannot capture A slot zero", bound([2, b_t], env_a), unbound([2, b_t]), [0, 0, 0, 1]);
    f.case("B constant cannot capture A slot zero", bound([CONSTANT_PARAMETER, b_n], env_a), unbound([CONSTANT_PARAMETER, b_n]), [0, 0, 0, 1]);

    // Change each owner component independently, then source ordinal while
    // retaining the same slot. Substitution must receive the original identity.
    for field in 0..5 {
        let mut owner = owner_a;
        owner[field] += 1;
        let p = f.parameter(owner, false, 0, 0);
        f.case(format!("owner component {field} must match"), bound([2, p], env_a), unbound([2, b_t]), [0, 0, 0, 1]);
    }
    let different_ordinal = f.parameter(owner_a, false, 9, 0);
    f.case("source ordinal is identity, not binding slot", bound([2, different_ordinal], env_a), unbound([2, b_t]), [0, 0, 0, 1]);

    let b_array = f.compound(2, [2, b_t], [2, b_n]);
    let b_slice = f.compound(3, b_array, [0, 0]);
    let b_reference = f.compound(4, b_slice, [0, 0]);
    let b_compound = f.nominal(23, &[b_reference, [CONSTANT_PARAMETER, b_n]]);
    let env_compound = f.environment(owner_a, &[(a_t, b_compound)], &[(a_n, [1, 99])]);
    f.equal("returned compound retains nested B type and constant identities", bound([2, a_t], env_compound), unbound(b_compound));
    f.equal("right returned compound retains B identities", unbound(b_compound), bound([2, a_t], env_compound));

    for (label, parameter, expected) in [
        ("valid unbound constant", b_n, [0, 1, 1, 1]),
        ("unknown unbound constant", unknown, [0, 0, 0, 0]),
        ("wrong-domain unbound constant", b_t, [0, 0, 0, 0]),
    ] {
        let array = f.compound(2, BOOL, [2, parameter]);
        let nominal = f.nominal(24, &[[CONSTANT_PARAMETER, parameter]]);
        f.case(format!("array length: {label}"), unbound(array), unbound(array), expected);
        f.case(format!("nominal argument: {label}"), unbound(nominal), unbound(nominal), expected);
    }
    f.rejected("unknown unbound type parameter", unbound([2, unknown]));
    f.rejected("constant identity used as type parameter", unbound([2, b_n]));
    let zero_array = f.compound(2, BOOL, [1, 0]);
    f.equal("zero length is a valid literal", unbound(zero_array), unbound(zero_array));

    let env_wrong_type = f.environment(owner_a, &[(a_t, [2, b_n])], &[]);
    f.rejected("type substitution cannot return a constant identity", bound([2, a_t], env_wrong_type));
    let env_wrong_type_tag = f.environment(owner_a, &[(a_t, [CONSTANT_LITERAL, 7])], &[]);
    f.rejected("type substitution cannot return a constant tag", bound([2, a_t], env_wrong_type_tag));
    let env_wrong_constant = f.environment(owner_a, &[], &[(a_n, [2, b_t])]);
    let wrong_array = f.compound(2, BOOL, [2, a_n]);
    let wrong_nominal = f.nominal(25, &[[CONSTANT_PARAMETER, a_n]]);
    f.rejected("array constant substitution cannot return a type identity", bound(wrong_array, env_wrong_constant));
    f.rejected("nominal constant substitution cannot return a type identity", bound(wrong_nominal, env_wrong_constant));

    let owner_wide = [5, 6, 1, 100, 200];
    let types: Vec<_> = (0..32).map(|slot| f.parameter(owner_wide, false, slot, slot)).collect();
    let constants: Vec<_> = (0..32).map(|slot| f.parameter(owner_wide, true, 32 + slot, slot)).collect();
    let type_bindings: Vec<_> = types.iter().map(|p| (*p, BOOL)).collect();
    let constant_bindings: Vec<_> = constants.iter().enumerate().map(|(slot, p)| (*p, [1, slot as u32])).collect();
    let env_wide = f.environment(owner_wide, &type_bindings, &constant_bindings);
    let symbolic31 = f.compound(2, [2, types[31]], [2, constants[31]]);
    let concrete31 = f.compound(2, BOOL, [1, 31]);
    f.equal("independent type31 and constant31 domains", bound(symbolic31, env_wide), unbound(concrete31));

    let before_roots = f.nodes.len();
    let mut roots = Vec::new();
    for slot in 0..32 {
        let mut root = f.compound(2, BOOL, [1, slot]);
        for depth in 0..8 {
            root = f.compound(if depth % 2 == 0 { 3 } else { 4 }, root, [0, 0]);
        }
        roots.push(root);
    }
    assert_eq!(f.nodes.len() - before_roots, 288);
    let compound_bindings: Vec<_> = types.iter().zip(&roots).map(|(p, r)| (*p, *r)).collect();
    let env_roots = f.environment(owner_wide, &compound_bindings, &constant_bindings);
    for slot in 0..32 {
        f.equal(format!("independent compound root {slot}"), bound([2, types[slot]], env_roots), unbound(roots[slot]));
    }
    let parameter_arguments: Vec<_> = types.iter().map(|p| [2, *p]).collect();
    let symbolic_roots = f.nominal(26, &parameter_arguments);
    let concrete_roots = f.nominal(26, &roots);
    f.equal("32 operands may traverse more than 256 aggregate nodes", bound(symbolic_roots, env_roots), unbound(concrete_roots));

    f.case("legacy scalar nominal is rejected at admission", unbound([1, 500]), unbound([1, 500]), [2, 0, 0, 0]);
    f.case("capacity beyond supplied graph is rejected at admission", unbound(BOOL), unbound(BOOL), [1, 0, 0, 0]);
    f.cases.last_mut().unwrap().node_capacity = Some(f.nodes.len() as u32 + 1);
    f
}

fn flatten<const N: usize>(rows: &[[u32; N]]) -> Vec<u32> {
    rows.iter().flat_map(|row| row.iter().copied()).collect()
}

#[test]
fn physical_gpu_parameter_scoped_type_graph_preserves_identity_and_capacity() {
    assert!(!crate::gpu::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU");
    let f = fixture();
    let gpu = device::global(); // Device initialization rejects CPU adapters.
    let params_value = Params {
        node_count: f.nodes.len() as u32,
        argument_count: f.arguments.len() as u32,
        parameter_count: f.parameters.len() as u32,
        environment_count: f.environments.len() as u32,
        binding_count: f.bindings.len() as u32,
        query_count: f.cases.len() as u32,
        reserved0: 0,
        reserved1: 0,
    };
    let query_rows: Vec<_> = f.cases.iter().map(|case| [
        case.left[0], case.left[1], case.left[2],
        case.right[0], case.right[1], case.right[2],
        case.node_capacity.unwrap_or(params_value.node_count), params_value.parameter_count,
    ]).collect();
    let params = uniform_from_val(&gpu.device, "scope_probe.params", &params_value);
    let nodes = storage_ro_from_u32s(&gpu.device, "scope_probe.nodes", &flatten(&f.nodes));
    let arguments = storage_ro_from_u32s(&gpu.device, "scope_probe.arguments", &flatten(&f.arguments));
    let parameters = storage_ro_from_u32s(&gpu.device, "scope_probe.parameters", &flatten(&f.parameters));
    let environments = storage_ro_from_u32s(&gpu.device, "scope_probe.environments", &flatten(&f.environments));
    let bindings = storage_ro_from_u32s(&gpu.device, "scope_probe.bindings", &flatten(&f.bindings));
    let queries = storage_ro_from_u32s(&gpu.device, "scope_probe.queries", &flatten(&query_rows));
    let word_count = f.cases.len() * 6;
    let results = storage_rw_for_array::<u32>(&gpu.device, "scope_probe.results", word_count);
    let pass = make_pass_data_from_shader_key(
        &gpu.device, "test.parameter_scoped_type_graph", "main", "tests/parameter_scoped_type_graph",
    ).unwrap();
    let entries = [
        ("gParams", params.as_entire_binding()),
        ("nodes", nodes.as_entire_binding()),
        ("arguments", arguments.as_entire_binding()),
        ("parameters", parameters.as_entire_binding()),
        ("environments", environments.as_entire_binding()),
        ("bindings", bindings.as_entire_binding()),
        ("queries", queries.as_entire_binding()),
        ("results", results.as_entire_binding()),
    ];
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        &gpu.device, Some("scope_probe.group"), &pass, 0, &entries,
    ).unwrap();
    let (x, y, z) = passes_core::plan_workgroups(
        passes_core::DispatchDim::D1,
        passes_core::InputElements::Elements1D(params_value.query_count),
        pass.thread_group_size,
    ).unwrap();
    let byte_count = word_count * 4;
    let readback = readback_bytes(&gpu.device, "scope_probe.readback", byte_count, word_count);
    let mut encoder = gpu.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("scope_probe.encoder"),
    });
    {
        let mut compute = passes_core::begin_counted_compute_pass(&mut encoder, &wgpu::ComputePassDescriptor {
            label: Some("scope_probe.compute"), timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        compute.dispatch_workgroups(x, y, z);
    }
    results.copy_to(&mut encoder, 0, &readback, 0, byte_count as u64);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, "scope_probe.readback").unwrap();
    let mapped = slice.get_mapped_range();
    let words: Vec<_> = mapped.chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap())).collect();
    drop(mapped);
    readback.unmap();
    for (case, row) in f.cases.iter().zip(words.chunks_exact(6)) {
        assert_eq!(&row[..4], &case.expected, "{}: {row:?}", case.label);
        if row[1] == 1 {
            assert_eq!(row[4], row[5], "equal references must hash equally: {}", case.label);
        }
        // Unequal references may collide; equality remains authoritative.
    }
}
