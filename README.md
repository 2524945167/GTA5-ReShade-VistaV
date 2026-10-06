# VistaV — Eye-comfort ReShade shader for GTA V

**English** | [简体中文](README.zh-CN.md)

VistaV is a single-file ReShade effect for **vanilla GTA V** (Enhanced and Legacy). It is built for long play sessions: stable exposure, balanced tones, readable nights and rain, restrained bloom, and no harsh sharpening.

It needs **no depth buffer** and **no game mods**. Everything is computed from the final image.

## Highlights

| Problem in vanilla GTA V | What VistaV does |
|---|---|
| One bright light (headlights, a street lamp) makes the game's eye adaptation darken the whole frame | **Anti eye-adaptation.** Background luminance is metered with light sources excluded. When the game over-darkens, exposure is compensated back through a highlight-preserving curve, so shadows are lifted while headlights and lit surfaces stay near their original level. |
| Rainy nights are dark, flat and hard to read | **Local shadow lift** raises only dark regions, and light sources are excluded so there are no dark halos around lamps. **Adaptive clarity** adds large-radius local contrast and strengthens automatically when the frame is flat (rain, fog, night). |
| Bloom either looks flat or washes the screen white | **Bloom pyramid**: 13-tap downsample, Karis average to stop rain sparkle flicker, soft threshold, a daytime-adaptive threshold, haze suppression, and night glare reduction. |
| Headlights at night are blinding | **Night glare reduction** dims only the brightest pixels at night and fades out during the day. |
| Notification text above the minimap looks soft | **HUD region**: the minimap and notification feed never glow and are excluded from metering. Text edges get halo-free crispening, and the region's tone matches the rest of the screen exactly, so there is no visible patch. |
| Camera turns feel static | **Camera motion blur** (optional). Global camera motion is estimated by block-matching the previous frame, and a light directional blur is applied only while the camera turns. It has a deadzone, a confidence gate, and protection for the HUD and crosshair. |

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

## GTA Online / BattlEye

Rockstar states that BattlEye does not work properly with ReShade, and that ReShade is **disabled during GTA Online gameplay** ([Rockstar Support](https://support.rockstargames.com/articles/ocorZr1KpQE8WvoHE3gBG/battleye-troubleshooting-for-grand-theft-auto-v)). VistaV is therefore meant for Story Mode (including speedruns). Do not try to bypass BattlEye.

## How it works

All processing happens in linear light with 16-bit intermediate textures, so lifting shadows does not cause 8-bit banding. The final output is dithered.

1. **Metering.** A quarter-resolution pass computes `log2` luminance. Highlights get near-zero weight, so the result measures the *background*. A 256×256 mip chain gives the frame's weighted log-average and log standard deviation (contrast), with optional center weighting. The HUD region is excluded.
2. **Adaptation.** The gain needed to move the background toward `Target background luminance` is scaled by the dark/bright compensation strengths, clamped, and smoothed over time with a frame-rate independent exponential filter.
3. **Highlight-preserving gain.** The gain is applied to `max(RGB)` through `f(m) = G·m / (1 + (G−1)·m^q)`. This curve is monotonic for `q ≤ 1`, gives near-full gain at black, and maps 1.0 to 1.0. `Highlight preservation` controls `q`.
4. **Local shadow lift.** A 1/16-resolution, Gaussian-blurred, highlight-excluded local background drives an extra lift for dark pixels only. Because light sources are excluded from the local mean, lamps do not get dark rings.
5. **Clarity.** The pixel's log deviation from the same local background is amplified for mid-tones. The amount rises when the measured frame contrast is low.
6. **Bloom.** Pseudo-HDR expansion of near-white pixels, a 13-tap prefilter with Karis average, soft-knee threshold scaled by a daylight factor, 7-level pyramid with tent upsampling, haze suppression `b·Y/(Y+h)`, and night scaling.
7. **Camera motion blur.** 1/32-resolution luminance of the current and previous frame. 169 candidate shifts (±6 texels) are scored in parallel as 8×8 tiles and reduced by mip level 3. The best shift is refined with a parabola fit and gated by a confidence measure (best vs. mean cost; featureless frames get none). A 12-tap jittered linear blur follows the estimated motion.
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
| Amount (shutter) | 0.28 | Blur length as a fraction of per-frame camera movement. |
| Deadzone | 6 px/frame | Slower motion produces no blur. |
| Max blur length | 40 px | |
| Temporal smoothing | 0.4 | Steadier vs. more responsive. |
| Crosshair protection radius | 0.03 | Screen center is never blurred. |

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
- **Metering mask + meters**: blue = highlights excluded from metering, red = HUD region. Meters in the top-left show global gain (red tick = 1×), frame contrast, daylight factor, motion confidence and camera speed.

### Preprocessor definitions
| Define | Default | Effect |
|---|---|---|
| `VISTAV_STREAK` | 0 | 1 compiles the anamorphic streak passes. |
| `VISTAV_MOTIONBLUR` | 1 | 0 removes all motion-blur passes. |

## Bundled preset

`presets/VistaV_Comfort.ini` sets the chain and these values for the companion effects:

- **ColorMatrix**: `Red (0.80, 0.18, 0.00)`, `Green (0.335, 0.67, 0.00)`, `Blue (0.15, 0.07, 0.87)`, strength 0.58. This mixes some red into green to neutralize GTA's yellow-green cast.
- **AdaptiveSharpen**: strength 0.15, with reduced overshoot (`D_overshoot 0.006`, `scale_lim 0.07`) so it does not glare.

## Recommended in-game settings

- Keep in-game brightness at default and let VistaV handle exposure.
- If notification text looks smeared, try disabling **frame generation**. Interpolated frames often smear sliding or fading HUD text.
- If the image feels harsh, lower the **DLSS / FSR sharpening** in the game (for example 0.2–0.3). It stacks with AdaptiveSharpen.

## Troubleshooting

- **Effect fails to compile:** check `ReShade.log` in the game folder and open an issue with the error line.
- **HUD region looks wrong:** adjust *Region top-left / bottom-right* using the *Metering mask + meters* debug view. The defaults assume 16:9 and the default HUD safe zone.
- **Motion blur triggers when it should not:** raise *Deadzone* or lower *Amount*. Featureless scenes such as open sky are ignored by design.

## Performance

Not formally benchmarked. The technique has about 34 passes. Only two run at full resolution (apply and final composite). The rest run at ½ to 1/128 resolution or on tiny textures.

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
