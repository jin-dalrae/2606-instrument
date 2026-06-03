# Product Requirements Document: MiniLab Particle DJ

## Overview

MiniLab Particle DJ is a native macOS app that turns an Arturia MiniLab Mk2 into a small live performance workstation. The product combines a MIDI-controlled sampler rig, automatic harmony, instrument switching, and an audio-reactive visualizer so a single performer can play layered synth/DJ-style sets without a DAW.

The implementation is a native macOS SwiftUI app powered by AudioKit 5. Performer can connect the controller, choose a layer, select instruments with pads, play keys, hear automatic harmony, and see visuals react to the performance with zero-latency audio and graphics rendering.

## Goals

- Provide a low-latency native macOS performance app for MiniLab Mk2 users.
- Keep audio, MIDI, harmony, and visualization fully on-device.
- Make common live controls available from the controller, not only the screen.
- Support free instrument libraries through SoundFont and DLS loading.
- Establish a clean architecture that can grow into a fuller mini-DAW/VJ tool.

## Non-Goals

- Cloud-based audio generation or remote inference.
- Full DAW editing, arrangement timeline, or clip launcher in the first version.
- Commercial SoundFont bundling without explicit license review.
- Deep controller editor support for every MiniLab mapping preset.
- Plugin hosting for VST/AU instruments.

## Target Users

- Musicians with an Arturia MiniLab Mk2 who want a lightweight performance rig.
- Producers who want fast sketching without opening a full DAW.
- Live visual performers who want visuals tied directly to MIDI/audio energy.
- Beginners who want automatic harmony while learning keys and chord structure.

## Scope

### Audio Engine

- One AudioKit `AudioEngine`.
- Four `AppleSampler` layers.
- One output `Mixer`.
- Built-in macOS DLS bank used for starter sounds.
- Runtime `.sf2` and `.dls` import into the current layer, with automatic security-scoped bookmark persistence.
- Separate loop playback samplers preserve the instrument sound used when a phrase was captured.
- Dedicated drum sampler provides the built-in beat.
- Independent Delay and Reverb effects configured per layer.

### MIDI Input

- AudioKit `MIDI` listens to Core MIDI inputs.
- Active device monitoring listing connected ports in real time.
- MIDI note-on plays the selected layer.
- MIDI note-off stops the played note and generated harmony notes.
- Pad notes `36...51` on the configured pad channel select the instrument preset.
- Modifier pad shortcuts: Hold Pad 13 to select active synthesizer layer or toggle looping/drums; Hold Pad 14 to select diatonic harmony modes.
- CC messages control visual parameters (brightness, gravity, particle size, trails).

### Harmony

- Tracks active notes per layer.
- Estimates key and chord context from active/recent melody notes.
- Generates diatonic harmony notes from scale degrees and detected chord tones.
- Routes harmony voices across the other sampler layers.
- Supports harmony styles: off, close thirds, open fifths, full triad, dreamy, seventh, and open octaves.
- Supports hardware-controlled voice count and spread.
- Supports screen-controlled key, scale, time signature, and harmony complexity.
- Timing micro arpeggiations and velocity humanization.

### Visualizer

- AudioKit `FFTTap` analyzes the mixed output.
- Bass, mid, and treble bands drive particle behavior.
- Note velocity adds transient visual energy.
- SwiftUI `Canvas` renders particles.
- Visual scenes: Hyperdrive, Rain, Orbit, and Nebula.
- Knobs control brightness, gravity, particle size, and trail feel.

### UI

- Main performance screen with full-window particle visualizer.
- Premium glassmorphism layout using macOS `.ultraThinMaterial` backgrounds.
- Fixed, no-scroll performance surface at the supported desktop minimum.
- Compact HUD for audio/MIDI state, last MIDI event, current instrument, and detected harmony/scale label.
- Key, scale, time-signature, custom playback toggles, and harmony-complexity controls.
- **Smart On-Screen Chord Pads**: Eight diatonic chord pads adapt to the active key and scale. A click triggers a quantized one-shot note with auto-release, while the played pitch writes directly to the grand staff score.
- **Real-Time Scrolling Note Score**: A scrolling grand staff displaying treble/bass clefs, Middle C ledger lines, color-coded layer note tracks, and active glows, synchronized with zero visual latency (playhead at `size.width - 60`).
- Instrument preset and layer selection remain controller-led through MiniLab pad shortcuts; the HUD shows the active instrument.
- Particle-only visualizer without graph-style meters over the performance view.

## User Stories

- As a performer, I can connect my MiniLab Mk2 and immediately play a sound from the keys.
- As a performer, I can press a pad to switch the current layer's instrument.
- As a performer, I can select a different layer from the controller and load a different instrument into the active layer.
- As a performer, I can play a melody and hear automatic harmony on companion layers.
- As a performer, I can turn knobs and see the visualizer respond during playback.
- As a producer, I can import a free SoundFont and use it without modifying the code.
- As a developer, I can change controller note/CC mappings in one place.

## Functional Requirements

### Audio
- The app must start an AudioKit engine when the main window opens.
- The app must create four playable sampler layers.
- The app must route all layers to a shared mixer output.
- The app must load starter presets from a local DLS source.
- The app must accept user-selected `.sf2` and `.dls` files at runtime, persisting access using security-scoped bookmarks.

### MIDI
- The app must listen to Core MIDI input ports and list active interfaces.
- The app must handle note-on and note-off events.
- The app must map MiniLab-style pad notes to instrument presets, layers, and harmony modes.
- The app must map selected CC messages to visual controls.
- The app must support an all-notes-off path from hardware controls (Hold Pad 1 + Pad 16).
- The app must support live MIDI Learn for remapping CC knobs and pads, automatically saving configurations in `UserDefaults`.

### Harmony
- The app must generate harmony voices in real time from incoming note-on events.
- The app must keep generated notes within the valid MIDI note range.
- The app should prefer diatonic harmony based on detected major/minor context.
- The app should support arpeggiator micro-delays and velocity humanization.

### Looping
- The app must collect notes released inside the current measure into a phrase buffer.
- The app must repeat captured phrase notes five times as one bar-aligned phrase, fading out gradually.
- The app must preserve the captured instrument timbre for scheduled repeats even after the live instrument changes.
- Drum beat companion must follow BPM and time-signature grid configurations.

### Visualization
- The app must analyze mixer output with FFT.
- The app must render particles continuously using custom visual scenes.
- The app must react to both audio energy and MIDI note velocity.

### UI
- The app must show active preset, app status, and last MIDI event without covering the visualizer.
- The app must keep the primary screen visualizer-first without vertical page scrolling.
- The app should be usable at a desktop window size of at least `1120 x 720`.

## Non-Functional Requirements

- Audio and MIDI response should feel immediate for live playing.
- The app must run without cloud services.
- The app should build as a Swift package and open cleanly in Xcode.
- Visual rendering should remain smooth under normal particle counts.
- Strict Swift 6 concurrency hardening is fully enforced across all modules.

## Success Metrics

- The app builds successfully with `swift build`.
- A connected MiniLab Mk2 can trigger sound from the hardware keys and pads.
- The on-screen chord pads can trigger quantized one-shot harmony figures without requiring click-and-hold input.
- All 16 pads can select starter presets.
- Holding pad 1 and pad 16 together stops active notes.
- Holding pad 13 and pressing pads 1-4 changes the current layer.
- Holding pad 14 and pressing pads 1-7 changes harmony mode.
- Imported `.sf2` or `.dls` files can be loaded into a layer.
- Particles respond to played audio and MIDI note velocity.

## Risks and Open Questions
- Enforced strict Swift 6 concurrency: all mutable audio/UI state is isolated to `@MainActor` in `AudioManager`, and background MIDI events route safely across concurrency boundaries.
- Command-line build works, but full app runtime testing should be done in Xcode with actual MIDI hardware.

## Milestones

### M1: Hardware Validation (Completed)
- Tested with a real MiniLab Mk2.
- Confirmed pad notes and knob CC values.
- Added a MIDI monitor panel for discovering custom mappings.
- Confirmed note-off behavior for generated harmony voices.
- Confirmed pad 1 + pad 16 panic behavior.

### M2: Instrument Workflow (Completed)
- Added a persistent instrument library browser.
- Configured security-scoped bookmarks for custom SoundFonts.
- Added save/load performance sessions in JSON format (plus auto-restore).

### M3: Harmony Controls (Completed)
- Added harmony modes: Off, Close 3rds, Open 5ths, Full Triad, Dreamy, Seventh, and Open Octaves.
- Added key/scale lock and arpeggiation micro-timing and velocity humanization.

### M4: Performance FX (Completed)
- Configured individual Delay and Reverb effects per layer.
- Mapped physical knobs to visual and audio parameters.
- Built-in output level protection and panic pathways.

### M5: Visual System (Completed)
- Added visual scenes: Hyperdrive, Rain, Orbit, and Nebula.
- Added native AppKit fullscreen mode.
- Built-in Scrolling Played Note Score grand staff replacing the played event log.
- Enforced a fixed no-scroll performance surface, on-screen chord-pad trigger, and glassmorphic `.ultraThinMaterial` styling.
