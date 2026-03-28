/*=============================================================================
  Diesel Generator Configurator — ASCII Graphics Library
  generator_graphics.pl

  All diagrams are stored as facts:
    diagram_lines(DiagramName, [Line1, Line2, ...])

  Public interface (called by menu(6) and the presentation layer):
    diagram(+Name)       — print a named diagram
    list_diagrams/0      — list all available diagram names

  To add a new diagram:
    1. Add a diagram_lines/2 fact with a unique name atom and line list.
    2. Add the call to menu(6) in generator.pl.
    Nothing else changes.

  Encoding note:
    This file uses plain ASCII only (+-|) for maximum terminal compatibility,
    including Windows cmd.exe and MSYS. No Unicode box-drawing characters.
=============================================================================*/

:- module(generator_graphics, [
    diagram/1,
    list_diagrams/0
]).

/*-----------------------------------------------------------------------------
  Diagram: single_line
  Shows the main single-line electrical diagram:
    Generator (G) — Main Breaker — Switchboard
    Controller block below the breaker
-----------------------------------------------------------------------------*/

diagram_lines(single_line, [
    "",
    "  SINGLE-LINE DIAGRAM — Diesel Generator System",
    "  -----------------------------------------------",
    "",
    "     +------+        +----------+      +----------+",
    "    /        \\       |   MAIN   |      |   LV     |",
    "   |    G     |------| BREAKER  |------|  SWBD    |",
    "    \\        /       |          |      |  =BGA    |",
    "     +------+        +----------+      +----------+",
    "                          |",
    "                          |",
    "                    +----------+",
    "                    |          |",
    "                    |  CTRL    |",
    "                    |          |",
    "                    +----------+",
    ""
]).

/*-----------------------------------------------------------------------------
  Diagram: genset_components
  Shows the internal breakdown of the genset block.
-----------------------------------------------------------------------------*/

diagram_lines(genset_components, [
    "",
    "  GENSET — Internal Components",
    "  ------------------------------",
    "",
    "  +--------------------------------------------------+",
    "  |  GENSET                                          |",
    "  |                                                  |",
    "  |   +-----------+          +-------------+         |",
    "  |   |           |          |             |         |",
    "  |   |  ENGINE   |~~~~~~~~~~| ALTERNATOR  |         |",
    "  |   |           |  (shaft) |             |         |",
    "  |   +-----------+          +-------------+         |",
    "  |        |                        |                |",
    "  |   +-----------+          +-------------+         |",
    "  |   |  COOLING  |          |   AVR /     |         |",
    "  |   |  SYSTEM   |          |  EXCITATION |         |",
    "  |   +-----------+          +-------------+         |",
    "  |                                                  |",
    "  |   +----------+    +----------+   +-----------+   |",
    "  |   |  LUBE    |    |  SPEED   |   | BASE      |   |",
    "  |   |  SYSTEM  |    |  GOV     |   | FRAME     |   |",
    "  |   +----------+    +----------+   +-----------+   |",
    "  |                                                  |",
    "  +--------------------------------------------------+",
    ""
]).

/*-----------------------------------------------------------------------------
  Diagram: def_system
  Shows the DEF (Diesel Exhaust Fluid) system layout.
-----------------------------------------------------------------------------*/

diagram_lines(def_system, [
    "",
    "  DEF SYSTEM — Diesel Exhaust Fluid",
    "  ------------------------------------",
    "",
    "  +-----------+     +-----------+     +-----------+",
    "  |           |     |           |     |           |",
    "  | DEF MAIN  |---->| DEF DAY   |---->| DEF PUMP  |",
    "  |   TANK    |     |   TANK    |     |           |",
    "  |           |     |           |     |           |",
    "  +-----------+     +-----------+     +-----+-----+",
    "                                            |",
    "                                            | dosing",
    "                                            v",
    "                                      +-----+-----+",
    "                                      |           |",
    "                                      | SCR UNIT  |",
    "                                      |           |",
    "                                      +-----------+",
    "                                            |",
    "                                            v",
    "                                       (exhaust out)",
    ""
]).

/*=============================================================================
  Public predicates
=============================================================================*/

%  diagram(+Name)
%  Print the named diagram. Fails with a clear message if name unknown.
diagram(Name) :-
    (   diagram_lines(Name, Lines)
    ->  forall(member(Line, Lines), format("~w~n", [Line]))
    ;   format("~n  Unknown diagram: ~w~n", [Name]),
        format("  Use list_diagrams. to see available diagrams.~n~n", []),
        fail
    ).

%  list_diagrams/0
%  Print all available diagram names.
list_diagrams :-
    format("~n  Available diagrams:~n", []),
    forall(
        diagram_lines(Name, _),
        format("    diagram(~w).~n", [Name])
    ).