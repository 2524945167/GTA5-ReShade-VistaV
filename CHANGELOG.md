# Changelog

## 1.0.0 — 2026-10-06

First public release. This version was developed iteratively, with every build tested in GTA V Enhanced (ReShade 6.8.0, DX12, 2560×1440 SDR).

### Features
- **Anti eye-adaptation.** Background metering excludes highlights. A **highlight-preserving gain curve** `f(m) = G·m / (1 + (G−1)·m^q)` lifts shadows while headlights and lit surfaces stay near their original level.
- **Local shadow lift** with highlight-excluded local means, so lamps get no dark halos.
- **Adaptive clarity** that strengthens automatically on flat frames (rain, fog, night).
- **Bloom pyramid**: 13-tap Karis prefilter, soft threshold, daytime-adaptive threshold, haze suppression.
- **Night glare reduction**: night peak dimming and night bloom scale.
- **HUD region** covering the minimap and notification feed: no bloom, excluded from metering, halo-free text crispening, and tone identical to the rest of the screen.
- **Camera motion blur** from global block matching against the previous frame (169 candidates, mip-reduced, sub-texel refined, confidence-gated). The HUD and crosshair are protected.
- **Automatic Chinese/English UI** through ReShade's localized annotations (`*_zh`).
- **Debug views**: split compare, gain heatmap, bloom only, metering mask with meters.
- **`VistaV_Comfort` preset** chaining `VistaV → ColorMatrix → AdaptiveSharpen`.

### Tuning history (from in-game feedback)
- Removed VistaV's own sharpening and lowered AdaptiveSharpen to 0.15 with reduced overshoot (sharpening felt glaring).
- Reverted ColorMatrix to the original user matrix. The blue tint now comes from temperature −0.15 and tint +0.40, giving a cool look without a green cast.
- Removed the region-local tone changes inside the HUD rectangle, which caused a visibly different patch on the left side of the screen.
- Restored the black level to 0 and white to 0.985, with slight contrast and saturation, after the image read as washed out.
- Replaced the old knee-based highlight roll-off with the highlight-preserving gain curve, and widened the night peak dimmer, to stop headlights from over-exposing.
- Reduced motion blur amount to 0.28.

### Fixes
- Replaced `fmod` with a floor-based modulo; ReShade FX has no `fmod` intrinsic.
- Restructured helper functions to single-return form, which removes the compiler's "potentially uninitialized variable" warnings.
