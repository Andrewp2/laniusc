import re, sys
path = sys.argv[1]
text = open(path).read()

def once(anchor, new, after=True):
    global text
    n = text.count(anchor)
    assert n == 1, (n, anchor[:80])
    text = text.replace(anchor, anchor + new if after else new + anchor)

def sub1(old, new):
    global text
    n = text.count(old)
    assert n == 1, (n, old[:80])
    text = text.replace(old, new)

def fn_of(lines, i):
    for j in range(i, -1, -1):
        m = re.match(r'(pub )?fn (\w+)', lines[j])
        if m: return m.group(2)

once('''    // element i of a place of an array type
    XPlaceAt(Box<MEff>, Box<MEff>),
''', '''    // F5 (S5b): a borrow of the place p (a local, a field of one, or a
    // place through a reference), of this reference type
    XBorrow(Ty, Box<MEff>),
''')
arms = {
 'pure_part': 'None', 'bare_eff': 'false', 'eff_ty': 'Some(bty)', 'call_parts': 'None',
 'eff_place': 'false', 'has_at': 'false', 'diverge_eff': 'x', 'eval_let_head': 'EvalOf(x)',
 'inferred': 'false', 'eff_acts': 'eff_acts(n, unbox(p))', 'eff_calls': 'eff_calls(unbox(p))',
 'eff_named_tys': 'cons(bty, eff_named_tys(unbox(p)))',
 'close_eff': 'e_borrow_closed(close_ty(fuel, t, bty), close_eff(fuel, t, unbox(p)))',
}
lines = text.split('\n'); out = []; seen = set()
for i, line in enumerate(lines):
    out.append(line)
    m = re.match(r'^(\s*)XPlaceAt\((\w+), (\w+)\) -> .*,$', line)
    if m:
        f = fn_of(lines, i); seen.add(f)
        out.append(f'{m.group(1)}XBorrow(bty, p) -> {arms[f]},')
assert seen == set(arms), set(arms) ^ seen
text = '\n'.join(out)

once('''pub fn e_place_field_closed(''', '''pub fn e_borrow_closed(t: core::option::Option<SrcType>, x: core::option::Option<SrcEff>) -> core::option::Option<SrcEff> {
    return match (t) {
        None -> None,
        Some(ty) -> match (x) {
            None -> None,
            Some(a) -> Some(EBorrow(ty, boxed(a))),
        },
    };
}

''', after=False)

# params: &self and &mut self are references to the impl's type
once('''fn p_param_self_ref() -> usize {
    return 64;
}
''', '''
fn p_param_self_ref_mut() -> usize {
    return 325;
}
''')
sub1('''    if (node_prod(p) == p_param_self_ref() && fd.in_impl) {
        return Some(fd.self_type);
    }
''', '''    if ((node_prod(p) == p_param_self_ref() || node_prod(p) == p_param_self_ref_mut()) && fd.in_impl) {
        return Some(fd.self_type);
    }
''')
sub1('''    if (node_prod(p) == p_param_self_ref()) {
        return kid_token(p, 1);
    }
    return kid_token(p, 0);''', '''    if (node_prod(p) == p_param_self_ref()) {
        return kid_token(p, 1);
    }
    if (node_prod(p) == p_param_self_ref_mut()) {
        return kid_token(p, 2);
    }
    return kid_token(p, 0);''')
sub1('''    if ((node_prod(pp) == p_param_named() || node_prod(pp) == p_param_self() || node_prod(pp) == p_param_self_ref()) && !member(penv.globals, tok.text) && fresh_id(pscope, minus(tok.start, penv.base))) {
        return match (pattern_of(pfd, pp)) {
            None -> None,
            Some(t) -> match (param_ty_of(pfuel, penv, t)) {''', '''    if ((node_prod(pp) == p_param_named() || node_prod(pp) == p_param_self() || node_prod(pp) == p_param_self_ref() || node_prod(pp) == p_param_self_ref_mut()) && !member(penv.globals, tok.text) && fresh_id(pscope, minus(tok.start, penv.base))) {
        return match (pattern_of(pfd, pp)) {
            None -> None,
            Some(t) -> match (self_param_ty(pfuel, penv, pp, t)) {''')
once('''// A list of parameter type expressions, each as param_ty_of reads it.
''', '''// A parameter's type: `&self` and `&mut self` are references to the impl's
// type (F5, SEMANTIC_DECISIONS "S5b: point 10"); another as param_ty_of.
pub fn self_param_ty(fuel: usize, env: FrontEnv, p: CTree, t: CTree) -> core::option::Option<Ty> {
    if (node_prod(p) == p_param_self_ref() || node_prod(p) == p_param_self_ref_mut()) {
        return ref_ty(ty_of(fuel, env, t));
    }
    return param_ty_of(fuel, env, t);
}

''', after=False)

# read_fn: no by-value restriction on &self
sub1('''            Some(items) -> refs_checked(fuel, f, items, ref_checked(func_params(fuel, env, params_of(fuel, env, fd, empty(), items), rt, kid(f, 8), kid(kid(f, 9), 1)), self_ref_id(env, items))),''',
'''            Some(items) -> refs_checked(fuel, f, items, func_params(fuel, env, params_of(fuel, env, fd, empty(), items), rt, kid(f, 8), kid(kid(f, 9), 1))),''')

# the lifetime filter: self, and receivers
sub1('''// `name.f` then anything but a call (`name.m(..)` is a method call).
pub fn names_field_base(pf: CTree, name: List<usize>) -> bool {
    let primary: CTree = kid(pf, 0);
    let tail: CTree = kid(pf, 1);
    return node_prod(primary) == p_ident() && node_prod(kid(primary, 1)) == p_ident_plain() && is_text(path_name(kid(primary, 0)), name) && node_prod(tail) == p_postfix_member() && node_prod(kid(tail, 2)) == p_member_type_args_none() && node_prod(kid(tail, 3)) != p_postfix_call();
}''', '''// The primary is the name (a plain name, or `self`).
pub fn primary_names(primary: CTree, name: List<usize>) -> bool {
    return (node_prod(primary) == p_ident() && node_prod(kid(primary, 1)) == p_ident_plain() && is_text(path_name(kid(primary, 0)), name)) || (node_prod(primary) == p_self_value() && same_text(text_self(), name));
}

// `name.f` or `name.m(..)` (a field, or a method's receiver: S5b).
pub fn names_field_base(pf: CTree, name: List<usize>) -> bool {
    let tail: CTree = kid(pf, 1);
    return primary_names(kid(pf, 0), name) && node_prod(tail) == p_postfix_member() && member_args(node_prod(kid(tail, 2)));
}

// The argument is the bare name.
pub fn arg_names(fuel: usize, c: CTree, name: List<usize>) -> bool {
    return match (peel(fuel, c)) {
        None -> false,
        Some(pf) -> primary_names(kid(pf, 0), name) && node_prod(kid(pf, 1)) == p_postfix_end(),
    };
}''')
sub1('''    if ((node_prod(t) == p_args_some() || node_prod(t) == p_args_after_comma_more()) && tree_names(fuel, kid(t, 0), name)) {''',
     '''    if ((node_prod(t) == p_args_some() || node_prod(t) == p_args_after_comma_more()) && arg_names(fuel, kid(t, 0), name)) {''')

# receivers
sub1('''            Some(fd) -> eff_bound(minus(fuel, 1), env, scope, expected, x.decl, fd, method_binds(minus(fuel, 1), env, fd, x.binds, targs), pre, items),''',
     '''            Some(fd) -> eff_bound_recv(minus(fuel, 1), env, scope, expected, x.decl, fd, method_binds(minus(fuel, 1), env, fd, x.binds, targs), receivers_of(minus(fuel, 1), env, scope, fd, pre), items),''')
once('''pub fn eff_found_with(''', '''pub fn eff_bound_recv(fuel: usize, env: FrontEnv, scope: List<Local>, expected: core::option::Option<Ty>, d: usize, fd: FnDecl, binds: core::option::Option<List<Bind>>, pre: core::option::Option<List<MEff>>, items: List<CTree>) -> core::option::Option<MEff> {
    return match (pre) {
        None -> None,
        Some(p) -> eff_bound(fuel, env, scope, expected, d, fd, binds, p, items),
    };
}

''', after=False)
open(path, 'w').write(text)
