import re, sys
path = sys.argv[1]
text = open(path).read()

def once(anchor, new, after=True):
    global text
    n = text.count(anchor)
    assert n == 1, (n, anchor[:80])
    text = text.replace(anchor, anchor + new if after else new + anchor)

def fn_of(lines, i):
    for j in range(i, -1, -1):
        m = re.match(r'(pub )?fn (\w+)', lines[j])
        if m: return m.group(2)
    return None

# --- MEff constructors
once('''    // a string literal's bytes: only as a call's argument (arg_eff)
    XStr(List<usize>),
''', '''    // F5 (S5): the referent of the reference r, of this type (the referent's)
    XDeref(Ty, Box<MEff>),
    // field j of a place (an XDeref, XPlaceField or XPlaceAt)
    XPlaceField(Box<MEff>, usize),
    // element i of a place of an array type
    XPlaceAt(Box<MEff>, Box<MEff>),
''')
# --- MStmt constructors
once('''    // SrcStmt's Unreachable
    MUnreachable(usize, Ty),
''', '''    // F5 (S5): place = value and place op= value, the place an XDeref,
    // XPlaceField or XPlaceAt (SrcStmt's SetPlace and SetPlaceOp)
    MSetPlace(MEff, MEff),
    MSetPlaceOp(SrcAssignOp, MEff, MEff),
''')

eff_arms = {
 'pure_part': ('None', 'None', 'None'),
 'bare_eff': ('false', 'false', 'false'),
 'eff_ty': ('Some(dty)', 'field_ty_of(fuel, env.decls, eff_ty(minus(fuel, 1), env, scope, unbox(b)), j)', 'elem_ty_of(eff_ty(minus(fuel, 1), env, scope, unbox(b)))'),
 'call_parts': ('None', 'None', 'None'),
 'diverge_eff': ('x', 'x', 'x'),
 'eval_let_head': ('EvalOf(x)', 'EvalOf(x)', 'EvalOf(x)'),
 'inferred': ('false', 'true', 'true'),
 'eff_acts': ('eff_acts(n, unbox(a))', 'eff_acts(n, unbox(b))', 'eff_acts(n, unbox(b)) || eff_acts(n, unbox(i))'),
 'eff_calls': ('eff_calls(unbox(a))', 'eff_calls(unbox(b))', 'concat(eff_calls(unbox(b)), eff_calls(unbox(i)))'),
 'eff_named_tys': ('cons(dty, eff_named_tys(unbox(a)))', 'eff_named_tys(unbox(b))', 'concat(eff_named_tys(unbox(b)), eff_named_tys(unbox(i)))'),
 'close_eff': ('e_deref_closed(close_ty(fuel, t, dty), close_eff(fuel, t, unbox(a)))', 'e_place_field_closed(close_eff(fuel, t, unbox(b)), j)', 'e_place_at_closed(close_eff(fuel, t, unbox(b)), close_eff(fuel, t, unbox(i)))'),
}
stmt_arms = {
 'writes_local': ('false', 'false'),
 'stmt_calls': ('concat(eff_calls(pl), eff_calls(v))', 'concat(eff_calls(pl), eff_calls(v))'),
 'stmt_tys': ('concat(eff_named_tys(pl), eff_named_tys(v))', 'concat(eff_named_tys(pl), eff_named_tys(v))'),
 'close_stmt': ('set_place_closed(close_eff(fuel, t, pl), close_eff(fuel, t, v))', 'set_place_op_closed(op, close_eff(fuel, t, pl), close_eff(fuel, t, v))'),
}
lines = text.split('\n')
out = []
seen_e, seen_s = set(), set()
for i, line in enumerate(lines):
    out.append(line)
    m = re.match(r'^(\s*)XStr\(cs\) -> .*,$', line)
    if m:
        f = fn_of(lines, i); ind = m.group(1)
        a = eff_arms[f]; seen_e.add(f)
        out.append(f'{ind}XDeref(dty, a) -> {a[0]},')
        out.append(f'{ind}XPlaceField(b, j) -> {a[1]},')
        out.append(f'{ind}XPlaceAt(b, i) -> {a[2]},')
    m = re.match(r'^(\s*)MUnreachable\((\w+), (\w+)\) -> .*,$', line)
    if m:
        f = fn_of(lines, i); ind = m.group(1)
        a = stmt_arms[f]; seen_s.add(f)
        out.append(f'{ind}MSetPlace(pl, v) -> {a[0]},')
        out.append(f'{ind}MSetPlaceOp(op, pl, v) -> {a[1]},')
assert seen_e == set(eff_arms), set(eff_arms) - seen_e
assert seen_s == set(stmt_arms), set(stmt_arms) - seen_s
text = '\n'.join(out)

# --- helpers: field/element types of places
once('''pub fn effs_tys(fuel: usize, env: FrontEnv, scope: List<Local>, xs: List<MEff>) -> core::option::Option<List<Ty>> {''', '''// Field j's type in a struct type, when the type is known.
pub fn field_ty_of(fuel: usize, decls: Decls, t: core::option::Option<Ty>, j: usize) -> core::option::Option<Ty> {
    return match (t) {
        None -> None,
        Some(x) -> field_ty_at(fuel, decls, x, j),
    };
}

// The element type of an array or slice type, when the type is known.
pub fn elem_ty_of(t: core::option::Option<Ty>) -> core::option::Option<Ty> {
    return match (t) {
        None -> None,
        Some(x) -> index_elem(x),
    };
}

''', after=False)

# --- referent, places
ty_ctors = ['TyI32', 'TyBool', 'TyUint(k)', 'TyPtr', 'TyIsize', 'TyChar', 'TyStr', 'TyFloat(ft)', 'TySlice(e)', 'TyArray(e, n)', 'TyNamed(d, args)', 'TySint(k)']
eff_ctors = ['XPure(e)', 'XCall(inst, args)', 'XApply(op, l, r)', 'XNeg(a)', 'XNot(a)', 'XCast(t, a)', 'XIndex(s, i)', 'XStruct(t, fs)', 'XVariant(t, k, ps)', 'XMatch(s, ety, t, bs, vs)', 'XDivide(op, l, r)', 'XStride(sl)', 'XArraySlice(e, sl)', 'XHost(id, args)', 'XIf(c, t, a, b)', 'XLet(id, t, v, rt, b)', 'XLen(sl)', 'XStr(cs)']
def arms(ctors, val, ind='        '):
    return ''.join(f'{ind}{c} -> {val},\n' for c in ctors)
helpers = '''// F5 (S5): the referent type of a reference type.
pub fn referent(t: Ty) -> core::option::Option<Ty> {
    return match (t) {
''' + arms(ty_ctors, 'None') + '''        TyRef(r) -> Some(unbox(r)),
    };
}

pub fn is_ref_ty(t: Ty) -> bool {
    return has_ty(referent(t));
}

// A type, or a reference type's referent type.
pub fn referent_or(t: Ty) -> Ty {
    return match (referent(t)) {
        None -> t,
        Some(r) -> r,
    };
}

// Whether x is a place: the referent of a reference, a field of a place or
// an element of one.
pub fn eff_place(x: MEff) -> bool {
    return match (x) {
''' + arms(eff_ctors, 'false') + '''        XDeref(dty, a) -> true,
        XPlaceField(b, j) -> true,
        XPlaceAt(b, i) -> true,
    };
}

// Whether the place x has an element step.
pub fn has_at(x: MEff) -> bool {
    return match (x) {
''' + arms(eff_ctors, 'false') + '''        XDeref(dty, a) -> false,
        XPlaceField(b, j) -> has_at(unbox(b)),
        XPlaceAt(b, i) -> true,
    };
}

pub fn x_at_of(b: MEff, i: core::option::Option<MEff>) -> core::option::Option<MEff> {
    return match (i) {
        None -> None,
        Some(x) -> Some(XPlaceAt(boxed(b), boxed(x))),
    };
}

'''
# --- field_value / field_of_ty
once('''// Field j of the value x of type t: Field of a local, else the call of the
// projection.
pub fn field_value(decls: Decls, x: MEff, t: Ty, j: usize) -> MEff {
    return match (eff_local(x)) {
        Some(id) -> XPure(Field(id, j)),
        None -> XCall(projection(decls, t, j), boxed(single(x))),
    };
}
''', '')
text = text.replace('''// Field j of the value x of type t: Field of a local, else the call of the
// projection.
pub fn field_value(decls: Decls, x: MEff, t: Ty, j: usize) -> MEff {
    return match (eff_local(x)) {
        Some(id) -> XPure(Field(id, j)),
        None -> XCall(projection(decls, t, j), boxed(single(x))),
    };
}
''', helpers + '''// Field j of the value x of type t: of a place, the field's place; of a
// reference, the field's place in its referent (F5, S5); else Field of a
// local, else the call of the projection.
pub fn field_value(decls: Decls, x: MEff, t: Ty, j: usize) -> MEff {
    if (eff_place(x)) {
        return XPlaceField(boxed(x), j);
    }
    return match (referent(t)) {
        Some(r) -> XPlaceField(boxed(XDeref(r, boxed(x))), j),
        None -> match (eff_local(x)) {
            Some(id) -> XPure(Field(id, j)),
            None -> XCall(projection(decls, t, j), boxed(single(x))),
        },
    };
}
''')
text = text.replace('''        Some(ty) -> match (field_index(env, ty, name)) {
            None -> None,
            Some(j) -> Some(field_value(env.decls, x, ty, j)),''', '''        Some(ty) -> match (field_index(env, referent_or(ty), name)) {
            None -> None,
            Some(j) -> Some(field_value(env.decls, x, ty, j)),''')
# --- eff_step: an element of a place
once('''    if (node_prod(tail) == p_postfix_index()) {
        return eff_chain(f, env, scope, expected, x_index_of(eff_slice_local(scope, x), eff_of(f, env, scope, None, kid(tail, 1))), kid(tail, 3));''', '''
        if (eff_place(x)) {
            return eff_chain(f, env, scope, expected, x_at_of(x, eff_of(f, env, scope, None, kid(tail, 1))), kid(tail, 3));
        }''', after=False) if False else None
text = text.replace('''    if (node_prod(tail) == p_postfix_index()) {
        return eff_chain(f, env, scope, expected, x_index_of(eff_slice_local(scope, x), eff_of(f, env, scope, None, kid(tail, 1))), kid(tail, 3));''', '''    if (node_prod(tail) == p_postfix_index() && eff_place(x)) {
        return eff_chain(f, env, scope, expected, x_at_of(x, eff_of(f, env, scope, None, kid(tail, 1))), kid(tail, 3));
    }
    if (node_prod(tail) == p_postfix_index()) {
        return eff_chain(f, env, scope, expected, x_index_of(eff_slice_local(scope, x), eff_of(f, env, scope, None, kid(tail, 1))), kid(tail, 3));''')
assert text.count('x_at_of(x, eff_of') == 1

# --- closers
once('''pub fn e_index_closed(s: usize, x: core::option::Option<SrcEff>) -> core::option::Option<SrcEff> {''', '''pub fn e_deref_closed(t: core::option::Option<SrcType>, x: core::option::Option<SrcEff>) -> core::option::Option<SrcEff> {
    return match (t) {
        None -> None,
        Some(ty) -> match (x) {
            None -> None,
            Some(a) -> Some(EDeref(ty, boxed(a))),
        },
    };
}

pub fn e_place_field_closed(x: core::option::Option<SrcEff>, j: usize) -> core::option::Option<SrcEff> {
    return match (x) {
        None -> None,
        Some(a) -> Some(EField(boxed(a), j)),
    };
}

pub fn e_place_at_closed(x: core::option::Option<SrcEff>, i: core::option::Option<SrcEff>) -> core::option::Option<SrcEff> {
    return match (x) {
        None -> None,
        Some(a) -> match (i) {
            None -> None,
            Some(b) -> Some(EAt(boxed(a), boxed(b))),
        },
    };
}

pub fn set_place_closed(p: core::option::Option<SrcEff>, v: core::option::Option<SrcEff>) -> core::option::Option<SrcStmt> {
    return match (p) {
        None -> None,
        Some(a) -> match (v) {
            None -> None,
            Some(b) -> Some(SetPlace(a, b)),
        },
    };
}

pub fn set_place_op_closed(op: SrcAssignOp, p: core::option::Option<SrcEff>, v: core::option::Option<SrcEff>) -> core::option::Option<SrcStmt> {
    return match (p) {
        None -> None,
        Some(a) -> match (v) {
            None -> None,
            Some(b) -> Some(SetPlaceOp(op, a, b)),
        },
    };
}

''', after=False)

# --- parameters
once('''// extract: inline
fn param_of(pfuel: usize''', '''pub fn ref_ty(referent: core::option::Option<Ty>) -> core::option::Option<Ty> {
    return match (referent) {
        None -> None,
        Some(e) -> Some(TyRef(boxed(e))),
    };
}

// A parameter's type: `&T` and `&mut T` (T a type, not a reference) are
// references to T (F5, SEMANTIC_DECISIONS "S5 in Lanius's syntax" point 1).
pub fn param_ty_of(fuel: usize, env: FrontEnv, t: CTree) -> core::option::Option<Ty> {
    if (node_prod(t) == p_type_ref()) {
        return ref_ty(ty_of(fuel, env, kid(t, 1)));
    }
    if (node_prod(t) == p_type_ref_mut()) {
        return ref_ty(ty_of(fuel, env, kid(t, 2)));
    }
    return ty_of(fuel, env, t);
}

''', after=False)
once('''            Some(t) -> match (ty_of(pfuel, penv, t)) {
                None -> None,
                Some(x) -> cons_param(MParam''', '')
text = text.replace('''            Some(t) -> match (ty_of(pfuel, penv, t)) {
                None -> None,
                Some(x) -> cons_param(MParam''', '''            Some(t) -> match (param_ty_of(pfuel, penv, t)) {
                None -> None,
                Some(x) -> cons_param(MParam''')
once('''// extract: inline
fn p_param_named() -> usize {''', '''// extract: inline
fn p_type_ref() -> usize {
    return 285;
}

// extract: inline
fn p_type_ref_mut() -> usize {
    return 324;
}

''', after=False)

# --- assignments through a reference
once('''pub fn assign_target(fuel: usize, env: FrontEnv, scope: List<Local>, target: CTree, v: usize, value: CTree) -> core::option::Option<MStmt> {
    let tail: CTree = kid(target, 1);
''', '''    if (node_prod(tail) != p_postfix_end() && ref_rooted(local_of(env, scope, kid(target, 0)))) {
        return set_place_of(fuel, env, scope, eff_of(fuel, env, scope, None, target), value);
    }
''')
once('''pub fn assign_target(fuel: usize''', '''// F5 (S5): the local is a reference parameter.
pub fn ref_rooted(l: core::option::Option<Local>) -> bool {
    return match (l) {
        None -> false,
        Some(x) -> is_ref_ty(x.ty),
    };
}

// `place = value;` through a reference parameter, value read at the
// place's type. With an element step in the place, a value that can act is
// not read (as for `v[i] = value`, set_index_eval_of).
pub fn set_place_of(fuel: usize, env: FrontEnv, scope: List<Local>, place: core::option::Option<MEff>, value: CTree) -> core::option::Option<MStmt> {
    return match (place) {
        None -> None,
        Some(pl) -> checked_stmt(eff_place(pl), set_place_value(pl, length(env.decls.fns), eff_of(fuel, env, scope, eff_ty(fuel, env, scope, pl), value))),
    };
}

pub fn set_place_value(pl: MEff, n: usize, v: core::option::Option<MEff>) -> core::option::Option<MStmt> {
    return match (v) {
        None -> None,
        Some(x) -> stmt_unless(has_at(pl) && eff_acts(n, x), MSetPlace(pl, x)),
    };
}

// The operator of a compound assignment to a place: `/=` and `%=` are not
// read there.
pub fn assign_op_of(p: usize) -> core::option::Option<SrcAssignOp> {
    if (p == p_assign_add()) {
        return Some(AAdd);
    }
    if (p == p_assign_sub()) {
        return Some(ASub);
    }
    if (p == p_assign_mul()) {
        return Some(AMul);
    }
    if (p == p_assign_band()) {
        return Some(AAnd);
    }
    if (p == p_assign_bor()) {
        return Some(AOr);
    }
    if (p == p_assign_xor()) {
        return Some(AXor);
    }
    if (p == p_assign_shl()) {
        return Some(AShl);
    }
    if (p == p_assign_shr()) {
        return Some(AShr);
    }
    return None;
}

// `place op= value;` through a reference parameter, as set_place_of.
pub fn set_place_op_of(fuel: usize, env: FrontEnv, scope: List<Local>, op: core::option::Option<SrcAssignOp>, place: core::option::Option<MEff>, value: CTree) -> core::option::Option<MStmt> {
    return match (op) {
        None -> None,
        Some(o) -> match (place) {
            None -> None,
            Some(pl) -> checked_stmt(eff_place(pl), set_place_op_value(o, pl, length(env.decls.fns), eff_of(fuel, env, scope, eff_ty(fuel, env, scope, pl), value))),
        },
    };
}

pub fn set_place_op_value(o: SrcAssignOp, pl: MEff, n: usize, v: core::option::Option<MEff>) -> core::option::Option<MStmt> {
    return match (v) {
        None -> None,
        Some(x) -> stmt_unless(has_at(pl) && eff_acts(n, x), MSetPlaceOp(o, pl, x)),
    };
}

''', after=False)
once('''pub fn compound_eval(fuel: usize, env: FrontEnv, scope: List<Local>, target: CTree, p: usize, value: CTree) -> core::option::Option<MStmt> {
''', '''    if (node_prod(kid(target, 1)) != p_postfix_end() && ref_rooted(local_of(env, scope, kid(target, 0)))) {
        return set_place_op_of(fuel, env, scope, assign_op_of(p), eff_of(fuel, env, scope, None, target), value);
    }
''')

# --- the lifetime filter
once('''            Some(items) -> ref_checked(func_params(fuel, env, params_of(fuel, env, fd, empty(), items), rt, kid(f, 8), kid(kid(f, 9), 1)), self_ref_id(env, items)),''', '')
text = text.replace('''            Some(items) -> ref_checked(func_params(fuel, env, params_of(fuel, env, fd, empty(), items), rt, kid(f, 8), kid(kid(f, 9), 1)), self_ref_id(env, items)),''', '''            Some(items) -> refs_checked(fuel, f, items, ref_checked(func_params(fuel, env, params_of(fuel, env, fd, empty(), items), rt, kid(f, 8), kid(kid(f, 9), 1)), self_ref_id(env, items))),''')
once('''pub fn read_fn(fuel: usize''', '''// F5 (S5): a reference parameter is used only as the base of a field read
// or write (`p.f`, `p.f[i]`, `p.f = v`) or as a whole call argument: it is
// not reassigned, stored, returned, compared or a method's receiver
// (SEMANTIC_DECISIONS "S5 in Lanius's syntax" point 4). A filter only: the
// reading's relations do not name it.
pub fn refs_checked(fuel: usize, f: CTree, items: List<CTree>, m: core::option::Option<MFunc>) -> core::option::Option<MFunc> {
    return match (m) {
        None -> None,
        Some(x) -> checked_func(refs_used_ok(fuel, cons(kid(f, 8), single(kid(f, 9))), items, x.params), x),
    };
}

pub fn checked_func(ok: bool, m: MFunc) -> core::option::Option<MFunc> {
    if (ok) {
        return Some(m);
    }
    return None;
}

pub fn known_true(x: core::option::Option<bool>) -> bool {
    return match (x) {
        None -> false,
        Some(b) -> b,
    };
}

// Each reference parameter's uses in the trees are allowed.
pub fn refs_used_ok(fuel: usize, trees: List<CTree>, items: List<CTree>, ps: List<MParam>) -> bool {
    return match (items) {
        Nil -> true,
        Cons(i, irest) -> match (ps) {
            Nil -> true,
            Cons(p, prest) -> (!is_ref_ty(p.ty) || known_true(ref_uses_ok(fuel, trees, param_token(i).text))) && refs_used_ok(fuel, trees, unbox(irest), unbox(prest)),
        },
    };
}

// Whether every token of the trees spelled name is an allowed use of a
// reference parameter (see refs_checked); None when fuel runs out.
pub fn ref_uses_ok(fuel: usize, todo: List<CTree>, name: List<usize>) -> core::option::Option<bool> {
    if (fuel == 0) {
        return None;
    }
    return match (todo) {
        Nil -> Some(true),
        Cons(t, rest) -> match (t) {
            Leaf(tok) -> and_known(Some(!same_text(tok.text, name)), ref_uses_ok(minus(fuel, 1), unbox(rest), name)),
            Node(q, kids) -> ref_uses_ok(minus(fuel, 1), concat(ref_kids(fuel, t, name), unbox(rest)), name),
        },
    };
}

// The subtrees of t still to check: an argument that is the bare name, and
// the name at the base of a field, are allowed uses.
pub fn ref_kids(fuel: usize, t: CTree, name: List<usize>) -> List<CTree> {
    if ((node_prod(t) == p_args_some() || node_prod(t) == p_args_after_comma_more()) && tree_names(fuel, kid(t, 0), name)) {
        return single(kid(t, 1));
    }
    if (node_prod(t) == p_postfix() && names_field_base(t, name)) {
        return single(kid(kid(t, 1), 3));
    }
    return kids_of(t);
}

// `name.f` then anything but a call (`name.m(..)` is a method call).
pub fn names_field_base(pf: CTree, name: List<usize>) -> bool {
    let primary: CTree = kid(pf, 0);
    let tail: CTree = kid(pf, 1);
    return node_prod(primary) == p_ident() && node_prod(kid(primary, 1)) == p_ident_plain() && is_text(path_name(kid(primary, 0)), name) && node_prod(tail) == p_postfix_member() && node_prod(kid(tail, 2)) == p_member_type_args_none() && node_prod(kid(tail, 3)) != p_postfix_call();
}

''', after=False)
open(path, 'w').write(text)
print('ok')
