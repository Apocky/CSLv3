package cslparser

// § A8 Session-15 : AST → Pike-VM bytecode compiler.
//
// I> Pike-VM instruction set (Cox 2007 "Regular Expression Matching :
//    the Virtual Machine Approach") :
//       CHAR r         advance if rune at ip matches r (consume 1 rune)
//       CLASS ^class   match rune against class descriptor (consume)
//       ANY            match any rune except \n (consume)
//       MATCH          report success (fire captures etc.)
//       JMP x          unconditional jump to program[x]
//       SPLIT x y      fork thread to x and y (both execute)
//       SAVE n         record current input pos into slot n
//       ANCHOR k       zero-width assert ^ $ \b \B
//       BACKREF g      match literal contents of capture group g
//
// I> SAVE slots : two per group (even = start, odd = end) ; group 0 is
//    the whole match.

// ------------------------- bytecode types -------------------------

Re_Op :: enum u8 {
    Char,
    Class,
    Any_Char,     // .  (no \n)
    Match,
    Jmp,
    Split,
    Save,
    Anchor,
    Backref,
}

Anchor_Kind :: enum u8 {
    BOS,    // ^
    EOS,    // $
    BOW,    // \b
    NBOW,   // \B
}

Re_Instr :: struct {
    op:    Re_Op,
    rune_val: rune,
    x, y:  int,                    // jump targets for Jmp / Split
    slot:  int,                    // for Save
    anchor: Anchor_Kind,            // for Anchor
    class: ^Char_Class,             // for Class
    backref: int,                   // for Backref (1-based group)
}

// Compiled program + metadata.
Regex_Program :: struct {
    code:       [dynamic]Re_Instr,
    n_groups:   int,                 // count of capturing groups
    group_names: [dynamic]string,    // parallel to group index ; 0 = ""
}

// ------------------------- compiler -------------------------

regex_compile_ast :: proc(root: ^Re_Node, group_names: []string, allocator := context.allocator) -> Regex_Program {
    context.allocator = allocator
    prog := Regex_Program{}
    for name in group_names do append(&prog.group_names, name)
    prog.n_groups = len(group_names) - 1     // subtract index-0 sentinel
    compile_walk(&prog, root)
    emit(&prog, Re_Instr{ op = .Match })
    // Wrap in SAVE 0 / SAVE 1 for whole-match capture : we prepend SAVE 0,
    // append SAVE 1 + MATCH. The SAVE 1 must go BEFORE MATCH, and SAVE 0 at
    // the start. Easier : patch after the fact.
    patch_whole_match_saves(&prog)
    return prog
}

@(private="file")
emit :: proc(prog: ^Regex_Program, ins: Re_Instr) -> int {
    append(&prog.code, ins)
    return len(prog.code) - 1
}

@(private="file")
compile_walk :: proc(prog: ^Regex_Program, n: ^Re_Node) {
    if n == nil do return
    switch n.kind {
    case .Lit:
        emit(prog, Re_Instr{ op = .Char, rune_val = n.rune_val })
    case .AnyChar:
        emit(prog, Re_Instr{ op = .Any_Char })
    case .CharClass:
        emit(prog, Re_Instr{ op = .Class, class = n.class })
    case .Anchor_BOS:  emit(prog, Re_Instr{ op = .Anchor, anchor = .BOS })
    case .Anchor_EOS:  emit(prog, Re_Instr{ op = .Anchor, anchor = .EOS })
    case .Anchor_BOW:  emit(prog, Re_Instr{ op = .Anchor, anchor = .BOW })
    case .Anchor_NBOW: emit(prog, Re_Instr{ op = .Anchor, anchor = .NBOW })
    case .Concat:
        for c in n.children do compile_walk(prog, c)
    case .Alt:
        // For each non-final child :
        //   SPLIT x=left y=right
        //   left   :   <child>   JMP end
        //   right  :   <next alt or final child>
        //   end    :
        // The .x direction is tried first (leftmost-first priority).
        if len(n.children) == 0 do return
        if len(n.children) == 1 {
            compile_walk(prog, n.children[0])
            return
        }
        jmp_pcs: [dynamic]int
        for child, i in n.children {
            if i + 1 < len(n.children) {
                split_pc := emit(prog, Re_Instr{ op = .Split })
                // left branch begins immediately after SPLIT
                left_start := len(prog.code)
                compile_walk(prog, child)
                jmp_pc := emit(prog, Re_Instr{ op = .Jmp })
                append(&jmp_pcs, jmp_pc)
                // right branch begins now ; patch split
                right_start := len(prog.code)
                prog.code[split_pc].x = left_start   // higher-priority : try left first
                prog.code[split_pc].y = right_start
            } else {
                // final branch : compile in place ; the last SPLIT's y
                // already points here.
                compile_walk(prog, child)
            }
        }
        end_pc := len(prog.code)
        for j in jmp_pcs do prog.code[j].x = end_pc
    case .Repeat:
        compile_repeat(prog, n)
    case .Group:
        // SAVE 2*idx ; child ; SAVE 2*idx + 1
        emit(prog, Re_Instr{ op = .Save, slot = 2 * n.group_idx })
        for c in n.children do compile_walk(prog, c)
        emit(prog, Re_Instr{ op = .Save, slot = 2 * n.group_idx + 1 })
    case .NonCaptGroup:
        for c in n.children do compile_walk(prog, c)
    case .Backref:
        emit(prog, Re_Instr{ op = .Backref, backref = n.backref })
    }
}

@(private="file")
compile_repeat :: proc(prog: ^Regex_Program, n: ^Re_Node) {
    // Strategy :
    //   {n,m}   : emit child n times, then (m-n) optional copies
    //   {n,}    : emit child n times, then greedy/lazy * at the end
    //   {n,n}   : emit child n times
    //   *  +  ? : handled as special {0,-1} / {1,-1} / {0,1}
    child := n.children[0]
    lo := n.lo
    hi := n.hi
    for _ in 0 ..< lo do compile_walk(prog, child)
    if hi == -1 {
        // infinite trailing : SPLIT-loop
        //   L1: SPLIT Lbody Lend     (lazy → SPLIT Lend Lbody)
        //   Lbody: child
        //         JMP L1
        //   Lend:
        split_pc := emit(prog, Re_Instr{ op = .Split })
        body_pc := len(prog.code)
        compile_walk(prog, child)
        emit(prog, Re_Instr{ op = .Jmp, x = split_pc })
        end_pc := len(prog.code)
        if n.lazy {
            prog.code[split_pc].x = end_pc
            prog.code[split_pc].y = body_pc
        } else {
            prog.code[split_pc].x = body_pc
            prog.code[split_pc].y = end_pc
        }
    } else {
        // optional copies up to hi - lo
        split_pcs: [dynamic]int
        for _ in 0 ..< (hi - lo) {
            split_pc := emit(prog, Re_Instr{ op = .Split })
            compile_walk(prog, child)
            append(&split_pcs, split_pc)
        }
        end_pc := len(prog.code)
        for sp in split_pcs {
            body_after_split := sp + 1
            if n.lazy {
                prog.code[sp].x = end_pc
                prog.code[sp].y = body_after_split
            } else {
                prog.code[sp].x = body_after_split
                prog.code[sp].y = end_pc
            }
        }
    }
}

@(private="file")
patch_whole_match_saves :: proc(prog: ^Regex_Program) {
    // Prepend SAVE 0 and insert SAVE 1 before the terminating MATCH.
    old := prog.code[:]
    new_code := make([dynamic]Re_Instr, 0, len(old) + 2)
    append(&new_code, Re_Instr{ op = .Save, slot = 0 })
    for ins in old[:len(old) - 1] {
        // Shift jump targets +1.
        shifted := ins
        if shifted.op == .Jmp || shifted.op == .Split {
            shifted.x += 1
            if shifted.op == .Split do shifted.y += 1
        }
        append(&new_code, shifted)
    }
    append(&new_code, Re_Instr{ op = .Save, slot = 1 })
    append(&new_code, Re_Instr{ op = .Match })
    delete(prog.code)
    prog.code = new_code
}
