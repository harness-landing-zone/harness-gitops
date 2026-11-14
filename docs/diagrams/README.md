# Diagrams

One idea per file. Open and edit them in Draw.io (desktop or app.diagrams.net).

| File | Shows | Used by |
|---|---|---|
| `people-and-ownership.drawio` | The three actors and what each owns, by where it lives | [People and ownership](../people-and-ownership.md) |

## Colours

Colour always means the owner, never the technology.

| Meaning | Fill | Border |
|---|---|---|
| Platform team | `#dae8fc` | `#6c8ebf` |
| Tenant | `#d5e8d4` | `#82b366` |
| Team | `#ffe6cc` | `#d79b00` |
| A place: Harness, Git, a cluster | `#f5f5f5` | `#666666` |
| Open: not built or not decided | white | `#b85450`, dashed, text in the same red |

## Shapes

| Shape | Meaning |
|---|---|
| Stick figure | An actor |
| Rounded box | A thing somebody owns |
| Square-cornered grey box | A place where things live |
| Dashed grey outline | A grouping with no meaning of its own, such as an actor's row |
| Solid arrow | Creates or changes |
| Dashed arrow | Reads, or connects to |

## Keeping them reviewable in git

Save every file uncompressed, so a change shows as readable XML in a diff:
in Draw.io, File > Properties, untick Compressed.
