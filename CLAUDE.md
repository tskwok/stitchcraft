# StitchCraft

Theatre costume measurement app: one self-contained file, `index.html` (HTML + CSS + JS, no build step).
Open it in a browser to run it. Originally published as a claude.ai artifact.

## Data
- localStorage key `stitchcraft-v2` = `{productions:[], members:[]}`.
- Production: `{id,name,website,poster,director,stageManager,producers,props,costumeTeam,setTeam,publicity,runStart,runEnd,fields:[{id,name,type,options,note}]}`
- Member: every `data-k` form value + `unit`, `id`, `productionId`, `cv:{fieldId:{value,comment}}`.
- Data lives only in the browser; there is no backend.

## Views
`#vHome` production list; `#vProd` production info, production-specific measurement builder, cast list, import/export; `#vCast` cast form (Sections 1-5).

## Key code (search for these)
- Storage: `loadDB/saveDB/normProd`
- Cast form: `read()/fill()/saveCast()`, `setUnit/calc/footCalc`, `wrapLabels` (runs once; wraps label text in `.lt`), unsaved-changes guard `snap()/dirty()`
- Number validation: one `change` handler on `#vCast` for inputs with `min="0"` (`isMeasure`)
- Measurement guide ("i" buttons): `GSVG`/`GTXT` arrays + base64 silhouette masks in CSS (`.sF`, `.sM`)
- Import / export (bottom bar of `#vProd`): `#pExp` writes `{app:"stitchcraft",version,productions:[one],members}` as JSON via `saveFile()`; `importData()` copies productions in with fresh ids, text-only values and `data:image` pictures only.
- PDF export: `pdfData/pdfBuild`, jsPDF 2.5.1 loaded lazily from cdnjs. Print uses `buildPrint()` + `#pSheet` with the same layout.
- The artifact `downloads` capability saves the PDF when hosted on claude.ai; outside it, the code falls back to `doc.save()`.

## Rules to keep
- Section 3 inputs are positive decimals only. Shoulder-to-Wrist is calculated. Other measurement inputs reject negatives. Validate on `change`, not on each keystroke.
- Field names use Title Case (custom names are converted by `titleCase()` when the field is left). Run end date must not be before start.
- Keep it a single file with light/dark theme CSS variables.
- Labels wrap; never shrink label text to fit. Tap targets stay at about 40px.
- Toggles set `aria-pressed`; `show()` moves focus to the view's `[data-vf]` heading; repeated row buttons get an `aria-label` naming their row.
- Unreadable saved data is copied to `stitchcraft-v2-unreadable-<timestamp>` before the app starts empty.
- Import never overwrites: it always adds a new production (name gets " (Imported)" if it clashes).
- Never use `confirm()`/`alert()`/`prompt()`: they are blocked in a claude.ai artifact. Use `ask(text, okLabel)` (in-page `#aDlg`, returns a Promise). The Print button is hidden when `window.claude` exists because artifacts cannot print.
- File downloads go through `saveFile()` / the `downloads` capability; plain download links do nothing in an artifact.
