# C7000 Service Truck — Upstream Tracking

## Upstream Source

| Field | Value |
|-------|-------|
| **Vehicle** | GMC C7000 81-89 |
| **Author** | Canada FS (community-rebuilt model) |
| **Version** | v1.3.0.0 |
| **Last Synced** | 2026-02-21 |
| **Synced By** | Claude + Samantha (UsedPlus dev session) |

## Asset Status

All assets (binary + i3d) are **identical** to vanilla C7000 v1.3.
The only custom file is `serviceTruck.xml` (our vehicle config with CUSTOM sections).

| File | Status | Notes |
|------|--------|-------|
| `C7000.i3d` | **Identical** | Vanilla v1.3 (158,040 bytes) — replaced 2026-02-21 |
| `C7000.i3d.shapes` (55.9 MB) | Identical | v1.3 binary mesh data |
| `wheels/wheels1.i3d` + `.shapes` | Identical | v1.3 wheel models |
| All 32 DDS textures | Identical | v1.3 textures |
| `AmberWhiteAmber/*.i3d.shapes` | Identical | v1.3 beacon shapes |
| `vehicleShader.xml` | Normalized | Was CRLF, converted to LF |
| `AmberWhiteAmber/i3d/*.i3d` | Normalized | Was CRLF, converted to LF |
| ~~`service.i3d`~~ | **Deleted** | Was our custom addition; tanks already in C7000.i3d |
| ~~`service.i3d.shapes`~~ | **Deleted** | Was our custom addition; no longer needed |

**Note:** The vanilla C7000.i3d already includes oil tank, hydraulic tank, and all
service bed prop nodes at the same tree paths our XML references (`0>0|19|2`, `0>0|19|3`).
The community author built these directly into the model in v1.3.

## Custom Additions in serviceTruck.xml

Search for `CUSTOM:` in `serviceTruck.xml` to find all UsedPlus additions.

| # | Section | What's Custom | Removable? |
|---|---------|---------------|------------|
| 1 | **Store Data** | Price ($75K), dailyUpkeep ($50), showInStore=false, l10n keys | Yes — revert to vanilla values |
| 2 | **Fill Units 3-4** | Oil tank (200L) + Hydraulic tank (200L) for restoration | Yes — delete the two `<fillUnit>` entries |
| 3 | **door_service** | Opens ALL 6 service doors + laptop (on-foot trigger) | Yes — vanilla has single-door version |
| 4 | **door_service_fold** | Opens ALL 6 doors, NO laptop (X-key while driving) | Yes — not in vanilla |
| 5 | **Foldable** | X-key door control while driving | Yes — entire `<foldable>` section |
| 6 | **serviceTruck** | Restoration config: radius, consumption, fill unit mapping | Yes — entire `<serviceTruck>` section |
| 7 | **i3D Mappings** (4 nodes) | oilTank, oilExactFillRootNode, hydraulicTank, hydraulicExactFillRootNode | Yes — delete last 4 mappings |
| 8 | **Vehicle type** | `type="usedPlusServiceTruck"` (line 38) | Revert to vanilla type |

## i3D Model Notes

The C7000.i3d is **unmodified vanilla v1.3**. The community author (Canada FS) built
all service bed props directly into the model, including:
- Oil tank + oilExactFillRootNode (`0>0|19|2`)
- Hydraulic tank + hydraulicExactFillRootNode (`0>0|19|3`)
- Air tank, battery charger, bottle jack, oiler, fuel can, coolant bottles, laptop

Our i3D mappings (items #7 in the table above) reference nodes that exist natively
in the vanilla i3d — no custom nodes were added.

## Upgrade Checklist

When a new C7000 version is released (e.g., v1.4):

### 1. Compare Binary Assets
```bash
# Compare shapes files (should be byte-identical if unchanged)
diff <(xxd vanilla/C7000.i3d.shapes) <(xxd ours/C7000.i3d.shapes)
diff <(xxd vanilla/wheels/wheels1.i3d.shapes) <(xxd ours/wheels/wheels1.i3d.shapes)

# Compare textures
for f in textures/*.dds; do diff <(xxd "vanilla/$f") <(xxd "ours/$f"); done
```

### 2. Compare serviceTruck.xml
```bash
# Diff the XMLs — our CUSTOM: sections will show as additions
diff vanilla/serviceTruck.xml ours/serviceTruck.xml
```

Expect differences ONLY in sections marked `CUSTOM:`. If vanilla changed an `UPSTREAM:` section, merge their changes into our file while preserving our custom sections.

### 3. Compare C7000.i3d
```bash
# Our i3d should be identical to vanilla — straight copy
diff vanilla/C7000.i3d ours/C7000.i3d
```

If vanilla's i3d changed, just copy the new version over ours. We have no custom
i3d modifications — all our customization lives in `serviceTruck.xml`.

### 4. Update Tracking
- Update version in this file
- Update "Last Synced" date
- Re-verify asset status table
- Run `node tools/build.js` to verify clean build
- Test in-game: doors, tanks, restoration, workshop

## Path Prefix Note

Our paths use `vehicles/serviceTruck/` (mod-relative).
Vanilla C7000 uses `$moddir$` or plain relative paths.
When diffing XML files, ignore path prefix differences — they're structural, not functional.
