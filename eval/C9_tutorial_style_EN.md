# Tutorial — Your First Spec

## Before You Start

This tutorial walks you through writing your first CSLv3 specification. You will need a recent build of the reference parser, a text editor that can save files as UTF-8, and roughly twenty minutes. Prior experience with a typed programming language helps but is not required. By the end you will have a working specification file that parses, type-checks, and pretty-prints cleanly.

## Hello, Spec

Open your editor and create a new file called hello.csl. Paste the following content into the file and save it.

The first line declares a section. Section declarations in CSLv3 use the glyph named section-sign. You can type this glyph directly if your keyboard supports it, or you can use the ASCII alias which the parser accepts as equivalent. Everything inside a section is indented relative to the section header, and the section ends when the indentation level drops back below the header.

Inside your first section, add a second-level section that declares a simple data type. The type declaration syntax will feel familiar if you have written in any of the ML-family languages. A type name on the left, an equals sign, and a type expression on the right.

## Run the Parser

Once you have written the file, run the parser against it from your shell. The parser prints either a clean parse confirmation or a list of diagnostics. For a first file, the diagnostics are usually about indentation mismatches, so read each diagnostic carefully and check the line number it references.

If your file parses cleanly, try adding a pretty-print command to the parser invocation. The pretty-printer has several modes. The canonical mode is the one you will use most often. It reformats your file to the project-standard layout and preserves the meaning of your original exactly. Passing your file back through the pretty-printer should produce the same text you started with (barring trivial whitespace normalization), which is a useful sanity check.

## Add a Function

Now extend your spec with a function declaration. Functions in CSLv3 are written with a name, a parameter list, a return type, and optionally a body. For this tutorial, leave the body absent. The parser will still accept a function signature without a body, which lets you sketch an interface before committing to an implementation.

Try running the parser again. You should see the function in the output of the pretty-printer, formatted consistently with the rest of your file. If the function fails to parse, check that you have the arrow glyph in the right position and that your parameter types are separated by commas.

## Explore the Diagnostics

Intentionally introduce an error. Change a type name to something that does not exist, or remove the equals sign from a declaration. Run the parser with the strict flag and observe how the diagnostic changes. The strict flag promotes warnings to errors and causes the parser to exit with a non-zero status code, which is what you want for continuous integration.

## Where to Go Next

The reference corpus in the eval directory contains seven small specifications that exercise the full range of notation features. Read through them in order from C1 to C7. Each one is paired with an English translation in a neighboring file, which will help if any of the glyphs are unfamiliar.

Once you are comfortable with the notation, look at the parser decisions log for the reasoning behind non-obvious design choices, and the specs directory for the formal grammar and tokenizer tables.

## Good Luck

Notation is a tool, not a destination. Use it where it helps and write plain English where it does not. The parser accepts both.
