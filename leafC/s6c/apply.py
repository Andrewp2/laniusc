# S6c on top of S6b's compiler.lani: calls (lowering-spec "S6c: calls").
import sys
p=sys.argv[1]; s=open(p).read()
def rep(a,b,count=1):
    global s
    n=s.count(a); assert n==count,(n,a[:100]); s=s.replace(a,b)

# 1. references compare by their referents (a reference argument at a &T parameter, a reference local passed on)
rep("""            Str -> other.is_str(),
            Ref(referent) -> false,
        };
    }
}
""","""            Str -> other.is_str(),
            Ref(referent) -> match (other) {
                I32 -> false,
                Bool -> false,
                Uint(other_kind) -> false,
                Struct(other_id, other_fields) -> false,
                Enum(other_id, other_variants) -> false,
                Ptr -> false,
                Slice(other_element) -> false,
                SrcType::Array(array_element, array_length) -> false,
                Unit -> false,
                Isize -> false,
                SrcType::Char -> false,
                SrcType::Float(ft) -> false,
                Sint(other_sk) -> false,
                View(other_length) -> false,
                Str -> false,
                Ref(other_referent) -> unbox(referent).same(unbox(other_referent)),
            },
        };
    }
}
""")

# 2. an array passed as a slice is lent: its home's address and its length (eval, any call)
rep("            ArraySlice(element, array) -> None,\n            EIf(condition, ty, then_value, else_value) -> eval_if(",
    "            ArraySlice(element, array) -> eval_lent(own_frame(sigs), lookup(scope, array), element, slot),\n            EIf(condition, ty, then_value, else_value) -> eval_if(")
anchor="""// extract: mutual begin
impl SrcEff {
    // The code computing this expression into slot, slot + 1, ..., and its type."""
rep(anchor, """pub fn lent_checked(frame: usize, home: usize, ty: SrcType, element: SrcType, slot: usize) -> core::option::Option<Evaluated> {
    let count: usize = ty.size();
    if ((element.same(I32) || element.same(Uint(Uint8))) && ty.same(SrcType::Array(boxed(element), count)) && (2147483648 > count)) {
        return Some(Evaluated { stmt: Seq(boxed(Assign(slot, lay_add_off(frame, home))), boxed(Assign(plus(slot, 1), Lit(count as u64)))), ty: Slice(boxed(element)) });
    }
    return None;
}

pub fn lent_home(frame: usize, b: Binding, element: SrcType, slot: usize) -> core::option::Option<Evaluated> {
    return match (b.home) {
        None -> None,
        Some(home) -> lent_checked(frame, home, b.ty, element, slot),
    };
}

// An array local passed as a slice (F5 S6c): a homed i32 or u8 array is
// lent with no copy, its home's address frame + offset into slot and its
// length into slot + 1 (HomeLendArgs). An array with no home is not passed.
pub fn eval_lent(frame: usize, binding: core::option::Option<Binding>, element: SrcType, slot: usize) -> core::option::Option<Evaluated> {
    return match (binding) {
        None -> None,
        Some(b) -> lent_home(frame, b, element, slot),
    };
}

"""+anchor)

# 3. a call passing slices is an ordinary call (its arguments' code, then Call)
rep("""// The code of a value a statement computes (LetEval, Discard): a call
// passing arrays as slices (array_call), or any other expression's code.
pub fn stmt_eval(value: SrcEff, sigs: List<Sig>, decls: SrcDecls, scope: List<Binding>, next: usize) -> core::option::Option<Evaluated> {
    if (value.passes_slices()) {
        return value.slice_call(sigs, scope, next);
    }
    return value.eval(sigs, decls, scope, next);
}""","""// The code of a value a statement computes (LetEval, Discard): its code.
// A call passing arrays as slices lends them (eval_lent, F5 S6c), so it is
// an ordinary call.
pub fn stmt_eval(value: SrcEff, sigs: List<Sig>, decls: SrcDecls, scope: List<Binding>, next: usize) -> core::option::Option<Evaluated> {
    return value.eval(sigs, decls, scope, next);
}""")
open(p,'w').write(s); print("applied")
