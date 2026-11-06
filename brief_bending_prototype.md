# Brief: Bending prototype (new project)

Read this whole document before doing anything. It has three parts: the owner's own description of the idea, the interpretation and technical thoughts of the agent (Kestrel) that worked on the owner's previous project, and the rules you must follow. The owner's words come first and take precedence over any interpretation.

## 1. Rules of conduct (non-negotiable)

**Quality.** The prototype may be rough in art. It may not be rough in its core feature: movement and bending.

- Animation must be fluid and natural. Water must always behave and look like water and move fluidly. Elements must never be amorphous blobs and must never look like generic particle effects.
- "Utterly realistic without exception" is the standard the owner holds the work to. It is not a claim that anything is achievable by default. It exists so you never hand over something cheap or generic and expect it to be accepted.
- Do not take the quick, generic version of a feature because it is easy to write. The owner has seen coding agents do this repeatedly. It is the failure this project is meant to avoid.

**Stop and ask, in every one of these cases:**
1. You cannot do something right away: say so before writing any code for it.
2. Something is possible but not quick: do not shortcut it. Propose a plan and ask the owner what help they can give. They intend to help as much as you help them (reference footage, models made in Blender, testing by hand).
3. Anything is unclear: ask for clarification first. Do not guess.
4. You cannot verify that something looks right (a single still frame cannot show motion quality): say that, and ask the owner to judge. Do not report it as done.

**Communication.** Concise, detailed, in the style of an encyclopedia entry. No overexplaining (the owner will ask for detail when needed). No restating or paraphrasing what the owner just said. No metaphors, no flowery or cute language, no compliments.

## 2. The owner's description, verbatim

The owner shared the following message to describe the idea. It is their own writing, unedited.

> So, bending is a very involved form of ability, where the user is far more intertwined with how they manipulate reality, arguably far more so than those with superpowers and those with magical spellcasting. 
> Bending is dynamic, and is not an on/off switch. Shooting laser beams, turning invisible, reading minds, etc do not relate in feel-of-use. They are not similar in function or activation. Casting fireball or any other spell may have some preliminary incantation and particular movement, but it is one effect each time. Sure, sometimes a firebender can do a single punch while drawing upon the energy within them to shoot a single fire blast, but they also can actively warp and shape flames, an active process more similar to working by hand with clay. Waterbending is by far the most dissimilar to non-bending supernatural abilities, the most involved in its movements, the water becoming almost part of the bender as the water literally bends to follow the nuanced movements of the bender. Sure there are particular waterbending moves, but once a waterbender truly knows these moves, they don't do the sequence every time for the same effect, but instead incorporate the bodily movement, the flow of their chi, and the feeling of the water that is melding with their self, in unique ways depending on the situation.
> Do you see where I'm going with this?
> What I want for a game is not a system of discreet actions producing set effects. I want active involvement with the elements, in a real and living way that AtLA presents it as. 
> This goes beyond our Avatar Mount and Blade prototype, so just set that aside right now and let me describe what I picture in my mind right now, set in a 3d game world, 3rd person perspective.
>
> I see the player's character, a waterbender, seen standing in a village of closely built tan earthen buildings on a dusty sandy ground. Among the moving people, decorations, and various other set dressings, is a barrel full of water. The character walks around with a walk animation like any other, idles in a normal idling stand, until the player presses a button and the character moves into a waterbending/martial-arts pose. They are readied and the barrel of water, as it goes for every source of water whenever the character is made readied to bend, is highlighted in a light outline, the water inside just visible as the player-facing side of the barrel is made 50% opaque. The player has an understanding that, mechanically, the water is available to be bended and, in-fiction, the character is feeling the water around, aware of it and ready to manipulate it through their own will. Another button press, this time held, and the character moves in a fluid drawing-in motion while the water rises from the barrel and travels to the character. The player retains hold on the button; the character moving their body in a gentle and fluid flowing motion, standing planted, but weaving the water around them. It is clear that this is how the waterbender idles when actively holding water, before deciding how to use it. The player turns the character to look at something in the scene, perhaps a hanging signpost. Aimed at the signpost, another button is pressed, the character makes a definitive martial arts move that evoke the energy of an aimed strike, and the water SHOOTS streamlined at the signpost, which flies off its hinges and lands wet on the ground.
> Other things that could be done with this waterbender character in a martial arts pose, ready:
> 1. standing in front of a body of water, maybe a fountain or lazy stream, and then doing a push and pull of the water, water rising and coming in with the swinging back of the body and arms, then back out with the swing back forward.
> 2. a variety of single-use moves, perhaps prepared like Kengo, or perhaps selected as through an inventory selector wheel, or both, that has the character shoot a piercing ice shard from their water, or volley a net that catches and turns to ice to trap, or the character makes martial arts moves that use slicing hands with the water slicing what's in front of them
> 3. moving water with precision, like how the force works in a lot of Star Wars games, where use of buttons and toggles has the water move any which way the player likes, including washing over people and getting them wet, firmly grabbing people and objects to move them, washing over fires to put them out, turning it to ice blocks or stairs or slides to aid movement about the terrain, and more
> And this is by no means an all inclusive list.
> What are your thoughts? I want to see if you're understanding the picture I have. I understand you've been doing so much for this mount and blade idea, and this could be quite a turn, so if it's better to go open a new chat, let me know

## 3. Interpretation and technical thoughts (Kestrel)

These are my reading and my suggestions. Where the owner's text above and this section disagree, follow the owner. Challenge anything here that seems wrong.

### 3.1 Scope of the prototype

Art is placeholder: featureless white; a default placeholder character; buildings of plain boxes with cut-out doors and windows; a signpost that is a flat rectangular prism. Movement, animation and bending are not placeholder.

The first milestone is a vertical slice of the owner's scene: walk and idle; press to enter the ready pose; water sources highlighted; hold to draw water from a barrel to the character (the barrel visibly empties); hold to keep the water weaving around the body; aim at a signpost and strike, so the water travels to it, the sign is knocked loose, and the sign ends up wet. Nothing else should be started before the owner approves this slice.

### 3.2 Reading of the design

Bending is a continuous state in which the player stays, with decisions made inside it. The scene suggests these states: normal (walk, idle), ready (pose, sources highlighted), drawn (water held and weaving), release (a strike or another action). Water is a conserved resource in the scene: a barrel that has been drawn from is lower, and a target hit by water is wet.

The owner's three examples are two different control paradigms:
- Examples 1 and 2 (push and pull at a fountain; ice shard, net, slicing hands) are body-driven. Animation drives the water, and the player picks the intent and timing.
- Example 3 (Force-style) is direct control: the player steers the water with a stick or cursor, with the body animation secondary.

They need different inputs, animation and tuning. I suggest building the body-driven paradigm as the core and the precision paradigm as a separate mode, entered deliberately (for example, with a held modifier). Ask the owner before deciding this.

### 3.3 Suggested technical approach

These are suggestions to evaluate, not instructions.

- **Engine:** Godot 4.7, standard build, **Forward+** renderer (not Compatibility). Water needs screen-space refraction, depth effects and a good shader pipeline. Headless mode uses a dummy renderer and draws nothing, so run the game in a real window and capture frames from the viewport.
- **Water as a simulated body, not an effect.** A chain of points with distance constraints and damping, anchored to hand bones, rendered as a tube or ribbon with a flowing shader. It must lag behind the hands and swing as the body turns. A particle burst started by an animation cannot do this. Consider whether a metaball-style surface or a screen-space fluid pass is needed to avoid the "blob" look, and say if you think it is out of reach.
- **Layered animation.** The held-water idle is an upper-body layer over normal locomotion, so the character can walk, turn and keep weaving. A full-body pose that blocks movement would break the idea of the water becoming part of the bender.
- **Responsiveness.** A fixed-duration cast time would feel like a spell. Draw, hold and release should follow the player's input and the character's motion.
- **Sources.** Barrels, fountains, streams and puddles each need a reserve and a visible way of depleting.
- **Animation supply.** Responsive bending needs many small, blendable motions, not whole clips. Flowing, circular water-bending motions probably have to be authored or captured. Tell the owner early what you need (reference video, Blender-made clips, motion-capture sources) and what the options cost.

### 3.4 Assets from the previous project (Beeferlyporkgame, GitHub)

The previous project is a Mount & Blade-style game in Godot, in `maeveywavey/Beeferlyporkgame` (private). The owner can give you access. Possibly reusable:
- The character rig and the placeholder mannequin model (Quaternius CC0 rig, 65 bones, +Z forward, `Armature/Skeleton3D`).
- `scripts/actors/stance_ik.gd`: a SkeletonModifier3D that pins feet and hands for standing stances.
- The Universal Animation Libraries 1 and 2 (CC0): locomotion and general motions. They have no strafe, backward walk, turning in place or bending clips.
- The Motifect martial-arts pack (40 clips, free for commercial use) and the retarget tool in `tools/motifect/`. Retarget quality is not good enough to trust unchecked. Some arms bend more than the source, and some hand poses are wrong.
- The bending lab (`scripts/ui/bending_lab.gd`), a tool for previewing clips.

Do not copy the old game's combat, map or economy code. Its structure assumes a different game.

### 3.5 Known limits and risks

- Fluid-looking water is a real graphics problem. Water is the right first element because it is the hardest and the most distinctive. Earth, fire and air will each need their own physical model later.
- A single screenshot cannot show whether motion looks natural. Capture short frame sequences or video, compare against reference footage, and ask the owner to judge.
- A press-and-hold interface is easy to build and hard to make expressive. Judge the first prototype by whether two minutes with one barrel is engaging.
- The owner is non-technical. They test by playing and will report by describing what they see. Give them short, specific things to try, and say exactly what you could not verify.

## 4. First steps

1. Confirm that you have read this and list anything unclear. Do not write code yet.
2. Propose a plan for the slice in section 3.1, with a list of what you need from the owner and anything you think cannot be done well at this stage.
3. Wait for the owner's approval before building.
