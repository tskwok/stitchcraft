# StitchCraft

Theatre costume measurement app: one self-contained file, `index.html` (HTML + CSS + JS, no build step).
Open it in a browser to run it. Originally published as a claude.ai artifact.

## Data
- localStorage key `stitchcraft-v2` = `{productions:[], members:[]}`.
- Production: `{id,name,website,poster,director,stageManager,producers,props,costumeTeam,setTeam,publicity,runStart,runEnd,fields:[{id,name,type,options,note,off?}],hidden:[]}` (`hidden` = `data-k` keys of cast-form fields switched off for this production; `off:true` on a production-specific field switches it off)
- Member: every `data-k` form value + `unit`, `id`, `productionId`, `cv:{fieldId:{value,comment}}`.
- Data lives only in the browser; there is no backend.

## Views
`#vHome` production list; `#vProd` production info, cast list, import/export; `#vFields` "Cast Page Fields" (reached from the Cast Members section; one switch per cast-form field, plus the production-specific measurements last); `#vCast` cast form (General Information, Ready to Wear Sizing, Body Measurements, Production Specific Measurements, Additional Information; headings carry no section numbers).

## Key code (search for these)
- Storage: `loadDB/saveDB/normProd`
- Cast form: `read()/fill()/saveCast()`, `setUnit/calc/footCalc`, `wrapLabels` (runs once; wraps label text in `.lt`), auto save `scheduleSave()/flushSave()` (saves 0.8 s after a change, on field change, on leaving the page and on the back button, once the cast member has a name) with `snap()/dirty()` tracking what is saved; `#asState` shows the status
- Cast page fields: `FMAP` is built from the cast form DOM by `buildFieldMap()` (so new `data-k` fields appear automatically; Name is locked on); `applyFieldVisibility()` hides switched-off fields, empty rows and empty sections (hidden data is kept and still saved; hidden fields drop out of print/PDF); `renderFieldsPage()` draws the switches, copying each field's "i" guide button (`data-g`) from the cast form. The production-specific measurement builder lives only on the Cast Page Fields page (`#fgBuild`/`#fgAdd`, one show/hide switch per row), built by `fieldRows()`/`renderFields()`/`bindBuilder()` from `BLDS`.
- Number validation: one `change` handler on `#vCast` for inputs with `min="0"` (`isMeasure`)
- Measurement guide ("i" buttons): `GSVG`/`GTXT` arrays (index = position in `BODY`, or the entry's third element; 14 = Shoulder To Wrist, 15 = Waist To Floor) + base64 silhouette masks in CSS (`.sF`, `.sM`)
- Import / export (bottom bar of `#vProd`): `#pExp` writes `{app:"stitchcraft",version,productions:[one],members}` as JSON via `saveFile()`; `importData()` copies productions in with fresh ids, text-only values and `data:image` pictures only.
- PDF export: `pdfData/pdfBuild`, jsPDF 2.5.1 loaded lazily from cdnjs. Print uses `buildPrint()` + `#pSheet` with the same layout.
- The artifact `downloads` capability saves the PDF when hosted on claude.ai; outside it, the code falls back to `doc.save()`.

## Rules to keep
- Body Measurements (`#body`) is split into Head / Body / Arms / Legs blocks (`.reg`, each a sub-heading plus rows); the Cast Page Fields page, print sheet and PDF follow the same split. Body Measurements inputs are positive decimals only. Shoulder-to-Wrist is calculated (Nape To Wrist minus Nape To Shoulder). Nape To Floor is calculated (Nape To Waist plus Waist To Floor); a Nape To Floor saved before Waist To Floor existed is used to back-fill Waist To Floor on open. Pant Waist, Pant Inseam, Height in feet and every numeric production-specific measurement (Type and Number) must also be greater than 0. Other measurement inputs reject negatives. Hat is a text box (fractions and letter sizes allowed) that rejects negative and zero numbers. Validate on `change`, not on each keystroke.
- Field names use Title Case (custom names are converted by `titleCase()` when the field is left). Run end date must not be before start.
- Keep it a single file with light/dark theme CSS variables.
- Labels wrap; never shrink label text to fit. Tap targets stay at about 40px.
- Toggles set `aria-pressed`; `show()` moves focus to the view's `[data-vf]` heading; repeated row buttons get an `aria-label` naming their row.
- Unreadable saved data is copied to `stitchcraft-v2-unreadable-<timestamp>` before the app starts empty.
- Import never overwrites: it always adds a new production (name gets " (Imported)" if it clashes).
- Never use `confirm()`/`alert()`/`prompt()`: they are blocked in a claude.ai artifact. Use `ask(text, okLabel)` (in-page `#aDlg`, returns a Promise). The Print button is hidden when `window.claude` exists because artifacts cannot print.
- File downloads go through `saveFile()` / the `downloads` capability; plain download links do nothing in an artifact.
