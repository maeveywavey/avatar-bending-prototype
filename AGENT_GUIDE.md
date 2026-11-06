# Agent guide: Avatar Bending Prototype

Notes for the next Claude session working here. Read this before touching animation. Also read `brief_bending_prototype.md`, which is the owner's brief.

## Owner rules (non-negotiable)
- Communicate concisely, encyclopedia-style. No flattery, metaphors or restating.
- Movement quality is the whole point. Never ship the quick, generic version.
- Respect human anatomy: no impossible arm swings and no wrist past its range.
- Feet never hover. A planted foot keeps the **ball** on the floor; only the heel/ankle lifts.
- Standing: feet shoulder-width apart, arms hanging relaxed.
- Ready stance: martial-arts stance, and the **back foot steps back** to open it.
- When asked for several animation attempts, make them radically different from each other.
- **Play it yourself** before reporting (see Testing). The owner should not be the one finding pops.
- When motion feel can't be judged from stills, say so and ask the owner.
- The owner will supply wrist/finger adjustments and when the water should move in each draw. Don't invent these; ask.

## How the animation works
1. The source is the owner's video `mocap/videos/full_right.mov`, with timings in `full_right_breakdown.txt`. The phone was fixed at about eye height.
2. `tools/pose/track.py` uses MediaPipe and writes `mocap/tracking/full_right.npz` (world landmarks and image landmarks). It already exists; don't rerun it unless there's a new video.
3. `tools/pose/retarget.py full_right` writes `mocap/clips/full_right__full.json` (bone rotations plus a pelvis offset). Run it with the venv:
   `tools/pose/venv/Scripts/python.exe tools/pose/retarget.py full_right`
4. `scripts/mocap_library.gd` cuts that file into clips (`SLICES`, in video seconds):
   - `AIM_YAW` (−50°) turns the bending clips so the ready stance faces the crosshair.
   - Horizontal travel goes on the `root` bone. `player.gd` takes it as root motion, so steps carry the character.
5. `scripts/player.gd` builds an AnimationTree state machine:
   - States: `loco`, `loco_ready`, `loco_hold`, `stand`, `ready_in`, `ready`, `draw1..3`, `hold`, `strike`.
   - `loco_ready` / `loco_hold` put walking legs under the recorded upper body (a Blend2 filtered to `spine_01` and below).
   - `stand` takes only the fingers from UAL `Idle`. Its arms are built in `MocapLibrary._hanging_arm`.

### What retarget.py corrects, and why (don't undo these)
- **Depth tilt (`_balance_depth`):** MediaPipe depth is unreliable. Whole-body lean along the camera's line of sight is removed by keeping the centre of mass over the feet. Without it, every pose leaned back.
- **Feet (`_foot`):** flat with yaw only. The tracker's foot pitch is garbage from an elevated camera.
- **Grounding (`_ground`):** pelvis height puts the lower foot on the floor, and planted feet don't slide.
- **Plant pass (`_plant`):** leg IK pins the ball of each planted foot. The heel lifts at most `HEEL_MAX` and the knee bends to take up the rest.
  - A foot counts as stepping when it moves fast **in the image** (`set_foot_speed`; the camera is static). Height alone glued the stepping back foot.
  - The plant weight is rate-limited (0.16/frame) so feet don't pop on landing or lift-off.
- **Limb twist (`_limb`):** eases in with elbow/knee bend, at most 7°/frame. A hard threshold caused forearm flips.
- **Wrist (`wrist_filter`):** clamped to human range (bend 75°, twist 60°), then smoothed.

## Water is conserved (owner: "we want things to make sense")
- Water is never created or deleted.
  - Circle drops it (letting go of R1 no longer does). Each point falls with the velocity it had, and the water collects into a `Puddle` (`scripts/puddle.gd`).
  - Struck water collects into a puddle under what it hit.
  - Puddles are water sources: they can be aimed at and drawn from, and they merge when water lands on them.
  - Planned, not built: puddles soaking into the ground over time.
- Drawing needs the crosshair on the source (`aim_hit`) within `DRAW_RANGE`. After R1 is pressed the camera is free.
- A draw takes `QUICK_DRAW_T` (0.5 s) from the press to the water held (owner: a tap of R1 siphons 30 L in 0.5 s). The clip still plays to its end before the hold.

## Precision mode (owner's example 3, Force-style)
- **Controls:** L2 (key R) toggles it while water is held.
  - The water goes to a point on the crosshair line; the left stick pushes it out or draws it in (1.2–14 m from the chest, 10 m/s). The bender stays planted.
  - The camera closes in (3.4 to 2.4 m) and its FOV narrows to 0.9x, down to 0.5x at 14 m.
  - R2 held (key F) catches a loose body within 1.1 m of the water, or the body under the crosshair within 2.6 m. Releasing R2 drops or throws it.
- **Catching a body:** the water does not coil around it. The stream pours into a sheet that spreads over the body from where it touched (`_film_*` in `water_body.gd`).
  - The sheet's thickness is the volume divided by the surface area, at most 6 cm. Volume moves between stream and sheet, so the total is constant.
  - On R2 release the sheet gathers back into the stream. Dropping the water (Circle) runs it off into a puddle below.
  - The body is carried only once the sheet has started to spread.
- **Code:** `WaterBody` states `STEER` and `FALL`.
  - The head chases the target with an underdamped spring, sphere-cast so it slides along surfaces.
  - At rest it circulates in a loop; at speed the loop closes into a stream.
- **Wetness:** `scripts/wetness.gd` puts decals where water touches and lets them dry over about a minute.
  - Wet patches are parented to rigid bodies so they move with them.
  - Render layer 2 (the bender, the water, the splash) is never marked.
- **Simulation steps:** `WaterBody._process` runs several steps on slow frames. Before this, capture runs at about 10 fps made the water run at a third of real speed while the physics stayed real-time.
- **Test:** `"$G" --path . -- --demo --play --steer --gamecam`. `W` lines log head, target, grab and head velocity; `WET` lines log each patch.
- **Not yet done:**
  - People, fire.
  - Arms that follow the steered water. The body plays `hold` for now, and a recording of directing water at a distance is needed.

## Moves, forms and bending (owner's design)
Deep bending (being rooted in place) was tried and removed: the owner found it clunky. Large volumes now come from drawing longer.
- **Two layers (owner's decision):**
  - **Moves**, on the d-pad, decide what R2 does with held water: Lash, Slice, Ice spike, Ice wall. In code they are still called forms (`Player.Form`, `form`).
  - **Forms**, on the forms wheel (L1), change the body and movement: Serpent and Octopus (`Player.BodyForm`, `body_form()`). Each has its own water, apart from the held water, so all moves work in it with newly drawn water.
  - Square is jump.
- **Controls (owner's scheme, 2026-11-06; expected to change often, so every binding is in the menu):**
  - **R1:** a tap draws 30 L in 0.5 s; held, drawing continues (the feed stream) until R1 is let go. With water already held, a tap adds 30 L the same way (`_draw_goal`, `WaterBody.feed_quick`: at least 60 L/s until it arrives). Letting go of R1 keeps the water.
  - **Circle:** drops the held water (and spikes forming). With nothing held, it relaxes out of the ready stance (decided here: L1 no longer does that). Relaxing no longer drops Serpent or Octopus.
  - **D-pad:** up Lash, right Slice, down Ice spike, left Ice wall; each also takes the ready stance. A second press of the same direction within `PAD_DOUBLE` (0.35 s) picks that direction's second move (`MOVE_PAD`); all four second slots are empty for now. R1 on a source also takes the ready stance.
  - **L1:** a tap goes back to the last form (no form counts as one, so it toggles in and out of a form); held, the forms wheel.
  - **Esc / Options:** the Options menu (`scripts/options_menu.gd`; owner's layout, 2026-11-06): Resume, Audio (greyed, "Coming soon!"), Visual (Graphics greyed; Edit Water Shapes), Controls (`ControlsPage`, `scripts/controls_menu.gd`), Quit. Esc / Options / Circle go back a page, and out of the menu from the first. The game is not paused (owner, as in Dark Souls); the bender takes no input while it is open (`Controls.blocked()`, and 150 ms after it closes so the closing press does nothing).
  - **Bindings (`scripts/controls.gd`):** `Controls.ACTIONS` lists every action, its menu name, and its default pad button and key. The player's changes are saved to `user://controls.cfg` and loaded over the defaults at start; "Reset to defaults" deletes the file. Rebinding to a button another action uses swaps the two. The HUD's hints are written with the default pad names and `Controls.relabel` swaps in the bound ones (the d-pad hints stay "D-pad").
  - Keyboard defaults: WASD move, arrows look, E draw, C drop, F use the move, R precision, Space jump, Q forms, 1–4 the d-pad directions (up, right, down, left).
  - Player input goes through `_ip`, `_ijp`, `_ijr`, `_iv` in `player.gd` (they return nothing while the menu is open). Do not call `Input` directly there.

- **Volumes (owner's numbers):**
  - **Normal draw:** a full stream is 30 L. `L_PER_M` is 30/3.4, so the held stream reads about 2.3 times its true volume; this is a game allowance. Puddles, ice and spikes count the real litres.
  - **Gathering (`WaterBody._feed_step`):** after a full draw, keeping R1 on the source raises a feed stream from the source to the held water's tail. The held water grows only by what arrives up it (14 m/s), never while unconnected.
    - **Rate:** `26 · e^(t/1 s)` L/s, rising the longer R1 is held: small amounts can be taken precisely, and 30 L to 600 L takes about 3.5–4 s (half the old 7 s). The feed's thickness follows the flow.
    - **Stopping:** letting go of R1 (once a tap's 30 L is in) lifts the feed's foot off the source, and the rest runs up into the held water. The aim may leave the source while R1 is held (owner: drawing continues until R1 is let go); it stops beyond `FEED_RANGE` (12 m) from the source. Dropping the water spills what is in the feed back into the source.
    - A 600 L stream looks as a 1,200 L one did before.
- **Held water:** `WaterBody.thick` scales the stream's radius, and litres per metre are `L_PER_M * thick²` (`lpm()`). The hold loop circles wider and higher for thick water.
  - `take_litres` and `add_litres` move water out of or into the held stream: it thins back to normal first, then shortens.
- **Movement:**
  - **Ready stance:** a run (3.6 m/s), the owner's request. Held water slows it: speed is divided by `1 + (V - 30) / 900`, so a full 600 L makes it a jog of 2.2 m/s.
  - **Camera:** it stands back with load, and with Serpent's height.
  - **Pitfall:** a water source drawn dry must stop giving at once (`IceBlock._gone` clears its parts). The draw runs several substeps a frame, and a freed source is still valid until the frame ends.
  - **Steps:** ledges up to `STEP_H` (42 cm) are stepped onto (`Player._step_up`). A blocked move is tried a step higher and 10 cm farther on, then set down; landing on the edge counts, at up to 55° (`floor_max_angle` 56°). The stride keeps its speed. Before this, 10–20 cm of ice stopped the bender.
  - **Upper body while walking (`scripts/upper_aim.gd`):** the ready and hold clips turn the whole body at the pelvis, and the walking legs don't. The chest faced about 75° left of its standing direction.
    - The fix turns the spine up to 52° (what a trunk allows). The hips turn up to 26° for the rest. It adds the aim's offset from the direction of travel.
    - Measured: walking shoulders within 2° of standing.
    - Pitfall: bone poses read outside a modifier are the unmodified ones, because Godot restores them after the modifiers run. Hand positions for the water come from `UpperAim.hand()`. People's cuts use the poses `Person.Severed` records.

- **Forms wheel:** hold L1 (key Q), in either stance. A tap shorter than `WHEEL_HOLD` (0.2 s) goes back to the last form. Held longer, the wheel opens and time slows to 0.2x.
  - **Slots:** eight, clockwise from up (`Player.WHEEL`): up Serpent, down Octopus (owner). The other six are empty, for later forms, and are drawn dim.
  - **Picking:** only a stick pushed past 0.6 picks; a centred stick changes nothing. Letting go of L1 chooses (`_choose_body_form`): from one form to the other, the water goes over; from no form, the held water melds in (300 L needed, else a notice in the hints); the form it is in again melds the held water in, or with none held, leaves it (its water falls as a puddle).
  - **Drawing:** `Hud.WheelView` draws the wheel. `shaders/wheel_backdrop.gdshader` blurs, greys and darkens the world behind it.
  - **Pitfall:** the first version drew no wheel. `WHEEL` lines log it.
- **Water drawing (owner, 2026-11-06: "what I've been wanting"):** every body of moved water is one implicit surface, ray-marched per pixel (`WaterSDF`, `shaders/water_sdf.gdshader`): Serpent, the held stream and its feed (one surface, so they meld), Octopus (ring and tentacles as one), geyser, wave, the volley's water to the spikes, the ice wall's stream. Not the slice (owner), the solid ice, or the still surfaces (stream, fountain, puddles, barrels, the shelf), which stay meshes with `water.gdshader`. The precision-grab sheet over a body (`_film`) also stays a mesh: it was the look the owner held up as right.
  - **Pieces:** each frame the owner of the water calls `clear()`, adds round cones (`seg(a, ra, b, rb)`: two end spheres and the cone between; optionally flattened along an axis, e.g. the Octopus ring), `sphere`, `chain`, then `commit(blend, origin, wave, floor_y)`. At most 64 pieces per surface. The shader joins them with a smooth minimum (`blend`, m), so where pieces meet the surface rounds over like liquid: no seams, no parts clipping.
  - **Drawing:** a box round the pieces, back faces, depth test off. The ray starts at the box (or the camera inside it) and stops at the opaque scene (depth texture), so what is in or behind the water is seen through it, bent by it. Colour deepens with the distance through the water (`absorb`): clear where thin, deep where thick. The rim fades over its last 6 mm. A cheap bounding test skips pieces far from the ray.
  - **The stream's surface is transparent and not in the depth buffer:** water rising out of it (geyser, wave over water) passes `floor_y`, the surface height, and is not drawn below it.
  - **Ripples** are taken from position (relative to `origin`, moving at `drift` m/s: e.g. up the geyser), never from a texture on the shape, so nothing stretches when the shape changes.
  - **Cost (owner, 2026-11-06: no lag, but the computer ran hot with the fan at full):** each piece is checked at every ray step for every pixel of the box, so cost is pieces × steps × pixels. Kept down by: `Engine.max_fps = 60` (World; past 60 the GPU only heats up), at most 56 march steps and 10 for the thickness, 3 noise octaves, and fewer pieces (held stream a piece every other point, 23; Octopus ring 10 and 4 per tentacle; Serpent's tail 5; wave 4 per tube). Add pieces sparingly; a cheaper next step if needed is drawing the water at a lower resolution.
  - **Not checked on screen:** headless runs do not compile shaders. A shader error shows as no water at all where these are.
- **Water shapes (Options > Visual > Edit Water Shapes; `scripts/water_shapes.gd`):** the numbers that set each water thing's shape, for the owner to learn the code and tune by eye.
  - `WaterShapes.GROUPS`: per water thing, the lines of its code that use the numbers, as they read in its script with each `k("name")` written `{name=default}`. The defaults come from these lines, so they are the single source. Scripts read `k("name")` (`WaterShapes.f(group, name)`) each frame, so an edit shows at once. **Keep each group's lines in step with its script**; a name missing from the lines is a `push_error` and reads 0.
  - The menu shows the lines in a code font with a box per number; the default is the grey placeholder, an empty box uses it, a typed number overrides it. Reset to Default, Save (named, per water thing; also made the values used at every start, `user://water_shapes.cfg`), Load (named saves, `user://water_shape_saves.cfg`; can be deleted there).
  - A builder that rebuilds only on change should also rebuild when `WaterShapes.revision` changes.
- **Serpent** (forms wheel, up; `scripts/serpent_water.gd`, `Player.serpent_form`): its own body of water, enveloping the hips and legs as one shape suggestive of a serpent's body, pooling into a tail on the ground behind (owner's drawing). It is not water coiled round the body (the first version was).
  - **Taking the form:** offered only with 300 L or more held (less is not enough water, in sense or on screen). Picking it melds the held water into it (`WaterBody` state `MELD`, 0.45 s, the head running to the waist). The bender then holds nothing and draws again as usual. Every move works with that water, independent of Serpent.
  - **Adding:** picking Serpent on the wheel while in it and holding water melds it in. Most 1,200 L.
  - **Leaving:** L1 tap (back to no form) or picking it again with nothing held drops it as a puddle.
  - **Running off:** 1 L per metre moved (600 L lasts about 400 m), leaving wet ground. Dry, it is gone.
  - **Spent (200 L or less):** still on, gives nothing (walking again), drawn as a thin layer round each leg and the hips. Above 200 L the full form: one body round both legs, a column to the ground when raised, a tail along where the bender passed. Margin beyond the legs and tail length grow with volume, with diminishing returns. Its look is set by eye (a game allowance); its litres are exact.
  - **Drawing:** see Water drawing below. `SerpentWater._shape()` lists the pieces: legs (hip–knee–ankle–ball), the hips, a band that rounds over at the waist, a body between the legs, a pool under the feet (a sphere mostly below the ground) or the column, and the tail (8 pieces). Thin and full blend smoothly (`blend_thin` 0.035 m, each leg separate; `blend_full`, one body). No flow along the body (owner); only a slow wave and ripples fixed to the bender.
  - **Speed (owner's numbers, diminishing):** ×1.5 at 300 L, ×2 at 600 L, about ×2.1 at most: `1 + 1.096 (1 − e^(−(V−200)/164))`, applied to the ready speed after the held-load slowdown. The legs stand still in the water.
  - **Smoothing:** acceleration `2.5 + 7 e^(−(V−300)/200)` m/s² (9.5 at 300 L, 4 at 600 L): more water, more momentum.
  - **Height:** holding Square rises at 2 m/s; letting go sinks. Feet at most `6.3 (1 − e^(−(V−200)/279))` m up: 1.9 m at 300 L (half a 3.8 m house), 4.8 m at 600 L (feet a waist's height above it). At 200 L or less, Square jumps.
  - **Roofs:** height is kept over a roof, so the bender can sink onto it (tested: the 3.8 m house past the fountain).
  - **Pitfall:** leg positions come from `UpperAim.leg()` (recorded inside the modifier), for the same reason as the hands.
- **Lash** (`WaterBody` state `LASH`):
  - **Strike:** R2 shoots the head from the hands to the target (9 m, 32 m/s). It used to start from the head's place on the loop, which can be 1.6 m off to the side with a lot of water, and then hit things beside the target.
  - **Aim assist (`Player.lash_target`):** a crate, dummy, person or boat within 7° of the crosshair (60 cm minimum), in reach and in sight, is the target, at its middle (`lash_point()`).
  - **Hit:** an impulse that grows with volume, capped at 7 m/s for the body's mass.
  - **Grab and swing:** holding R2 at contact latches on and holds the body 2.3 m in front. The spring matches the hold point's velocity, so the body swings round with the bender. Force is 150 N/kg (900 N minimum, 4,000 N maximum). Turning is faster while latched (4.2 rad/s).
  - **Throw:** letting go mid-swing sends the body at 2.2 times the swing speed, at most 26 m/s, scaled by √(25/mass). `THROW` lines log it.
  - **Lift limit:** the lash lifts at most `LIFT_MAX_N` (1,000 N). The boat is dragged, never lifted or thrown.
  - **Dummies:** a dummy held 8 cm off its post for 0.4 s tears loose.
  - **People:** they are knocked down limp, then can be grabbed.
- **Slice** (`scripts/water_blade.gd`): R2 throws a crescent of 12 L (less if less is held). It spends itself on the first thing it meets (owner: one arm of the nearest person, not a line of people).
  - **Size:** 2.4 m tip to tip, 5 cm thick and 19 cm deep; an elliptical section tapering to the tips holds exactly 12 L.
  - **Angles:** quick successive slices cycle horizontal, vertical, diagonal, diagonal.
  - **What it cuts:** the first body along its flight (`_first_along`): a sliceable body is cut (`scripts/slicer.gd`), another loose body shoved, a fixed surface stops it. Then it lands as a puddle there.
  - **People:** `Flesh.cut_person(..., dir)` cuts only the bone crossing met first along the flight and those within 14 cm deeper and 15 cm of it (the same limb). Tested (`line`): three people in a row, a horizontal slice cut only the first one's upper arm.
- **Slicer:** sliceable bodies (crates, dummies, the boat, ice blocks) keep convex parts in meta `"parts"` and `"stuff"`. A part may carry its own `mat` / `cap_mat`; a body with `make_piece()` makes its own kind of cut-off piece.
  - A cut splits each part the plane crosses and caps each half; mass is shared by volume.
  - `keep_point()` decides which side stays. Pieces under 40 cm³ are dropped.
- **Ice spike** (`scripts/ice_spike.gd`, `scripts/spike_volley.gd`):
  - **Shape:** an irregular six-sided crystal with flat faces, a long front point and a short blunt back point. Each spike's shape is its own (seeded).
  - **Size:** `EXPAND` (68/30) times its water's volume, the owner's choice: a 30 L spike is as big as the old 68 L cone. Real ice is 1.09.
  - **Tap R2:** a 6 L spike.
  - **Hold R2 (volley):** one large spike per 30 L, up to 20, or one with everything under 30 L.
    - The water arcs from the nearest part of the held body (not the hands) to a fan of slots around and above the bender, and the spikes freeze there pointing at the crosshair.
    - On release, each flies from where it is to its own point near the crosshair (scatter 35 cm + 6% of the distance), like a shotgun.
    - What is left over after the last whole spike goes into the last spike, so nothing stays held (owner).
  - **Sticking:** spikes go 45% of their length into fixed surfaces and 30% into bodies. The knock on a body is capped at 8 m/s for its mass. A large spike (over 25 L) in a fixed surface is solid.
  - **Melting:** after 90 s, into a puddle.
  - **Pitfall:** the volley's own update must stop once it has fired, or it starts a new set the same frame.
- **Ice wall, tapped** (`scripts/ice_wall.gd`, `scripts/ice_block.gd`): 30 L of the held water flies from the held body (26 m/s) and rises out of the ground as a wall facing the bender, 1.3 × 2.2 × 0.25 m (owner: about 1.25 bender heights tall, 0.75 wide, half a crate thick; width read as 0.75 of the bender's height, since 0.75 of the body's width would not cover them). Less water, a smaller wall.
  - **Body:** an `IceBlock`, a frozen `RigidBody3D` of Slicer parts, slightly narrower at the top. Its litres are its volume × `l_per_m3` (about 42 L/m³ for a wall, set from the owner's size), shared by volume when cut.
  - **Breaking:** a slice cuts it (the part on the ground stays; the rest falls loose). Water hits (strikes, spikes, lashes) add up; past 80% of its litres it breaks into pieces round the hit. Loose pieces are crates: grabbed, lashed, thrown, floating. Slivers under 0.25 L melt into puddles.
  - **Drawing:** a water source. Drawn from, it shrinks (about its base when standing) and is gone when drawn dry.
- **Ice wall, held** (`scripts/ice_field.gd`, `scripts/ice_caster.gd`): hold R2 to freeze ice where the crosshair is, within 14 m. The water runs from the held body's head, not the hands. Ice is a grid of 0.35 m columns with smoothed tops. The ice can be drawn back up as water (aimed at, the cell hit melts from its top, then its neighbours); it does not break yet.
  - **By surface:**
    - Ground: rises.
    - Water surface: a floating slab, made from that water.
    - Wall: a ledge.
    - Ice side: it extends.
    - Ice top: it rises.
  - **Cost:** `ICE_L_PER_M3` is 91.7 L of water per m³ of ice, a tenth of the real 917, the owner's request. Ice does not melt yet.
  - **Pitfall:** the trimesh reports its normal from the wrong side; `_ice_target` flips it to face the camera.
- **A large body, nothing held** (`Player._update_large`): with the crosshair on the stream's surface within 25 m (or on something floating in it: the water under it), in any move but Ice wall (which freezes the surface instead):
  - **Geyser** (R2 tap; `scripts/geyser.gd`): a column 7 m high, 0.45 m across (flared at the surface), up in 0.3 s, standing 0.5 s, falling in 0.7 s. What is over it is thrown up once (11 m/s, less for heavy bodies; tested: the 190 kg boat rose 1.8 m); a person is knocked down. Its water is the stream's.
  - **Wave** (R2 held; `scripts/water_wave.gd`, rewritten): rises where R2 was pressed, 0.5 m to 2.4 m over 1.8 s; the crosshair swept across the water stretches the crest (3 m to 16 m). Released, it runs away from the bender at 7 m/s, its lip pitching forward over the front as it goes, shoving and lifting what floats; a person is knocked down. The owner found the old one a rounded blob: it is a wave's cross-section (long back slope, crest, steep front, curling lip) made of five tubes running along the crest (`_tubes`: back, shoulder, crest, face, lip; each at a place in the cross-section in units of the height, blended from standing to breaking as it curls), tapering to nothing at its ends.
    - **Water:** over water a wave moves energy, not water, so it is not counted there. Reaching the shore it breaks and surges on with `RUNUP_L` (30 L per metre of crest per metre of height), slowing, lowering and soaking in, and leaves the rest as a puddle. A wall stops it. Over open water it dies away after 40 m.
    - Tested: a 7.2 m crest crossed the stream (27 m) and threw 444 L onto the far bank.
  - **Parting** (L2 + R2 held; `Pond.hold_part`): a hollow from about 1.2 m behind the bender to 5.8 m ahead and 5 m across. Owner, 2026-11-06: the first (2 m behind to 12 m ahead, 4.4 m across, an ellipse) was goofily large; halve it, a little wider, a blend between a long ellipse and a rectangle, rounder round the bender. Its shape is a superellipse (`Pond.part_shape`: exponent 3 ahead of its centre, squarer; 2 round the bender, an ellipse); its numbers are editable (Water shapes, Parting). Earlier note kept: a hard rectangle is too firm and inorganic for water (that is for earthbending). Its walls round up into ridges of the water pushed aside (0.9 m high), so the far end cups back up to the normal height. It goes with the bender as they walk and turns after the aim (5/s), so they can walk the bed dry (tested: walking down into the stream, the water stayed 1.5 m or more below the feet). Opens in 0.8 s; closes in 0.6 s, where it is, when either button is let go.
    - **Surface:** the stream's surface is now a 0.3 m grid in 20 m chunks; `water.gdshader` (`parting`, `part_h`) moves its vertices. `Pond.part_shape` is the same function on the CPU (`surface_y` and floating use it); Pond sends its numbers to the shader every frame. Keep the two matching.
  - **Waterfall: deleted** (owner, 2026-11-06: it had issues not worth tinkering with now; the concept may come back). It was a 4 m cliff across the stream upstream of the village with a curtain falling from it, and parting opened a gap in the curtain. If it returns: draw the curtain as falling strands flattened into a sheet (so parting moves the strands aside); the first single-sheet mesh stretched its texture instead of parting.
- **Octopus** (forms wheel, down; `scripts/octopus.gd`, `Player.octopus`; owner's design and reference images of Katara's octopus form): its own body of water, apart from the held water.
  - **Exclusive with Serpent:** only one form at a time. Picking the other on the forms wheel (or L1 tap back to it) switches, the water going over (`take_all`). Entering from held water needs 300 L (`MIN_ENTER`); held water then melds in by picking the form that is on. The bender holds nothing after and draws again (held-water moves are off in Octopus: R2 is its own). Leaving it (L1 tap to no form, or picking it with nothing held) drops it as a puddle.
  - **Shape:** a wide ring of water flush with the ground, with a dry gap of 0.7 m from the bender's middle (about two feet round the feet), and always six tentacles standing in it (two either side of ahead, two at the sides, two behind, set where the bender faced on entering). Each is thick where it flares into the ring and tapers to a soft point, bowing up and out; stretched out to reach, it thins. Not tentacles from the torso (the first version).
  - **Size (owner's numbers, not physical):** 300 L: 0.3 m wide at the base, shoulder high (1.45 m); 600 L: 0.6 m wide, a foot over head high (2.05 m). Between, linear; more, slowly larger (`length_for`, `base_r_for`). The ring widens and rises with volume.
  - **Rooted:** the bender cannot walk. The left stick picks the active tentacle by its direction (camera-relative). The active tentacle stays planted but stands raised and 20% thicker. L3 does nothing (owner).
  - **Marking (hold R2; after Dead Eye in Red Dead Redemption):** time slows to 0.5×, the camera closes in as in precision mode, everything grabbable within reach is highlighted, and each one the crosshair is directly on (no leeway, on purpose) is marked and numbered, up to the free tentacles. Let go: for each in turn, in the order marked, the free tentacle facing it reaches for it (0.12 s apart) and holds it up at its tip. A person is caught up limp. Each pulls like the lash (40 N per litre of its share, 600–4,000 N), lifting at most `LIFT_MAX_N` (the boat is dragged).
  - **Active tentacle's actions:** R2 tapped throws what it holds at the crosshair (20 m/s for 25 kg or less, slower heavier). L2 drops it. Square strikes: it rears back up and away, then whips down over the top at the crosshair (as far as twice its length) and settles back. Empty it is fast (0.11 s back, 0.07 s down); holding something it is heavier (0.3 s, 0.17 s), the held thing slammed with it. What the tip sweeps through is hit: a person knocked down, a loose body knocked away at the tip's speed (counted at most 30 m/s), the button or ice answer as to water; not the tentacles' own held things.
  - Tested (`octopus`): 600 L melded in, R1 let go, two marked and grabbed in order (a 6 kg and the 35 kg crate), a tentacle picked with the stick, an empty strike and a held strike, a throw, a drop, switched to Serpent and back with the water kept (599.9 L), relaxed into a 599.9 L puddle.
- **Dummies** (`scripts/dummy.gd`): straw figures held on posts by springs scaled with the remaining mass and inertia.
- **Stream** (`scripts/pond.gd`, still class `Pond`): behind the left-hand houses, running the length of the ground.
  - **Shape:** about 29 m bank to bank (twice the old pond, the owner's request) and 1.3 m deep, with gently winding banks (`centre_x`, `half_w`).
  - **Ground cut:** the world cuts its outline from the ground.
  - **Endless:** for the bender, it never runs out.
  - **Floating:** loose bodies in group `"crate"` float (`_buoyancy`): four columns under the corners of the body's box, by the volume displaced. That is meta `disp_vol` (the boat's open hull), else the parts' volume, else most of the box. Drag applies where wet.
- **Dock and boat** (`World._build_dock`, `scripts/boat.gd`):
  - **Dock:** a plank dock out from the near bank at z −3.
  - **Boat:** a 3 m jon boat of 4 cm planks (about 190 kg) floats beside it, about 5 cm deep. It collides with ice and everything else, can be dragged by the lash and cut like a crate, but is too heavy to lift or throw.
- **People** (`scripts/person.gd`, `scripts/flesh.gd`, `scripts/flesh_piece.gd`):
  - **Spawning:** the blue button (`scripts/spawn_button.gd`) is on the near side of the first house on the right, at (10, 1.3, −2.5), away from its door and windows. It calls out a person on any water hit: a strike, lash, slice or spike (`water_hit`), or the water in precision mode pushed into it. Any number at once.
  - **Behaviour:** villagers in the player's mannequin, recoloured, who idle and wander and keep out of the stream.
  - **Lifetime:** hurt, they bleed and despawn 5 s later (game time) with everything that came off them.
  - **Cutting (`Flesh.cut_person`):**
    - The skinned mesh is posed on the CPU (`Flesh.bake`). `bake_mesh_from_current_skeleton_pose` needs the skin registered with the renderer, so it fails in headless runs.
    - The blade's plane cuts each bone whose link to a child (or tip) it crosses within the blade's width. Using bone tips (the middle of the children) left a gap at the waist.
    - A union-find over (bone, side) groups the skeleton into pieces.
    - Each triangle goes to its main bone's group on its side. Triangles that cross the plane near a cut are clipped, and the cut edges cap each piece in flesh (fans).
    - If the pelvis group keeps the head and both feet, the person lives as an amputee. The lost part is hidden by scaling bones (`Severed`), and a capped, bleeding stump rides the bone. Otherwise every group falls as a `FleshPiece`.
  - **Pieces:** a `FleshPiece` is a convex-hull rigid body that can be cut again, grabbed, lashed and floated.
  - **Other hits:** a spike, strike or lash knocks a person down limp, as one rigid piece (not a ragdoll). A spike stays in the body.
  - **Blood:** sprays from cut faces, and splats on the ground.
- **Not yet built (owner agreed):**
  - Arms for each move (they play `hold`).
  - **Telegraphing the stance** on the body and the held water, not only in the HUD (owner's ideas):
    - Lash: the water wraps the hands and upper arms and extends them like tentacles.
    - Slice: the water in its stream form swishes around the bender in vertical, horizontal and diagonal arcs. A slice's angle is the angle the water is at when R2 is pressed, which would replace the fixed cycle.
  - Swimming; ragdolls for people; ice melting.
- **Aim tolerance:** sources implement `aim_miss(o, d)` (gap, distance along the crosshair line). A source counts within 4.5° (35 cm minimum) unless something blocks it.
- **HUD (`scripts/hud.gd`):**
  - The move (and Serpent) and litres are shown top right (`Player.mode_name()`).
  - The controls available now are bottom right (`Player.control_hints()`). Add a hint whenever you add a control.
- **Fountain (`scripts/fountain.gd`):** a 5,200 L basin, drawn from at the aimed point. `catches(p)` lets falling water rejoin it.
- **Tests (headless, no window):** `"$G" --headless --path . -- --demo --play --<name> --nocap [--len=<s>]`, where `<name>` is one of:
  - `forms`: lash, grab and throw, slices, small spikes and a volley, gather, ice on the ground.
  - `pond`: drawing from the stream, ice on it, standing on the ice.
  - `volley`: 600 L into 20 spikes thrown at the boat.
  - `serpent`: gather 600 L, meld into Serpent (forms wheel), draw again inside it, rise, glide over the fountain, sink onto a roof, add the held water (wheel), leave it with an L1 tap (drops it as a puddle).
  - `wall`: two tapped walls; one sliced, one broken by small spikes; one drawn back up.
  - `line`: three people in a row; one slice cuts only the first one's arm.
  - `octopus`: entering from 600 L, letting go of R1, marking and grabbing in order, picking a tentacle with the stick, empty and held strikes, a throw, a drop, switching to Serpent and back, leaving it on the wheel.
  - The tests press actions by name (`Input.action_press`), so they hold whatever the bindings are. The old wheel picks are d-pad taps; the old R1 releases that dropped water are a release plus a Circle tap; an R1 hold is let go where the test turns away from the source (drawing used to stop there).
  - `large`: a geyser under the boat, a wave swept wider and sent across the stream, the stream parted upstream, walking into the parted stream (`DRY` lines: the water beside the feet), letting it close.
  - `people`: the button, slicing and spiking people, despawning.
  - `amputee`: a person standing still sliced through one side.
  - `step`: walking over 25 cm and 40 cm ice.
  - `twist`: shoulder yaw standing against walking.
  - `steer`, `fountain`.
  - **Log lines:**
    - `S`: litres everywhere, to check conservation.
    - `X`: speed, Serpent height, boat, people, pieces.
    - `SERP`: Serpent on, litres, in effect, thin, height limit; feed on, litres coming.
    - `LARGE`: parting open, surface in and beside the trench, geysers, waves.
    - `OCT`: litres, marking, marked, time scale, zoom, the held water's state, each tentacle's phase and what it holds (`*` the active one).
    - Events: `CUT`, `SLICE`, `PERSON`, `BUTTON`, `LASH`, `THROW`, `WHEEL`, `WALL`, `ICE broke`, `GEYSER`, `WAVE`, `PART`, `OCTO`.

## Testing loop (do this every change)
Godot console exe: `C:/Users/djoey/Documents/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`. The `.exe` in that path is a folder.

- **Full scripted playthrough:**
  `"$G" --path . -- --demo --play` (add `--gamecam` for the player's camera, `--front` for a front follow camera)
  - Sequence: stand → d-pad up (ready) → walk in ready → stop → draw → hold → walk holding → strike → Circle (drop, relax) → stand → walk.
  - Frames go to `%APPDATA%/Godot/app_userdata/Bending Prototype/demo/run_<unixtime>/` (path printed as `RUNDIR`).
  - Each `F` log line has the state and the largest single-frame bone rotation (`worst=`). Look for spikes at state changes.
  - The capture runs at about 10 fps, so large numbers in fast motion are normal. Compare against neighbouring frames.
- **Short run:** add `--short` to quit at 4 s. `--aimyaw=<deg>` overrides `AIM_YAW` for a test run.
- **Pose vs video:**
  1. `"$G" --path . --script res://tools/pose/compare.gd -- full_right__full "cam:-3.1,1.65,2.5" <times...>` renders the mannequin from about the phone's position. Use `cam:2.6,1.1,3.3` for 90° off, where depth errors show.
  2. `python tools/pose/side_by_side.py mocap/videos/full_right.mov full_right__full out.jpg <times...>` stacks the video frames over the renders.
- **Clip smoothness check without Godot:** load `full_right__full.json` and compute the per-frame quaternion angle per bone inside each slice. Above ~12°/frame is suspicious, except the strike, which is genuinely fast.
- **Script errors:** `"$G" --headless --path . --quit-after 30 2>&1 | grep -iE "error|parse"` (leak messages at exit are harmless).

## Pitfalls already hit
- **Root motion:** when a clip is reset as another starts, the AnimationTree reports the clip's whole travel undone in a single frame (the character jumped back 0.3 m after every draw). `player._process` drops root-motion frames faster than 1.6 m/s. `--rmlog` prints per-frame root motion.
- **Mesh winding:** Godot front faces are clockwise. Generated meshes facing the wrong way vanish; the first puddle did.
- **Scripted aiming:** in test scripts, use `"aimat"` events (`barrel`, `puddle`, `crate`, `pond`, `fountain`, `dummyN`, `boat`, `button`, `personN`, which follows the person), since drawing needs the crosshair on a source. The test camera eases onto a target over about a second: a move made sooner goes where the crosshair still is (a lash hit the wall beside the button that way).
- **Transitions:** `AnimationNodeStateMachineTransition.advance_mode` must be `ENABLED` for `travel()`. `DISABLED` makes every change an instant snap.
- **Scripted input:** the owner's DualShock is usually connected, and its centred stick cancels `Input.action_press` for movement. Scripted runs set `player.debug_move` instead.
- **Shell commands:**
  - Bash heredocs containing apostrophes break. Write patch scripts with the Write tool (see `tests/patchN.py`) and run them.
  - Patch scripts must write to a new file and then move it into place. Python's `open(path, "w")` empties the file before it can fail. There is no git here, and `world.gd` was lost this way once and rebuilt from the session transcript.
  - Glob `rm` is blocked by a safety hook. Don't work around it; write to a new folder instead.
  - Paths contain spaces: quote everything, and don't pass file lists through unquoted `$VAR`.
- **Registering classes:** after adding a `class_name`, run `"$G" --headless --path . --import` once.
- **Read-only folder:** `Avatar Mount and Blade` (the sibling project) is read-only: assets were copied from it, never modify it.

## Open items
- Water timing per draw is a placeholder (`REACH_END` 0.4 in `player.gd`). Ask the owner when the water moves.
- Hands use the tracked wrist and rest fingers. The owner will give adjustments.
- The left-side video (`full_left`) is unused.
- Two fast spots, the end of draw 3 and the strike, were left as recorded.
- The held-water ring follows the hand midpoint loosely (`_ring_off` in `player.gd`).
- **Owner's to-do, noted 2026-11-05 (not started):**
  1. **More ice as water sources:** spikes from the held-R2 volley (stuck or lying) and ice walls must be drawable. A draw aimed at ice takes from the ice around the aimed piece too (a radius of leeway), not only the one spike or cell aimed at.
  2. **Serpent's water:**
     - Twice as thick per litre: it reads as if volume went missing. Not done: the owner is tuning `margin()` and `tail_len()` themselves.
     - Done with the implicit surface (2026-11-05, awaiting the owner's review): one continuous form from the waist to the tail tip; the waist rounds over; no flowing animation, only a light wave.
  3. **Serpent's turning, twice as responsive:** only steering (changing direction) carries half the momentum it does now; it turned in very wide circles unless moving slowly. Speeding up and slowing down along the direction of travel stay as they are (`SerpentWater.accel`). Split the velocity change into along-travel and across-travel parts and give the across part twice the acceleration.
  4. **Walking in the ready stance (polish, waits for the owner's mocap):** a fighting-stance walk. The feet never cross in front of each other, and the back foot never passes the front foot.
  5. **Blocking (when enemies come in):** the Octopus' active tentacle, and what it holds, blocks attacks and projectiles.
  6. **Large-body moves need the owner's review:** geyser, wave and parting each have issues the owner will describe after testing (screen recordings to come). Only the parting's shape (ellipse) and following the bender are done so far.
  7. **Owner's order of work:** large-body moves next (geyser, wave, parting), then Octopus. Showing the stance and per-move arm motions wait for the owner's research and mocap.
