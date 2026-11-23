# After Ragnarok - Teaser v01

1920x1080, 24 fps, H.264 + AAC, 26.0 s. Rebuild with `build_trailer.sh` (ffmpeg); it expects copies of the
source clips in `src/` named as below. Originals in concept_art/heyoz_experiments were not touched.

## Shot list

| # | Scene | Source file (02_generated_videos) | Source in-out | Trailer time | Framing |
|---|---|---|---|---|---|
| 1 | Midgard survives | Seedance 2.5 Video (2).mp4 (854x480) | 0.0-5.0 | 0.0-5.0, fade in from black | 16:9, upscaled |
| 2 | Doom spreads | Seedance 2.0 Video.mp4 (960x960) | 0.0-5.0 | 4.3-9.3, crossfade | square centred, blurred dark side-fill |
| 3 | The abyss | Seedance 2.0 Mini Video.mp4 (960x960) | 0.5-4.0 | 8.6-12.1, dip to black | square centred, blurred side-fill |
| 4 | Skoll awakens | Seedance 2.5 Video.mp4 (854x480) | 0.0-5.0 | 11.4-16.4, dip to black | 16:9, upscaled |
| 5 | Sunna, the last light | Seedance 2.5 Video (1).mp4 (854x480) | 0.0-5.0 | 15.7-20.7, 1 s crossfade | 16:9, upscaled |
| 6 | Title | generated card | - | 20.0-26.0 | "AFTER RAGNAROK" / "The world ended. The struggle did not." |

Not used: Seedance 2.0 Mini Video (1) (flat map flyover), (2) (Skoll on grey studio background), (3) (Sunna T-pose turnaround).

## Sound
All sound is synthesized in the script (no third-party audio, no licence issues): filtered wind (Midgard),
low rumble and cracking noise (Doom), detuned low drones with echo (abyss), rising sub swell and pulsing growl
(Skoll), a slow A-minor rising motif (Sunna), sub impact on the title. It is a placeholder, not finished sound design.

## Limitations
- Sources are 480p (16:9 clips) and 960x960 (square clips). Upscaled to 1080p with lanczos; that adds no real detail and the 480p shots look soft on a large screen.
- The two square clips (Doom, abyss) use a centred square with a dark blurred fill at the sides. The Doom clip has a pale paper background, so it shows as a lighter panel in the middle of an otherwise dark trailer.
- The Doom clip is 5 s, so the final "sinking into the void" stage is only just reached.
- Synthesized audio is functional but thin; no real music.
- Title font is Lora (free); no custom game logo yet.
- AI-generated footage: if this goes on Steam or other marketing, it needs Steam's AI-content disclosure.

## Next version
1. Regenerate Midgard, Skoll and Sunna shots at 1080p (16:9), and the Doom transformation as 16:9 on a dark background and 8-10 s so the tile visibly sinks.
2. Real score and Foley: licensed music or a commissioned 30 s cue; real wind, stone and wolf sounds.
3. A designed logo / title treatment.
4. End on a shot of actual gameplay (the 3D hex map) so viewers see what the game is.
5. Tighter cut to the music: hold Skoll's roar and cut to black on the beat before Sunna.
