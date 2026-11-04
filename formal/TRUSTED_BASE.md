# Trusted base of the verified compiler

Roadmap steps 14 and F13. This file lists every assumption the top theorems
rest on and do not prove, each as a specification: what is assumed, not how
the code is built. Evidence for the assumptions (tests against the CPU, the
difftests) is in section 9, and what is not trusted is in section 10.

Gate step `trusted` (`formal/tools/trusted_check.py`, quick tier) runs
`lake exe topAxioms` (`Lanius/Tools/TopAxioms.lean`) on the built modules
and fails
- when a top theorem depends on an axiom other than `propext`,
  `Classical.choice` and `Quot.sound` (section 1);
- when a top theorem's statement hash is not the one beside its entry below,
  or a theorem is listed here and not in `TopAxioms.lean`'s `tops`, or the
  other way round;
- when the hash of the trusted definitions is not the one given below
  (`definitions`);
- when the modules are not built from the current sources.

So a statement, or a definition it means, cannot change without this file
changing. The hashes are the kernel's structural hash of each statement
(`Expr.hash`, 32 bits, printed as 16 hex digits). When one changes, update the
entry (what the theorem says and assumes) and then the hash.

## Top theorems

Each entry: the theorem, its file, its statement hash, and what it says,
with its premises. The sections named are the ones it rests on. "The
caller's obligations" are the premises on the x86 state at entry (section
8): the image loaded at some base apart from the stack window and the heap,
`rip` at the function's entry, the arguments' slots below the return
address, `HeapAt` and `StackAt`. Every theorem's run is a run of the x86
model (section 6) and every Core run is Core's evaluator (section 3).

The trusted definitions: every constant of the project that these
statements reach, through types, definition bodies and constructors,
stopping at the computations the theorems are about (`compileSource`,
`compileText`, `compileProgram`, `compileOptimized`, `compileModules`,
`linkObjects`, `elfFile`, `sourceProgramFiles`, `compileWords`,
`frontEndWords`, the self program `Lanius.Faithful.Self.prog` and
`funcNeeds`, which are not trusted, section 10), with each one's type and
body:
definitions `0f6a55aee2f2995d` (4909 constants). This covers Core's
semantics, the x86 model, the reading of source text, the Linux model and
the statements' own definitions (section 2). A private name is hashed
without its module, so a definition that only moves between generated
modules keeps its hash. The last change of the hash (11-04, leafC, merging lang `07bb5c4a3` into leafC-s5b, giving `0f6a55aee2f2995d`; `0a6475e07ff0859d` on leafC-s5b before the merge, SEMANTIC_DECISIONS "S5b: point 10, receivers are references" and S5's point 3, F5 S5b): the reading of source text reads `&self` and `&mut self` as reference parameters and method receivers as borrows. `ParamsR.cons` reads a parameter's type with `SelfParamTyR` (`Reading/Funcs.lean`): `byRef` gives `self_ref` and `self_ref_mut` (`pParamSelfRefMut`, 325, new; `PatternOf.selfRefMut`) the type `tyRef` of the impl's type, and `other` reads any other parameter with `ParamTyR`, which moved to `Reading/Types.lean` with `paramTyList_sound`. The by-value reading of `&self` and its `writesLocal` condition are gone from `ReadFn`; `self` is checked by `refsChecked` like any reference parameter (`primaryNames`, extracted, names `self`). `MEff` gains `xBorrow ty place`, closed to `SrcEff.eBorrow` (`EffClosed.borrow`) and typed `ty` (`EffTy.borrow`). `EffChain.method` and `EffR.method` find the method on the referent of the receiver's type (`referentOr`) and read the receivers with `Receivers` (`Reading/Effs.lean`): a method taking `&self` gets a receiver of reference type as it is and a borrow (`borrowOf`, `placeOf`, extracted) of any other receiver's place (a local, a field or element of one, or a place through a reference); a by-value `self` method on a reference receiver is not read (`receiverOf`). `MethodEff` and `effFoundWith` carry the receivers. S5's point 3: `MatchTy` gains `ref` and `refMut`, which match `type_ref` and `type_ref_mut` against a reference type's referent, and `ParamExpects`/`ArgExpected` read a parameter's type with `ParamTyR`, so a reference parameter passed whole to a reference parameter is read. Nothing lowers a borrow yet, so `compileSource` accepts no program with a `&self` call (S6b). The self program's functions moved (`frontend.lani` gained the readings), so the prim table `prims` was regenerated; the merge changed none of the other side's definitions. The change before (11-04, leafB, giving `449ff9754ce0ed32`, SEMANTIC_DECISIONS "A call's array offsets checked as they add up"): only the prim table `prims` changed, regenerated because the self program's functions moved: `compiler.lani`'s `array_args` rejects an offset over `block_limit` (2^31 - 1), and the new `array_arg_before` (split out of `array_arg_local`) rejects the later arguments' bytes over it before adding an array's; `block_limit` moved to `Compiler/P/bindingBytes.lean`. `compileSource` is not trusted (section 10); its correctness theorems cover what it accepts. The change before (11-03, leafA, merging lang `6163ae1f2` (S5) into leafA-slots, giving `1ab522a8e6fc9323`, SEMANTIC_DECISIONS "The evaluator's slots checked against a limit"): only the prim table `prims` changed, regenerated because the self program's functions moved. On leafA-slots (giving `fc0ed3b8d0a06079` before the merge), `compiler.lani` gained `eval_slot_limit` (2^40), which `eval_args`, `eval_let_body` and `eval_arm_in` check their start slot against, returning `None` at or past it. `compileSource` is not trusted (section 10); its correctness theorems cover what it accepts. The change before (11-03, leafC, merging lang `938574f47` (leafA-frame) into leafC, giving `8383ab6c600c2220`, SEMANTIC_DECISIONS "S5 in Lanius's syntax", F5 S5): the reading of source text reads `&T` and `&mut T` parameters as references, and field and element reads and writes through them as places. `Ty.tyRef referent` is new (`Frontend/Types.lean`, extracted), made only by a parameter's type: `ParamsR.cons` reads its type with `ParamTyR` (`Reading/Funcs.lean`), whose `ref` and `refMut` read `type_ref` (production `pTypeRef`, 285) and `type_ref_mut` (`pTypeRefMut`, 324) as `tyRef` of the type the inner type expression names, and whose `plain` reads any other type expression with `TyR` as before. It lowers to `SrcType.ref` (`LowerR.ref`, `TyInsts.ref`). `MEff` gains `xDeref ty r` (the referent of the reference `r`, of type `ty`), `xPlaceField place j` and `xPlaceAt place i` (a field or element of a place), closed to `SrcEff.eDeref`, `eField` and `eAt` (`EffClosed.deref`, `placeField`, `placeAt`) and typed by `EffTy.deref`, `placeField` (with `FieldTyAt`, which moved to `Reading/Calls.lean`), `placeAt` and `placeAtArray`; `MStmt` gains `mSetPlace` and `mSetPlaceOp`, closed to `SrcStmt.setPlace` and `setPlaceOp` (`StmtClosed.setPlace`, `setPlaceOp`). `EffChain.field` reads the field's index in the referent of a reference type (`referentOr`), and `fieldValue` (extracted) gives a field of a place, or of a value of a reference type, `xPlaceField` of the place, or of `xDeref` of the reference (`effPlace`, `referent`); `EffChain.at` reads `[i]` after a place as `xPlaceAt`. `AssignTargetR.place` reads `p.f = v;`, `p.f[i] = v;` and the like, `p` a reference parameter (`isRefTy`), as `mSetPlace` of the target read as a place and the value read at the place's type, the value not acting when the place has an element step (`hasAt`, as for an element of a slice local); `AssignTargetR.indexEval` now asks that the local not be a reference. `CompoundR.placeEval` reads `place op= v;` as `mSetPlaceOp` with `assignOpOf`'s operator (not `/=` or `%=`). A function whose reference parameter is used other than as the base of a field (`p.f` not followed by a call) or as a whole call argument is not read (`refsChecked`, `refsUsedOk`, extracted): a filter only, which no relation names (`refsChecked_some`). The lexer reads `mut` as a keyword, as laniusc does: `TokenKind.mutKeyword` (code 203, `Compiler/Tokens.lean`) and its entry in `keywordRules` (`Compiler/LexerCanonical.lean`; the front end's `lx_keyword_rules`). A reference parameter passed whole to a call is allowed by the filter but not yet read (`MatchTy` has no reference pattern; S5b). Nothing lowers a reference yet, so `compileSource` accepts no program the new readings give. It combines S5 with leafA-frame's frame and need checks (below), which did not change each other's definitions; the self program's functions moved (`frontend.lani` gained the readings), so the prim table `prims` was regenerated. The change before (11-03, leafA, merging lang `5f3bf3734` into leafA-frame, giving `22cfeaed626f1154`, SEMANTIC_DECISIONS "A function's frame block checked as it adds up" and "A function's room checked before its temporaries are counted"): only the prim table `prims` changed, regenerated because the self program's functions moved. On leafA-frame (giving `329cf49b61666582` before the merge), `compiler.lani`'s `frame_block` takes each parameter's and each let's block bytes out of `block_limit` (2^31 - 1) as they add up (`params_room` and `block_room` replace `params_array_bytes` and `SrcStmt::array_bytes`; the new `setPlace` and `setPlaceOp` take none), and a block over the limit is 2^31; `need_round` saturates each need at `need_limit` (2^40, `need_capped`, `need_round_at`), and `lower_func` rejects a function whose need reaches it; `compile_func` asks `room_fits` before it counts `locals + temps`. `frameBlock`, `funcNeeds` and `compileFunc` are not trusted (`compileSource` and `funcNeeds` are cut, section 10); `compileSource_unchecked` (`Mini/FrameRoom.lean`) shows that `compileSource` gives the old compiler's result for a program whose needs are below the limit and rejects the others, and `compileFunc_checksLast` (`Mini/Room.lean`) that the reordered checks give the same result. The change before (11-03, leafC, giving `793d1e4339a7c10d`, SEMANTIC_DECISIONS "Stage 1's order", S3): the front-pass program has reference forms that nothing accepts yet. `SrcEff` gains `eBorrow ty place` (a borrow of the place `place` names, of reference type `ty`), `eDeref ty reference` (the value `reference` points to), `eField base field` and `eAt base index` (a field or element of the place `base` names); `SrcStmt` gains `setPlace place value` and `setPlaceOp op place value` (a plain or compound assignment to the place `place` names), with the operator enum `SrcAssignOp` (`aAdd` to `aShr`, eight operators) (`Compiler/Types.lean`, extracted). The compiler gives every new form the rejecting answer (`lower`, `eval`), so `compileSource` accepts no program that has one. Their Core meaning (`SourceCore.lean`): `eBorrow ty place` is `.borrow ty.toCore (exprPlace place.toCore)`, `eDeref _ r` is `.dereference r.toCore`, `eField b f` is `.field b.toCore f`, `eAt b i` is `.index b.toCore i.toCore`, and `setPlace p v` and `setPlaceOp op p v` are the expression statements `.assign .set (exprPlace p.toCore) v.toCore` and `.assign op.toCore (exprPlace p.toCore) v.toCore`, `SrcAssignOp.toCore` naming Core's operator of the same name. `exprPlace` (an exhaustive match over Core's expressions) reads the place an expression names: a local is that local, a field or element of an expression the field or element of the place the expression names, and a dereference `*r` the place `.deref r`. Any other expression `e` gives `.deref e`. That fallback is harmless: Core's typing accepts `.deref e` only when `e` has a reference type (`PlaceHasType.deref`), and then the place is the one the reference names, a reborrow; any other such place is ill-typed and is rejected by the checker before its result is used. The front end's copy of these types (`Frontend/Types.lean`) has the same constructors, which the reading never makes. The literal pass of the reading (`Reading/Lits.lean`) leaves each new form as it is (`LitEff.borrow`, `deref`, `field` and `at`, `LitStmt.setPlace` and `setPlaceOp`), as the front end's `lit_eff` and `lit_stmt` do. The pure and cost meanings of the new forms (`peff`, `pstmt`, `qeff`, `qstmt`) are `none`, as for `eStr` (the self program has no references). The self program's functions moved (the new match arms in `compiler.lani` and `frontend.lani`), so the prim table `prims` was regenerated. The change before (11-03, f6v, merging lang `5f7f1dcd4` into f6v, giving `6db99dcc5c70f4dc`): it combines f6v's file model (stage (a), below) with leafA's front-end limits (below), which did not change each other's definitions. The change before (11-03, f6v, giving `374c7c482d5ab210`, SEMANTIC_DECISIONS "str values" point 8, stage (a)): Core's file services are Linux's system calls on a model file system, as laniusc's runtime makes them (`World.lean`). `openFile` (now `Option`: `none` is unavailable) runs the runtime's path copy (`pathCopyError`: longer than `pathLimit` = 4095 bytes is -36, a NUL byte -22), gives the empty path -2, stops (`none`) on a path that is not `simplePath` (relative, single slashes, no empty, `.` or `..` component) or when `State.lowestFree` (the lowest descriptor from 3 on that `fileHandles` does not hold, `freeFrom`) reaches `descriptorLimit` (1024), returns `parentError`'s -2 or -20 for a missing or non-directory parent (`parentPaths`, `pathComponents`), -21 for a directory opened for writing (none for reading), -2 for a missing file opened for reading, and otherwise creates or truncates as before and gives `lowestFree` (the counter `nextFileHandle` is gone). `FileHandle.append` is new: an append descriptor writes at the file's end, and a write past the end fills the gap with zeros (`writeFileBytes`). `read` and `write` (`call`): fd 0 reads the standard input and 1 and 2 write the output streams; reading 1 or 2, writing 0 and a count above `transferLimit` (`0x7ffff000`) are unavailable; `read` first checks the whole buffer (a trap, before the call); a descriptor not open or not opened for the direction returns -9 instead of -1. `close`/`close_file` return -9 instead of -1 for a descriptor not open and are unavailable for 0, 1 and 2. The open services return unavailable where `openFile` stops. `Semantics/HostCall.lean`'s read lemmas take a file descriptor (`3 ≤ handle`) and a count within `transferLimit`. The change before (11-03, leafA, giving `6f0e7f37780ae7cf`, SEMANTIC_DECISIONS "The front end's implementation limits"): only the prim table `prims` changed, regenerated because the self program's functions moved: `frontend.lani` gained the limit check (`depth_limit`, `depth_sum`, `lim_one`, `lim_slots`, `lim_param_slots` and the other `lim_` walks), which `untyped_rejected` runs on the closed functions with their string literals placed. The front end (`frontEndWords`) is not trusted; `buildClosed_sound` (`Mini/Reading/Lits.lean`) covers the new rejection, so a program it returns is still the reading's. The change before (11-03, f6v, merging lang `e51443e05` into f6v, giving `3e2d79cbfea12073`): it combines f6v's str changes (S3, S4 and S2 below) with lang's (leafB's per-function code check, leafC's references, F5 stage 1 S1 to S4, and the changes before them), which did not change each other's definitions; `src_ty` gives `Str` its `tyStr` and `Ref` none. The self program's functions moved, so the prim table `prims` was regenerated. The change before (11-03, f6v, giving `5be562f6ab9cc7a1`, SEMANTIC_DECISIONS "str values" point 7): the reading of source text reads `str` parameters and string literal arguments. `Ty.tyStr` is new (`Frontend/Types.lean`, extracted), the primitive type `str` (`primNames`, `primTys` and the extracted `primitive`), lowered to `SrcType.str` (`LowerR.str`, `TyInsts.str`, `ScalarTy.str`: no cast to `str` is read). `MEff.xStr chars` is a string literal argument: `ArgList` (nil, cons and `str`, a `StringInit` literal) reads a non-generic call's arguments, and `EffInfer.plain` uses it in place of the effect list, so no other reading reads a literal; `EffTy.str` types it `tyStr` and `EffClosed.str` closes it to `SrcEff.eStr 0 chars`. `ClosedProgram` now ends `p = placedProgram gs`: `placedProgram` (extracted with `placeFuncs`, `placeStmt`, `placeEff`, `placeEffs`, `funcsBytes`, `stmtBytes`, `effBytes`, `effsBytes` and `strBytes`) gives each literal the offset of the literal bytes before it and the program the statics of all of them; `toCore` reads neither. `hostId` names `write_text` and `write_newline` the host ids `2^32 + 8` and `2^32 + 9` (`textWriteText`, `textWriteNewline`). The self program's functions moved (`frontend.lani` gained the reading and the placement pass), so the prim table `prims` was regenerated. The change before (11-03, f6v, giving `515b4e769e2308d2`, SEMANTIC_DECISIONS "str values" points 5 and 6): the mini `write` system call may write bytes of the static region. `Heap.span heap a c` (`Mini/Semantics.lean`, new) is the `c` bytes at `a`: frame memory's `slice a c` when `a + c` is at most the heap's `top`, otherwise the static bytes from `a - staticBase`. `Syscall.run`'s write (fd 1 or 2, at most `maxTransfer` bytes) now runs when the range is below `top` or, with the region at or above `top`, lies wholly inside the static region, and appends `write fd (span a c)` to the trace; every other range stops as before. A range below `top` writes the same bytes as before. No trusted statement changed: the verified compiler now lowers `write_text` and `write_newline` (host ids `2^32 + 8` and `2^32 + 9`, `eval_host_text`), proved against Core's `writeText` and `writeNewline` as they stood. The self program's functions moved (`compiler.lani` gained `eval_host_text` and the two lowering arms), so the prim table `prims` was regenerated. The change before (11-03, leafB merging lang (leafC's S1-S3), giving `f4b274867e23528a`): it combines leafB's per-function code check (giving `c6e25c9ba4f62ae4` on leafB) with leafC's S1, S2 and S3 (giving `07a55955abaf2624` on lang), which changed none of each other's definitions beside the prim table `prims`, regenerated from the merged self program. leafB's change (11-03, leafB, giving `c6e25c9ba4f62ae4`, SEMANTIC_DECISIONS "A function's code checked against the image limit first"): `compileFunc` also asks `roomFits (stmtRoom imageLimit func.body)`. The new `spend`, `exprRoom`, `argsRoom`, `stmtRoom` and `roomFits` (`Compiler/P/compileArgs.lean` and `Compiler/P/roomFits.lean`, extracted) take one out of the room for each node of the body, and a call one more for each result; `imageLimit` moved to `Compiler/P/compileArgs.lean` and `linkedSize`, `roomAfter` and `compileProgram` to `Compiler/P/linkedSize.lean`. `stmtRoom_eq`, `weight_le_codeSize`, `codeSize_le` and `compileProgram_unchecked` (`Mini/Room.lean`) show that `compileProgram` accepts the same programs with the same binary as without the check. The self program's functions moved (`compiler.lani` gained the room functions), so the prim table `prims` was regenerated. leafC's change (11-03, leafC, giving `07a55955abaf2624`, SEMANTIC_DECISIONS "Stage 1's order", S3): Core's typing has a rule for the place a reference names, `PlaceHasType.deref` (`Typing.lean`): `.deref r` has type `T` when `r` has type `.reference T`, as `ExprHasType.dereference` types the read. The checker's `checkPlaceAnyFuel` (`Typing/Check/Expressions.lean`, not trusted) has the case, which returns the rule's proof, so it stays sound by construction. Like `ValueHasType.reference`, the rule does not say the cell at the path holds a `T` (no store typing yet). The change before (11-03, leafC, giving `22827062f6a3c346`, SEMANTIC_DECISIONS "Stage 1's order", S2): `SrcType.HoldsAt` gains `ref`: a reference to a `referent` is held by its one slot `w` when `RefHeld places referent v w`, that is, `v` is Core's `.reference referent.toCore cell path` and `RefTo places referent cell path w`: some place of `places` has cell `cell`, and `w` is the lowest byte of its sub-place at `path` (`Addressed.sub`), of type `referent`. This makes the layout definitions it reaches trusted; they moved from `Refs/Model.lean` to the new `Mini/Layout.lean` with their names: `Access` with `bytes` and `narrow`, `SrcType.accessKind` and `packed`, `SrcType.words` with `fieldWords` and `variantWords` (a value's native words, SEMANTIC_DECISIONS "References: the memory model" point 4), `SrcType.subStep` and `SrcType.sub` (the byte offset and type of a field or element: a struct's field below the words of the fields before it, a packed array's element `i` widths up, another array's element `i + 1` elements below the top), `Addressed.sub`, `RefTo` and `RefHeld`. `Addressed` moved there from `Source.lean` unchanged, and `Addressed.pointer` (a lent place's slice pointer) is now the native top word `address + 8 * (ty.words - 1)` for types other than `i32` and `u8` arrays, which keep `address`; only those two are lent, so `HoldsAt.borrowed` means what it did. The top theorems pass `places = []`, where no reference is held. The change before (11-03, leafC, giving `c8747dc3573ef186`, SEMANTIC_DECISIONS "Stage 1's order", S1): the front-pass program has a reference type that nothing accepts yet. `SrcType.ref referent` (`Ref(Box<SrcType>)`, `Compiler/Types.lean`, extracted) is one slot (`size`); no type with a reference is declared (`declare` is `none`), it is the same as no type (`same` is false), and every other case of the compiler gives it the rejecting answer, so `compileSource` accepts no program that has one. Its Core meaning (`SourceCore.lean`): `toCore` is Core's `.reference referent.toCore`, and `typeId`, `literal`, `toScalar` and `sliceFrom` give it their defaults; `SrcType.Holds` is `False` at it (`Source.lean`), and `SrcType.HoldsAt` has no case for it yet (S2 adds `HoldsAt.ref`). The front end's copy of `SrcType` (`Frontend/Types.lean`) has the same constructor, which the reading never makes. The self program's functions moved (the new match arms), so the prim table `prims` was regenerated. The change before (11-03, leafB, giving `d75635f4ee0dd1d2`, SEMANTIC_DECISIONS "The image limit checked as the sizes add up"): `compileProgram` checks the image limit as the functions' sizes add up. The new `roomAfter room codes` (`Compiler/P/imageLimit.lean`, extracted) takes each function's size out of the room and is `none` as soon as one does not fit. `compileProgram` checks that the statics fit, then the functions through `roomAfter`, before it lays them out. `roomAfter_eq` and `compileProgram_eq` (`Mini/Correct.lean`) show that it accepts the same programs with the same binary as before. The self program's functions moved (`compiler.lani` gained `room_after`, `room_next` and `link_fitting`), so the prim table `prims` was regenerated. The change before (11-03, f6v, giving `9c1a21481238db7d`, SEMANTIC_DECISIONS "str values"): the front-pass program has str values. `SrcType.str` and `SrcEff.eStr offset chars` (a string literal, its bytes at `offset` of the program's statics) are extracted (`Compiler/Types.lean`), and `SrcProgram` and `SrcDecls` carry the static bytes (`statics`; `SrcProgram.decls` of a rejected program keeps the program's). Their Core meaning (`SourceCore.lean`): `str` is Core's `string` scalar (`toCore`, `toScalar`; `typeId`, `literal` and `sliceFrom` give it the defaults), and `eStr _ chars` is the value `.string (strValue chars)`. `hostService?` names the host ids `2^32 + 8` and `2^32 + 9` `writeText` and `writeNewline` (the verified compiler lowers no call of them yet). `Statics` (a region's mini base and bytes) and `Heap.StaticsAt hp sx` (the heap's `staticBase` and `statics` are `sx`'s, the region is at or above the heap's top when it holds bytes, and it ends below `2^64`) are new (`Source.lean`); `SrcType.HoldsAt` and `FieldsHold` take the region `sx`, and `HoldsAt.str` says a str's two slots are the mini address `sx.base + k` and the byte count, below `2^31`, with the region's bytes from `k` on the string's UTF-8 bytes. Core's `writeText` (`World.lean`, `callSimple` and `call`) returns the number of bytes written instead of 0, as laniusc's `std::io::write_text` does (`write_line` adds the counts). The pure and cost meanings of `eStr` (`peff`, `qeff`) are `none` (the self program has no str values). The self program's functions moved (`compiler.lani` gained `eval_str`, `str_placed`, `static_byte_is`), so the prim table `prims` was regenerated. The change before (11-02, f6v, merging lang into f6v, giving `8e49c84069f2b7bf`): `TypedSlicePath` states the path's segments as the list `[textCore, textMem, textTypedSliceFromRawParts]` (the definition `typedSliceSpellings` is gone: the reading compares the segments one by one, `isTypedSliceSegments`), and `textTypedSliceFromRawParts` is `typed_` consed onto `textSliceFromRawParts` (the same text; one 26-element literal was too slow for F14's height lemmas). The prim table `prims` was regenerated. The change before (11-02, f6v, giving `85851955686d2177`, SEMANTIC_DECISIONS "Addressed locals" point 6, stage (c)): the reading of source text reads `let x: str = "chars";` directly followed by `return core::mem::typed_slice_from_raw_parts(core::mem::string_data_ptr(x), n);` (or `typed_slice_from_raw_parts<u8>`), the last statement of its block, in a function returning `[u8]`, as one string literal's pointer and its raw view. `StmtsR.letStr` (`Reading/Stmts.lean`) reads the two statements as `MStmt.mLetStr x chars (.mLetSlice r u8 (.local x) n (.mReturn (.local r))))`, x numbered by the str local's token and r by the value's first token (as `ReturnR.slice` numbers it); `StmtClosed.letStr` (`Reading/Close.lean`) closes `mLetStr` to `SrcStmt.letStr`. Its parts: `StrType` (the type is the bare path `str`), `StringInit` and `StringLiteral` (the initializer is a string literal whose bytes between the quotes are each `PlainStringByte`, printable ASCII other than the quote and the backslash, so no escape is read and laniusc's literal is these bytes), and `StringReturnR` with `TypedSlicePath` (the path `core::mem::typed_slice_from_raw_parts` with no type argument or the one `u8`), `DataPtrOf` (`core::mem::string_data_ptr(x)`, `stringDataPtrPath`), `TreeNames` (the argument is the bare name x) and an integer literal n (`IntLiteral`). The stdlib function is `assert(length >= 0); return slice_from_raw_parts(data, length);`, and a literal is never negative, so its call is read as the raw view itself; the reading takes `core::mem` to be the stdlib's. The grammar's production `pString` (177) is named. `MStmt` gains `mLetStr` (`Frontend/Types.lean`, extracted). The self program's functions moved (`frontend.lani` gained the string reading), so the prim table `prims` was regenerated. The change before (11-02, f6v, giving `a2b318bf5c30f9cb`, SEMANTIC_DECISIONS "Addressed locals" point 6, stage (b)): the front-pass program has a string literal's pointer, `SrcStmt.letStr pointer chars body` (`Compiler/Types.lean`, extracted), `chars` the string's Unicode scalar values. Its Core meaning (`SourceCore.lean`) is `let pointer: rawPtr = string_data_ptr("chars"); body` (`letLocal` of `stringDataPtr` of the string value), the string being `strValue chars`, the string of the characters `Char.ofNat` of each value. The literal pass of the reading (`Reading/Lits.lean`) gains `LitStmt.letStr`, which reads the body with the pointer's local in scope, as `letView` does. The self program's functions moved (`compiler.lani` gained `lower_str` and its helpers), so the prim table `prims` was regenerated. The change before (11-02, f6v, giving `64acd215bab52adb`, SEMANTIC_DECISIONS "Addressed locals" point 6, stage (a)): the mini language gets a read-only static region. `Heap` gains `staticBase` and `statics` (the region's heap offset and its bytes). The mini program carries the bytes (`Program.statics`, extracted) and the binary puts them after the code in its image (`Binary.statics`, `link`, `linkOnto`'s tail). `Stmt.static target offset` sets `target` to `staticBase + offset` (`Exec.static`), and a `loadByte` at `staticBase + k`, for `k` below the region's length and the region at or above the heap's top, reads byte `k` (`Exec.loadByteStatic`); no statement writes the region. The machine (`Mini/Asm.lean`) has `Instr.static` and the `loadAt` of a static byte (`Step.loadAtStatic`), and its call step asks that the callee leave the region as it was (`Step.call`; a mini callee does, `Exec.statics`). On x86 `Instr.static offset` is `lea rax, [r8 + offset]; sub rax, r12` (10 bytes), and `HeapAt` gains `static` (r8 is r12 plus `staticBase`) and `statics` (each static byte is in memory at r12 plus its offset, apart from the stack window and the heap). The startup code sets r8 to the address of the image's static bytes, after its code (`mov r8, imm64`: the startup is 95 bytes and the image starts at `elfBase + 215`). The self program's functions moved (`compiler.lani` gained `static_agrees`), so the prim table `prims` was regenerated. The change before (11-02, f6v, giving `cbbfa2c060f54f28`, SEMANTIC_DECISIONS "Addressed locals" point 5, stage (d)): the reading of source text reads `let a: [i32; n] = [..]; let p: ptr = core::mem::i32_array_data_ptr(a);` as one viewed array. `core::mem::i32_array_data_ptr` is a reserved path (`textMem`, `textI32ArrayDataPtr`, `viewPath`, a seventh entry of `builtinPaths`), read by `CallPathHeadR.view` as the let head `LetHead.viewOf x` (one argument), which `letStmt` and `sliceReturned` give no statement of their own. `StmtsR.letView` reads the two lets, the first typed `[i32; n]` with a literal of `n` elements and the second, directly after it, typed `ptr`, fresh, not a global, with head `viewOf` of the first's local, as `MStmt.mLetView a n elements p body`, its body read in a scope with both locals; `StmtClosed.letView` closes it to `SrcStmt.letView`, and `stmt_tys` counts the array's type. The self program's functions moved, so the prim table `prims` was regenerated. The change before (11-02, f6v, giving `e8d6d7939ebcedcf`, SEMANTIC_DECISIONS "Addressed locals" point 5): the front-pass program has a viewed array, `SrcType.view length` and `SrcStmt.letView id length elements pointer body` (`Compiler/Types.lean`, extracted). Its Core meaning (`SourceCore.lean`): `letView` is `let id: [i32; length] = [elements]; let pointer: rawPtr = i32_array_data_ptr(id); body` (`letLocal` twice), and `view n` is the Core type `[i32; n]` in `SrcType.toCore`, `literal` and the slice of raw parts (the other type functions give it their default). `SrcType.HoldsAt` gains `view`: Core's cell holds `length` in-range i32s, and the slots hold nothing that matters (the truth is the view's heap block, `Views.ViewsHold`). The pure and cost meanings of `letView` (`mstmt`, `pstmt`, `qstmt`, `Faithful/Pure.lean`, `Faithful/Cost.lean`) are `none`, as for `letAlloc`: the self program uses no views. The change before (11-02, f6v, giving `a593873d90485ed8`): `State.Fresh` no longer asks that Core have no i32 array views; it asks that every view hold its cell (`Views.ViewsHold`: the view has no projections, its root cell holds an array of as many i32s as the view is long, and the view's address is the base of a live, borrowed heap block whose bytes encode those elements, which nothing overlaps (`Views.Owns`) and which ends below the cursor (`Views.Before`); no two views share a root), so Core's syncs change nothing. `Views.Before`, `Views.IsI32`, `Views.Owns`, `Views.ViewHolds` and `Views.ViewsHold` (`Mini/Views.lean`) are trusted. This weakens a premise of `compileSource_correct_from`: a state with no views still satisfies it (`ViewsHold.nil`). The change before (11-02, merge of f11b `7eb93b7916d84bb4` and its step D into lang `70d594d3ee80699d`, giving `f991f205862cd76e`): it combines F11b's changes with lang's, which did not change each other's definitions, beside the prim table `prims`, regenerated from the merged self program. Step D (9af4023ad) adds `while`, `break` and `continue` to the pure fragment: `mstmt`, `ploop`, `Out` with `Out.then`, `Out.pop` and `outValue` (`Faithful/Pure.lean`), and the cost semantics' `qstmt` with `qloop` (`Faithful/Cost.lean`), are trusted; lang's F14 cost statements (`qcallG`, `qcallB`, the budget certificates) now run statements with `qstmt`'s loop fuel and end calls with `outValue`. F11b's (11-01, the
front end's reading of int bases, literal patterns, `for` and `slice_len`):
Core has the intrinsic `slice_len` (`Intrinsic.sliceLength`,
`sliceLength?`, its `evalExpr` case and `ExprHasType.sliceLength`;
SEMANTIC_DECISIONS "Slice length"), and raw nominal slices take `u32`,
`u64`, `i64` and `bool` elements (`RawNominalSliceElement`,
`mapRawNominalSlice`, `rawSliceElementAddress?`, `NativeLayout.words?` and
`elementStride?`). The reading of source text reads based int literals
(`basedDigits`, `intLiteral`, `Reading.intValue`), literal patterns in
`match` (`LitMatch`, `LitMatchR`, `litChain` and their helpers), `for` over
arrays and slices (`forArray`, `forSlice`, `StmtR.forArray`,
`StmtR.forSlice`) and `if`, `let` and `slice_len` inside effects
(`SrcEff.eIf`, `eLet`, `eLen`, `MEff.xIf`, `xLet`, `xLen`, and the cases
of the functions over them); the float literal pieces were restated with
the shared digit reader. The pure fragment's statements return an `Out`
(next, break, continue or return) through `mstmt`, which replaces `Done`
and `pstmt` and adds local assignment (`Env.set`), and `prims` names the
self program's functions at their new indices. The hash before it was
`8884c49974b65a57`. Before that (11-01, step 3.5a of array-to-slice arguments): lang's (11-02, merge of front-fixes `d76509417115a874` into lang `339ca6217ec1aa8b`, giving `70d594d3ee80699d`): it combines step 3.5b's verified compiler changes with review-fixes' F14 changes, which did not change each other's definitions, beside the prim table `prims`, regenerated from the merged self program. Step 3.5b (11-01 of array-to-slice arguments):
the verified compiler lowers a `LetEval` or `Discard` value through
`stmt_eval` and checks an array call's result and block
(`array_call_code`), which adds functions to the self program and moves
the indices in the prim table `prims`; `ixTimes` stays 105. No other
definition changed. The top theorems' frame-room premise grew
`fsp ≤ top ∧ top < 2 ^ 62` (section 8, "Frame room"), which changes their
statement hashes but no definition. The hash before it was
`8884c49974b65a57`. Before that, review-fixes (11-01, merge of lang `8884c49974b65a57` into
review-fixes `5aa62e3705d251c9`): it combines lang's frame-room steps and
review-fixes' F14 changes, which did not change each other's definitions,
beside the prim table `prims` (`Faithful/Gen/SelfPureTab.lean`) and `ixTimes`,
regenerated from the merged front end. Before that (11-01, merge of lang
`30cfc8a1287e8470` into review-fixes `a3b90bcb2fad7cd0`, giving
`5aa62e3705d251c9`): lang's array-to-slice steps and review-fixes' F14
changes, beside `prims`. review-fixes' (11-01, F14):
`CompileBounded` takes its cost threshold `T` as a parameter in place of
`2 ^ 62`, and `SelfShortW`'s third reason says the wrapped compile costs
more than the heap limit, in place of at least `2 ^ 62`; the hash before was
`e5a4ad804bd2998c`. That one: the
conditional top theorem `selfCompiler_total_reason_of_bounds` brings in 11
new constants and changes none: `SelfFaultReasonW`, `SelfShortW`,
`CompileBounded`, `costW` and `compileG` (`Faithful/SelfTotal.lean`),
`safeW` and `NoWrap` (`Faithful/SelfAgree.lean`), and `pcallG` with its
three auxiliary definitions (`Faithful/Sim/Agree.lean`). The hash before it
was `feb6c15367fe3046`. That one (11-01, F14's type
weights, SEMANTIC_DECISIONS "Type weights"): only the prim table `prims`
(`Faithful/Gen/SelfPureTab.lean`) changed, because the front end's new
weight functions shift the indices of the self program's later
`boxed` and `unbox` instances. The weight functions themselves (`srcWeight`,
`typesWeighed`, ...) are the front end's, not trusted. The hash before it was `a784f30fce5c9322`. lang's (11-01, step 3.5a of array-to-slice arguments):
the top theorems on `compileSource`, `compileText` and processes take the
frame room their function needs (section 8, "Frame room"), which brings in
`SrcProgram.need` (`Mini/LowerStmt.lean`, new), whose `funcNeeds` is cut
(section 10). The verified compiler's need computation and prologue
(`frame_block`, `func_needs`, `with_frame`) add and drop functions of the
self program, so `prims` and `ixTimes` (106 to 105) name the same functions
at their new indices again. No other definition changed. The hash before it
was `6d0c833ce4ab9a8d`. Before that (11-01, the frame-memory
budget of array-to-slice arguments, before step 3.5): the verified
compiler's signatures carry a need, a room and a block (`Sig`,
`with_budget`, `frame_block`), which adds functions to the self program, so
the generated tables that name its functions by index moved: the prim
table `prims` (`Faithful/Gen/SelfPureTab.lean`) and `ixTimes`
(`Faithful/Gen/SelfLiveTab.lean`, 105 to 106) name the same functions at
their new indices. No other definition changed, and no statement's meaning
did. The hash before it was `d230774a2b033659`.
Before that (11-01, steps 3.3 and 3.4 of
array-to-slice arguments): `SrcType.HoldsAt` has a constructor `borrowed`,
a slice of a caller's array in `places` (marked `sliced`, a whole array of
`i32` or `u8` elements), the slot holding `Addressed.pointer` (new, with its
match and case helpers) and the next slot its length, and Core's value the
safe slice `.slice element cell [] 0 length` of the array's cell. Core's
`rawSliceStride?` answers for a safe slice with its element's native stride,
as it does for a raw slice (SEMANTIC_DECISIONS, "Addressed locals"). The
top theorems pass `places := []`, where `borrowed` cannot hold, so their
statements mean what they did. The hash before it was `30cfc8a1287e8470`.
Before that (11-01, step 3.3 of array-to-slice arguments): `Addressed` (`Mini/Source.lean`) has a field
`sliced`, which marks an array passed as a slice, laid out as a slice's
elements in frame memory; no constructor of `SrcType.HoldsAt` reads it yet.
The hash before it was `c1629d03f01a2c36`. Before that (11-01, merge of lang
into rfront's step 3.1 of array-to-slice arguments, lang `6415d962ec6a970a`
and step 3.1 `779c1a8a7e04e0c6`, which did not change each other's
definitions): `SrcType.HoldsAt` and `FieldsHold` take a list
`places : List Addressed` (`Mini/Source.lean`) of the caller's arrays held in
memory, each a cell, its type and its frame address (two new constants,
`Addressed` and its constructor). It is a uniform parameter that no
constructor reads yet, and the top theorems pass `[]`, so their statements
mean what they did; their statement hashes changed with the extra argument.
Before that (lang, 11-01, F11b, merged
with the review-fixes restatement and rfront's `u16` views,
`a784f30fce5c9322`): an array local passed at a `[T]` parameter is
`SrcEff.arraySlice T x`, whose meaning is Core's `arrayToSlice T (local x)`
(`SrcEff.toCore`), read by `argView`/`argViews` in `EffInfer.plain`,
`EffNamed.explicit` and `EffArgs.arg` (`MEff.xArraySlice`,
`EffTy.arraySlice`, `EffClosed.arraySlice`, `LitEff.arraySlice`); the
compiler does not lower it yet; and the reading of a method call with type
arguments `x.m<T, ..>(..)`: `MethodBinds` binds m's own type parameters to
the written types after the receiver's binds, used by `EffR.method`,
`EffChain.method` and `MethodEff`, and `MethodForm` and `TryMethodForm`
allow the type arguments (section 4). Before that (11-01, merge of
review-fixes into lang): it combines lang's `u16` views
(`b8d2e28d6f544c42`) and review-fixes' restatement of review finding 5's
first reason (`adcfd7afcaf25cbd`), which did not change each other's
definitions. The restatement: `SelfShort`'s first reason is
`SelfPanics W` (`Faithful/SelfPanics.lean`): no cost at any fuel, and with
the prelude's `plus` and `times` wrapping the pure compile has a value
(`compileW`, through `pcall` of `progW`, which is `prog` with those two
functions' bodies replaced by `wrapAt` and `wrapFunc`,
`Faithful/Sim/Wrap.lean`, at `ixPlus` and `ixTimes`,
`Faithful/Gen/SelfLiveTab.lean`). The `u16` views (11-01, merge of
rfront's `u16` views into lang): Core's `u16` views (SEMANTIC_DECISIONS
"`u16` views"): a raw slice of `u16` is a word view in laniusc's layout, one
descending 8-byte word per element (`rawSliceElementAddress?` and
`mapRawNominalSlice` take it as they take a struct or enum,
`NativeLayout.elementStride?` is -8 and `words?` of a `[u16]` is 3), and
`RawNominalSliceElement.word16` types it; the hash before it was
`da057f9f0d2562a7` (Reviewer A's change kept it). Before that (11-01, review finding
5 piece (c)): the new top theorems `selfCompiler_reason`,
`selfHost_fixpoint_reason` and `selfHost_outcome_reason` bring in
`SelfFaultReason` and `SelfShort` (`Faithful/SelfShort.lean`), `selfCost`,
`consCost` and `listVal` (`Faithful/SelfLive.lean`), and through them the
cost semantics `qcall` (`Faithful/Cost.lean`), the pure semantics it
shares with `pcall` (`Faithful/Pure.lean`), `boxCost`
(`Faithful/Fwd/Prim.lean`) and the prim table `prims`
(`Faithful/Gen/SelfPureTab.lean`); no existing definition changed; merged with F12's module conversion,
which changes no definition's meaning. Before that (11-01, F12): Core's
semantics, the x86 model, the memory model and the self program's
simulation became Lean `module`s, so their auxiliary definitions (matchers,
`_proof_N`) are named per module: the same constants, with 18 hashes that
differ only in the names of the auxiliaries they mention; no definition's
meaning changed. Before that (11-01): the lexer
(`Lanius/Compiler/Lexer*.lean`, `Tokens.lean`) and the reading became Lean
`module`s, so a function's matcher is its own (`OneTokenResult.shift.match_1`)
rather than shared with a derived `Repr` instance's; no definition's meaning
changed (this hash is that change on top of the ones below). Before that
(10-31, merge of rfront's byte views with F11b's reading changes; neither changed the other's definitions): Core's byte
views (SEMANTIC_DECISIONS "Byte views"): a raw slice of `u8` is one byte
per element at `pointer + i` (`isByte`, `rawSliceElementAddress?`,
`NativeLayout.elementStride?` and `words?`), `mapRawNominalSlice` checks its
bytes, a read loads one byte (`readRawElement`) and a write stores one
(`storeRawByte`, `writeRawNative`, chosen by `ResolvedPlace.rawByte`), and
`RawNominalSliceElement.byte` types it. Before that (10-31, F11b):
`amountWant` reads a bare shift amount at `i32`, as laniusc does, not at
the shifted value's type (section 4). Before that (10-31, F11b): `picks`
allows a method's type arguments `.f<...>` where `generic_open` holds
(section 4, "One reading"). Before that (10-31, F11b): the
reading of patterns: a payload name spelled like a variant is never a
binder (`BindersR`'s `NoVariant`), match statements and lets' matches read
nested arms (`StmtOrder`, `NestedRows`, `ArmsStmtR.inner`,
`LetArmsR.inner`, `LetArmsR.value`'s bare-match condition), and a plain
arm before a nested one for the same variant is that variant's arm
(`VariantArm.shadow`); `MatchArmsOrder` is gone. Before that (10-31): the
self-host theorems state the reason for a fault (`SelfFaults`, `selfRun`,
review finding 5), `compileSource_behaviour_rawFree` brings in `RawFree`,
and the front end's review fixes changed the reading. `trusted_check.py` writes each constant's own hash to
its work directory's `definitions.txt`, to find which one changed.

### Processes (`Lanius/Mini/Process.lean`)

#### `Lanius.Mini.process_exits`

statement `00000000ca619f9e`. If `compileSource sp = some binary`,
`elfFile binary entry stack heap = some file`, and function `entry` of `sp`
has no parameters and needs at most `stack` bytes of frame memory
(`sp.need entry ≤ stack`, section 8, "Frame room"): whenever Core runs
`entry()` from `startState given` to
a value `v` with the heap ending within `heap` bytes, then Core's final
standard output and error are what a write trace puts on fds 1 and 2
(`outputOf`), and from every state Linux may leave for `file` (`Loaded`)
whose streams are `given` (standard input, the clocks' readings, the
secure bytes and the read limits, `s.io = given`), either some run reaches `exit`
(`Exits`) with that trace and the last of `v`'s slots as the status, every
run of that length agreeing but for flags (`Det`), or the stack is too
small for the call's depth and the process faults. The result slots hold `v`
with the process's static region (`elfStatics binary stack`: the binary's
static bytes after its code in the image, below the heap's base). Rests on
sections 3, 6, 7 and 8 (Linux: `Loaded`, `Exits`, the kernel calls).

#### `Lanius.Mini.process_behaviour`

statement `00000000a1f74da3`. Same premises, for any run from a `Loaded`
state to a state with no step that is not a fault: Core's run of `entry()`
finishes within the heap and the run is at `exit` with the last result
slot, or Core's run reaches an undefined trap (`undefinedTrap`) within the
heap. Rests on the same sections.

#### `Lanius.Mini.textProcess_exits`

statement `00000000006822ab`. `process_exits` from source text: if
`compileText files = some binary` and `elfFile` gives `file`, the files'
texts have a reading `sp` (`TextReading`, section 4), the only one, and
`process_exits`'s conclusion holds of `sp`. Adds section 4.

#### `Lanius.Mini.textProcess_behaviour`

statement `0000000062e7f29e`. `process_behaviour` from source text, as
`textProcess_exits` is `process_exits`.

### Source text (`Lanius/Mini/TextCorrect.lean`)

#### `Lanius.Mini.compileText_correct`

statement `000000000f320c4d`. If `compileText files = some binary`, the
files' texts have exactly one reading `sp`, and `compileSource_correct`'s
conclusion holds of `sp` and `binary`, from the start state of the mini
heap's streams (standard input, the clocks' readings, the secure bytes; the
read limits are any), for a static region holding the reading's static
bytes. Rests on sections 3, 4, 6 and 8.

#### `Lanius.Mini.compileText_behaviour`

statement `00000000901618e1`. If `compileText files = some binary`, the
texts have one reading `sp`, and `compileSource_behaviour`'s conclusion
holds of it.

#### `Lanius.Mini.textReading_unique`

statement `00000000d7c363fc`. Two readings of the same texts are equal.
Rests on section 4 only.

### Source programs (`Lanius/Mini/SourceCorrect.lean`, `SourceStops.lean`, `Determinism.lean`, `TypeSound.lean`)

#### `Lanius.Mini.compileSource_correct`

statement `000000009e264115`. If `compileSource sp = some binary`, `f` is a
function of `sp`, and `args` are values of its parameter types held in
slots `bits` (`FieldsHold`), the mini heap's static region `sx` holds the
program's static bytes (`heap.StaticsAt sx`, `sx.bytes = sp.decls.statics`;
str values are read against `sx`), and Core runs `f(args)` from the start state
(`startState` of the heap's streams: standard input, the clocks' readings
and the secure bytes; the heap's read limits are any) to `v` with the heap ending within the limit: there are a
depth and result slots representing `v` (`HoldsAt`), with Core's final
standard output and error those of the mini heap's trace, such that from
every x86 state meeting the caller's obligations, with a stack window of at
least `binary.stackNeed depth` (and at most 2^62), a fresh heap (cursor 1,
zero bytes, limit below 2^62, an empty trace) with the frame memory `f`
needs (section 8, "Frame room"), some run returns those slots
(`Returned`), and every run of that length agrees with it but for flags.
Rests on sections 3, 6 and 8.

#### `Lanius.Mini.compileSource_correct_from`

statement `00000000217bb1c2`. The same from any Core state `st` with no
live cells (`State.Fresh`, which also asks that every i32 array view hold its
cell) whose heap and world the mini heap represents
(`HeapCorr`); the final heap and world are again represented.

#### `Lanius.Mini.compileSource_stops`

statement `000000007d45a3a2`. Same premises on the compiler and the
arguments, a fresh heap of limit at least 1 with the frame memory `f`
needs, and the caller's obligations (any window up to 2^62): if every fuel of Core's run of `f(args)` fails
(`Failing`: runs out, traps with a defined trap, or ends past the heap
limit), then every run of the code that stops, stops at a fault (`Faults`).

#### `Lanius.Mini.compileSource_behaviour`

statement `00000000e4da78be`. Same premises: a run to a state with no step
that is not a fault comes from a Core run of `f(args)` that finished within
the heap limit, or reached an undefined trap within it.

#### `Lanius.Mini.compileSource_behaviour_rawFree`

statement `00000000ca0b8475`. `compileSource_behaviour` for a program without raw
memory (`RawFree`: no `alloc`, `load_byte`, `store_byte`, `dealloc`, raw
slices or `slice_stride`), from a fresh heap: the undefined trap its second
case allows is not `typeMismatch` (`Lanius/Mini/ShapeSource.lean`).

#### `Lanius.Mini.compileSource_deterministic`

statement `00000000e21cfd67`. `compileSource_correct` (without the output
conjuncts) with: every run of the same length ends `DataEq` to the
returning one (registers, `rip` and memory equal; section 7).

#### `Lanius.Mini.compileSource_wellTyped`

statement `000000001f1f2c4c`. If `compileSource sp = some binary`, then
`sp.toCore` is well typed (`Typing.ProgramWellTyped`, Core's type system).
Rests on section 3.

### Mini IR programs (`Lanius/Mini/Correct.lean`, `StopsCorrect.lean`, `Validate.lean`, `Determinism.lean`)

#### `Lanius.Mini.compileProgram_correct`

statement `00000000bbd77b6e`. If `compileProgram prog = some binary` and
the mini big-step semantics returns `value` and heap `after` for `f(args)`
at a depth (`Program.Returns`), then from every state meeting the caller's
obligations with a window of at least `binary.stackNeed depth`, some run
returns `value` (`Returned`), deterministically (`Det`). Rests on the mini
semantics (section 2), sections 6 and 8.

#### `Lanius.Mini.compileProgram_stops`

statement `0000000047f291ee`. If for every `n` the mini run of `f(args)` is
still running after `n` ticks or stopped at a checked fault
(`Program.Stops`), every run of the code that stops, stops at a fault.

#### `Lanius.Mini.compileOptimized_correct`

statement `000000007e57d6d7`. `compileProgram_correct` for
`compileOptimized`, whose optimizer's output is kept only when the
validator accepts it.

#### `Lanius.Mini.compileProgram_deterministic`

statement `0000000041d7b047`. `compileProgram_correct` with every run of
the same length `DataEq` to the returning one.

### Linking (`Lanius/Mini/Link.lean`)

#### `Lanius.Mini.link_eq`

statement `000000007181c690`. Compiling modules one at a time and linking
the objects (`compileModules`, `linkObjects`) gives the executable part
(`Binary.executable`) of compiling the linked program
(`linkProgram`, `compileProgram`).

#### `Lanius.Mini.linked_correct`

statement `00000000960e6c54`. `compileProgram_correct` for an executable
from `compileModules` and `linkObjects`, with the program `linkProgram ms`.

#### `Lanius.Mini.linked_deterministic`

statement `00000000a7365b5d`. `linked_correct` with every run of the same
length `DataEq` to the returning one.

### The self program (`Lanius/Faithful/SelfDriver.lean`, `SafeDriver.lean`)

`prog` is the self program, `Lanius.Faithful.Self.prog`: the front end's
reading of the driver and the verified compiler's sources (section 5).
Function 0 is the driver `w(input, words, output, room)`.

#### `Lanius.Faithful.SelfDriver.driver_faithful`

statement `00000000cc70d93c`. If Core runs `w` from a state satisfying the
invariant `Inv` (no live `i32` array views, block bases unique), with an
input view reading words `W` (`Reads`), fewer than 2^31 of them and of
output room, `room * 4` readable bytes at the output, and ends within 2^64
bytes of heap: it returns -1 when `compileWords (frontEndWords grammar W)`
is `none`, and otherwise the result's length, with the output view reading
the result (`Result`). Rests on section 3.

#### `Lanius.Faithful.SelfDriver.driver_files`

statement `00000000faae0dee`. `driver_faithful` for the words of source
files (`filesWords`, each file's bytes, productions and parents, within
`FilesFit`'s bounds): the result is `binaryWords (compileText files)`.
Rests on sections 3 and 4 (`compileText`'s meaning, through
`compileText_correct`).

#### `Lanius.Faithful.SelfDriver.driver_safe`

statement `00000000370c8fc9`. Under `driver_faithful`'s premises on the
state and views, with the input and output ranges checked in Core's heap,
Core's run of `w` never reaches an undefined trap, at any fuel (`SafeE`).

### The self-built verified compiler (`Lanius/Faithful/SelfCompiler.lean`, `SelfHost.lean`, `SelfShort.lean`, `SelfPanics.lean`, `SelfTotal.lean`)

#### `Lanius.Faithful.SelfCompiler.selfCompiler_outcome`

statement `00000000c90eab02`. If `compileSource prog = some B` (section 5):
for files within `FilesFit`, fewer than 2^31 words and output room, a heap
laid out as `selfHeap` (the words, then the output room, then the bump
heap up to a limit at least `selfNext` and below 2^62), argument slots
`selfBits`, and the caller's obligations for `B` with entry 0, the run
faults (`SelfFaults`: only when Core's run of `w` fails at every fuel, or
completes within the limit with the stack window below `B.stackNeed`), or
some run returns, deterministically, with rax's low 32 bits -1
when `compileText files` is `none` and otherwise the number of words of its
binary, which are in the output view (`SelfOutput`). Rests on sections 3,
4, 5, 6 and 8.

#### `Lanius.Faithful.SelfHost.selfHost_fixpoint`

statement `0000000089161915`. For source files `self` that the front end
reads as `prog` (`read : sourceProgramFiles self = some prog`) and `B` with
`compileText self = some B` (`compiled`), both computed (section 5): `prog`
is the files' one reading (`TextReading`), and `B`'s code for `w`, entered
as in `selfCompiler_outcome` with the words of `self`, faults as
`SelfFaults` allows or returns `B`'s own words: the verified compiler compiles its own text to itself.
Rests on sections 3, 4, 5, 6 and 8.

#### `Lanius.Faithful.SelfHost.selfHost_outcome`

statement `00000000dc4933a2`. `selfCompiler_outcome` for any files, with
`read` and `compiled` in place of `compileSource prog = some B`.

#### `Lanius.Faithful.SelfShort.selfCompiler_reason`

statement `00000000803be923`. `selfCompiler_outcome`, premises unchanged,
with `SelfFaults` replaced by `SelfFaultReason`: when the run faults
because Core's run of `w` fails at every fuel, one of `SelfShort`'s reasons
holds. Either the cost semantics gives the pure compile no cost at any fuel
(`selfCost N W = none` for every `N`) because the prelude's `plus` or
`times` panics (`SelfPanics W`: with the two wrapping, `compileW` has a
value at some fuel), or `compileText files`'s binary has
more words than `room`, or it has a cost and the heap limit is short:
`limit < selfNext W room + h` for every cost `h` that `selfCost` gives
(`W = filesWords files`). The other fault branch, Core's run completing
within the limit with the stack window short, is as before. Rests on
sections 3, 4, 5, 6 and 8.

#### `Lanius.Faithful.SelfShort.selfHost_fixpoint_reason`

statement `000000005a4ddf64`. `selfHost_fixpoint` with `SelfFaults`
replaced by `SelfFaultReason`.

#### `Lanius.Faithful.SelfShort.selfHost_outcome_reason`

statement `00000000b38b3b9b`. `selfHost_outcome` with `SelfFaults`
replaced by `SelfFaultReason`.

#### `Lanius.Faithful.SelfTotal.selfCompiler_total_reason_of_bounds`

statement `00000000b986c107`. **Conditional**: it assumes
`CompileBounded T (filesWords files)`, the open part of F14 (ROADMAP F14),
for some threshold `T` above the heap limit (`limit < T`), and is not a
replacement for `selfCompiler_reason` until per-function bounds prove that
premise for all words. `CompileBounded T W`: whenever
`progW`'s compile of `W` has a heap cost `k < T` (`costW`, which is
`selfCost` run on `progW`), the guarded compile `compileG` has a value at
some fuel. `compileG` is `compileW` run by `pcallG progW prims safeW`, the
pure semantics in which a call of `plus` or `times` has no value unless both
arguments are `usize` and the result is below `2 ^ 64` (`safeW`, `NoWrap`).
Under that premise, the statement is `selfCompiler_reason` with
`SelfFaultReasonW`, where `SelfShortW` replaces `SelfShort` and has no
panic reason. A fault because Core's run of `w` fails at every fuel comes
with one of three reasons:
- the output room is short;
- the heap limit is below `selfNext W room + h` for every cost `h` of
  `selfCost`;
- the self program's compile has no cost at any fuel, `progW`'s compile has
  a cost, and every cost it has is more than the heap limit.
Rests on sections 3, 4, 5, 6 and 8, as `selfCompiler_reason` does.

#### `Lanius.Faithful.SelfPanics.compileW_total`

statement `00000000cb6e99e6`. For any words `W`, the pure compile of the
self program with the prelude's `plus` and `times` replaced by their
operators, which wrap (`progW`), has a value at some fuel: `compileW N W =
some v`, `grammar()`, then `front_end_words(grammar(), list W)` and
`compile_words(..)` by `pcall`. Every function the compile reaches
terminates (`SelfTerm.termOk`), is typed (`SelfPure.selfPure`) and cannot
fail but at a call (`SelfPure.livesOk`, `LiveFn` of `Sim/Live.lean`), so
`pcall_live` gives each call a value. Rests on section 1 only: it is about
the pure semantics, not Core or the machine.

## 1. Lean

- **What.** The Lean 4 kernel (toolchain `leanprover/lean4:v4.33.1`, pinned
  in `lean-toolchain`; the project has no package dependencies) and three
  axioms, `propext`, `Classical.choice` and `Quot.sound`. Every top theorem
  depends on exactly these (`link_eq` on `propext` and `Quot.sound`), as
  `#print axioms` gives; gate step `trusted` prints them. There is no
  `sorryAx` and no `Lean.ofReduceBool`, so nothing relies on
  `native_decide`, `bv_decide` or compiled code. Elaboration and tactics
  are not trusted, because the kernel rechecks every term they produce.
  Modules hide definition bodies from each other (the module system); that
  changes what the elaborator may unfold, not what the kernel checks.

## 2. The statements' definitions

A theorem only means what its definitions say. These definitions are part of
the statements, so a reader has to agree that each one says what is intended:

| definition | file | says |
|---|---|---|
| `SrcProgram.toCore` and the `toCore` of each construct | `Mini/Source.lean` | which Core program a source program *is*: each construct is the Core construct of the same name (`Null` is Core's literal `.pointer 0`), and functions are numbered by position, then the host functions (`hostFuncs`, ids 2^32 up). A literal (`EStruct`, `LetStruct`) means `SrcType.literal`: Core's array value `.array T vs` at an array type `[T; N]`, and a struct value otherwise. `ArraySlice(T, x)` is Core's `arrayToSlice T (local x)`. `EIf(c, T, a, b)` is Core's `matchValue c [(literal true, a), (_, b)]`, Core's match on the bool (Core has no conditional expression). `ELet(x, T, v, R, b)` is Core's `matchValue v [(bind x, b)]`, the one arm binding x (Core has no let expression). `ELen(x)` is Core's `intrinsic sliceLength (local x)` |
| `FieldsHold`, `SrcType.HoldsAt` | `Mini/Source.lean` | how a Core value sits in 64-bit slots: an `i32` is zero-extended, a `bool` is 1/0, a struct is its fields in order, an enum is a tag then its payload, a pointer is its address, an array `[T; N]` is its N elements in order, as a struct of N fields of type T, a float is its bits. Their argument `places` lists the places held in memory (`Addressed`): a lent array's slice (`borrowed`) and a reference (`ref`, `RefHeld`) name one of them; the top theorems pass `[]` |
| `Addressed`, `RefTo`, `RefHeld`, `SrcType.words`, `SrcType.sub` | `Mini/Layout.lean` | the places references and lent slices name (a Core cell and projection path, a source type, the lowest byte of its block), a value's native words, the byte offset and type of a sub-place, and when a word is a reference to a sub-place of a place (`HoldsAt.ref`); SEMANTIC_DECISIONS "References: the memory model" points 4 and 5 |
| `startState`, `State.Fresh`, `HeapCorr`, `outputOf` | `Mini/SourceCorrect.lean`, `Mini/HeapCorr.lean` | Core's start state for a standard input (empty heap, the world with that input); a state with no live cells whose i32 array views each hold their cell (`Views.ViewsHold`, `Mini/Views.lean`); the mini heap representing Core's heap and world (standard output and error are `outputOf 1` and `outputOf 2` of the mini heap's trace, the bytes its writes put on fds 1 and 2, no open files, the same standard input) |
| `Returned`, `HeapAt`, `StackAt`, `Contract`, `Scratch`, `InHeap` | `Mini/Simulation.lean` | the calling convention and what "returns" means (section 8) |
| `Below`, `Binary.stackNeed`, `Binary.guard` | `Mini/Frame.lean`, `Mini/Bytes.lean` | the stack window |
| `Det`, `DataEq`, `Live`, `Faults`, `Fault` | `Mini/StepDet.lean`, `X86/Machine/Scalar.lean` | every run agrees but for flags and does not stop early; a run that stops, stops at an architectural fault (`ud2`, `#DE`) |
| `undefinedTrap`, `Failing` | `Mini/Fails.lean` | a Core run fails at a fuel when it runs out of fuel, stops at a trap that is not undefined, exits (`.exited`), or completes or traps with the heap past the mini heap's limit; the undefined traps are the raw memory errors (`invalidPointer`, `rawMemoryBounds`, `doubleFree`, `allocatorContract`), `typeMismatch`, and the end of a clock's readings or of the secure bytes (`clockExhausted`, `entropyExhausted`) |
| `SrcProgram.need` | `Mini/LowerStmt.lean` | the frame memory a call of function `f` takes: `f`'s entry of `funcNeeds sp.funcs`, 0 past its end. `funcNeeds` is a computation the theorems are about (section 10): the premise that uses it (section 8, "Frame room") holds whatever it computes when the heap has that many bytes of frame memory |
| `Program.Returns`, `Exec` | `Mini/Semantics.lean` | the mini IR's big-step semantics, at a call depth |
| `Stops`, `Program.Stops` | `Mini/Stops.lean`, `Mini/StopsCorrect.lean` | a mini run that, within `n` ticks (loop iterations and calls), has not finished or has stopped at an allocation past the limit from a cursor within it, or at a division by zero or of the least value by -1 |
| `Typing.ProgramWellTyped` | `Lanius/Typing.lean` | Core's type system on programs |
| `CodeAt`, `Steps`, `Step` | `X86/Machine/State.lean`, `X86/Machine/Scalar.lean` | the image is loaded, and the machine runs (section 6) |
| `Loaded`, `Exits` | `Mini/Process.lean` | what Linux does at `execve` and at `exit` (section 8) |
| `linkProgram`, `Stmt.rename`, `Binary.executable`, `Executable.stackNeed` | `Mini/Compiler.lean`, `Mini/Link.lean` | which mini program a list of modules *is* (their functions in link order, each callee renamed to its program index, imports checked for owner, function and arity), and what of a binary a linked executable keeps |
| `TextReading`, `SourceFile` | `Mini/TextCorrect.lean`, `Mini/FrontLex.lean`, `Mini/Reading/` | the reading of source text (section 4); a file is its bytes with laniusc's tree (production ids in preorder, each node's parent), and the theorems mention no tree |
| `filesWords`, `FilesFit` | `Mini/TextWords.lean` | the driver's input format: per file its byte count, bytes, production count, productions and parents, one 32-bit word each, after a file count; the bounds within which each count fits a word |
| `binaryWords`, `imageWords`, `packRounds` | `Mini/Compiler/P/packRound.lean` | the driver's output format: the entry count, the entries, the image's length in bytes, then its bytes four to a word, the first in the low byte, the last word padded with zeros |
| `Inv`, `Reads`, `Result`, `Readable` | `Faithful/Sim/State.lean`, `Faithful/SelfDriver.lean`, `Memory/Read.lean` | the Core state invariant (no live `i32` array views, block bases unique); an input view reading words; the driver's result (-1, or the length with the output view reading the words); readable bytes of Core's heap |
| `SafeE` | `Faithful/Safe/Run.lean` | no fuel of Core's run reaches an undefined trap |
| `SelfOutput`, `selfHeap`, `selfBits`, `selfNext` | `Faithful/SelfCompiler.lean` | what the self-built compiler's `w` returned in x86 memory; the heap layout and argument slots its caller sets up (the input words, then the output room, then the bump heap) |
| `SelfFaultReason`, `SelfShort`, `selfCost`, `qcall`, `boxCost`, `prims` | `Faithful/SelfShort.lean`, `Faithful/SelfLive.lean`, `Faithful/Cost.lean`, `Faithful/Fwd/Prim.lean`, `Faithful/Gen/SelfPureTab.lean` | why the self-built compiler's `w` may fault when Core's run of it fails at every fuel: no pure cost, the output room short, or the heap limit below `selfNext` plus every cost. `selfCost` is `w`'s heap cost by the pure cost semantics `qcall` (the pure semantics of `pcall`, adding `boxCost`, the box's storage and 8 bytes of alignment, at each call of a `prims.boxed` function): one `List<i32>` box per input word, then `grammar()`, `front_end_words` and `compile_words` |
| `SelfFaultReasonW`, `SelfShortW`, `CompileBounded`, `costW`, `compileG`, `pcallG`, `safeW`, `NoWrap` | `Faithful/SelfTotal.lean`, `Faithful/Sim/Agree.lean`, `Faithful/SelfAgree.lean` | the conditional theorem's reasons and its premise. `SelfShortW` is `SelfShort` with the panic reason replaced: the self program's compile has no cost, and `progW`'s compile costs more than the heap limit at every fuel where it has a cost (`costW` is `selfCost` on `progW`). The premise `CompileBounded T W`: a cost of `progW`'s compile below `T` means the guarded compile `compileG`, `compileW` run by `pcallG`, has a value. `pcallG sp prims safe` is `pcall` where a call ruled out by `safe` has no value. `safeW c vs`: if `c` is `ixPlus` or `ixTimes`, then `vs` is two `usize` values whose sum or product, respectively, is below `2 ^ 64` (`NoWrap`) |
| `SelfPanics`, `compileW`, `progW`, `wrapAt`, `wrapFunc`, `pcall`, `ixPlus`, `ixTimes` | `Faithful/SelfPanics.lean`, `Faithful/Sim/Wrap.lean`, `Faithful/Pure.lean`, `Faithful/Gen/SelfLiveTab.lean` | `SelfShort`'s first reason: no cost at any fuel, and the pure compile (`pcall` of `grammar()`, `front_end_words` and `compile_words`, as `selfCost` runs them) of `progW` has a value. `progW` is `prog` with functions `ixPlus` and `ixTimes` (the prelude's `plus` and `times`, found by name by `faithful_pure.py`) wrapped: `wrapFunc op f` is `f` with the body `return a op b` of its first two parameters, which wraps, where the prelude's panics when the result overflows |

The computations the theorems are about are not trusted (section 10):
whatever `compileSource`, `compileText`, `compileProgram`, the optimizer,
`compileModules`, `linkObjects`, `elfFile` and the front end's code compute,
the theorems say what it means.

## 3. Core semantics as the meaning of Lanius

- **What.** The theorems are stated against Core's fuel-indexed evaluator
  `Lanius.Semantics.evalExpr` (`Lanius/Semantics.lean`, `Lanius/Semantics/`),
  Core's heap (`Lanius/Memory.lean`, `Lanius/Memory/`; the allocator is
  unbounded and `nextAddress` starts at 1) and Core's world
  (`Lanius/World.lean`: standard input, output and error, files and clocks,
  with `World.call` the meaning of each host service, such as `write_byte`,
  `write_stdout`, `read_stdin` and `sleep_ms_i32`). It is assumed that these
  are what Lanius programs mean. No other formal semantics exists to compare
  them with, and laniusc, the GPU compiler, is not proved against them.
- **Coverage.** `compileSource_correct` is about Core runs that finish
  (`= .done v final`) within the heap; `compileSource_stops` and
  `compileSource_behaviour` about the others: when every fuel runs out or
  traps definedly, the code never returns, and a run that stops other than
  at a fault comes from a Core run that finished or reached an undefined
  trap (`undefinedTrap`). Programs outside the subset (`compileSource`
  returns `none`) are not covered. Core's allocator never fails; on x86 the
  heap limit is enforced (the bump allocator executes `ud2` past it), and
  the theorems assume that Core's run fits: `final.heap.nextAddress ≤
  heap.limit`.
- **Raw views.** `i32_slice_from_raw_parts` and the raw
  slices of structs and enums (`Heap.checkRange`) check that the range is
  nonempty, aligned, and inside one live block whose alignment is enough,
  and leave the heap as it was. A view may cover any aligned range inside a
  block (a prefix, a middle), and the block stays owned: `dealloc` after a view
  succeeds, and a read through the view after that traps
  (`invalidPointer`), so use-after-free still traps. Arrays and strings
  that the language itself lends (`mapBorrowed`) still make borrowed blocks.
  This is the meaning `Vec` needs: its buffer is one block and its
  elements are a view of a prefix of it.
- **Writes through references (F5).** Core's places gain
  `Place.deref reference` (`Lanius/Core.lean`): `evalPlace` evaluates the
  reference, and the place is its cell at its projection path, with the
  value there read (`readCellProjection`). An assignment to it, or to a
  field or element of it, writes the referenced cell, as an assignment to
  a local's field does. Core's type checker
  (`checkPlaceAnyFuel`) has no rule for it yet and rejects it.
- **Shift amounts.** A shift of a signed or unsigned
  integer may take an amount of another such type (`x << n` with `x: i64`,
  `n: u32`), as laniusc allows: typing `BinaryOpHasType.shiftLeftBy` and
  `shiftRightBy` (`ShiftTy` on both sides, the result the left operand's
  type), evaluation `Semantics.evalShiftBy`, which checks the amount's
  number against the left operand's width, as a shift by its own type does
  (`u8` by a `u32` amount of 256 traps).
- **Floats (F9).** Core's `f32` and `f64` values are their
  IEEE 754 binary32 and binary64 bit patterns (`.f32Bits`, `.f64Bits`), and
  every float operation is defined on exact integers in `Lanius/IEEE.lean`
  (234 lines; no Lean `Float` anywhere, so the kernel can evaluate and
  reason about it). The specification:
  - A finite pattern's value is `(-1)^s * significand * 2^unitExp`: a normal
    one has the hidden bit, a subnormal one the unit `2^(1 - bias - f)`.
  - `roundRatio` rounds an exact rational `num / den * 2^exp` to nearest,
    ties to even, with gradual underflow (no flush to zero) and overflow to
    infinity. `+ - * /` compute the exact result and round it once
    (`add`, `sub`, `mul`, `div`); an exact zero sum is `+0` unless both
    operands are `-0`; a zero product or quotient has the sign of the
    signs' xor.
  - NaN results follow x86 SSE: an operation with a NaN operand returns the
    first NaN operand with its quiet bit set (sign and payload kept); an
    invalid operation on non-NaNs (`inf - inf`, `0 * inf`, `0 / 0`,
    `inf / inf`) returns the default NaN (sign set, exponent all ones, only
    the quiet bit), and `x / 0` is a signed infinity.
  - `==`, `<`, `<=` are false when either operand is a NaN, and `-0 == +0`;
    `!=` is the negation of `==`, `>` and `>=` swap the operands.
  - Negation flips the sign bit, NaNs included (`neg`), as `xorps` does.
  - Integer to float (`ofInt`) rounds the exact integer; `f32 -> f64` is
    exact, `f64 -> f32` rounds; a NaN converts with its sign and the top bits
    of its payload, quieted (`convert`), as `cvtss2sd`/`cvtsd2ss` do.
  - Float to integer (`truncSat`, added: Core had no such cast) truncates
    toward zero and saturates to the target's range, NaN to 0, as Rust's
    and laniusc's `as` do.
  - A decimal literal `m * 10^e` is rounded once to the nearest pattern
    (`ofDecimal`, used by elaboration); past `10^400` it is infinity and
    below `10^-400` zero, only to avoid huge powers.
  This specification is also the meaning of the SSE instructions in the
  x86 model (section 6), under Linux's default MXCSR (section 6).
- **`slice_stride`.** `Intrinsic.sliceStride` gives a raw
  view's signed byte stride as an `isize` (`rawSliceStride?`): 4 for `i32`
  views, and `-8 × words` for views of structs and enums. On these views
  laniusc gives the same values. Core gives
  a view of a language array no stride (it traps), while laniusc gives that
  array's own layout. Programs that ask for one are outside the theorem.
- **`slice_len`.** (added 11-01, F11b) `Intrinsic.sliceLength` gives a
  slice's length as a `usize` (`sliceLength?`): the `length` of a slice of a
  language array and of a raw view alike. Any other value traps. Its typing
  rule is `ExprHasType.sliceLength`, from `[T]` to `usize`. laniusc reads
  the same length from word 1 of the slice's descriptor, but it has no
  surface intrinsic for it yet (SEMANTIC_DECISIONS "Slice length").
- **One-word scalar views.** (added 11-01, F11b) A raw slice of `u32`,
  `u64`, `i64` or `bool` is a word view, as a `[u16]` is: one descending
  8-byte word per element (`rawSliceElementAddress?` and
  `mapRawNominalSlice` take them as a struct or an enum,
  `NativeLayout.elementStride?` is -8 and `words?` of such a slice is 3),
  typed by `RawNominalSliceElement.word32`, `.word64`, `.signed64` and
  `.boolean` (SEMANTIC_DECISIONS "One-word scalar views").
- **Native layout.** Core reads and writes values in memory
  with laniusc's layout (`docs/wasm-memory-layout.md`). A value's address is
  its word 0, its highest word; word k is 8k bytes below it. A struct's field
  j has its word 0 at 8·W_j bytes below the struct's, W_j being the words of
  the fields before it. An enum's tag is word 0, and its payload starts one
  word below. Element i of a raw view of a w-word type is 8wi bytes below
  element 0. `str` is 2 words (data, then length) and a slice is 3 (data,
  length, stride). Each scalar is one word, so `u8`, `u16`, `u32`, `i8`,
  `i16`, `i64`, `u64` and `isize` have a native layout too. A raw field
  place `s[i].f` is the element's address less the field's offset, and it
  traps (`rawMemoryBounds`) when that would go below 0. One difference from
  laniusc remains. Core writes `i32`, `bool`,
  `i8`, `i16`, `u8`, `u16`, `u32` and enum tags as 4 bytes and the 64-bit
  kinds as 8, while laniusc writes every scalar as a whole 8-byte word,
  zero-extended. The 4-byte writes are needed because the same writer
  stores packed `i32` view elements, which are 4 bytes apart. Both read the
  32-bit kinds with 4-byte loads. So the two differ only in the upper half
  of such a word, which only an aliasing 8-byte read sees. Core traps when a
  4-byte `u8`, `u16`, `i8` or `i16` read is out of the type's range; laniusc
  does not mask.

## 4. Source text: the reading

The theorems from source text are stated with `TextReading`
(`Mini/TextCorrect.lean`): an inductive relation between the files' texts
and a `SrcProgram`, through the lexer and the grammar below. It is trusted
to give each text the program Lanius means by it.

Not trusted: laniusc's lexer and parser, and the parse trees they give.
`compileText` takes each file's bytes with laniusc's tree (`SourceFile`:
the production ids in preorder and each node's parent), but the theorems
mention no tree: they are about the one reading of the texts. A wrong tree
is rejected, or it is still the parse tree of the same tokens, which is
unique. So the trees the certificates and the self program's files are made
from need not be laniusc's own runs either: `formal/tools/cert_trees.py`
takes each file's tree from a cache keyed by the file's bytes and the text
of the extracted definitions `grammar` uses (not laniusc's binary), or from
an untrusted CPU parser (`fuzz_oracle.Parser`), and asks laniusc only for a
file neither gives a tree for. Every tree, from any of them, is checked by
the validator before it is used, and a tree the validator accepts is the
one parse tree of the tokens (`Lanius.Mini.Unique`), the tree laniusc gives
when it is right; a stale cache entry is rejected, never used. Trusted:

- **The lexer.** `Lanius.Compiler.Lexer.lexCanonical`
  (`Lanius/Compiler/LexerCanonical.lean`) is the meaning of Lanius's lexical
  syntax. The self program's own lexer, `lex_source` in `frontend.lani`, is
  proved equal to it (`lexSource_eq`, `Mini/LexCorrect.lean`), so it is not
  trusted. `lexTokens` adds one keyword that `keywordRules` lacks: `as` is
  token code 195, as in laniusc. Token kinds are laniusc's codes
  (`TokenKind.gpuCode`). `requires` is a keyword (F10); `ensures` and the
  contextual `distinct` have no rule, so a file that uses them lexes them as
  identifiers and its tree is rejected.
- **The grammar.** The table `grammar` in `frontend.lani` is
  `grammar/lanius.bnf` as laniusc built its parse tables
  (`tables/parse_tables.meta.json`). Production `k` is entry `k`, a terminal
  is the token code of its lexer kind, and parser retags map back through
  `canonical_lexer_kind` (`crates/laniusc-compiler/src/lexer/tables/tokens.rs`).
  One mapping is added: `MatchArrow` becomes `Arrow`, because the lexer emits
  `->` in match arms as `Arrow`. `formal/tools/grammar_table.py` writes the
  table mechanically, and `--check` confirms that it is current. The grammar
  is trusted to say what Lanius's concrete syntax is, including precedence
  and associativity, which it encodes in its levels.
- **One reading (V4, proved).** The grammar is not unambiguous on the
  subset, as this file used to claim: `a < b > (c)` is both a comparison chain
  and a call of a generic path `a<b>`, and `f(a < b, c > (d))` likewise.
  `picks` (`frontend.lani`, checked by the validator at every node) is part of
  the syntax's definition: a path segment `x<...>` in an expression is read
  as type arguments exactly when `generic_path_at` holds of the tokens from
  `x` on (the matching `>`, counted outside brackets with `>>` closing two,
  comes before a bracket closes or a `;`, with no `||`, `==`, `!=`, `<=` or
  `>=` before it, and is followed by `(`, `::` or `{`), which is laniusc's
  rule without its 64-token limit; a statement that begins with `{` is a
  block statement (production 84), never an expression statement (85), as
  in Rust, since `{ a } - b;` has both trees; and a method's type arguments
  `.f<...>` (production 298, against none, 297), ambiguous too
  (`x.f < a > (b)`), are read exactly when `generic_open` holds of the
  tokens from the `<` on, by the same rule as a path segment's (F11b: before,
  they were not allowed, so laniusc's tree of any file with one, such as
  `alloc::vec`, was rejected).
  `grammar_unique` (`Mini/ParseUnique.lean`, standard axioms) proves that at
  most one parse tree for `file` is `Picked` for given tokens, from a
  certificate of first and follow sets (two token kinds deep, `>>` read
  either way) that the kernel checks (`grammarCert_ok`,
  `Mini/GrammarCert.lean`, written by `formal/tools/grammar_cert.py`), and
  `Cert.parse_unique` (`Mini/Unique.lean`). So `validate_unique`: the tree the
  validator accepts is the only one, and `sourceProgram_determined` and
  `sourceProgramFiles_determined`: the front end's program depends on the
  source text alone, not on the tree laniusc gives. What stays trusted is
  that `picks` says what the syntax means where it decides.
- **The reading.** `Reading roots sp` (`Mini/Reading/`, V8) is the meaning of
  the subset's concrete syntax, as `toCore` is the meaning of `SrcProgram`
  (section 2): an inductive relation on the files' parse trees, with lookups
  and choices said declaratively, and small total helpers of the builder
  (expected-type and literal-typing helpers such as `intAt`, `operandWant`,
  `knownExpr`, and the wide-literal check `wideLeftFuncs`) as its
  vocabulary. `buildFiles_sound` (standard axioms) proves that what `build`
  returns is a reading, so `build`'s code is no longer the specification.
  The builder's choices are ones the relation states exactly
  (SEMANTIC_DECISIONS.md, "The reading is one reading"), and the relation
  is deterministic (`reading_unique`, F1, `Mini/Reading/Det/`), so a text
  has at most one reading and the theorems are about it alone. The reading
  makes these choices:
  - each file is a module, named by its `module` item (the empty path
    without one); `m::x` names `x` of the module `m`, a bare `x` names `x`
    of the current module; `import m;` only adds m's variants to those a
    bare variant name may mean, and trait declarations, type aliases with
    a `where` clause and extern functions are skipped (a trait impl's
    methods are functions, and the impl itself is kept for the bounds,
    `Decls.impls`), except that an `extern
    "lanius_std" fn` named `write_byte`, `write_stdout` or `write_stderr`
    (`hostExtern`) is a function whose instance returns the call of that
    host service on its parameters, `ECall(2^32 + k, params)` (`ReadExtern`;
    Core's meaning of that id is the host function, section 2);
  - `type A<P..> = T;` is an alias: a type path that names no type
    parameter, primitive or declared type names the alias of that module,
    and means T read in the alias's module with its parameters standing for
    the arguments (a cycle runs out of fuel and rejects); a cast may name an
    alias of a scalar type;
  - generic declarations are monomorphized (`mono`): an instance is a
    declaration with its type arguments, and a function or type id is a
    position in the instance tables. The first file's functions without type
    parameters come first, in order; every other function instance follows
    in the order it is first called. Types: the first file's non-generic
    types in order, then each instance as the functions' types (parameters,
    result, then the body's lets) first need it. A program without generics
    keeps the numbering of the next two lines;
  - a function is its position among the functions;
  - a struct or enum is its position among the type declarations;
  - a call's type arguments are written, or inferred by matching the
    callee's result type with the type its value is stored at, then its
    parameter types with the argument types in order, each argument read at
    its parameter's type once all are bound; an integer literal argument
    (or arithmetic of literals, or a shift whose value is one: a shift's
    type is its value's, whatever its amount, `bareInt`/`bareEff`) binds
    nothing unless a parameter is left unbound, when it counts as
    `i32`; a conflict or an unbound parameter rejects;
  - `x.m(args)` (`x` any value) and `T::m(args)` (`T` a type parameter, or
    a primitive type as in `i32::hash(v)`) call
    the method `m` of the one `impl` whose type matches the receiver's type,
    with `self` (by value) the receiver; `x.m<T, ..>(args)` binds m's own
    type parameters to the written types in order, after the impl's binds
    from the receiver, instead of inferring them (`MethodBinds`, F11b; a
    count other than m's parameters rejects);
  - a `match` has one arm per variant of its scrutinee's enum, in any order,
    and its arms are listed in variant order (only one runs, so their order
    has no effect);
  - (F11) a match expression with a nested arm (`Ok(Some(x))`) is read as
    nested matches (`MatchOrder`, `NestedOrder`, `Reading/Nested.lean`):
    variant V's arm is `V(b, .., h, ..) -> match (h) { p -> value, .. }`,
    the arms naming V in order matched on the first arm's first column j
    that is not a binder, every other column a binder spelled as the first
    arm's, a binder at j in the last arm read as `_` when its value spells
    no token as its name (`Mentions`), then the outer wildcard unless no
    value of V reaches it (an inner `_`, or `Covers`) and only when its
    value spells none of the first arm's other binders (`ColsQuiet`); h is
    the binder spelled `[0]`, which no source can spell. No arm's value is
    a block (`BlockValue`). A match statement's nested arms are read the
    same way (`StmtOrder`, arms may be blocks), the inner match read as a
    match statement on h (`ArmsStmtR.inner`), and so are a let's match's
    (`LetArmsR.inner`; a value arm's value is not that bare match node).
    When V's first arm is plain and a later one nested, the plain arm is
    V's arm and the later ones are not read (`VariantArm.shadow`).
    SEMANTIC_DECISIONS "Nested patterns";
  - (F11b) a match whose first arm's pattern is an integer literal, `true`
    or `false` (`LitMatchR`, `LitArmsR`, `Reading/Stmts.lean`), as a
    statement, a `let`'s typed value or a returned value, has a scrutinee
    of an integer type or `bool` (`litTy`); its value is bound to the
    match token's local unless it is a local. It is read as a chain of ifs
    in arm order: `x == n` (n read at x's type) for an integer arm, `x` or
    `!x` for `true` and `false` arms, the first matching arm's body run.
    Its last arm is `_`, or at `bool` some earlier arms are `true` and
    `false` and the chain ends unreachable; a let's rest follows each
    arm's value (`LitBodyR.letValue`). A let or return reads it this way
    only when some arm's value is a block (`LitWanted`). Otherwise, and
    anywhere in an expression, a match on a scrutinee of such a type whose
    arms' values are expressions (`EffR.litMatch`, `Reading/Effs.lean`) is
    the conditional expression `XIf` (closing to `EIf`) chained in arm
    order (`litChain`), on the scrutinee when it is pure, or else on the
    `match` token's local, fresh, bound to the scrutinee first by `XLet`
    (closing to `ELet`; `LitBound`): each literal arm's test as above, its
    value, else the rest;
    the `_` arm's value, or at `bool` the last arm's once `true` and
    `false` both have arms, untested. Each arm's value is read at the
    expected type, and the type is that, or else the first arm's.
    SEMANTIC_DECISIONS "Literal patterns";
  - (F11b) a payload pattern binds a name only when no enum of the program
    has a variant so spelled (`BindersR`'s `NoVariant`): laniusc reads one
    that resolves to a variant as a check. SEMANTIC_DECISIONS "Payload
    names that are variants";
  - (F11b) `for x in a { body }`, a an array local of n elements
    (`StmtR.forArray`, `Reading/Stmts.lean`), is `forArray`'s loop: a
    hidden `usize` index i (the `for` token's local) from 0 while i < n,
    `let x = a[i]` (x's token's local), i = i + 1, then the body; n below
    2^31. SEMANTIC_DECISIONS "`for` over an array";
  - (F11b) `for x in s { body }`, s a slice local (`StmtR.forSlice`), is
    `forSlice`'s loop: the hidden `usize` index i (the `for` token's local)
    from 0, the hidden `let n: usize = slice_len(s);` (x's token's local)
    once before the loop, then while i < n, `let x = s[i]` (the `in`
    token's local), i = i + 1, then the body. A body that writes s itself
    is not read. SEMANTIC_DECISIONS "`for` over an array";
  - `x.f` is `Field` when `x` is a local, and otherwise the call of the
    projection `fn(v: T) -> F { return v.f; }` on `x`, an instance numbered
    like any other;
  - bounds and `where` clauses (F7) are checked on each function
    instance (`FnBound`, `Implements`, `Reading/Bounds.lean`; a method's
    impl's too): the type a bounded type parameter stands for must have an
    impl of the bound's trait at its arguments, an `impl<P..> Tr<..> for S`
    whose trait and type read as the bound's for some P.., with its own
    bounds holding there. A trait is the module and spelling its path
    resolves to (as a type path's) with its type arguments; there are no
    implicit impls. This decides which programs are read, not what a read
    program means. A struct, enum or alias with a `where` clause or a
    bounded type parameter is not read (`FreeParams`);
  - a type parameter that no field or payload uses (a phantom) still makes
    distinct instances, but they lower to the same field types;
  - a constant is replaced by its value, which must be a literal of its
    declared type: `Int` for `i32`, `Unsigned` (range-checked) for the
    unsigned types, `Cast(Isize, Int(n))` for `isize`, `Boolean` for `bool`;
    a value whose tokens are `n` or `-` `n` with n of 2^31 or more is the
    type's literal of that value (`Int` of -2^31 for `i32`, `Unsigned` up to
    the type's largest value, the cast of the `u64` literal of its bits for
    `isize`);
  - an integer literal's value (`intValue`, `Reading/Exprs.lean`) is that of
    its decimal digits, or of the digits of base 16, 8 or 2 after `0x`,
    `0o` or `0b` (the letter in either case, as laniusc's lexer takes it);
    each `_` is a separator and skipped. Below 2^31 it is an `i32` literal,
    up to 2^64 the wide marker (`IntLiteral`); a constant's `n` or `-` `n`
    is read the same way (`WideConst`). An array length is still decimal;
  - a char literal (`CharLiteral`) is the code of the one
    Unicode scalar value (`ScalarValue`: below 0x110000, not a surrogate)
    whose UTF-8 encoding (`utf8Encode`) its text holds between the quotes,
    other than the quote, backslash and newline, or of one of the escapes
    `\n \r \t \0 \' \" \\` (`Escape`). laniusc's `parse_char_token` decodes
    these the same way; it also takes texts this reading rejects (`'ab'`,
    `\x` for other `x`, a malformed encoding as code 0). A constant of type
    `char` is its literal. `char` is the primitive type `SrcType.char`,
    held as its code (`UInt32`), which Core's `Value.character` is;
  - `f32` and `f64` (F9) are `SrcType.float .f32/.f64`, held
    as their IEEE bit patterns as Core's `.f32Bits`/`.f64Bits` are. A float
    literal (`floatParts`, `Reading/Exprs.lean`) is decimal digits with an
    optional `.` and fraction and an optional `e`/`E` exponent with a sign,
    read as the exact `m * 10^e`; underscores are rejected, and so is an
    exponent of more than 99999 (only so that the powers stay small). Its
    value is `ofDecimal` of `m` and `e` at the expected type when that is a
    float type, and at `f32` (Core's `literalDefaultType`) otherwise.
    `flDecimal_eq` (`Reading/FloatBits.lean`) proves that the front end's
    bignum rounding equals `Lanius.IEEE.Format.ofDecimal`, so the rounding
    is not trusted; only `ofDecimal` itself is (section 3). A constant of a
    float type is its literal, or the negation of its literal;
  - `[T; N]` (F6) is `SrcType.array T N`, Core's array type,
    when N is written as a decimal integer literal (`ArrayLen`; a constant
    name as the length is not read). An array literal is read only where an
    array type is expected (a `let`'s type, a parameter, a field):
    `[a, b, ..]` must have exactly N elements, each read at T, and `[x; n]`
    needs a pure x and n written as the decimal N; it is read as N copies
    of x (`EffR.array`, `EffR.arrayRepeat`). Both are the struct literal
    node `EStruct`/`LetStruct` at the array type, whose meaning is Core's
    array value (section 2). Copies of a pure x have the value Core's
    `[x; n]` gives, which evaluates x once; `a[i]` of an array local is
    read as `a[i]` of a slice local is (`EffTy.indexArray`), and so is
    `a[i] = v`, with v read at the element type (`indexElem`);
  - a local is the byte offset of its binding (a parameter, `let` or match
    binder) from the start of its function's name (so that an
    edit to one function renumbers the locals of no other);
  - a use names the innermost binding with the same spelling, and locals may
    not be spelled like a type, type alias, variant or constant of their
    module (a function is only named by a call, so a local may share its
    spelling);
  - `let` scopes over the rest of its block;
  - `if` without `else` has an empty else;
  - binary operators fold to the left;
  - an integer literal below 2^31 is `Int`, and `-` before it is `negate`;
    one from 2^31 to 2^64 - 1 takes the type its context expects (decided by
    `lit_funcs`, below): `Unsigned(u, n)` when n fits u, for `isize` below
    2^63 the cast of the `u64` literal n, `-2147483648` at `i32` (or with no
    expectation) `Int` of -2^31, and `-n` at `isize` (n at most 2^63) the
    cast of the `u64` literal of its two's complement bits; any other
    rejects the program;
  - a bare literal operand of a shift takes the shifted
    value's type, or else the shift's expected type, as a shift's type is
    its left operand's, and a bare amount (literals only; a constant reads
    as a literal of its type) is `i32`, as laniusc types it (`amountWant`;
    10-31, F11b: it was the value's, a reading bug fuzz_oracle.py found);
  - `&self` is read as `self`: the method takes the impl's
    type by value (`PatternOf.selfRef`, `paramToken`). laniusc's `&self`
    may write the caller's value (`self.n = ..` reaches the caller), so a
    method that writes `self` is not read (`writesLocal`,
    `refChecked`, `ReadFn`); while nothing writes through it, the reference
    and the value read the same, as no other code runs during the call;
  - `S::m(args)` (F7), where
    S names, as a type path resolved like any other (the current module's,
    an item import's, or `p::S`), a struct, or an enum with no variant
    spelled m, is read as `T::m` is for a type parameter bound to S: the
    one method spelled m of an impl whose type matches S read without type
    arguments (`TypeOwner`, `BareTy`); `E::V(args)` for a variant V of E
    still names the variant;
  - `0` where a `ptr` is expected (a `let`, a parameter, an operand beside a
    `ptr`, a `ptr` constant) is `Null`, Core's null pointer;
  - a match arm whose value calls a `-> !` function g, in a match of value
    type t, calls g's instance at t: a function with g's parameters, result
    t and body `g(params); return self(params);`. Core traps in g (each
    `-> !` function in the stdlib is `assert(false)`), so the return, which
    only gives every path a value of type t, is not reached; if g returned,
    the instance would recurse until Core's fuel ran out, and the theorem
    covers only runs that return;
  - the path `alloc::allocator::alloc(size, align)`, in a `let` of type
    `ptr`, is Core's `alloc`, and the statement
    `alloc::allocator::dealloc(p, size, align);` is Core's `dealloc`; the
    alignment must be a literal `2^k` (`8` or `(8 as usize)`), read as the
    shift `k`. `slice_from_raw_parts(p, n)`, in a `let` of type `[T]`, is
    Core's raw view of `T`. These spellings are fixed: build does not look
    at the extern declarations in `alloc::allocator`, and these paths,
    `slice_stride`, `slice_len` and `assert` are never read as a function or variant
    (`builtinPaths`);
  - `x op= e` is `x = x op e`, and `x.f op= e` is `x.f = x.f op e`, for
    `op` one of `+ - * & | ^`. Core has the compound form itself
    (`assign .add` and so on, `evalAssignValue`), which reads `x` (its
    place, `evalPlace` in read mode) before it evaluates `e`, as `x = x op
    e` does; for the subset's expressions, which neither trap nor have
    effects, the two forms give the same value and state;
  - an expression that calls a function, indexes a slice, divides (`/`,
    `%`), or is a struct literal, variant or `match` is a `SrcEff`, and its
    statement the effectful form (`LetEval`, `SetEval`, `SetFieldEval`,
    `IfEval`, `WhileEval`, `ReturnEval`, `SetIndexEval`, `Discard` for
    `f(x);`).
    Operators, casts and negations of pure operands are `EPure`, and a
    statement with a form of its own keeps it (`LetCall`, `SetCall`,
    `LetStruct`, `LetEnum`, `LetMatch` on a local, `LetIndex`, when their
    parts are pure). `x op= e` with `e` effectful, and `x /= e`, `x %= e`,
    are `SetEval(x, x op e)`, and `x.f op= e` is `SetFieldEval(x, f, x.f op
    e)`: `x` is read before `e` is evaluated, which is Core's order too
    since reading a local has no effect. A struct
    literal's or variant's type arguments come from the type its value is
    stored at when that is known (a `let`, the assigned local, the result
    type for `return`, a parameter of a callee whose type arguments are
    known), else from its fields' or payload's types; a match's result type
    is the stored-at type or its first arm's.

  - a function without `-> T`, or with `-> !`, returns `Unit`; `return;`
    is `ReturnUnit`; `assert(c);` (that spelling, one argument) is
    `Assert(c)`, Core's assert intrinsic. So `core::panic::panic()`, whose
    body in `stdlib/core/panic.lani` is `assert(false);`, traps.

  - `isize` is `Isize`. An integer literal whose expected type is `isize`
    is `Cast(Isize, Int(n))`, and one whose expected type is unsigned is
    `Unsigned(u, n)`, decided after monomorphization by `lit_funcs` from the
    types of locals, fields, parameters, callees and results; an operator's
    operands expect the type of whichever operand has one.

  - `slice_stride(x)` of a slice local x is `EStride(x)`;
  - (F11b) `slice_len(x)` of a slice local x is `ELen(x)`, a `usize`;
  - (F11b) a call's argument at a parameter of type `[T]` that is an array
    local of element type T is `ArraySlice(T, x)` (`argView`), Core's
    `arrayToSlice T x`, so the callee's writes reach the array, as in
    laniusc; an array local of another element type rejects;
  - `return slice_from_raw_parts(p, n);` in a function whose result is a
    slice is a slice local (named by the offset of `slice_from_raw_parts`)
    and its return;
  - a bare variant name is the one variant of that spelling among the
    current module's enums, else among its imported modules' enums;
    `E::V` and `m::E::V` name enum E's variant V, `m::V` module m's one V;
  - a function's `requires c;` clauses (F10) are `assert(c)`s, in
    order, before its body (`ContractsR`), so a false one is Core's assert
    trap.

  A text outside the subset has no reading, and the theorems say nothing
  of it (`compileText` returns `none`).
- **Core**, as in section 3. `build`, the front end's code, is not trusted:
  `buildFiles_sound` proves that what it returns is a reading.

## 5. Premises computed by Lean's compiled code, and how the compiler is run

The theorems are about the Lean definitions (`compileSource`, `compileText`
and the rest), whatever they compute. Which code is run as the compiler,
and how, adds these assumptions.

### The self-built verified compiler

The verified compiler that is run is `B`, the self program compiled by
itself. `selfHost_fixpoint` and `selfHost_outcome` take two facts about the
self program's files `self` (the driver `w` and the module closure of
`mini::selfhost`: the driver, `compiler.lani`, `frontend.lani` and the
stdlib modules they import, each with laniusc's parse tree, laid out as
`self_host.py` and `faithful_current.py` lay them out) as premises, and
`selfCompiler_outcome` takes one. The kernel cannot evaluate the front end
on the self text (about 800 KB) or `compileSource` on `prog` (an image of
about 15 MB), so each is computed by Lean's compiled code, and trusted:

- **`read : sourceProgramFiles self = some prog`.** `lake exe srcDump`
  (`Lanius/Tools/SrcDump.lean`) runs the front end on the files and prints
  its program with `repr`, and the generators (`faithful_dump.py`,
  `faithful_certs.py`) write it to `Faithful/Gen/` as `prog`. Assumed: the
  term `prog` that elaborates from `Gen/` is the value the front end's
  compiled code computed for the current sources.
- **`compiled : compileText self = some B`**, and for `selfCompiler_outcome`
  `compileSource prog = some B`. `lake exe runAll` (manifest line `compile
  self ...`) computes it and writes `B`'s image and entries. Assumed: the
  image and entries files are `B`'s, as `compileText` defines them.
- **The native run.** `self_host.py`'s ctypes stub (`Native`) maps the
  image and sets up the x86 state for `w`. Assumed: the state it sets up
  meets `selfCompiler_outcome`'s premises: the caller's obligations of
  section 8 for `B` with entry 0, the heap laid out as `selfHeap` with the
  input words, the argument slots `selfBits`, and a heap limit within the
  bounds. The theorem then says what the run returns; that the stub reads
  the output view back as `SelfOutput` describes it is assumed too.

### Lean's compiled code

Wherever a premise is computed by Lean's compiled code (`srcDump`, `runAll`,
`#eval`, any `lake exe`), Lean's code generator and runtime are trusted on
that run: GMP `Nat`, and the `@[extern]` and `implemented_by`
implementations of `BitVec`, `UInt8`, `List` and `Array`. The kernel sees
none of this code.

### The laniusc build

laniusc can also compile `formal/lani/mini/compiler.lani` itself (the
difftests do). A binary built that way is not covered by any top theorem
unless these are assumed:

- **The extractor.** `Lanius/Mini/Compiler.lean` and `Frontend.lean` are
  extracted from the `.lani` sources by the extractor in Lanius
  (`formal/lani/mini/extract.lani`, run by `lake exe extract` on laniusc's
  tree once the front end's validator accepts it; `formal/tools/extract.py`
  for the programs the front end does not read yet). Assumed: each
  construct it accepts has the Lean meaning Lanius gives it. Types map one
  to one (`i32` and `u32` to `BitVec 32`, `u64` to `BitVec 64`, `usize` to
  `Nat`, `u8` to `UInt8`, `List<T>` to `List T`, `Box<T>` to `T`).
- **The prelude table** (`PRELUDE_FNS`, `PRELUDE_TYPES` in `extract.py`,
  and the same table in `extract.lani`). Assumed: `boxed` and `unbox` are
  the identity, `plus`/`times`/`minus` are `Nat` `+`/`*`/`-` on every run
  that returns (`plus` and `times` panic instead of wrapping; `minus`
  returns 0 when `b > a`, as `Nat` `-` does), and `max_of` is `max`. The prelude bodies are the only code
  that touches raw memory (`alloc`, `typed_slice_from_storage`).
- **laniusc and the Lanius runtime** (allocation, panics, stack depth) on
  this program.

None of these is on the path from the self text to `B`: `B` is
`compileText self`, and `selfHost_fixpoint` is about it, whatever the
extractor wrote. The list operations (`SPEC_FNS`) are extracted with spec
theorems the kernel checks, so they are not trusted either way.

## 6. The x86 model

- **What.** The x86 semantics that `Steps` uses:
  - `Lanius/X86/Machine/State.lean`: user-mode state, meaning sixteen 64-bit
    registers, `rip`, RFLAGS as one 64-bit word, and memory as a total function
    from 64-bit addresses to bytes;
  - `Machine/Scalar.lean`: `decode`, `execute`, `Step`, `Steps` and `Fault`;
  - `Machine/Flags.lean` and `Machine/Alu.lean`: flag results and condition
    codes;
  - `Machine/Memory.lean`: little-endian reads and writes;
  - `Control/Decode.lean`, `Register.lean` (REX) and `Word.lean`;
  - `Machine/Sse.lean` (F9): the low 64 bits of xmm0-xmm15
    (`State.xmm`) and the scalar SSE instructions the compiler emits.

  These were written by hand from the Intel SDM. Here is what the model does
  not contain, so each of the following is assumed:
  - **Faults.** Pages are mapped and have the right permissions, addresses are
    canonical, alignment checking is off (AC), and nothing raises #GP or #PF.
    Model addresses wrap modulo 2^64. Every address the code touches must be
    mapped, and then it is also canonical.
  - **Concurrency.** There are no interrupts or signals that change state, no
    other thread or process writes to the image, stack or heap, and memory
    ordering is irrelevant because the program is single-threaded.
  - **Code fetch.** One byte map serves both code and data. The proofs keep
    the image apart from every write, so self-modifying code never comes up.
  - **Not modeled at all.** Segment bases, CET shadow stacks (the compiled code
    pairs every `call` with a `ret`), and the CPU being in 64-bit mode with
    default operand sizes.
  - **SSE (F9).** The meaning of each SSE instruction is `Lanius.IEEE`'s
    operation on the bits (section 3); that the CPU computes it is trusted:
    - `movd xmm, r32` and `movq xmm, r64` (66 [REX.W] 0F 6E /r) put the
      zero-extended register in the low 64 bits; `movd r32, xmm` writes the
      low 32 bits zero-extended, `movq r64, xmm` the low 64 (66 [REX.W] 0F
      7E /r);
    - `addss subss mulss divss` (F3 0F 58/5C/59/5E /r) replace the
      destination's low 32 bits by binary32 `add sub mul div` of the two low
      32-bit fields (destination first) and keep bits 32-63; the `sd` forms
      (F2) replace all 64 low bits by the binary64 operation;
    - `cmpss`/`cmpsd` (F3/F2 0F C2 /r ib) with predicates 0 (EQ_OQ), 1
      (LT_OS) and 2 (LE_OS) write all ones in the low 32 (single) or 64
      (double) bits when `eq`, `lt` or `le` holds, else zeros (false on a
      NaN); only these three predicates decode;
    - `cvtsi2ss`/`cvtsi2sd` (F3/F2 [REX.W] 0F 2A /r) round the signed 32-
      or 64-bit register (`ofInt`); `cvtss2sd` (F3 0F 5A) widens and
      `cvtsd2ss` (F2 0F 5A) rounds (`convert`);
    - the high 64 bits of each xmm register are not modeled: no modeled
      instruction reads them into the low half, so they cannot change a
      result;
    - MXCSR is not modeled. It is assumed to hold Linux's default at exec,
      0x1F80 (round to nearest, every exception masked, no flush to zero,
      no denormals as zero), which no compiled code changes; its sticky
      exception flags are set by the CPU and never read.
- **Encoders are proved, not trusted.** The literal bytes in `Compiler.lean`
  are proved equal to the `X86/Machine` encoders (`Instr.encode_eq`,
  `prologue_eq`). Those encoders are proved to decode to the intended
  instruction for every tail of following bytes. `decode` and `execute` remain
  trusted: they are the model's claim about what the CPU does.

## 7. One model run versus the CPU's run

- **What.** `compileSource_correct` and `compileProgram_correct` are
  existential: *some* model run `Steps n s s'` returns. `Step` is a relation,
  and it leaves these choices free:
  - AF after AND, OR, XOR and TEST;
  - every flag after IMUL, NEG, shifts, DIV and IDIV;
  - r11 after a `syscall` (`Kernel`, where Linux leaves RFLAGS);
  - the byte list it decodes, which may be any list loaded at `rip`.

  The CPU's run is generally a different model run from the one the
  proofs build: the CPU's free flags differ from `execute`'s choice.
- **Proved.** Every model run of the same length ends the same way:

  ```text
  compileProgram_deterministic (Mini/Determinism.lean), same premises as
  compileProgram_correct:
    ∃ n s', Steps n s s' ∧ Returned window s s' value after ∧
      ∀ t, Steps n s t → DataEq s' t ∧ Returned window s t value after
  ```

  `DataEq` is equality of the registers, rip, memory, the xmm registers'
  low halves and the process side (`io`), so only RFLAGS may differ. `compileSource_deterministic` and `linked_deterministic` are the
  same for `compileSource_correct` and `linked_correct`, and the process
  theorems carry `Det`.
- **Still assumed.** That the CPU's run is one of the model's runs (section
  6). The theorem covers runs of exactly `n` steps, the length of the run to
  the return; after `n` steps the code is back in the caller, and no shorter
  run stops (`Live`). It says nothing about longer runs.

## 8. Linux, and what the caller must provide

### A process: the loader, the start state and the system calls

For an executable from `elfFile`, the process theorems discharge every
obligation on the x86 state below from what Linux does. Trusted about Linux:

- **`Loaded` (`Mini/Process.lean`).** For a file with one program header, a
  loadable segment from file offset 0, `execve` leaves the segment's
  `p_filesz` file bytes (header offset 96) at `p_vaddr` (80), zeros after
  them up to `p_memsz` (104), and rip at `e_entry` (24). It reads those
  fields from the file's own bytes (`fieldAt`), so a wrong header could not
  make the theorem easier. Registers, flags and the rest of memory are
  arbitrary. `elfFile`'s segment is at 2^32, readable, writable and
  executable, and its `p_memsz` covers the stack and the heap.
- **`Exits`.** A `syscall` with rax 60 ends the process with status rdi, of
  which the parent sees the low byte. The model's `Kernel` has no exit
  case, so the theorems' runs stop there (`Exits.stuck`).
- **The kernel's `write` (`Kernel` in `X86/Machine/Scalar.lean`, roadmap
  F8).** The x86 model's only other `syscall` step (`Step.syscalled`) is
  this trusted meaning of Linux's `write`: with rax 1, rdi 1 or 2, and rdx at
  most `maxTransfer` (2,147,479,552, Linux's `MAX_RW_COUNT`), the call
  - writes all rdx bytes read from memory at rsi, recorded as the event
    `.write rdi bytes` appended to the state's trace (`State.io`,
    `X86/Machine/Io.lean`), and changes no memory;
  - returns rdx in rax, leaves the next instruction's address in rcx and
    rip, an unknown value in r11 (where Linux saves RFLAGS), and every other
    register, the xmm registers and RFLAGS as they were (`State.syscalled`).

  So it is trusted that fds 1 and 2 are open for writing when the process
  starts, that a write to them never fails, blocks forever or is partial
  (a pipe whose reader has gone raises SIGPIPE, a full disk gives ENOSPC,
  and a write to a terminal or pipe may in principle return short; none of
  these is modeled), and that no signal handler runs. Any other rax, fd or
  count has no step, so a run that reaches it stops, and the theorems say
  nothing past it. `Loaded` starts the trace empty, and `process_exits`
  says the trace at the exit is the compiled mini program's write trace,
  whose bytes on fds 1 and 2 (`outputOf`) are what Core's world gained on
  its standard output and error. Core's `write_byte`, `write_stdout` and
  `write_stderr` are lowered to this `write` (SEMANTIC_DECISIONS.md,
  "Externs and the runtime"); their Core meaning is `World.call`, part of
  Core's semantics (section 3).
- **The kernel's `read` (`Kernel.read`, roadmap F8).** The state's
  `io` also holds `input`, the bytes not yet read from standard input,
  and `readLimits`, how many bytes each read delivers. With rax 0, rdi 0
  and rdx at most `maxTransfer`, the call
  - delivers the first k bytes of `input` (`Io.readBytes`), written to
    memory from rsi on (`writeBytes`; no other byte changes), and drops
    them from `input` (`Io.afterRead`). k is rdx, or all that is left
    when fewer are left, and at most the next of `readLimits` plus one,
    which the call takes (past the end of the list there is no such bound);
  - returns k in rax, with rcx, rip, r11 and the other registers and
    RFLAGS as for `write`.

  So a read may deliver any k with 0 < k ≤ min(rdx, bytes left), as a
  terminal or a pipe may (a short read), and delivers 0 only when rdx is
  0 or the input is used up (`Io.readBytes_length`); every such k is the
  one some list delivers (`Io.readBytes_any`). The list is fixed when the
  process starts, as `input` is, and the theorems hold for every one, so
  they cover every way the reads may come: the run is determined by how
  many bytes each read delivered, and that sequence is a list. It is
  trusted that fd 0 is open for reading when the process starts, that a
  read never fails, never blocks forever and is never interrupted, and
  that a read delivering 0 means the input has ended (on a terminal, the
  end-of-file key ends it). Linux checks the buffer with `access_ok`
  before reading, and could return EFAULT for a range outside user space
  even when the file has no bytes left; the
  model assumes the call does not fault, and the verified compiler's
  buffers are inside its heap, whose end is below 2^62 (`HeapAt`). Core's
  `read_stdin` is lowered to this `read` (SEMANTIC_DECISIONS.md, "Host
  reads"). `Loaded` leaves `io` as the process was given it:
  `process_exits` takes it as a premise (`s.io = given`), with Core's world
  starting from the same streams (`startState given`).
- **The clocks' readings and the secure bytes are streams.** The
  state's `io` also holds `monotonic` and `realtime`, the readings
  (seconds, nanoseconds) the two clocks will give, one a read, and
  `entropy`, the random bytes `getrandom` will deliver. They are fixed
  when the process starts, like `input`, so a run's behaviour is a
  function of them; what Linux's clocks and random source actually give is
  some such stream, and the theorems hold for every one. Core's world
  starts from the same streams (`startState`: `monotonicReadings`,
  `systemReadings`, `secureByteStream`), and a Core run that reads past
  their end traps (`clockExhausted`, `entropyExhausted`), a trap the
  theorems say nothing about (`undefinedTrap`), since the kernel's streams
  do not end. `clock_gettime` and `getrandom` read them (below).
- **The kernel's `poll` with no fds (`Kernel.poll`, roadmap F8).**
  With rax 7, rdi 0 (no array), rsi 0 (no fds) and an rdx below 2^31 (a
  nonnegative `int` timeout in milliseconds), the call returns 0 in rax,
  changes no memory and no trace, and leaves rcx, rip, r11 and the other
  registers and RFLAGS as for `write`. Linux reads the timeout from the low
  32 bits of rdx; the compiled code passes a nonnegative `i32` held
  zero-extended, so the whole register is that value. So it is trusted that
  such a poll only waits (Linux's `do_sys_poll` with `nfds` 0 touches no
  user memory) and that no signal interrupts it (an interrupted poll
  returns EINTR, which the model does not have; the stdlib's sleep checks
  for 0 and would report failure, but the theorems do not cover it). How
  long it waits is not modeled: the x86 model has no clock. Core's
  `sleep_ms_i32` is lowered to this `poll` (SEMANTIC_DECISIONS.md, "Host
  sleep"); Core's world advances only its whole-second compatibility clock
  by the count, which no modeled call reads.
- **The kernel's `clock_gettime` (`Kernel.clock`, roadmap F8, 10-31).**
  With rax 228 and rdi 0 (`CLOCK_REALTIME`) or 1 (`CLOCK_MONOTONIC`), the
  call stores the next reading of that clock's stream (`Io.readings`:
  `monotonic` for 1, `realtime` for 0) from rsi on as a `struct timespec`,
  16 bytes, `tv_sec` then `tv_nsec`, each a little-endian 64-bit word
  (`timespecLE`), drops the reading (`Io.afterReading`), returns 0 in rax,
  and leaves rcx, rip, r11, the other registers and RFLAGS as for `write`.
  The compiled code passes a heap address with 16 bytes inside the heap
  (`add rsi, r12`). So it is trusted that `clock_gettime` of these two
  clocks into writable memory always succeeds (Linux returns EFAULT only
  for an address it cannot write, and EINVAL only for other clocks), that
  the seconds and nanoseconds it gives are some stream of readings fixed
  for the run (the code makes the system call itself, not the vDSO
  call). When the stream has no
  reading left the model has no step: such runs are outside the theorems,
  as Core's `clockExhausted` is.
- **The kernel's `getrandom` (`Kernel.getrandom`, roadmap F8, 10-31).**
  With rax 318, rsi (the count) at most 256, rdx 0 (no flags) and at
  least that many bytes left in `entropy`, the call stores the next count
  of them from rdi on, drops them, returns the count in rax, and leaves
  the other registers as for `write`. The compiled code asks for at most
  256 bytes at a time, to a heap address inside the heap (`add rdi,
  r12`). So it is trusted that such a `getrandom` returns every byte asked
  for and is not interrupted (Linux's documented guarantee for requests of
  at most 256 bytes once the entropy pool is initialized; before that the
  call blocks, which the model does not see), that it never fails on
  writable memory, and that the bytes it gives are some stream fixed for
  the run.
  No other system call is modeled (SEMANTIC_DECISIONS.md, "Externs and the
  runtime").
- The startup code sets rsp, r12 to r15, r10 (the heap's top), rbx (the
  frame pointer, at the heap's top) and r8 (the address of the static bytes,
  which the image holds after its code) and calls `entry` (the driver's
  convention is function 0, `main`), and `mov rdi, rax; mov eax, 60;
  syscall` follows the call. Its 95 bytes are proved, not trusted. The
  program header maps frame memory, as many bytes as the stack, above the
  heap: the heap's top is `heap + stack`. `entry` must take
  no parameters.
- **Linux's start state.** Registers other than those the startup code
  sets, flags and memory outside the segment are arbitrary (`Loaded`); fds
  0, 1 and 2 are open as above; MXCSR holds its default 0x1F80 (section 6);
  the operating system is as in "Operating system" below.

### Code entered another way: the caller's obligations

For code entered some other way (the theorems on `compileSource`,
`compileText`, `compileProgram` and the self-built compiler), the premises
are obligations on whatever sets up the x86 state. `compileSource_stops`
and `compileSource_behaviour` have them without `stackNeed depth ≤ window`,
and with a heap limit of at least 1.

- **Image.** `CodeAt s.memory imageBase binary.image`: the image is loaded
  byte for byte at any base and is executable. Its bytes are apart from the
  stack window and from the heap. The proofs then show that nothing writes to
  them.
- **Entry.** `s.rip = imageBase + entries[f]`. The function is entered by a
  near call, so the return address is at `[rsp]`.
- **Arguments.** Argument `k` is the 64-bit word at `rsp - (8k + 16)`, just
  below the return address. The results come back in the same slots, and the
  last one is also in rax. This is not the SysV convention, so a stub has to
  translate between the two.
- **Stack.**
  - r15 holds the stack limit, and the window is the stack from
    `binary.guard` bytes below r15 up to the return address (`StackAt`:
    `r15 + window = rsp + guard`, r15 above 4 GiB and at most 8 bytes above
    rsp). Its bytes must be mapped and writable, and they must be apart from
    the image. `binary.guard` is one frame plus 8 bytes: what a call writes
    (arguments, return address) before the callee's check.
  - Each prologue ends with `cmp r15, rsp; jbe +2; ud2`, so a frame that
    would end below r15 faults before it writes a slot. The contract of
    every function is therefore "returns, or the window is short of
    `binary.stackNeed depth` and the run stops at a fault"; with
    `binary.stackNeed depth ≤ window ≤ 2^62` it returns.
  - `depth` is existential in `compileSource_correct`, so nobody can compute
    the needed stack before the run.
- **Heap (`HeapAt`).**
  - The base is in r12, the cursor (an offset) in r13, the limit in r14 and
    the heap's top in r10, with `top < 2^62` (`HeapAt.small`).
  - The bytes at `r12 + a` for `a < top` are the heap: the bump heap below
    the limit, then frame memory. They are mapped,
    writable, and apart from the stack window, the return address and the
    image.
  - `compileSource_correct` also requires `r13 = 1` and zero bytes from
    offset 1 up, which a fresh anonymous mapping provides, and an empty
    write trace (`silent`: the state's trace, which `HeapAt` makes the mini
    heap's, has no events yet), so that the output it concludes equal to
    Core's world's is the code's own.
  - `compileProgram_correct` accepts any cursor.
  - rbx holds the frame pointer `fsp`, an offset from r12 like the cursor
    (`HeapAt.fsp`), at most the heap's top (`HeapAt.fspLe`). Frame memory
    is the bytes from `limit` up to the top in r10 (`HeapAt.top`); the
    startup code sets r10 and rbx to `heap + stack`.
  - **Static bytes.** r8 holds r12 plus the heap offset `staticBase` of the
    read-only static region (`HeapAt.static`; an offset that wraps around
    2^64 when the region is below r12, as the loader places it), and each of
    the heap's `statics` is in memory at r12 plus `staticBase` plus its
    index, apart from the stack window and the heap (`HeapAt.statics`). The
    process theorems' heap has the binary's `statics`, which the image holds
    after its code. r8 is kept across calls; a SysV caller's stub has to set
    it when the program has static bytes.
  - **Frame room.** The theorems on `compileSource` and `compileText` take
    `0 < sp.need f → limit + sp.need f ≤ fsp ∧ fsp ≤ top ∧ top < 2 ^ 62`:
    when the function run needs frame memory (`SrcProgram.need`, its own
    block for the arrays it passes as slices and the largest need of a
    function it calls; SEMANTIC_DECISIONS "Addressed locals", point 7), the
    frame pointer is that many bytes above the limit, at most the top (the
    blocks taken below it are below the top, so their stores reach them),
    and the top is below `2 ^ 62` (a block's addresses add without
    wrapping). The process theorems take `sp.need entry ≤ stack`, which gives
    it for the loader's layout (frame memory is as large as the stack, and
    the frame pointer starts at the top, `heap + stack`, below `2 ^ 41`). It
    holds for any heap when the need is 0, as it is when no function the run
    can reach passes an array as a slice; the self program's need is 0 at
    every function (`SelfPure.prog_need`, a kernel check over its bodies in
    `Faithful/Gen/SelfNeeds.lean`), so the self-built compiler's theorems do
    not take it.
- **Registers after the call.**
  - rsp is restored to `rsp + 8` and rbp is restored.
  - rax, rbx, rcx, rdx, rsi, rdi, r11 and r13 may change (the code writes rdx,
    rsi and rdi only for a `Sys` statement). Each call saves rbx in the
    caller's first result slot and loads it back after the return, so a
    callee need not keep it. r10 is kept (`Returned.top`: the callee's
    heap ends at the same top). rbx and r13 are callee-saved under SysV, so a
    SysV caller's stub has to save them. The stubs also save r12, r14 and
    r15, which they set, and must set r10 to the top of the region they hand
    over (r10 is caller-saved under SysV).
  - RFLAGS is unspecified. DF is never changed, and the code has no string
    instructions.
- **Memory.** Only the window and the heap change.
- **Operating system.** Linux maps memory as requested, saves and restores
  the full register state and RFLAGS across preemption and signal delivery,
  and no debugger or second thread changes the process. Linux enables CET
  shadow stacks only for programs that opt in. They are compatible with the
  compiled code anyway, because every `call` is paired with a `ret`.

## 9. Evidence

These test the assumptions above; none of them is part of the trusted base,
and a passing test proves nothing beyond its cases.

- **The x86 model against the CPU** (`formal/tools/x86_model_test.py`, gate
  step `x86-model`). Every instruction form the compiler emits (the Lean
  side prints `Instr.encode` for every constructor, `prologue` and
  `epilogue`; the tool fails on a byte it cannot place in its form table, so
  a new emitted form cannot go untested), on random registers, flags, DF,
  memory and immediates, with the SSE forms on edge float patterns under
  MXCSR 0x1F80. A stub runs the bytes natively with a landing pad at every
  possible next `rip`; Lean runs `decode` and `execute` on the same states.
  Compared: exact on the sixteen registers, `rip`, the xmm registers' low
  64 bits and the memory region; on the flag bits `Step` fixes; `decode`
  must return exactly the instruction's length, decode no shorter prefix,
  ignore a random tail and not decode as a division. On 10-31 (AMD Ryzen 9
  5900HX): 10,603 cases, 0 disagree. A deliberately wrong model is caught
  (CF flipped after `cmp`, ZF after `add`, rbx changed by `pop rbp`). It
  once found `88 /r` without REX decoded as a store of SPL..DIL, where the
  CPU stores AH..BH; `decode` now rejects it, and `--probes` checks that.
- **Core's IEEE operations against the CPU** (`formal/tools/float_test.py`,
  gate step `float`): `Lanius.IEEE`, compiled, against `addss`...`divsd`,
  `cmpss`/`cmpsd`, `xorps`, the conversions, libc's `strtof`/`strtod` and
  exact integer truncation, on edge patterns, ties, near operands and random
  bits: 79,214 cases, 0 differ.
- **Processes** (`formal/tools/elf_test.py`, gate step `elf`): executables
  from `elfFile` run natively: exit statuses, a division by zero
  (SIGFPE) and a stack too small for the recursion (SIGILL).
- **The compiler and the front end against laniusc**: `mini_difftest.py`
  (images from `#eval compileProgram` and the laniusc build, byte for
  byte), `fn_difftest.py` (each extracted function in Lean and natively),
  `oracle_difftest.py`, `frontend_difftest.py` (the front end against the
  generator's programs and the cases), `stdlib_oracle.py` and
  `programs_oracle.py` (compiled code against laniusc's on the stdlib and
  test programs).
- **The extraction** (gate step `extract`, `lani_extract.py --check`): the
  extracted Lean files are what the extractor in Lanius writes from
  laniusc's trees.
- **The self program and `B`**: gate step `self-current`
  (`faithful_current.py`) regenerates `Gen/` from the current sources and
  fails unless it is what is checked in, so `prog` is never stale; the
  certificates hold of every function of `prog` reachable from the driver's
  roots, so a reachable function printed with another meaning fails to
  check. Gate step `self-host-fixpoint` runs `B` natively on `self`: it
  returns exactly runAll's words for `self`, `B`'s own image byte for byte,
  so an error in Lean's compiled code for `compileText` would have to be one
  `B` itself reproduces.
- **This file** (gate step `trusted`): the axioms, statements and trusted
  definitions are the ones listed.

## 10. Not trusted

- The computations the theorems are about: `compileSource`, `compileText`,
  `compileProgram`, the optimizer inside them (its output is kept only when
  the proved validator accepts it), `compileModules`, `linkObjects`,
  `elfFile`, `sourceProgramFiles` and the front end's `build`,
  `compileWords`, `frontEndWords`, the self program `prog`, and
  `funcNeeds`, each function's need of frame memory. The theorems say what
  their results mean, whatever they are.
- laniusc's lexer and parser, and the parse trees they give (section 4).
- The encoders, the startup code's bytes and every proof file: the kernel
  checks them.
- The certificate generators (`faithful_certs.py`, `faithful_pure.py`) and
  the tests of section 9.
- The native harness stubs, except as the loader of section 5 when they are
  used that way.

Outside the verified compiler's theorems: the `&mut` pilot
(`Lanius/Mini/MutPilot.lean`, `MutPilotCorrect.lean`) and the state-machine
theorems (`Lanius/Machines/`) are about programs extracted by `extract.py`,
so they rest on its extraction (section 5) and, for the pilot, on laniusc's
exclusivity check of `&mut` arguments and their passing by address. No top
theorem depends on them.
