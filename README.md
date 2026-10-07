# VistaV — Eye-comfort ReShade shader for GTA V

**English** | [简体中文](README.zh-CN.md)

VistaV is a single-file ReShade effect for **vanilla GTA V** (Enhanced and Legacy). It is built for long play sessions: stable exposure, balanced tones, readable nights and rain, restrained bloom, and no harsh sharpening.

It needs **no depth buffer** and **no game mods**. Everything is computed from the final image.

## Highlights

| Problem in vanilla GTA V | What VistaV does |
|---|---|
| One bright light (headlights, a street lamp) makes the game's eye adaptation darken the whole frame | **Anti eye-adaptation.** Background luminance is metered with light sources excluded. When the game over-darkens, exposure is compensated back through a highlight-preserving curve, so shadows are lifted while headlights and lit surfaces stay near their original level. |
| Nights (and rain) are dark, flat and hard to read | **Local shadow lift** raises only dark regions, and light sources are excluded so there are no dark halos around lamps. **Adaptive clarity** adds large-radius local contrast and strengthens automatically when the frame is flat (rain, fog, night). |
| Bloom either looks flat or washes the screen white | **Bloom pyramid**: 13-tap downsample, Karis average to stop rain sparkle flicker, soft threshold, a daytime-adaptive threshold, haze suppression, and night glare reduction. |
| Headlights at night are blinding | **Night glare reduction** dims only the brightest pixels at night and fades out during the day. |
| Post-processing makes HUD text glow or skews metering | **HUD region**: the minimap and notification feed never glow and are excluded from metering. Text edges get halo-free crispening, and the region's tone matches the rest of the screen exactly, so there is no visible patch. |
| Camera turns feel static | **Motion blur** (optional). A per-region motion field (160×90 blocks matched against the previous frame) drives a light directional blur. Things that move with the camera — your character, your car, the HUD — are detected as static and stay sharp. |

The effect UI **switches language automatically**: Chinese when ReShade's UI language is Chinese, English otherwise. This uses ReShade's built-in localized annotations (`ui_label_zh`, `ui_tooltip_zh`, ...).

## Requirements

- GTA V Enhanced (DX12) or GTA V Legacy (DX11). Tested on Enhanced.
- [ReShade](https://reshade.me) **6.0 or newer** (localized UI annotations need 6.x). Tested with 6.8.0.
- For the bundled preset, two effects from the official ReShade repositories, both selectable in the ReShade installer:
  - `AdaptiveSharpen.fx` (*Standard effects*)
  - `ColorMatrix.fx` (*SweetFX by CeeJay.dk*)

  VistaV itself has no dependencies besides `ReShade.fxh`.

## Installation

1. Install ReShade for `GTA5_Enhanced.exe` (or `GTA5.exe` for Legacy), select the DirectX 12 (or 10/11) API, and include *Standard effects* and *SweetFX*.
2. Copy `reshade-shaders/Shaders/VistaV/VistaV.fx` into `<game folder>\reshade-shaders\Shaders\VistaV\`.
3. Copy `presets/VistaV_Comfort.ini` into the game folder.
4. In game, open the ReShade overlay and pick `VistaV_Comfort.ini` from the preset list.

The preset chain is **`VistaV → ColorMatrix → AdaptiveSharpen`**. Keep VistaV first.

## GTA Online

VistaV works in both Story Mode and **GTA Online** (tested with BattlEye enabled). It does not use the depth buffer, so it is unaffected by ReShade's depth restrictions in online games. Use the standard ReShade build; the *full add-on support* build is intended for single-player only.

## How it works

All processing happens in linear light with 16-bit intermediate textures, so lifting shadows does not cause 8-bit banding. The final output is dithered.

1. **Metering.** A quarter-resolution pass computes `log2` luminance. Highlights get near-zero weight, so the result measures the *background*. A 256×256 mip chain gives the frame's weighted log-average and log standard deviation (contrast), with optional center weighting. The HUD region is excluded.
2. **Adaptation.** The gain needed to move the background toward `Target background luminance` is scaled by the dark/bright compensation strengths, clamped, and smoothed over time with a frame-rate independent exponential filter.
3. **Highlight-preserving gain.** The gain is applied to `max(RGB)` through `f(m) = G·m / (1 + (G−1)·m^q)`. This curve is monotonic for `q ≤ 1`, gives near-full gain at black, and maps 1.0 to 1.0. `Highlight preservation` controls `q`.
4. **Local shadow lift.** A 1/16-resolution, Gaussian-blurred, highlight-excluded local background drives an extra lift for dark pixels only. Because light sources are excluded from the local mean, lamps do not get dark rings.
5. **Clarity.** The pixel's log deviation from the same local background is amplified for mid-tones. The amount rises when the measured frame contrast is low.
6. **Bloom.** Pseudo-HDR expansion of near-white pixels, a 13-tap prefilter with Karis average, soft-knee threshold scaled by a daylight factor, 7-level pyramid with tent upsampling, haze suppression `b·Y/(Y+h)`, and night scaling.
7. **Motion blur.** A coarse global camera vector is estimated first: 1/32-res luminance, 169 candidate shifts scored in parallel and reduced by mip level 3, refined with a parabola fit. Then a **per-region motion field** is built at 1/16 resolution with a candidate search on 1/8-res luminance, in the style of 3-D recursive search. Each block tests zero, the global vector, and last frame's vectors at itself and 4 neighbors, followed by ±1 and ±0.5 texel refinement, with a small temporal coherence penalty. A 3×3 vector median removes outliers while keeping object boundaries. The blur gathers 4–16 jittered samples along the local vector, and **only samples that move like the center pixel are accepted**, so static-on-screen objects neither blur nor smear into the background.
8. **Tone.** White balance, an exponential shoulder, a night peak dimmer, shadows/highlights, a gentle S-curve with shadow protection, vibrance/saturation, split toning, output levels, an optional vignette, and triangular dither.

## Parameters

Defaults equal the `VistaV_Comfort` preset.

### 1. Exposure Balance (anti eye-adaptation)
| Parameter | Default | Description |
|---|---|---|
| Target background luminance | 0.08 | Desired linear log-average of the background. Higher = brighter nights. |
| Dark scene compensation | 0.40 | Fraction of the gap closed when the scene is too dark. |
| Bright scene compensation | 0.30 | Fraction of the gap closed when the scene is too bright. |
| Max brighten / Max darken | 2.0× / 0.8× | Gain limits. |
| Highlight exclusion threshold | 0.25 | Pixels brighter than this are ignored when metering. |
| Center weighting | 0.40 | Bias metering toward the screen center. |
| Adaptation speed | 1.5 | Lower = calmer, higher = faster. |
| Highlight preservation | 0.75 | How strongly bright areas are kept out of the boost. |

### 2. Local Shadow Lift
| Parameter | Default | Description |
|---|---|---|
| Dark region target | 0.045 | Regions darker than this are lifted. |
| Strength | 0.50 | |
| Max lift | 1.8× | |
| Region radius | 1.0 | Also sets the clarity radius. |

### 3. Clarity
| Parameter | Default | Description |
|---|---|---|
| Clarity | 0.14 | Large-radius local contrast. |
| Low-contrast boost | 1.0 | Clarity × (1 + this) on flat frames. |
| Low-contrast reference | 2.0 stops | Frames below this contrast count as flat. |

### 4. Bloom
| Parameter | Default | Description |
|---|---|---|
| Intensity | 0.15 | |
| Threshold / Threshold softness | 1.2 / 0.5 | In expanded (pseudo-HDR) units. |
| Highlight energy (pseudo HDR) | 0.80 | How much near-white pixels are treated as light sources. |
| Radius | 0.65 | Upsample scatter. |
| Haze suppression | 0.15 | Removes faint wide glow, keeps halos near lights. |
| Daytime threshold raise | 2.0 | Threshold multiplier grows with scene brightness. |
| Bloom saturation / tint | 0.9 / (0.95, 0.94, 1.0) | |

### 4b. Anamorphic Streak
Compiled out by default (`VISTAV_STREAK=0`). Horizontal lens streak with intensity, threshold and color.

### 4c. Camera Motion Blur
| Parameter | Default | Description |
|---|---|---|
| Amount (shutter) | 0.20 | Blur length as a fraction of per-frame movement. |
| Deadzone | 6 px/frame | Slower motion produces no blur. |
| Max blur length | 40 px | |
| Temporal smoothing | 0.25 | Steadier vs. more responsive. |
| Crosshair protection radius | 0.015 | Extra safety radius at the screen center (static HUD is already detected). |

### 5. Tone
| Parameter | Default | Description |
|---|---|---|
| Exposure | 0.0 stops | |
| Temperature / Tint | −0.15 / +0.40 | Cool without going green. |
| Shadows / Highlights | +0.15 / −0.20 | |
| Contrast / shadow protection | 0.05 / 1.0 | |
| Vibrance / Saturation | 0.10 / 1.08 | |
| Split toning, shadow / highlight color | 0.10 | Cool shadows. |
| Night peak brightness | 0.82 | Brightest pixels at night are dimmed to this level. |
| Night bloom scale | 0.60 | Bloom multiplier at night. |
| Output black / white | 0.0 / 0.985 | |
| Vignette | 0.0 | |

### 6. HUD Region
| Parameter | Default | Description |
|---|---|---|
| Region top-left / bottom-right | (0.008, 0.400) / (0.215, 0.990) | Minimap + notification feed for 16:9 with default safe zone. |
| Text crispening | 0.4 | Halo-free edge steepening, clamped to the 3×3 min/max. |

### 7. Debug
- **Split compare**: left original, right result.
- **Gain heatmap**: total exposure change per pixel (blue = darkened, green = unchanged, red = brightened, ±2.5 stops).
- **Bloom only**.
- **Metering mask + meters**: blue = highlights excluded from metering, red = HUD region. Meters in the top-left show global gain (red tick = 1×), frame contrast, daylight factor, global motion confidence and camera speed.
- **Motion vectors**: hue = direction, saturation = speed (full at 48 px/frame), dimmed by confidence.

### Preprocessor definitions
| Define | Default | Effect |
|---|---|---|
| `VISTAV_STREAK` | 0 | 1 compiles the anamorphic streak passes. |
| `VISTAV_MOTIONBLUR` | 1 | 0 removes all motion-blur passes. |

## Bundled preset

`presets/VistaV_Comfort.ini` sets the chain and these values for the companion effects:

- **ColorMatrix**: `Red (0.80, 0.18, 0.00)`, `Green (0.335, 0.67, 0.00)`, `Blue (0.15, 0.07, 0.87)`, strength 1.0. This mixes some red into green to neutralize GTA's yellow-green cast. Make sure only **one** `ColorMatrix.fx` exists under `reshade-shaders\Shaders` — some installs ship a duplicate in the root folder and in `SweetFX\`, which makes ReShade run it twice.
- **AdaptiveSharpen**: strength 0.15, with reduced overshoot (`D_overshoot 0.006`, `scale_lim 0.07`) so it does not glare.

## Recommended in-game settings

- Keep in-game brightness at default and let VistaV handle exposure.
- If the image feels harsh, lower the **DLSS / FSR sharpening** in the game (for example 0.2–0.3). It stacks with AdaptiveSharpen.
- **Frame generation:** generated frames may not pass through ReShade, so processed and unprocessed frames can alternate. If you see flicker (especially in recordings), test with frame generation off, or use a driver-level option such as NVIDIA Smooth Motion instead.

## Troubleshooting

- **Effect fails to compile:** check `ReShade.log` in the game folder and open an issue with the error line.
- **HUD region looks wrong:** adjust *Region top-left / bottom-right* using the *Metering mask + meters* debug view. The defaults assume 16:9 and the default HUD safe zone.
- **Motion blur triggers when it should not:** raise *Deadzone* or lower *Amount*. Featureless scenes such as open sky are ignored by design.
- **Recording flickers in OBS:** OBS *Game Capture* and ReShade both hook the game's present call, which can make the capture alternate between processed and unprocessed frames ([obs-studio#11250](https://github.com/obsproject/obs-studio/issues/11250)). Use *Display Capture* instead, or the NVIDIA App recorder.
- **Colors look doubled or too strong:** make sure only one `ColorMatrix.fx` exists under `reshade-shaders\Shaders`.

## Performance

Measured with ReShade's statistics page at 2560×1440 on an RTX 4070 (GTA V Enhanced, full `VistaV_Comfort` preset, 169 fps):

| Effect | GPU time |
|---|---|
| VistaV (32 passes) | ≈ 1.27 ms |
| ColorMatrix | ≈ 0.09 ms |
| AdaptiveSharpen | ≈ 1.01 ms |
| Whole chain | ≈ 2.36 ms |

Only two VistaV passes run at full resolution (apply and final composite); the rest run at ½ to 1/128 resolution or on tiny textures. Motion blur uses 4–16 samples depending on blur length and is skipped for pixels below the deadzone. Once tuned, enable ReShade's **Performance Mode** so disabled features are compiled out. Numbers vary with GPU and scene.

## Authors

- **ROSS2014**: concept, requirements, in-game testing and tuning.
- **Claude** (Anthropic): shader design and implementation, documentation.

VistaV was built collaboratively. ROSS2014 described the problems, tested every build in game and steered the look; Claude wrote the code and docs.

## Credits

- Bloom downsample filter: Jorge Jimenez, *Next Generation Post Processing in Call of Duty: Advanced Warfare* (SIGGRAPH 2014). Karis average: Brian Karis.
- `AdaptiveSharpen` by bacondither, `ColorMatrix` by Christian Cann Schuldt Jensen (CeeJay.dk). These are not included in this repository; install them through the ReShade installer.
- ReShade by crosire.

## License

[MIT](LICENSE)
