# MiniLab Particle DJ - User Manual

Welcome to **MiniLab Particle DJ**, a native macOS performance app that transforms your Arturia MiniLab Mk2 (or any Core MIDI keyboard) into a compact synthesizer, loop station, auto-harmony engine, and reactive VJ visuals station.

---

## 1. Overview & Setup

### Requirements
*   **Operating System**: macOS 14 (Sonoma) or newer.
*   **Controller**: Arturia MiniLab Mk2 (recommended) or any Core MIDI keyboard.
*   **Audio Output**: Built-in Mac speakers or standard audio interface.

### Running the App
1.  Connect your MIDI controller via USB.
2.  Open the project in Xcode:
    ```sh
    open Package.swift
    ```
3.  Ensure the target destination is set to **My Mac** and run the project (`Cmd + R`).
4.  Play the keys to verify audio generation and visual feedback.

---

## 2. Interactive Performance Controls

The main workspace is designed around a premium visualizer-first layout. The controls are housed in responsive, floating glassmorphic panels using macOS `.ultraThinMaterial` backgrounds. This allows the VJ visuals to bleed and blur beautifully behind the interface.

To accommodate different monitor sizes and configurations (with a minimum height requirement of `720` points), all panels below the HUD are wrapped in a vertical scrolling list. The HUD remains pinned at the top for immediate feedback, while other controls can be scrolled if needed (such as when the MIDI Mapping panel is open).

### On-Screen Interactive Keyboard
An interactive, 2-octave piano keyboard is available in the center of the panels:
*   **Play Keys**: Click and hold down any white or black key with the mouse to play the note. Release the mouse button to stop.
*   **Glow Indicators**: Keys will glow in cyan when active (either clicked by the mouse or played via your connected MIDI controller).
*   **Score Integration**: Any key clicked on the screen keyboard is played in real-time and automatically written/drawn on the **Played Note Score** grand staff below, spawning at the playhead line instantly.

### Played Note Score (Real-Time Grand Staff)
The **Played Note Score** is a real-time grand staff piano roll displayed in the center of the panels:
*   **Playhead**: A vertical dotted red line is fixed at the right side of the canvas representing "Now".
*   **Note Spawning**: As you press keys (hardware or on-screen), notes spawn instantly at the playhead line and scroll-move left into the past, passing the static Treble (𝄞) and Bass (𝄢) clefs on the left.
*   **Note Tails**: Note tails stretch to represent the duration of the note. Active notes (still held down) remain anchored to the playhead, showing an active glow ring until released.
*   **Layer Color-Coding**: Notes and tails are color-coded based on the layer that triggered them (Layer 1: Green/Mint, Layer 2: Cyan, Layer 3: Pink, Layer 4: Purple), making it easy to see which part of the melody or generated harmony plays each note.
*   **Ledger Lines**: The view automatically draws a ledger line for Middle C (C4 / MIDI Pitch 60) when triggered.

### Instrument Selection Panel
Each of the 4 sampler layers can have its instrument preset changed on the screen:
*   **Active Indicator**: The currently active keyboard layer is highlighted with its specific theme color indicator dot and row border. Click on a layer row to select it as the active layer.
*   **Preset Selection Dropdown**: Click on the preset selector dropdown next to the layer to choose a Melodic/Drum kit starter sound bank, or import custom `.sf2`/`.dls` libraries.

---

## 3. The Auto-Harmony Engine

### Where is Auto Harmonic Play?
Auto-harmony is **triggered automatically on your keyboard inputs**. When you play a melody on the current active layer, the harmony engine calculates appropriate accompaniment notes in real-time and plays them arpeggiated across the other three background sampler layers.

### Harmony Modes & Selection
You can cycle through 7 distinct harmony structures using your pads. 
*   **How to Trigger**: Hold down **Pad 14** (which acts as a modifier) and tap any of the first 7 pads:
    *   **Hold Pad 14 + Pad 1**: Harmony **Off** (plays only your melody note)
    *   **Hold Pad 14 + Pad 2**: **Close 3rds** (adds a close diatonic third)
    *   **Hold Pad 14 + Pad 3**: **Open 5ths** (adds perfect fifths)
    *   **Hold Pad 14 + Pad 4**: **Full Triad** (diatonic root, third, and fifth)
    *   **Hold Pad 14 + Pad 5**: **Dreamy** (floating scale extensions)
    *   **Hold Pad 14 + Pad 6**: **Seventh** (chords with major/minor 7ths)
    *   **Hold Pad 14 + Pad 7**: **Open Octaves** (doubles notes across octaves)

### Modulating Harmony via Knobs & HUD
The scale, pitch root, and complexity can be set from the top settings bar:
*   **Key & Scale Pickers**: Tell the harmony engine what scale (e.g. C Major, A Minor) to snap to.
*   **Complexity Slider**: Adjusts arpeggiation micro-delays, velocity deviations, and max voices.
*   **CC Knob 3**: Modulates the harmony **Spread** (octave separation of voices).
*   **CC Knob 4**: Modulates the harmony **Maximum Voice Count** (up to 4 voices).

---

## 4. Performance Looping & Capturing

MiniLab Particle DJ captures phrases on the fly for automatic echo replays.

*   **Phrase Loop**: Play any melody + auto-harmony phrase inside a bar. At the start of the next measure, it repeats that phrase on the selected grid.
*   **Decay Echoes**: The phrase loops up to **5 times**, fading out gradually on each repetition.
*   **Drum Companion**: Toggle the `Drums` switch on the top bar to enable a built-in step beat companion aligned with the BPM and Time Signature.
*   **Tactile Pad Shortcuts (Hold Pad 13 as Modifier)**:
    *   **Hold Pad 13 + Pad 15**: Toggles **Loop Playback** on/off.
    *   **Hold Pad 13 + Pad 16**: Toggles the **Drumbeat** on/off.

---

## 5. VJ Canvas & Visual Scenes

The visualizer responds dynamically to note velocities, MIDI CC inputs, and real-time FFT audio bands (Bass, Mid, Treble).

### Visual Scenes
Select a visual background scene from the **Visuals** picker on the settings bar:
*   **Hyperdrive**: Radial bursts exploding from the center of the screen at high speeds.
*   **Rain**: Falling vertical droplets reacting to gravity, with bass triggering splashes.
*   **Orbit**: Swirling vortex paths rotating around the screen center like a spiral galaxy.
*   **Nebula**: Soft translucent cosmic clouds slowly drifting and fading.

### Knob Modulators
You can shape the visuals with your knobs:
*   **Knob 1 (CC 74)**: Controls visual **Brightness**.
*   **Knob 2 (CC 71)**: Controls visual **Gravity** (pushes particles down or pulls them up).
*   **Knob 3 (CC 73)**: Modulates **Particle Size**.
*   **Knob 4 (CC 72)**: Modulates **Trail Length** (motion blur decay).

### Fullscreen Mode
Click the **Expand** button (`arrows.expand`) next to the Visuals picker to enter fullscreen VJ mode. Press the button again or use `Esc` to return.

---

## 6. MIDI Learning & Map Config

If your MIDI controller has a different layout than the factory default, you can remap controls instantly:
1.  Click **Map...** next to the MIDI channel stepper.
2.  At the top of the mapping panel, you can see all active **Inputs** (connected MIDI device names) detected by the OS.
3.  To map a Knob: Click **Learn** or **Unmapped** next to a parameter (e.g., Gravity). The button will say **Waiting...**. Twist a knob on your controller to bind it.
4.  To map a Pad: Click a pad cell (e.g. Pad 1) in the 4x4 grid. Press a physical pad on your controller to map it.
5.  All mappings are saved automatically to your Mac's `UserDefaults` and persist across sessions.
6.  Click **Reset Defaults** to restore the factory Arturia MiniLab configuration.
