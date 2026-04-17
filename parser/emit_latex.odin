package cslparser

// § CSLv3 EMIT-LATEX BACKEND (T28.4 Session-10)
// I> article-class + listings-package + unicode-math macros for 74-glyphs
// I> morpheme annotations → \textsubscript{'d} style
// I> refinement → {v : T \mid \phi} math-rendered
// I> experimental : requires latexmk to compile to PDF (CI-optional)

import "core:fmt"
import "core:strings"

LATEX_STY_TEXT :: `% CSLv3 LaTeX Emit Style (latex-v1)
\ProvidesPackage{cslv3}[2026/04/16 CSLv3 style]
\RequirePackage{listings}
\RequirePackage{xcolor}
\RequirePackage{unicode-math}
\RequirePackage{amsmath}
\RequirePackage{hyperref}

\definecolor{cslkw}{HTML}{CC66CC}
\definecolor{cslop}{HTML}{FFCC66}
\definecolor{cslgl}{HTML}{FFFF88}
\definecolor{cslmo}{HTML}{66CCCC}
\definecolor{cslev}{HTML}{99CC66}
\definecolor{cslty}{HTML}{88CCFF}
\definecolor{cslcm}{HTML}{666666}

\lstdefinelanguage{csl}{
  basicstyle=\ttfamily\small,
  keywordstyle=\color{cslkw}\bfseries,
  commentstyle=\color{cslcm}\itshape,
  stringstyle=\color{cslev},
  morecomment=[l]{\#},
  morestring=[b]",
  showstringspaces=false,
  keepspaces=true,
  columns=fullflexible,
  upquote=true,
  literate=
    {§}{{\S}}1 {¶}{{\P}}1
    {≤}{{\ensuremath{\leq}}}1 {≥}{{\ensuremath{\geq}}}1
    {≠}{{\ensuremath{\neq}}}1 {→}{{\ensuremath{\to}}}1
    {←}{{\ensuremath{\leftarrow}}}1 {↔}{{\ensuremath{\leftrightarrow}}}1
    {∧}{{\ensuremath{\land}}}1 {∨}{{\ensuremath{\lor}}}1
    {¬}{{\ensuremath{\neg}}}1 {∀}{{\ensuremath{\forall}}}1
    {∃}{{\ensuremath{\exists}}}1 {∈}{{\ensuremath{\in}}}1
    {⊆}{{\ensuremath{\subseteq}}}1 {⊂}{{\ensuremath{\subset}}}1
    {∪}{{\ensuremath{\cup}}}1 {∩}{{\ensuremath{\cap}}}1
    {⇒}{{\ensuremath{\Rightarrow}}}1 {∵}{{\ensuremath{\because}}}1
    {∴}{{\ensuremath{\therefore}}}1 {⊗}{{\ensuremath{\otimes}}}1
    {⊕}{{\ensuremath{\oplus}}}1 {⊑}{{\ensuremath{\sqsubseteq}}}1
    {⊔}{{\ensuremath{\sqcup}}}1 {⊓}{{\ensuremath{\sqcap}}}1
    {✓}{{\checkmark}}1 {✗}{{\ensuremath{\times}}}1
    {◐}{$\bullet$}1 {○}{$\circ$}1
    {⟨}{{\ensuremath{\langle}}}1 {⟩}{{\ensuremath{\rangle}}}1
    {⌈}{{\ensuremath{\lceil}}}1 {⌉}{{\ensuremath{\rceil}}}1
    {⟦}{{\ensuremath{\llbracket}}}1 {⟧}{{\ensuremath{\rrbracket}}}1
    {«}{{\ensuremath{\langle\!\langle}}}2 {»}{{\ensuremath{\rangle\!\rangle}}}2
}

\newcommand{\cslmorph}[1]{\textsubscript{\color{cslmo}\textquotesingle #1}}
\newcommand{\cslmodal}[1]{\textcolor{cslkw}{\textbf{#1}}}
\newcommand{\cslref}[2]{\hyperref[#1]{#2}}
`

emit_latex :: proc(ctx: ^Emit_Context) -> string {
    sb := strings.builder_make()
    standalone := ctx.config.standalone

    strings.write_string(&sb, "% schema: latex-v1\n")
    if standalone {
        strings.write_string(&sb, "\\documentclass[11pt]{article}\n")
        strings.write_string(&sb, "\\usepackage{cslv3}\n")
        strings.write_string(&sb, "\\usepackage[margin=1in]{geometry}\n")
        strings.write_string(&sb, "\\usepackage{xunicode}\n")
        strings.write_string(&sb, "\\usepackage{xltxtra}\n")
        title := derive_title_tex(ctx.source_file)
        // Note : Odin's fmt.tprintf treats `{...}` as verb syntax, so we
        // cannot use `\title{%s}` as a format string. Write in parts.
        strings.write_string(&sb, "\\title{")
        strings.write_string(&sb, tex_escape(title))
        strings.write_string(&sb, "}\n")
        strings.write_string(&sb, "\\author{CSLv3 auto-emit}\n")
        strings.write_string(&sb, "\\date{\\today}\n\n")
        strings.write_string(&sb, "\\begin{document}\n")
        strings.write_string(&sb, "\\maketitle\n")
        strings.write_string(&sb, "\\tableofcontents\n\n")
    }

    if ctx.ast_root != nil {
        for c in ctx.ast_root.children do emit_tex_node(&sb, c, 1)
    } else {
        emit_tex_listing(&sb, ctx.source_text)
    }

    if standalone {
        strings.write_string(&sb, "\n\\end{document}\n")
    }
    return strings.to_string(sb)
}

@(private="file")
derive_title_tex :: proc(path: string) -> string {
    last := strings.last_index_any(path, "/\\")
    stem := path if last < 0 else path[last+1:]
    if dot := strings.last_index(stem, "."); dot > 0 do stem = stem[:dot]
    return stem
}

@(private="file")
emit_tex_node :: proc(sb: ^strings.Builder, n: ^Node, level: int) {
    if n == nil do return
    #partial switch n.kind {
    case .Section:
        cmd: string
        switch level {
        case 1: cmd = "section"
        case 2: cmd = "subsection"
        case 3: cmd = "subsubsection"
        case:   cmd = "paragraph"
        }
        label := tex_label(n.text)
        // Odin fmt treats `{...}` as verb braces ; emit in parts.
        strings.write_byte(sb, '\\')
        strings.write_string(sb, cmd)
        strings.write_byte(sb, '{')
        strings.write_string(sb, tex_escape(n.text))
        strings.write_string(sb, "}\\label{")
        strings.write_string(sb, label)
        strings.write_string(sb, "}\n")
        for c in n.children do emit_tex_node(sb, c, level + 1)
    case .Comment:
        strings.write_string(sb, "\\begin{quote}\\textit{\\# ")
        strings.write_string(sb, tex_escape(n.text))
        strings.write_string(sb, "}\\end{quote}\n")
    case .Document:
        for c in n.children do emit_tex_node(sb, c, level)
    case:
        emit_def_as_tex(sb, n)
    }
}

@(private="file")
emit_def_as_tex :: proc(sb: ^strings.Builder, n: ^Node) {
    csb := strings.builder_make(context.temp_allocator)
    pprint_doc_with_mode(n, &csb, .Canonical)
    s := strings.trim_space(strings.to_string(csb))
    if len(s) == 0 do return
    emit_tex_listing(sb, s)
}

@(private="file")
emit_tex_listing :: proc(sb: ^strings.Builder, s: string) {
    strings.write_string(sb, "\\begin{lstlisting}[language=csl]\n")
    strings.write_string(sb, s)
    if !strings.has_suffix(s, "\n") do strings.write_byte(sb, '\n')
    strings.write_string(sb, "\\end{lstlisting}\n")
}

@(private="file")
tex_escape :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        switch c {
        case '\\': strings.write_string(&sb, "\\textbackslash{}")
        case '&':  strings.write_string(&sb, "\\&")
        case '%':  strings.write_string(&sb, "\\%")
        case '$':  strings.write_string(&sb, "\\$")
        case '#':  strings.write_string(&sb, "\\#")
        case '_':  strings.write_string(&sb, "\\_")
        case '{':  strings.write_string(&sb, "\\{")
        case '}':  strings.write_string(&sb, "\\}")
        case '~':  strings.write_string(&sb, "\\textasciitilde{}")
        case '^':  strings.write_string(&sb, "\\textasciicircum{}")
        case:      strings.write_rune(&sb, c)
        }
    }
    return strings.to_string(sb)
}

@(private="file")
tex_label :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    strings.write_string(&sb, "sec:")
    for c in s {
        if c >= 'A' && c <= 'Z' do strings.write_rune(&sb, c + 32)
        else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') do strings.write_rune(&sb, c)
        else if c == ' ' || c == '_' || c == '-' do strings.write_byte(&sb, '-')
    }
    return strings.to_string(sb)
}
