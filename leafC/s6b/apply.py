import sys
D='/home/andrew-peterson/code/laniusc/target/claude-work/leafC/s6b/'
p=sys.argv[1]; s=open(p).read()
def rep(a,b,count=1):
    global s
    n=s.count(a)
    assert n==count, (n, a[:120])
    s=s.replace(a,b)
def ins_before(anchor, text):
    rep(anchor, text+anchor)

# --- Binding comment, lookup split
rep("""// home: the byte offset of the binding's home in its function's frame block,
// for a local that lives in frame memory (F5 S6b, a borrowed local); None for
// a local in slots, which every binding is until S6b.""",
"""// home: the byte offset of the binding's home in its function's frame block,
// for a local that lives in frame memory (F5 S6b: a local a borrow's place
// names, or an array local passed as a slice); None for a local in slots.""")
rep("""// The innermost binding of id.
pub fn lookup(scope: List<Binding>, id: usize) -> core::option::Option<Binding> {
    return match (scope) {
        Nil -> None,
        Cons(binding, rest) -> lookup_at(binding, unbox(rest), id),
    };
}

// extract: inline
fn lookup_at(binding: Binding, rest: List<Binding>, id: usize) -> core::option::Option<Binding> {
    if (binding.id == id) {
        return Some(binding);
    }
    return lookup(rest, id);
}""",
"""// The innermost binding of id (homed or not).
pub fn lookup_any(scope: List<Binding>, id: usize) -> core::option::Option<Binding> {
    return match (scope) {
        Nil -> None,
        Cons(binding, rest) -> lookup_at(binding, unbox(rest), id),
    };
}

// extract: inline
fn lookup_at(binding: Binding, rest: List<Binding>, id: usize) -> core::option::Option<Binding> {
    if (binding.id == id) {
        return Some(binding);
    }
    return lookup_any(rest, id);
}

// A binding when it has no home.
pub fn unhomed(binding: core::option::Option<Binding>) -> core::option::Option<Binding> {
    return match (binding) {
        None -> None,
        Some(b) -> match (b.home) {
            None -> Some(b),
            Some(offset) -> None,
        },
    };
}

// The innermost binding of id when it has no home: every read of a slot
// goes through this, so a homed local is never read into an Expr (F5 S6b).
// lookup finds a binding homed or not.
pub fn lookup(scope: List<Binding>, id: usize) -> core::option::Option<Binding> {
    return unhomed(lookup_any(scope, id));
}""")

# --- Sig.frame
rep("""pub struct Sig {
    params: List<SrcType>,
    ret: SrcType,
    need: usize,
    room: usize,
    block: usize,
}""","""pub struct Sig {
    params: List<SrcType>,
    ret: SrcType,
    need: usize,
    room: usize,
    block: usize,
    // the frame slot of the function lowered against the signatures (F5
    // S6b: its block's address, with_budget's)
    frame: usize,
}""")
rep("""pub fn with_budget(sigs: List<Sig>, room: usize, block: usize) -> List<Sig> {
    return match (sigs) {
        Nil -> empty(),
        Cons(sig, rest) -> cons(Sig { params: sig.params, ret: sig.ret, need: sig.need, room: room, block: block }, with_budget(unbox(rest), room, block)),""",
"""pub fn with_budget(sigs: List<Sig>, room: usize, block: usize, frame: usize) -> List<Sig> {
    return match (sigs) {
        Nil -> empty(),
        Cons(sig, rest) -> cons(Sig { params: sig.params, ret: sig.ret, need: sig.need, room: room, block: block, frame: frame }, with_budget(unbox(rest), room, block, frame)),""")
rep("room: 0, block: 0 }, sigs_with(", "room: 0, block: 0, frame: 0 }, sigs_with(")

# --- layout after width_of
anchor="""// A struct or enum slice's descriptor points at element zero's word 0, its high"""
ins_before(anchor, open(D+'layout.lani').read().lstrip('\n')+"\n")

# --- homes before SrcEff.eval
anchor="""// extract: mutual begin
impl SrcEff {
    // The code computing this expression into slot, slot + 1, ..., and its type."""
h=open(D+'homes.lani').read().replace("    if (id_absent(uses, id)) {\n        return None;\n    }\n    return Some(homed_bytes(scope));",
 "    if (id_listed(uses, id)) {\n        return Some(homed_bytes(scope));\n    }\n    return None;")
h=h.replace("// The home of a declaration of id:", """// id is one of ids.
pub fn id_listed(ids: List<usize>, id: usize) -> bool {
    return match (ids) {
        Nil -> false,
        Cons(other, rest) -> (other == id) || id_listed(unbox(rest), id),
    };
}

// The home of a declaration of id:""")
ins_before(anchor, h.lstrip('\n')+"\n")

# --- eval arms
rep("            EPure(e) -> eval_pure(scope, e, slot),\n            ECall(callee, args) -> eval_call(",
    "            EPure(e) -> eval_pure_any(own_frame(sigs), scope, e, slot),\n            ECall(callee, args) -> eval_call(")
rep("            EIndex(slice, index) -> eval_index(decls, scope, slice, slot, unbox(index).eval(sigs, decls, scope, slot)),",
    "            EIndex(slice, index) -> eval_index_any(own_frame(sigs), decls, scope, slice, slot, unbox(index), unbox(index).eval(sigs, decls, scope, slot)),")
rep("""            EBorrow(bty, bplace) -> None,
            EDeref(dty, dref) -> None,
            EField(fbase, fidx) -> None,
            EAt(abase, aindex) -> None,
        };
    }
}

// The arguments, each in the slots after the one before.""","""            EBorrow(bty, bplace) -> eval_borrow(bty, place_code(own_frame(sigs), scope, slot, unbox(bplace))),
            EDeref(dty, dref) -> eval_place_at(own_frame(sigs), scope, EDeref(dty, dref), slot),
            EField(fbase, fidx) -> eval_place_at(own_frame(sigs), scope, EField(fbase, fidx), slot),
            EAt(abase, aindex) -> eval_place_at(own_frame(sigs), scope, EAt(abase, aindex), slot),
        };
    }
}

// The arguments, each in the slots after the one before.""")

# --- stmts helpers before stmt_eval
anchor="// The code of a value a statement computes (LetEval, Discard): a call"
st=open(D+'stmts.lani').read()
st+="""
pub fn if_pick(reads: bool, slot: usize, g: Expr, condition: core::option::Option<Expr>, twin: core::option::Option<Evaluated>, then_branch: core::option::Option<Stmt>, else_branch: core::option::Option<Stmt>) -> core::option::Option<Stmt> {
    if (reads) {
        return lower_if_eval(slot, twin, then_branch, else_branch);
    }
    return guarded(slot, g, lower_if(condition, then_branch, else_branch));
}

pub fn while_pick(reads: bool, slot: usize, g: Expr, condition: core::option::Option<Expr>, twin: core::option::Option<Evaluated>, body: core::option::Option<Stmt>) -> core::option::Option<Stmt> {
    if (reads) {
        return lower_while_eval(slot, twin, body);
    }
    return lower_while(slot, g, condition, body);
}

pub fn return_pick(reads: bool, slot: usize, g: Expr, values: core::option::Option<List<Expr>>, ret: SrcType, twin: core::option::Option<Evaluated>) -> core::option::Option<Stmt> {
    if (reads) {
        return lower_return_eval(slot, ret, twin);
    }
    return guarded(slot, g, lower_return(values));
}

// let id = array[index] on a homed array: the element's load (LetEval of eAt).
pub fn let_index_pick(homed: bool, decls: SrcDecls, scope: List<Binding>, next: usize, ty: SrcType, slice: usize, index: SrcExpr, twin: core::option::Option<Evaluated>, body: core::option::Option<Stmt>) -> core::option::Option<Stmt> {
    if (homed) {
        return lower_let_eval(ty, twin, body);
    }
    return lower_let_index_any(decls, scope, next, ty, slice, index, body);
}
"""
ins_before(anchor, st.lstrip('\n')+"\n")

# --- SrcStmt.lower arms
F="own_frame(sigs)"; B="own_block(sigs)"
def H(body): return f"home_for(unbox({body}).slice_uses(), scope, id)"
def bodyl(body, ty="ty", size="ty.size()", home=None):
    return f"unbox({body}).lower(sigs, decls, ret, cons(Binding {{ id: id, slot: next, ty: {ty}, home: {home or H(body)} }}, scope), plus(next, {size}))"
arms = {
"Let(id, ty, value, body) -> ":
  f"fits_then(home_fits({H('body')}, ty, {B}), let_pick(reads_home(scope, value), next, value.guard(scope), lower_value(scope, value, ty), ty, eval_pure_any({F}, scope, value, next), home_store_then({F}, {H('body')}, ty, next, {bodyl('body')}))),",
"LetStruct(id, ty, fields, body) -> ":
  f"fits_then(home_fits({H('body')}, ty, {B}), let_pick(reads_homes(scope, fields), next, guard_all(scope, fields), lower_literal(scope, ty, fields), ty, EStruct(ty, boxed(pures(fields))).eval(sigs, decls, scope, next), home_store_then({F}, {H('body')}, ty, next, {bodyl('body')}))),",
"LetCall(id, ty, callee, args, body) -> ":
  f"fits_then(home_fits({H('body')}, ty, {B}), let_call_pick(reads_homes(scope, args), next, guard_all(scope, args), ty.size(), callee, lower_call(sigs, scope, callee, args, ty), ty, ECall(callee, boxed(pures(args))).eval(sigs, decls, scope, next), home_store_then({F}, {H('body')}, ty, next, {bodyl('body')}))),",
"LetEnum(id, ty, variant, payload, body) -> ":
  f"fits_then(home_fits({H('body')}, ty, {B}), let_pick(reads_homes(scope, payload), next, guard_all(scope, payload), lower_enum_value(scope, ty, variant, payload), ty, EVariant(ty, variant, boxed(pures(payload))).eval(sigs, decls, scope, next), home_store_then({F}, {H('body')}, ty, next, {bodyl('body')}))),",
"LetMatch(id, ty, scrutinee, enum_id, arms, body) -> ":
  f"fits_then(home_fits({H('body')}, ty, {B}), lower_then(lower_match(scope, lookup(scope, scrutinee), enum_id, arms, ty, next), home_store_then({F}, {H('body')}, ty, next, {bodyl('body')}))),",
"Set(id, value) -> ":
  f"set_pick(is_homed(lookup_any(scope, id)), store_place(next, place_code({F}, scope, next, EPure(Local(id))), eval_pure_any({F}, scope, value, plus(next, 1))), stmt_pick(reads_home(scope, value), guarded(next, value.guard(scope), lower_set(lookup(scope, id), scope, value)), lower_set_eval(next, lookup(scope, id), eval_pure_any({F}, scope, value, next)))),",
"SetField(id, index, value) -> ":
  f"set_pick(is_homed(lookup_any(scope, id)), store_place(next, place_code({F}, scope, next, EField(boxed(EPure(Local(id))), index)), eval_pure_any({F}, scope, value, plus(next, 1))), stmt_pick(reads_home(scope, value), guarded(next, value.guard(scope), lower_set_field(lookup(scope, id), index, scope, value)), lower_set_field_eval(next, lookup(scope, id), index, eval_pure_any({F}, scope, value, next)))),",
"SetCall(id, callee, args) -> ":
  f"set_pick(is_homed(lookup_any(scope, id)), store_place(next, place_code({F}, scope, next, EPure(Local(id))), ECall(callee, boxed(pures(args))).eval(sigs, decls, scope, plus(next, 1))), stmt_pick(reads_homes(scope, args), guarded(next, guard_all(scope, args), lower_set_call(sigs, scope, lookup(scope, id), callee, args)), lower_set_eval(next, lookup(scope, id), ECall(callee, boxed(pures(args))).eval(sigs, decls, scope, next)))),",
"If(condition, then_branch, else_branch) -> ":
  f"if_pick(reads_home(scope, condition), next, condition.guard(scope), lower_as(scope, condition, Bool), eval_pure_any({F}, scope, condition, next), unbox(then_branch).lower(sigs, decls, ret, scope, next), unbox(else_branch).lower(sigs, decls, ret, scope, next)),",
"While(condition, body) -> ":
  f"while_pick(reads_home(scope, condition), next, condition.guard(scope), lower_as(scope, condition, Bool), eval_pure_any({F}, scope, condition, next), unbox(body).lower(sigs, decls, ret, scope, next)),",
"Return(value) -> ":
  f"return_pick(reads_home(scope, value), next, value.guard(scope), lower_value(scope, value, ret), ret, eval_pure_any({F}, scope, value, next)),",
"LetIndex(id, ty, slice, index, body) -> ":
  f"unhomed_then({H('body')}, let_index_pick(is_homed(lookup_any(scope, slice)), decls, scope, next, ty, slice, index, eval_place_at({F}, scope, EAt(boxed(EPure(Local(slice))), boxed(EPure(index))), next), {bodyl('body', home='None')})),",
"SetIndex(slice, index, value) -> ":
  f"set_pick(is_homed(lookup_any(scope, slice)), store_place(next, place_code({F}, scope, next, EAt(boxed(EPure(Local(slice))), boxed(EPure(index)))), eval_pure_any({F}, scope, value, plus(next, 1))), lower_set_index_any(decls, scope, next, slice, index, value)),",
"LetEval(id, ty, value, body) -> ":
  f"fits_then(home_fits({H('body')}, ty, {B}), lower_let_eval(ty, stmt_eval(value, sigs, decls, scope, next), home_store_then({F}, {H('body')}, ty, next, {bodyl('body')}))),",
"SetEval(id, value) -> ":
  f"set_pick(is_homed(lookup_any(scope, id)), store_place(next, place_code({F}, scope, next, EPure(Local(id))), value.eval(sigs, decls, scope, plus(next, 1))), lower_set_eval(next, lookup(scope, id), value.eval(sigs, decls, scope, next))),",
"SetIndexEval(slice, index, value) -> ":
  f"set_pick(is_homed(lookup_any(scope, slice)), store_place(next, place_code({F}, scope, next, EAt(boxed(EPure(Local(slice))), boxed(index))), value.eval(sigs, decls, scope, plus(next, 1))), lower_set_index_eval(decls, next, lookup(scope, slice), index.eval(sigs, decls, scope, next), value.eval(sigs, decls, scope, plus(next, 1)))),",
"SetFieldEval(id, field, value) -> ":
  f"set_pick(is_homed(lookup_any(scope, id)), store_place(next, place_code({F}, scope, next, EField(boxed(EPure(Local(id))), field)), value.eval(sigs, decls, scope, plus(next, 1))), lower_set_field_eval(next, lookup(scope, id), field, value.eval(sigs, decls, scope, next))),",
"SetPlace(aplace, avalue) -> ":
  f"store_place(next, place_code({F}, scope, next, aplace), avalue.eval(sigs, decls, scope, plus(next, 1))),",
"SetPlaceOp(aop, aplace, avalue) -> ":
  f"store_place_op(aop, next, place_code({F}, scope, next, aplace), avalue.eval(sigs, decls, scope, plus(next, 2))),",
}
# locate SrcStmt.lower body
start=s.index("impl SrcStmt {\n    pub fn lower(self, sigs: List<Sig>, decls: SrcDecls, ret: SrcType, scope: List<Binding>, next: usize) -> core::option::Option<Stmt> {")
end=s.index("    pub fn breaks_out(self) -> bool", start)
seg=s[start:end]
lines=seg.split('\n')
out=[]
done=set()
for ln in lines:
    st_=ln.strip()
    hit=None
    for k in arms:
        if st_.startswith(k):
            hit=k
    if hit:
        out.append('            '+hit+arms[hit]); done.add(hit)
    else:
        out.append(ln)
assert done==set(arms), set(arms)-done
seg='\n'.join(out)
# unhomed-only declarations: LetAlloc, LetLoad, LetSlice, LetView, LetStr
for k,idv in [("LetAlloc(id, size, shift, body) -> ","id"),("LetLoad(id, pointer, offset, body) -> ","id"),("LetSlice(id, element, pointer, length, body) -> ","id"),("LetView(id, length, fields, pointer, body) -> ","id"),("LetStr(pointer, chars, body) -> ","pointer")]:
    i=seg.index(k); j=seg.index('\n', i)
    rhs=seg[i+len(k):j].rstrip(',')
    seg=seg[:i]+k+f"unhomed_then(home_for(unbox(body).slice_uses(), scope, {idv}), {rhs}),"+seg[j:]
s=s[:start]+seg+s[end:]

# --- slice_uses: borrows name their roots
rep("            EBorrow(bty, bplace) -> unbox(bplace).slice_uses(),",
    "            EBorrow(bty, bplace) -> concat(place_roots(unbox(bplace)), unbox(bplace).slice_uses()),")

# --- decl_bytes: a home's native words
rep("""// The block bytes of a declaration of id at type ty: its array bytes when
// id is passed as a slice.
pub fn decl_bytes(uses: List<usize>, id: usize, ty: SrcType) -> usize {
    if (id_absent(uses, id)) {
        return 0;
    }
    return array_bytes_of(ty);
}""","""// The block bytes of a declaration of id at type ty: its home's native
// words when it has one (a borrow names it or it is passed as a slice).
pub fn decl_bytes(uses: List<usize>, id: usize, ty: SrcType) -> usize {
    if (id_absent(uses, id)) {
        return 0;
    }
    return times(8, ty_words(ty));
}""")

# --- param_scope with homes
rep("""pub fn param_scope(params: List<SrcParam>, slot: usize, scope: List<Binding>) -> List<Binding> {
    return match (params) {
        Nil -> scope,
        Cons(param, rest) -> param_scope(unbox(rest), plus(slot, param.ty.size()), cons(Binding { id: param.id, slot: slot, ty: param.ty, home: None }, scope)),
    };
}""","""// A borrowed parameter has a home (stack order: the parameters first).
pub fn param_scope(params: List<SrcParam>, slot: usize, scope: List<Binding>, uses: List<usize>) -> List<Binding> {
    return match (params) {
        Nil -> scope,
        Cons(param, rest) -> param_scope(unbox(rest), plus(slot, param.ty.size()), cons(Binding { id: param.id, slot: slot, ty: param.ty, home: home_for(uses, scope, param.id) }, scope), uses),
    };
}""")

# --- with_frame comment, lower_func
rep("""// The body after the function's block is taken (its address into slot,
// which the body's first let overwrites), when it has one.""","""// The body after the function's block is taken (its address into slot, the
// frame slot, which the body keeps: it is lowered from slot + 1), when it
// has one.""")
rep("""    let count: usize = params_size(func.params);
    let block: usize = frame_block(func);
    if ((func.ret.size() > 0) && params_valid(func.params) && !func.body.breaks_out() && (own.need >= block) && (2147483648 > block) && (need_limit() > own.need)) {
        return lower_body(count, func.ret.size(), func.body.depth(), unit_tail(func.ret, with_frame(count, block, func.body.lower(with_budget(sigs, minus(own.need, block), block), decls, func.ret, param_scope(func.params, 0, empty()), count))));
    }
    return None;""","""    let count: usize = params_size(func.params);
    let block: usize = frame_block(func);
    let uses: List<usize> = func.body.slice_uses();
    let scope: List<Binding> = param_scope(func.params, 0, empty(), uses);
    if ((func.ret.size() > 0) && params_valid(func.params) && !func.body.breaks_out() && (own.need >= block) && (2147483648 > block) && (need_limit() > own.need) && params_homes_fit(scope, block) && !((length(uses) > 0) && holds_pointer(func.ret))) {
        return lower_body(count, func.ret.size(), func.body.depth(), unit_tail(func.ret, with_frame(count, block, entry_then(count, scope, func.body.lower(with_budget(sigs, minus(own.need, block), block, count), decls, func.ret, scope, frame_body_start(count, block))))));
    }
    return None;""")
ins_before("// Results and struct parameters have slots; a function returns its result", """// The body's first slot: past the frame slot when the function has a block.
pub fn frame_body_start(count: usize, block: usize) -> usize {
    if (block > 0) {
        return plus(count, 1);
    }
    return count;
}

""")

# --- array args: homed arrays pass their home, no copies
rep("pub fn array_arg_local(b: Binding, element: SrcType, ty: SrcType, id: usize, t: usize, offset: usize, rest: core::option::Option<ArrayArgs>) -> core::option::Option<ArrayArgs> {",
    "pub fn array_arg_local(frame: usize, b: Binding, element: SrcType, ty: SrcType, id: usize, t: usize, offset: usize, rest: core::option::Option<ArrayArgs>) -> core::option::Option<ArrayArgs> {")
rep("        Some(r) -> array_arg_before(b, element, ty, id, t, offset, width, count, r),",
    "        Some(r) -> array_arg_home(frame, b, element, ty, id, width, count, r),")
ins_before("pub fn array_arg_local(frame: usize,", """// The homed array local b before the arguments r (F5 S6b): its home's
// address frame + offset and its length, with no copy (HomeLendArgs).
pub fn array_arg_home(frame: usize, b: Binding, element: SrcType, ty: SrcType, id: usize, width: usize, count: usize, r: ArrayArgs) -> core::option::Option<ArrayArgs> {
    return match (b.home) {
        None -> None,
        Some(home) -> array_arg_checked((width > 0) && b.ty.same(SrcType::Array(boxed(element), count)) && ty.same(Slice(boxed(element))) && (2147483648 > count) && id_absent(r.ids, id), ArrayArgs { stores: r.stores, args: cons(lay_add_off(frame, home), cons(Lit(count as u64), r.args)), loads: r.loads, guard: r.guard, bytes: r.bytes, ids: cons(id, r.ids) }),
    };
}

""")
rep("pub fn array_arg_slice(binding: core::option::Option<Binding>,", "pub fn array_arg_slice(frame: usize, binding: core::option::Option<Binding>,")
rep("        Some(b) -> array_arg_local(b, element, ty, id, t, offset, rest),", "        Some(b) -> array_arg_local(frame, b, element, ty, id, t, offset, rest),")
rep("pub fn array_arg(scope: List<Binding>, arg: SrcEff,", "pub fn array_arg(frame: usize, scope: List<Binding>, arg: SrcEff,")
rep("        ArraySlice(element, array) -> array_arg_slice(lookup(scope, array), element, ty, array, t, offset, rest),",
    "        ArraySlice(element, array) -> array_arg_slice(frame, lookup_any(scope, array), element, ty, array, t, offset, rest),")
rep("pub fn array_args(scope: List<Binding>, args: List<SrcEff>,", "pub fn array_args(frame: usize, scope: List<Binding>, args: List<SrcEff>,")
rep("            Cons(ty, more) -> array_arg(scope, arg, ty, t, offset, array_args(scope, unbox(rest), unbox(more), t, plus(offset, arg_bytes(scope, arg)))),",
    "            Cons(ty, more) -> array_arg(frame, scope, arg, ty, t, offset, array_args(frame, scope, unbox(rest), unbox(more), t, plus(offset, arg_bytes(scope, arg)))),")
rep("    return match (array_args(scope, args, sig.params, plus(next, sig.ret.size()), 0)) {",
    "    return match (array_args(sig.frame, scope, args, sig.params, plus(next, sig.ret.size()), 0)) {")
rep("""    let count: usize = sig.ret.size();
    let t: usize = plus(next, count);
    if ((count > 0) && sig.ret.is_scalar() && (sig.need <= sig.room) && (sig.block > 0) && (a.bytes <= sig.block)) {
        return Some(Evaluated { stmt: check_then(next, a.guard, Seq(boxed(Stmt::Frame(t, 0)), boxed(Seq(boxed(a.stores), boxed(Seq(boxed(Stmt::Call(next, count, callee, a.args)), boxed(Seq(boxed(Stmt::Frame(t, 0)), boxed(a.loads))))))))), ty: sig.ret });
    }
    return None;""","""    let count: usize = sig.ret.size();
    if ((count > 0) && sig.ret.is_scalar() && (sig.need <= sig.room)) {
        return Some(Evaluated { stmt: check_then(next, a.guard, Stmt::Call(next, count, callee, a.args)), ty: sig.ret });
    }
    return None;""")
# --- slice_uses (and callee_need) before SrcStmt.lower: lower declares homes from them
a=s.index("// extract: mutual begin\nimpl SrcEff {\n    // The ids of the arrays the expression passes as slices.")
e=s.index("// The room left of room after each declaration's block bytes", a)
blk=s[a:e]
s=s[:a]+s[e:]
anchor="impl SrcStmt {\n    pub fn lower(self, sigs: List<Sig>,"
assert s.count(anchor)==1
s=s.replace(anchor, blk+anchor)
# --- names: lookup stays the lookup of any binding (the open statements' lookup);
# slot reads use lookup_slot
import re
s=re.sub(r'(?<![\w.])lookup\(', 'lookup_slot(', s)
s=re.sub(r'(?<![\w.])lookup_any\(', 'lookup(', s)
open(p,'w').write(s)
print("applied")
