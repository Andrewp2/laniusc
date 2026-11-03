# FrontEndStmtDepth

- 11-03 (leafB): stated for PreCompileWords.red3. `SrcStmt.depth` is the compiler's own measure
  (`Compiler/P/arrayCallSig.lean`); lowering hands out let slots from `next` along it, so a function's
  slot numbers are its params plus its depth plus its temporaries. Rejected forms:
  - `sz p <= A * W.length + B` for the whole program: false (monomorphization copies bodies).
  - The same per function: false (a wildcard arm is copied once per variant it covers, and nested
    wildcard matches multiply the copies).
  - A generated statement depth (every SrcStmt node counted): false at this bound, because a match
    over v variants is a chain of v `matchArm`s, and nesting k of them gives a depth of k * v from
    O(k + v) words. `depth` takes the max over a match arm's body and the rest, so it does not grow with
    the chain.
- 11-03 (leafA): unused; replaced by FrontEndStmtDepthV2 (`depth <= 2 ^ 40`, from the front end's depth check in
  `untyped_rejected`). PreCompileWords.red4 uses V2. Proving this one needs a W-linear simulation through
  monomorphization and match lowering.
