# Linner - Development Milestones

## Phase 1: Environment & Toolchain Foundation
*   **Goal:** Establish the WSL development loop.
*   **Tasks:**
    *   Set up WSL Linux workspace directory structure (`/src`, `/build`, `/tools`).
    *   Configure `Makefile` or build script to compile Z80 assembly using `rasm`.
    *   Automate disk image creation using `idsk` to generate an extended disk format (`.dsk`).
    *   Set up launch scripts to instantly boot the compiled `.dsk` in both `cpcemu` and `caprice32` snap packages.
    *   *Deliverable:* A basic "Hello World" or blank screen successfully compiling and running in the emulators with a single command.

## Phase 2: Core Vector Engine & 50 FPS Display
*   **Goal:** Achieve a solid 50 frames-per-second baseline for vector drawing.
*   **Tasks:**
    *   Initialize Amstrad CPC screen modes and CRTC hardware for optimal vector rendering (likely Mode 1 for 4 colors or Mode 0 for 16, depending on memory/speed trade-offs for the single-color background).
    *   Implement an ultra-fast line-drawing routine (e.g., optimized Bresenham algorithm).
    *   Create pre-calculated Lookup Tables (LUTs) in memory for Sine/Cosine to handle fast rotation calculations without runtime math.
    *   Implement an efficient screen clearing/erasing routine (dirty rectangles/lines) to maintain 50fps without redrawing the whole screen.

## Phase 3: The Line & The Hero
*   **Goal:** Get Linner on screen and moving.
*   **Tasks:**
    *   **The World:** Implement the procedural or data-driven generation of the ground line (green/brown) scrolling from right to left.
    *   **The Hero:** Draw Linner (a circle) with the single internal ray.
    *   **Physics:** Stick Linner to the line. Make the internal ray rotate based on horizontal movement and terrain slope.
    *   **Controls:** Implement the 5-speed variable acceleration system.

## Phase 4: Terrain Hazards & Agility
*   **Goal:** Introduce platforming elements.
*   **Tasks:**
    *   Implement "empty space" gaps in the line.
    *   Implement "water lines" (blue) that slow down or destroy the player if not traversed correctly.
    *   Add jump mechanics, complete with gravity and smooth landing detection back onto the vector line.

## Phase 5: Combat & The Geometry of Doom
*   **Goal:** Enemies and the firing system.
*   **Tasks:**
    *   **Enemies:** Create routines to draw and spawn hostile vector primitives (Rectangles, Triangles).
    *   **Targeting:** Implement the 180-degree targeting system (from behind to front). Use the pre-calculated LUTs for 10-degree increments (19 distinct firing angles).
    *   **Controls:** Bind the UP and DOWN arrows to adjust the firing angle, and a fire button to shoot vector projectiles.
    *   **Collision:** Implement point-in-polygon or bounding-box collision detection for projectiles hitting enemies.

## Phase 6: Powerups & Game Loop
*   **Goal:** Items, timers, and level completion.
*   **Tasks:**
    *   Spawn Rhombus powerups.
    *   Implement the "Phase Out" (invincibility/clipping) powerup effect.
    *   Implement the "Maximum Speed" powerup effect (unlocking the 5th speed tier).
    *   Add obstacles/traps to the ground line.
    *   Implement the level countdown timer and end-of-level triggers.

## Phase 7: Disk I/O & High Scores
*   **Goal:** Persistent player glory.
*   **Tasks:**
    *   Create the High Score screen logic (Top 10 list).
    *   Implement a 5-character name entry system using the joystick/keyboard.
    *   Write Z80 routines to interact with the AMSDOS/Firmware (or direct FDC commands) to save and load the high score table to a specific sector on the extended `.dsk` via `idsk` compatibility.

## Phase 8: Polish, Balance, & Release
*   **Goal:** Finalize the game.
*   **Tasks:**
    *   Design and encode level data (terrain maps, enemy spawn timings).
    *   Balance the 5 speeds and the 50fps difficulty curve.
    *   Extensive playtesting on both `cpcemu` and `caprice32` to ensure hardware timing accuracy and no frame drops.
    *   Finalize disk label and release package.