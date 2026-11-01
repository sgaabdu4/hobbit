---
name: hobbit-pets
description: Generate and validate animated sprite companions for the Hobbit iPhone app, including angry expressions and audio-driven mouth frames. Use for Hobbit assets, not ChatGPT Work pets.
---

Create app-specific sprites using the existing Images API or the available Imagegen tool. Inspect the user's reference before generating. Preserve character identity and the reference's style. Default Pip is the orange, rounded, pointy-eared 2D creature, not a plush 3D mascot.

Use a transparent square PNG with a 4 by 4 atlas. Preferred dimensions are 1024 or 2048 pixels. The runtime also accepts other square dimensions from 512 to 4096 pixels.

| Row | Expression |
| --- | --- |
| 1 | Calm and attentive |
| 2 | Stern, impatient coach |
| 3 | Furious comic drill sergeant |
| 4 | Happy, proud celebration |

Every row has these columns: closed mouth, small open mouth, wide open mouth, eyes closed in a blink with closed mouth. Keep body size, pose, eye position and baseline identical across columns. Leave at least 8% transparent margin in every cell. Keep ears and feet inside their cells. Request clean alpha with no ground, shadow, text, labels, grid lines, glow or detached specks.

The app generation prompt lives in `server/pet-design.mjs`; preserve this atlas contract when changing that prompt. Generated assets live in `output/imagegen`, with selected app resources copied into `Sources/Habitaker/Resources`. Keep prompts and credit the generator. Do not put API keys or personal references in Git.

Inspect all 16 frames on both cream and dark olive backgrounds before selecting an asset. Check that stern and furious are distinct, closed mouths are closed, pupils stay registered, no ears are clipped, and transparent gutters contain no visible flecks. If generation fails these checks, make one targeted revision and inspect again. Do not claim an atlas is clean based only on file dimensions.

Ask for creature, colour and optional details, with useful defaults. Generate the sheet automatically and preview its moods and talking frames before saving. Do not expose a file-import control. `PetStore.importSheet(data:columns:)` is the internal decoder for generated sheets. New sheets use 4 columns; existing 2-column custom pets remain compatible. Preserve the current pet during generation and on failure.

Use `AnimatedPetView` and `PetMotion` for rendering. Feed real received WebRTC `audioLevel` into the mouth envelope. This is amplitude-driven mouth movement, not phoneme-level lip sync. Mode maps Gentle to calm, Aggressive to stern and Unhinged to furious; clear success can override with happy. Respect Reduce Motion by disabling body movement while retaining mouth indication. Cosmetic expression decisions must never save habit completion.

Run the focused PetMotion tests after changing motion logic. Build the native app and inspect the animation on a device or simulator before claiming playback works. Preserve the approved voice configuration when changing artwork or animation.
