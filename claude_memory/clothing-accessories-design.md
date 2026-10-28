---
name: clothing-accessories-design
description: "Clothing + accessories system brainstorm (2026-10-25): owner's asks (unique item copies, Robux main income + some SC, head-to-toe slots, Sculptor for face shapes, nothing clips) and my proposed rules; awaiting owner's go"
metadata:
  node_type: memory
  type: project
  originSessionId: 25c85d49-de6e-4f92-9c82-8f5fba9ab143
  modified: 2026-10-24T23:51:30.766Z
---

Owner asked 2026-10-25 (after the queue/receptionist work) for a clothing + accessories system and its pipeline; design first.

**Owner's wishes (decided by owner):**
- Each item is a unique copy: dressing two Quins alike means buying two.
- Robux is the owner's only income, so many items for Robux; some for SC.
- Categories run head to toe.
- Face shapes (head shape, eyes, nose, lips, ear type) are changed at a separate place ("Quin Surgery", name open). Focus on clothes and accessories first.
- Nothing may clip: hair under hats, tucked shirts, layers stacked right. The owner said this matters most.
- The owner references Koikatsu.

**My proposal (not yet approved):**
- Every item has slot, layer, covers, variants and mount. Hair is authored in parts, with `Capped` variants (Sims "hat hair" + WoW-style hide flags).
- Roblox Layered Clothing cages handle stacking, tucking and male/female fit.
- Spring bones (client) for swing.
- Wardrobe (wearables) is kept separate from the clinic venues (body parts; "The Sculptor" name rejected). Every head shape ships the standard mount points.
- Robux via Developer Products, with receipts granted exactly once.
- Dyes on 3 colour zones.
- Wrists: team bands always show (holograms, see below).
- Blender template + one-click export → `QUIN_DESIGN\export\` → data-driven catalogue.

**Owner decisions, 2026-10-25 (follow-up):**
- Team bands are **holograms**, worn by every Quin, in Alpha or Beta colour. Pack Leaders get a slightly different shade.
- The bands are always readable, even over other wrist items: they draw just outside them, and "clipping is fine, it's a hologram".
- I suggested a "holo" item line that is clip-proof by design.
- "The Sculptor" is rejected as too plain. The owner wants something scientific, like a private clinic, e.g. "Mira's Clinic", with 2–3 venues.
- My proposals (not canon):
  - Mira's Clinic (everyday);
  - Halden Morphology Institute (prestige);
  - Vesper Bioform Lab (experimental).
  - All of them do the basics, and each has a signature catalogue. The alternative is a split by body part.
  - Each venue's NPC uses NpcDialog.
- **Decided (owner, 2026-10-25): 6 clinic venues, for a FUTURE version.**
  - The venues: Mira's Clinic, Halden Morphology Institute, Vesper Bioform Lab, Kessler Morphics, Lumen Facial Works, Corvin & Hale.
  - **Signature catalogues:** each venue does the basics, plus its own exclusive shapes.
  - Venue roles and lore are not set yet.
- Owner: focus on the clothes + accessories pipeline now; clinics and face shapes later.
- Owner said go on the feasibility test, and asked me to model the test items in Blender myself.

**First step proposed:** a feasibility test on QuinMale (test shirt, pants, hair with a capped crown, cap). Main risk: does Layered Clothing work on the custom Mixamo rig. Also offered: `CLOTHING_DESIGN.md`.

Related: [[quin-body-design]], [[skylark-economy-design]], [[npc-dialog-reception]]

**2026-10-25: feasibility pack built** (`D:\SKYLARK\QUIN_DESIGN\clothing\`).
- Owner rule: the Quin body and head aren't final, so NOTHING is hardcoded. Regions come from the skeleton (the bone that owns each cage face) plus clean cuts on planes taken from the bones. Sizes come from the body's own measurements.
- Scripts in `scripts\`:
  - `build_test_pack.py <body.blend> <out.blend>` builds the pack.
    - QuinCage is a template made once (`work\QuinCage_template.blend`: 1502 verts / 3000 tris; its topology and UVs are the contract) and fitted to each body (shrinkwrap + an `enclose` pass, so the whole body sits inside).
    - The items, all LAYERED: Shirt (order 2), Pants (3, over the shirt's hem = tucked), Hair_Crown / Hair_Crown_Capped / Hair_Fringe / Hair_Back / Hair_Tail (1), Cap (5).
    - Each item has `<Item>_InnerCage` (= QuinCage) and `_OuterCage` (pushed out over the item).
    - Items are skinned by copying the body's weights.
  - `render_pack.py` makes the renders (`renders\ClothingTest_v1_sheet.png`).
  - `export_pack.py` writes the FBX with the same settings as the body export.
- Output: `export\ClothingTest_v1.fbx` (25 meshes).
- Roblox facts (docs):
  - Custom characters ARE supported: WrapTarget on the body, WrapLayer on the items, cages matched by UV.
  - Custom cage UVs are fine for in-game items (not for the Marketplace).
  - A non-R15 body needs a manual Weld.
  - WrapLayer / WrapTarget CageMeshContent, Order and AutoSkin are all settable from Studio Lua (checked).
- Next: the owner imports the FBX in Studio. I then wire a test Quin: WrapTarget on Alpha_Surface (cage QuinCage, CageOrigin from the imported positions), WrapLayers, align by the Hips bone, and test tucked vs untucked (swap orders) plus the cap-swaps-crown rule.
- Trap: a bash heredoc with a Python r''' string broke on quoting. Write patch scripts to a file instead.

**THE HANDBOOK: `D:\SKYLARK\QUIN_DESIGN\clothing\CLOTHING_PIPELINE.md`** — read it before touching the pipeline, and update it when the pipeline changes. Approved snapshots are kept in `clothing\snapshots\<date>_<name>\` (v1 = 2026-10-25_catalogue_v1). The build log is in `workuild.log`.

**2026-10-25: quinwear catalogue (104 items)**, `clothing\scripts\quinwear\` (core, garments, headgear, hair, accessories, catalogue). The owner asked for "many many combinations", all beautiful.
- **Fit labels:** every item is Unisex, Male or Female. Female items are made on the female body; Unisex and Male items on the male body. The grid leaves impossible pairs as blank cells.
- **Hat rule** (`hair.py`):
  - Constants: HAT_LOW (face, sides, back) = (0.42, −0.02, −0.40); CAP_OFF 0.005; HAT_OFF 0.0145; HAT_THICK 0.004; PRESSED 0.0008.
  - Hats swap Hair→Capped. Capped hair is pressed thin and low (flat/clamp), and anchors (tie, bun, braid) walk below the line.
  - `build_catalogue.py` checks every capped hair and every hat pair, printing OK / POKES THROUGH / HAIR SHOWS THROUGH. Run it after any hair or hat change.
- **Traps:**
  - `head_line` args are (front, side, back). They were swapped once.
  - Preview `resolve()` must push along the skin's normal (skin BVH), not the hair's normals, or hats render under hair.
  - Skin-tight accessories (team band, bracers, necklace) are authored snug (SNUG 0.007), because Roblox layering lifts them; don't add an offset by order.
  - Solidify with even offset makes spikes, so keep it off and use despike.
  - Stripes must use one continuous coordinate and one plane cut per stripe edge, or the triangle count explodes.
- **Commands:**
  - `blender -b --python build_catalogue.py [-- only=a,b]`
  - `render_catalogue.py -- items|grid|outfits`
  - Renders go in `clothing\renders\`.
- **Open:**
  - Roblox export (one texture per MeshPart, so a palette texture/UV step; FBX per category with cages), then a WrapTarget/WrapLayer Studio test.
  - Stripes should become textures.
  - Coats are ~9k tris.
  - The hood is weak and the afro is lumpy.

**2026-10-25: Roblox export + Studio test WORKS.**
- Export: `export_roblox.py -- set=test` writes one FBX per item variant (rig + item + `_InnerCage` / `_OuterCage`) with the palette texture and `STUD_SCALE` 0.044 (the body is 4.40 studs/m).
- The owner imports with the 3D Importer at default settings into Workspace.
- I wire it up with `clothing\scripts\studio\dress_test.lua`:
  - a WrapTarget on Alpha_Surface (cage = an item's ReferenceMeshId, origin lined up by the Hips bone);
  - Accessory + WeldConstraint for each item, with Order and AutoSkin EnabledOverride.
- Proved: tuck variants, layering, the hat→Capped swap, cross-body wear, bands, posed bones.
- Open:
  - baggy jeans;
  - the skirt stretches with the leg (try AutoSkin Disabled);
  - full-catalogue export;
  - a game-side wardrobe system.
- Details are in CLOTHING_PIPELINE.md.

**2026-10-25: permanent IDs** (owner: "imagine 10,000 items").
- `registry\registry.json` is append-only (`quinwear\registry.py`).
- Asset name `<SKU>_<variant>_<slug>`, e.g. `TOP00001_T_tee_plain`.
  - Slot codes: HAR HAT FCE NCK TOP OUT BTM WST ARM FTW BCK SYS.
  - Variants: B, T, U, H, C.
- Colours `COL001+` are fixed palette cells in the shared `TEX_QuinPalette_v1`.
- Export goes to ONE folder, `export\roblox\all\` (166 FBX + INDEX.csv + COLOURS.csv + manifest.json).
- Owner preference: one flat folder to import. Organising is by naming. I can't touch Asset Manager folders from Lua.
- Handbook section 13.

**2026-10-25: IN GAME.**
- Items are in `ReplicatedStorage.Clothing.<Slot>.<asset>` (166 Accessories), converted by `scripts/studio/convert_imports.lua`.
- Module `QuinCore.Modules.QuinWardrobe`.
- Quins wear `QuinInstance.Outfit`, or a random outfit at every spawn (hooked in QuinSpawner), team band = client hologram (QuinHoloBands); every Quin dressed, paced by QuinWardrobePacer.
- Wardrobe: a WARDROBE button on the MY QUINS cards opens WardrobeClient, which talks to the QuinWardrobeService remote.
- Workspace attribute WardrobeOff = bare spawns.
- Handbook section 14.
- MCP trap: clicks can't reach the top-bar MENU button (it sits in the 58px inset); test the remotes from the Client datamodel instead.
- TRAP (fixed 2026-10-25): never weld worn items yourself. The engine strips a Weld or disables a WeldConstraint inside an Accessory Handle on a Humanoid model, and the clothes fall off. Use matching Attachments (QuinWearAttachment on Alpha_Surface and in the Handle); the Humanoid builds an AccessoryRigidConstraint.
- 2026-10-26: Team bands are client holograms (StarterPlayerScripts.QuinHoloBands, RIGHT wrist only at the leader band's spot, hidden while SocialRole=Leader so LeaderWristbands shows instead; the SYS layered band never wrapped, so it is retired). Clothes cost the CLIENT: ~0.2 ms per dressed Quin, ~0.03 ms per extra item, triangles barely matter; only WrapLayer.Enabled=false removes the cost. The nearest-16 LOD was REJECTED by the owner (wants all Quins dressed start to finish); replaced by StarterPlayerScripts.QuinWardrobePacer: builds 2 Quins per 0.25 s hidden, reveals each whole Quin 0.75 s later (WardrobePacerOff, readout WardrobePacerStats). Clean A/B: wraps off 74-78 fps / 6 ms render CPU vs on 28-34 / 21 ms; the cost is the wraps, not triangles. Planned fix: bake clothes as skinned MeshParts like Quin_Joints (SKYLARK_PERFORMANCE_PLAN.md step D). Handbook 14.x.
- TRAPS: a wrap sent Enabled=false from the server and enabled on the client isn't drawn (send ON, disable on the client); weak Instance-keyed tables lose entries; benchmark only with Studio focused (it throttles).

**Wardrobe preview: owner chose the flat ViewportFrame (2026-10-26).** Tried showing the Quin in the 3D world (a studio room, then a backdrop card in front of the camera); the owner rejected both as too much ("just make the box pretty"). Do not retry the in-world approach unless asked. Look now:
- slate gradient on a separate Backdrop frame behind the ViewportFrame (a UIGradient on the ViewportFrame tints the model too: that was the dull grey body);
- LightDirection (0.45,-0.9,-0.75), warm LightColor, Ambient (168,174,190);
- DISTANCE 18.5, LOOK_HEIGHT -1.4.
Known limit: in a ViewportFrame, layered clothes keep the bind (T-) pose shape while the body idles (sleeves stick out). Client-made models: the Humanoid never joins accessories (they fall) unless welded yourself.
