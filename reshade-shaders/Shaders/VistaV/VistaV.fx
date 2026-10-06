/*
    VistaV.fx - Balanced exposure, readability and bloom for GTA V (vanilla)
    -------------------------------------------------------------------------
    Target: GTA V Enhanced / Legacy, SDR output, no depth buffer required.
    Designed to run first in the chain:  VistaV -> ColorMatrix -> AdaptiveSharpen

    Goals (in priority order):
      1. Eye comfort for long sessions: no pumping, no harsh highlights, no over-sharpening
      2. Balanced tone: highlights not too bright, shadows not too dark
      3. Readability at night / in rain
      4. Clean, restrained bloom

    Pipeline (linear light, 16-bit intermediates):
      1. Scene analysis   : log-average background luminance with highlights excluded
      2. Anti eye-adapt   : when a single bright light makes the game darken the whole frame,
                            the background gets darker -> exposure is compensated back
      3. Local shadow lift: lifts dark regions only, light sources excluded (no dark halos)
      4. Adaptive clarity : mid-frequency local contrast, boosted when the frame is flat (rain/fog)
      5. Bloom            : 13-tap pyramid, Karis average (no rain sparkle flicker),
                            soft threshold, day-adaptive threshold, haze suppression
      6. HUD region       : minimap + notification feed get no bloom, less local processing,
                            and halo-free text crispening
      7. Tone             : shadows / highlights, gentle contrast, output levels, dither
*/

#include "ReShade.fxh"

// Set to 1 to compile the anamorphic streak passes (off by default for eye comfort)
#ifndef VISTAV_STREAK
    #define VISTAV_STREAK 0
#endif

// Set to 0 to compile out the camera motion blur passes
#ifndef VISTAV_MOTIONBLUR
    #define VISTAV_MOTIONBLUR 1
#endif

// ============================================================================
// UI
// ============================================================================

// ---- 1. Exposure balance ----
uniform bool EnableExposure <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_label = "Enable";
    ui_label_zh = "启用";
> = true;

uniform float TargetKey <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.02; ui_max = 0.30; ui_step = 0.005;
    ui_label = "Target background luminance";
    ui_label_zh = "目标背景亮度";
    ui_tooltip = "Desired average luminance of the background (light sources excluded).\nHigher = brighter nights.";
    ui_tooltip_zh = "希望背景（排除光源后）达到的平均亮度。\n越大夜晚越亮。";
> = 0.08;

uniform float DarkStrength <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Dark scene compensation";
    ui_label_zh = "暗场景补偿强度";
    ui_tooltip = "Fraction of the gap to the target that is closed when the scene is too dark.";
    ui_tooltip_zh = "场景过暗时，向目标亮度靠拢的比例。";
> = 0.40;

uniform float BrightStrength <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Bright scene compensation";
    ui_label_zh = "亮场景压暗强度";
    ui_tooltip = "Fraction of the gap that is closed when the scene is too bright.";
    ui_tooltip_zh = "场景过亮时，向目标亮度靠拢的比例。";
> = 0.30;

uniform float MaxGain <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 1.0; ui_max = 5.0; ui_step = 0.05;
    ui_label = "Max brighten (x)";
    ui_label_zh = "最大提亮倍数";
> = 2.0;

uniform float MinGain <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.5; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Max darken (x)";
    ui_label_zh = "最大压暗倍数";
> = 0.80;

uniform float HighlightIgnore <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.05; ui_max = 0.8; ui_step = 0.01;
    ui_label = "Highlight exclusion threshold";
    ui_label_zh = "高光排除阈值";
    ui_tooltip = "Pixels brighter than this (street lights, headlights, neon) are ignored\nwhen measuring the background. This is what defeats the\n'one bright spot darkens everything' behaviour.";
    ui_tooltip_zh = "亮于此值的像素（路灯、车灯、霓虹）不参与背景亮度统计。\n这就是解决「一个亮点把整个画面压暗」的关键。";
> = 0.25;

uniform float CenterFocus <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Center weighting";
    ui_label_zh = "画面中心权重";
> = 0.40;

uniform float AdaptSpeed <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.3; ui_max = 10.0; ui_step = 0.1;
    ui_label = "Adaptation speed";
    ui_label_zh = "适应速度";
    ui_tooltip = "Lower = smoother and calmer (less eye strain). Higher = reacts faster.";
    ui_tooltip_zh = "越低越平滑稳定（更护眼），越高反应越快。";
> = 1.5;

uniform float HighlightPreserve <
    ui_category = "1. Exposure Balance (anti eye-adaptation)";
    ui_category_zh = "1. 曝光平衡（反自动曝光）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Highlight preservation";
    ui_label_zh = "高光保护";
    ui_tooltip = "How much bright areas are excluded from the exposure boost.\nHigher = headlights, lit roads and lamps keep their original brightness\nwhile shadows are still lifted.";
    ui_tooltip_zh = "亮部有多大程度不参与曝光补偿。\n越大，车灯、被照亮的路面和路灯越接近原本亮度，\n暗部照常提亮。";
> = 0.75;

// ---- 2. Local shadow lift ----
uniform bool EnableLocal <
    ui_category = "2. Local Shadow Lift";
    ui_category_zh = "2. 局部暗部提亮";
    ui_label = "Enable";
    ui_label_zh = "启用";
> = true;

uniform float LocalTarget <
    ui_category = "2. Local Shadow Lift";
    ui_category_zh = "2. 局部暗部提亮";
    ui_type = "slider"; ui_min = 0.005; ui_max = 0.20; ui_step = 0.005;
    ui_label = "Dark region target";
    ui_label_zh = "暗区目标亮度";
    ui_tooltip = "Regions darker than this get lifted (alleys, under cars, interiors).";
    ui_tooltip_zh = "比这个暗的区域会被提亮（巷子、车底、室内）。";
> = 0.045;

uniform float LocalStrength <
    ui_category = "2. Local Shadow Lift";
    ui_category_zh = "2. 局部暗部提亮";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Strength";
    ui_label_zh = "强度";
> = 0.50;

uniform float LocalMax <
    ui_category = "2. Local Shadow Lift";
    ui_category_zh = "2. 局部暗部提亮";
    ui_type = "slider"; ui_min = 1.0; ui_max = 4.0; ui_step = 0.05;
    ui_label = "Max lift (x)";
    ui_label_zh = "最大提亮倍数";
> = 1.8;

uniform float LocalRadius <
    ui_category = "2. Local Shadow Lift";
    ui_category_zh = "2. 局部暗部提亮";
    ui_type = "slider"; ui_min = 0.5; ui_max = 3.0; ui_step = 0.05;
    ui_label = "Region radius";
    ui_label_zh = "区域半径";
    ui_tooltip = "Also controls the clarity radius.";
    ui_tooltip_zh = "同时决定清晰度的作用半径。";
> = 1.0;

// ---- 3. Clarity ----
uniform bool EnableClarity <
    ui_category = "3. Clarity (night / rain readability)";
    ui_category_zh = "3. 清晰度（夜间 / 雨天可读性）";
    ui_label = "Enable";
    ui_label_zh = "启用";
> = true;

uniform float Clarity <
    ui_category = "3. Clarity (night / rain readability)";
    ui_category_zh = "3. 清晰度（夜间 / 雨天可读性）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Clarity";
    ui_label_zh = "清晰度";
    ui_tooltip = "Large-radius local contrast. Separates shapes from rain and fog\nwithout the harshness of fine sharpening.";
    ui_tooltip_zh = "大半径局部对比度，让物体轮廓从雨雾中分离出来，\n又不像细节锐化那样刺眼。";
> = 0.14;

uniform float RainBoost <
    ui_category = "3. Clarity (night / rain readability)";
    ui_category_zh = "3. 清晰度（夜间 / 雨天可读性）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 3.0; ui_step = 0.05;
    ui_label = "Low-contrast boost";
    ui_label_zh = "低对比自动增强";
    ui_tooltip = "When the frame is flat (rain, fog, night), clarity is multiplied by (1 + this).";
    ui_tooltip_zh = "画面发灰（雨、雾、夜晚）时，清晰度乘以（1 + 此值）。";
> = 1.0;

uniform float ContrastRef <
    ui_category = "3. Clarity (night / rain readability)";
    ui_category_zh = "3. 清晰度（夜间 / 雨天可读性）";
    ui_type = "slider"; ui_min = 0.5; ui_max = 4.0; ui_step = 0.05;
    ui_label = "Low-contrast reference (stops)";
    ui_label_zh = "低对比判定参考（档）";
> = 2.0;

// ---- 4. Bloom ----
uniform bool EnableBloom <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_label = "Enable";
    ui_label_zh = "启用";
> = true;

uniform float BloomIntensity <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.5; ui_step = 0.01;
    ui_label = "Intensity";
    ui_label_zh = "强度";
> = 0.15;

uniform float BloomThreshold <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.2; ui_max = 4.0; ui_step = 0.01;
    ui_label = "Threshold";
    ui_label_zh = "阈值";
> = 1.2;

uniform float BloomKnee <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.05; ui_max = 1.5; ui_step = 0.01;
    ui_label = "Threshold softness";
    ui_label_zh = "阈值柔和度";
> = 0.5;

uniform float BloomExpand <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.95; ui_step = 0.01;
    ui_label = "Highlight energy (pseudo HDR)";
    ui_label_zh = "高光能量（伪 HDR）";
    ui_tooltip = "Treats near-white pixels as bright light sources so lamps and neon glow properly.";
    ui_tooltip_zh = "把接近纯白的像素当作强光源处理，让路灯和霓虹有足够的光晕。";
> = 0.80;

uniform float BloomScatter <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.3; ui_max = 0.95; ui_step = 0.01;
    ui_label = "Radius";
    ui_label_zh = "扩散范围";
> = 0.65;

uniform float BloomHazeCut <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.5; ui_step = 0.005;
    ui_label = "Haze suppression";
    ui_label_zh = "雾化抑制";
    ui_tooltip = "Removes faint wide-area glow, keeps the halo near light sources.\nPrevents a white veil over rainy streets full of lights.";
    ui_tooltip_zh = "去掉大面积的微弱泛光，保留光源附近的光晕。\n防止雨夜满街灯光时整个画面蒙上一层白雾。";
> = 0.15;

uniform float BloomDayThreshold <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.0; ui_max = 4.0; ui_step = 0.05;
    ui_label = "Daytime threshold raise";
    ui_label_zh = "白天阈值提升";
    ui_tooltip = "The brighter the scene, the higher the threshold: glowing nights, clean days.";
    ui_tooltip_zh = "场景越亮阈值越高：夜晚灯光有光晕，白天画面保持干净。";
> = 2.0;

uniform float BloomSaturation <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    ui_label = "Bloom saturation";
    ui_label_zh = "泛光饱和度";
> = 0.9;

uniform float3 BloomTint <
    ui_category = "4. Bloom";
    ui_category_zh = "4. 泛光";
    ui_type = "color";
    ui_label = "Bloom tint";
    ui_label_zh = "泛光色调";
> = float3(0.95, 0.94, 1.0);

#if VISTAV_STREAK
uniform bool EnableStreak <
    ui_category = "4b. Anamorphic Streak";
    ui_category_zh = "4b. 横向镜头光晕";
    ui_label = "Enable";
    ui_label_zh = "启用";
> = true;

uniform float StreakIntensity <
    ui_category = "4b. Anamorphic Streak";
    ui_category_zh = "4b. 横向镜头光晕";
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    ui_label = "Intensity";
    ui_label_zh = "强度";
> = 0.15;

uniform float StreakThreshold <
    ui_category = "4b. Anamorphic Streak";
    ui_category_zh = "4b. 横向镜头光晕";
    ui_type = "slider"; ui_min = 0.0; ui_max = 6.0; ui_step = 0.05;
    ui_label = "Threshold";
    ui_label_zh = "阈值";
> = 2.0;

uniform float3 StreakTint <
    ui_category = "4b. Anamorphic Streak";
    ui_category_zh = "4b. 横向镜头光晕";
    ui_type = "color";
    ui_label = "Color";
    ui_label_zh = "颜色";
> = float3(0.55, 0.72, 1.0);
#endif

#if VISTAV_MOTIONBLUR
// ---- 4c. Camera motion blur ----
uniform bool EnableMotionBlur <
    ui_category = "4c. Camera Motion Blur";
    ui_category_zh = "4c. 转镜头动态模糊";
    ui_label = "Enable";
    ui_label_zh = "启用";
    ui_tooltip = "Light directional blur that appears only while the camera turns.\nCamera motion is estimated by matching the previous frame (no depth needed).\nThe HUD region and the crosshair area are never blurred.";
    ui_tooltip_zh = "只在转动镜头时出现的轻度方向模糊。\n通过与上一帧比对来估算镜头运动（不需要深度缓冲）。\nHUD 区域和准星附近不会被模糊。";
> = true;

uniform float MotionBlurAmount <
    ui_category = "4c. Camera Motion Blur";
    ui_category_zh = "4c. 转镜头动态模糊";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Amount (shutter)";
    ui_label_zh = "强度（快门）";
    ui_tooltip = "Blur length as a fraction of the per-frame camera movement.";
    ui_tooltip_zh = "模糊长度占每帧镜头移动距离的比例。";
> = 0.28;

uniform float MotionDeadzone <
    ui_category = "4c. Camera Motion Blur";
    ui_category_zh = "4c. 转镜头动态模糊";
    ui_type = "slider"; ui_min = 0.0; ui_max = 40.0; ui_step = 0.5;
    ui_label = "Deadzone (px / frame)";
    ui_label_zh = "死区（像素 / 帧）";
    ui_tooltip = "Camera movement slower than this produces no blur at all.";
    ui_tooltip_zh = "镜头移动慢于这个速度时完全不模糊。";
> = 6.0;

uniform float MotionMaxLength <
    ui_category = "4c. Camera Motion Blur";
    ui_category_zh = "4c. 转镜头动态模糊";
    ui_type = "slider"; ui_min = 4.0; ui_max = 128.0; ui_step = 1.0;
    ui_label = "Max blur length (px)";
    ui_label_zh = "最大模糊长度（像素）";
> = 40.0;

uniform float MotionSmoothing <
    ui_category = "4c. Camera Motion Blur";
    ui_category_zh = "4c. 转镜头动态模糊";
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.9; ui_step = 0.01;
    ui_label = "Temporal smoothing";
    ui_label_zh = "时间平滑";
    ui_tooltip = "Higher = steadier blur, but it lingers slightly after the camera stops.";
    ui_tooltip_zh = "越大模糊越稳定，但镜头停下后会略微残留。";
> = 0.4;

uniform float CenterProtect <
    ui_category = "4c. Camera Motion Blur";
    ui_category_zh = "4c. 转镜头动态模糊";
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.2; ui_step = 0.005;
    ui_label = "Crosshair protection radius";
    ui_label_zh = "准星保护半径";
> = 0.03;
#endif

// ---- 5. Tone ----
uniform float Exposure <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = -2.0; ui_max = 2.0; ui_step = 0.01;
    ui_label = "Exposure (stops)";
    ui_label_zh = "曝光（档）";
> = 0.0;

uniform float Temperature <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Temperature (cool <-> warm)";
    ui_label_zh = "色温（冷 <-> 暖）";
    ui_tooltip = "Luminance-preserving white balance. Negative = cooler (bluer).";
    ui_tooltip_zh = "保持亮度不变的白平衡。负值更冷（更蓝）。";
> = -0.15;

uniform float TintGM <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Tint (green <-> magenta)";
    ui_label_zh = "色调（绿 <-> 品红）";
> = 0.40;

uniform float Shadows <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Shadows";
    ui_label_zh = "暗部";
    ui_tooltip = "Positive lifts dark tones.";
    ui_tooltip_zh = "正值提亮暗部。";
> = 0.15;

uniform float Highlights <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Highlights";
    ui_label_zh = "高光";
    ui_tooltip = "Negative tames bright tones (less glare).";
    ui_tooltip_zh = "负值压暗亮部（减少刺眼）。";
> = -0.20;

uniform float Contrast <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Contrast";
    ui_label_zh = "对比度";
> = 0.05;

uniform float ShadowProtect <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Contrast shadow protection";
    ui_label_zh = "对比度暗部保护";
    ui_tooltip = "Contrast never crushes dark tones.";
    ui_tooltip_zh = "增加对比度时不会把暗部压黑。";
> = 1.0;

uniform float Vibrance <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = -1.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Vibrance";
    ui_label_zh = "自然饱和度";
> = 0.10;

uniform float Saturation <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01;
    ui_label = "Saturation";
    ui_label_zh = "饱和度";
> = 1.08;

uniform float SplitTone <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Split toning amount";
    ui_label_zh = "冷暖分离强度";
> = 0.10;

uniform float3 ShadowColor <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "color";
    ui_label = "Shadow color";
    ui_label_zh = "暗部颜色";
> = float3(0.95, 0.94, 1.08);

uniform float3 HighlightColor <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "color";
    ui_label = "Highlight color";
    ui_label_zh = "亮部颜色";
> = float3(1.0, 1.0, 1.0);

uniform float NightPeak <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.75; ui_max = 1.0; ui_step = 0.005;
    ui_label = "Night peak brightness";
    ui_label_zh = "夜间最高亮度";
    ui_tooltip = "At night, the brightest pixels (headlights, street lamps) are dimmed to this level.\nFades out automatically during the day. HUD region is not affected.";
    ui_tooltip_zh = "夜晚把最亮的像素（车灯、路灯）压到这个亮度。\n白天自动淡出，HUD 区域不受影响。";
> = 0.82;

uniform float NightBloom <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Night bloom scale";
    ui_label_zh = "夜间泛光比例";
    ui_tooltip = "Bloom intensity multiplier at night (reduces headlight glare).";
    ui_tooltip_zh = "夜间泛光强度倍数（减少车灯眩光）。";
> = 0.60;

uniform float OutputBlack <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.1; ui_step = 0.001;
    ui_label = "Output black level";
    ui_label_zh = "输出黑点";
    ui_tooltip = "Slightly raised black reduces eye strain in dark scenes.";
    ui_tooltip_zh = "略微抬高黑色，暗场景下更不累眼。";
> = 0.0;

uniform float OutputWhite <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.8; ui_max = 1.0; ui_step = 0.001;
    ui_label = "Output white level";
    ui_label_zh = "输出白点";
    ui_tooltip = "Slightly lowered peak white reduces glare.";
    ui_tooltip_zh = "略微降低最亮的白色以减少刺眼。";
> = 0.985;

uniform float Vignette <
    ui_category = "5. Tone";
    ui_category_zh = "5. 影调";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Vignette";
    ui_label_zh = "暗角";
> = 0.0;

// ---- 6. HUD region ----
uniform bool HudProtect <
    ui_category = "6. HUD Region (minimap + notification feed)";
    ui_category_zh = "6. HUD 区域（小地图 + 短信通知）";
    ui_label = "Enable";
    ui_label_zh = "启用";
    ui_tooltip = "Inside this region the HUD never glows, text edges are crispened\n(edge-gated, halo-free) and it is excluded from exposure metering.\nTone is identical to the rest of the screen, so there is no visible patch.";
    ui_tooltip_zh = "这片区域内 HUD 不发光，文字边缘会被锐化（只作用于边缘，不产生白边），\n并且不参与曝光统计。\n影调与屏幕其它区域完全一致，不会出现色块。";
> = true;

uniform float2 HudMin <
    ui_category = "6. HUD Region (minimap + notification feed)";
    ui_category_zh = "6. HUD 区域（小地图 + 短信通知）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
    ui_label = "Region top-left";
    ui_label_zh = "区域左上角";
> = float2(0.008, 0.400);

uniform float2 HudMax <
    ui_category = "6. HUD Region (minimap + notification feed)";
    ui_category_zh = "6. HUD 区域（小地图 + 短信通知）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.001;
    ui_label = "Region bottom-right";
    ui_label_zh = "区域右下角";
> = float2(0.215, 0.990);

uniform float TextCrisp <
    ui_category = "6. HUD Region (minimap + notification feed)";
    ui_category_zh = "6. HUD 区域（小地图 + 短信通知）";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Text crispening";
    ui_label_zh = "文字锐化";
    ui_tooltip = "Steepens text edges, clamped to the local min/max so it never adds bright halos.";
    ui_tooltip_zh = "让文字边缘更锐利，结果被限制在周围像素的明暗范围内，不会产生白边。";
> = 0.4;

// ---- 7. Debug ----
uniform int DebugView <
    ui_category = "7. Debug";
    ui_category_zh = "7. 调试";
    ui_type = "combo";
    ui_items = "Off\0Split compare (left original / right result)\0Gain heatmap\0Bloom only\0Metering mask + meters\0";
    ui_items_zh = "关闭\0分屏对比（左原图 / 右效果）\0提亮倍数热力图\0只看泛光\0测光遮罩 + 数值条\0";
    ui_label = "Debug view";
    ui_label_zh = "调试视图";
> = 0;

uniform float SplitPos <
    ui_category = "7. Debug";
    ui_category_zh = "7. 调试";
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01;
    ui_label = "Split position";
    ui_label_zh = "分屏位置";
> = 0.5;

uniform float FrameTime < source = "frametime"; >;
uniform int FrameCount < source = "framecount"; >;

// ============================================================================
// Textures
// ============================================================================

#define VV_TEXEL(div) float2(1.0 / (BUFFER_WIDTH / div), 1.0 / (BUFFER_HEIGHT / div))

// Linear scene (16-bit). Alpha = total log2 gain applied to this pixel (debug)
texture VV_SceneTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler VV_Scene { Texture = VV_SceneTex; };

// Quarter-res analysis: r = w*logY, g = w*logY^2, b = w, a = logY
texture VV_QuarterTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler VV_Quarter { Texture = VV_QuarterTex; };

// Global statistics (256x256 with full mip chain down to 1x1)
texture VV_StatsTex { Width = 256; Height = 256; Format = RGBA16F; MipLevels = 9; };
sampler VV_Stats { Texture = VV_StatsTex; };

// Temporally smoothed state: r = global gain (log2), g = contrast (stops), b = background (log2), a = initialized
texture VV_AdaptTex { Width = 1; Height = 1; Format = RGBA16F; };
sampler VV_Adapt { Texture = VV_AdaptTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
texture VV_AdaptPrevTex { Width = 1; Height = 1; Format = RGBA16F; };
sampler VV_AdaptPrev { Texture = VV_AdaptPrevTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

// 1/16-res local luminance
texture VV_LocalATex { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
sampler VV_LocalA { Texture = VV_LocalATex; };
texture VV_LocalBTex { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F; };
sampler VV_LocalB { Texture = VV_LocalBTex; };

// Bloom pyramid
texture VV_B0Tex { Width = BUFFER_WIDTH / 2;   Height = BUFFER_HEIGHT / 2;   Format = RGBA16F; };
texture VV_B1Tex { Width = BUFFER_WIDTH / 4;   Height = BUFFER_HEIGHT / 4;   Format = RGBA16F; };
texture VV_B2Tex { Width = BUFFER_WIDTH / 8;   Height = BUFFER_HEIGHT / 8;   Format = RGBA16F; };
texture VV_B3Tex { Width = BUFFER_WIDTH / 16;  Height = BUFFER_HEIGHT / 16;  Format = RGBA16F; };
texture VV_B4Tex { Width = BUFFER_WIDTH / 32;  Height = BUFFER_HEIGHT / 32;  Format = RGBA16F; };
texture VV_B5Tex { Width = BUFFER_WIDTH / 64;  Height = BUFFER_HEIGHT / 64;  Format = RGBA16F; };
texture VV_B6Tex { Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F; };
sampler VV_B0 { Texture = VV_B0Tex; };
sampler VV_B1 { Texture = VV_B1Tex; };
sampler VV_B2 { Texture = VV_B2Tex; };
sampler VV_B3 { Texture = VV_B3Tex; };
sampler VV_B4 { Texture = VV_B4Tex; };
sampler VV_B5 { Texture = VV_B5Tex; };
sampler VV_B6 { Texture = VV_B6Tex; };

texture VV_U0Tex { Width = BUFFER_WIDTH / 2;   Height = BUFFER_HEIGHT / 2;   Format = RGBA16F; };
texture VV_U1Tex { Width = BUFFER_WIDTH / 4;   Height = BUFFER_HEIGHT / 4;   Format = RGBA16F; };
texture VV_U2Tex { Width = BUFFER_WIDTH / 8;   Height = BUFFER_HEIGHT / 8;   Format = RGBA16F; };
texture VV_U3Tex { Width = BUFFER_WIDTH / 16;  Height = BUFFER_HEIGHT / 16;  Format = RGBA16F; };
texture VV_U4Tex { Width = BUFFER_WIDTH / 32;  Height = BUFFER_HEIGHT / 32;  Format = RGBA16F; };
texture VV_U5Tex { Width = BUFFER_WIDTH / 64;  Height = BUFFER_HEIGHT / 64;  Format = RGBA16F; };
sampler VV_U0 { Texture = VV_U0Tex; };
sampler VV_U1 { Texture = VV_U1Tex; };
sampler VV_U2 { Texture = VV_U2Tex; };
sampler VV_U3 { Texture = VV_U3Tex; };
sampler VV_U4 { Texture = VV_U4Tex; };
sampler VV_U5 { Texture = VV_U5Tex; };

#if VISTAV_STREAK
// Anamorphic streak (horizontal-only downscale)
texture VV_S1Tex  { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture VV_S2Tex  { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture VV_S3Tex  { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture VV_S4Tex  { Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture VV_SU3Tex { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture VV_SU2Tex { Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
texture VV_SU1Tex { Width = BUFFER_WIDTH / 8;  Height = BUFFER_HEIGHT / 4; Format = RGBA16F; };
sampler VV_S1  { Texture = VV_S1Tex; };
sampler VV_S2  { Texture = VV_S2Tex; };
sampler VV_S3  { Texture = VV_S3Tex; };
sampler VV_S4  { Texture = VV_S4Tex; };
sampler VV_SU3 { Texture = VV_SU3Tex; };
sampler VV_SU2 { Texture = VV_SU2Tex; };
sampler VV_SU1 { Texture = VV_SU1Tex; };
#endif

#if VISTAV_MOTIONBLUR
// Camera motion estimation
#define VV_MB_RANGE 6                        // search radius in 1/32-res texels (+-192 px at 1440p)
#define VV_MB_SIDE  13                       // VV_MB_RANGE * 2 + 1 candidates per axis
#define VV_MB_TILE  8                        // 8x8 threads per candidate, reduced via mip level 3
#define VV_MB_GX    64                       // matching grid
#define VV_MB_GY    32

texture VV_MotionCurTex  { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = R16F; };
sampler VV_MotionCur     { Texture = VV_MotionCurTex; };
texture VV_MotionPrevTex { Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = R16F; };
sampler VV_MotionPrev    { Texture = VV_MotionPrevTex; };

// 13x13 candidates, each an 8x8 tile of partial sums; mip 3 = per-candidate average
texture VV_SADTex { Width = 104; Height = 104; Format = RG16F; MipLevels = 4; };
sampler VV_SAD    { Texture = VV_SADTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };

// r,g = camera velocity (uv / frame), b = confidence, a = initialized
texture VV_MotionVecTex     { Width = 1; Height = 1; Format = RGBA16F; };
sampler VV_MotionVec        { Texture = VV_MotionVecTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
texture VV_MotionVecPrevTex { Width = 1; Height = 1; Format = RGBA16F; };
sampler VV_MotionVecPrev    { Texture = VV_MotionVecPrevTex; MagFilter = POINT; MinFilter = POINT; MipFilter = POINT; };
#endif

// ============================================================================
// Helpers
// ============================================================================

static const float3 LUMA = float3(0.2126, 0.7152, 0.0722);

float Luma(float3 c) { return dot(c, LUMA); }
float Max3(float3 c) { return max(c.r, max(c.g, c.b)); }
float Min3(float3 c) { return min(c.r, min(c.g, c.b)); }

float3 SRGBToLinear(float3 c)
{
    c = saturate(c);
    return lerp(c / 12.92, pow((c + 0.055) / 1.055, 2.4), step(0.04045, c));
}

float3 LinearToSRGB(float3 c)
{
    c = saturate(c);
    return lerp(c * 12.92, 1.055 * pow(c, 1.0 / 2.4) - 0.055, step(0.0031308, c));
}

float Hash(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

// 1 inside the HUD region, soft 1% edge
float HudMask(float2 uv)
{
    float2 d = max(HudMin - uv, uv - HudMax);
    float m = 1.0 - smoothstep(0.0, 0.01, max(d.x, d.y));
    return HudProtect ? m : 0.0;
}

// Shoulder asymptotic to 1 (after bloom is added)
float ShoulderExp(float x, float knee)
{
    float r = knee + (1.0 - knee) * (1.0 - exp(-max(x - knee, 0.0) / (1.0 - knee)));
    return x <= knee ? x : r;
}

// 0..1, how "daylit" the compensated background is
float Dayness(float4 ad)
{
    float bg = ad.b + ad.r;
    return saturate((bg - log2(0.02)) / (log2(0.20) - log2(0.02)));
}

// ============================================================================
// Pass 1: analysis
// ============================================================================

float4 PS_Prep(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 t = BUFFER_PIXEL_SIZE;
    float2 offs[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float4 acc = 0;
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float3 c = SRGBToLinear(tex2Dlod(ReShade::BackBuffer, float4(uv + offs[i] * t, 0, 0)).rgb);
        float Y = Luma(c);
        float lY = log2(max(Y, 0.0005));
        // Highlights get ~zero weight (small floor avoids division by zero)
        float w = 1.0 - 0.98 * smoothstep(HighlightIgnore, HighlightIgnore * 2.4, Y);
        acc += float4(w * lY, w * lY * lY, w, lY);
    }
    return acc * 0.25;
}

// Global metering: adds center weighting and excludes the HUD region
float4 PS_Stats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 q = tex2D(VV_Quarter, uv);
    float2 d = (uv - 0.5) * float2(BUFFER_ASPECT_RATIO, 1.0);
    float cw = lerp(1.0, exp(-dot(d, d) * 6.0), CenterFocus) + 0.001;
    cw *= 1.0 - HudMask(uv);
    return float4(q.rgb * cw, 1.0);
}

float4 PS_Adapt(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float4 s = tex2Dlod(VV_Stats, float4(0.5, 0.5, 0, 8));
    float wsum = max(s.b, 1e-5);
    float meanLog = s.r / wsum;
    float stdLog = sqrt(max(s.g / wsum - meanLog * meanLog, 0.0));

    float diff = log2(TargetKey) - meanLog;
    float g = diff > 0.0 ? diff * DarkStrength : diff * BrightStrength;
    g = clamp(g, log2(MinGain), log2(MaxGain));
    if (!EnableExposure) g = 0.0;

    float4 cur = float4(g, stdLog, meanLog, 1.0);
    float4 prev = tex2Dlod(VV_AdaptPrev, float4(0.5, 0.5, 0, 0));

    float dt = clamp(FrameTime * 0.001, 0.0, 0.25);
    float a = 1.0 - exp(-dt * AdaptSpeed);
    if (prev.a < 0.5) a = 1.0;
    return lerp(prev, cur, a);
}

float4 PS_AdaptStore(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return tex2Dlod(VV_Adapt, float4(0.5, 0.5, 0, 0));
}

// ============================================================================
// Pass 2: local luminance (1/16 res) + gaussian blur
// ============================================================================

float4 PS_LocalDown(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 t = VV_TEXEL(4);
    float4 a = tex2D(VV_Quarter, uv + t * float2(-1, -1));
    float4 b = tex2D(VV_Quarter, uv + t * float2( 1, -1));
    float4 c = tex2D(VV_Quarter, uv + t * float2(-1,  1));
    float4 d = tex2D(VV_Quarter, uv + t * float2( 1,  1));
    return (a + b + c + d) * 0.25;
}

float4 Gauss9(sampler s, float2 uv, float2 dir)
{
    float4 c = tex2D(s, uv) * 0.2270270;
    c += tex2D(s, uv + dir * 1.3846154) * 0.3162162;
    c += tex2D(s, uv - dir * 1.3846154) * 0.3162162;
    c += tex2D(s, uv + dir * 3.2307692) * 0.0702703;
    c += tex2D(s, uv - dir * 3.2307692) * 0.0702703;
    return c;
}

float4 PS_LocalBlurH(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Gauss9(VV_LocalA, uv, float2(VV_TEXEL(16).x * LocalRadius, 0));
}

float4 PS_LocalBlurV(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return Gauss9(VV_LocalB, uv, float2(0, VV_TEXEL(16).y * LocalRadius));
}

// ============================================================================
// Pass 3: exposure + local lift + clarity -> 16-bit linear scene
// ============================================================================

float4 PS_Apply(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 c = SRGBToLinear(tex2D(ReShade::BackBuffer, uv).rgb);
    float4 ad = tex2Dlod(VV_Adapt, float4(0.5, 0.5, 0, 0));
    float gLog = ad.r;

    float Y = Luma(c);
    float logY = log2(max(Y, 0.0005));

    // Global gain through a highlight-preserving curve on max(RGB):
    //   f(m) = G*m / (1 + (G-1) * m^q),  f(0)' = G, f(1) = 1, monotonic for q <= 1.
    // Shadows get (almost) the full gain, lit surfaces and headlights stay near their original level.
    // When darkening (G < 1) a plain multiply is used.
    float m0 = max(Max3(c), 1e-6);
    float G = exp2(gLog);
    float q = lerp(1.0, 0.4, HighlightPreserve);
    float gPix = G > 1.0 ? (G / (1.0 + (G - 1.0) * pow(m0, q))) : G;
    float gPixLog = log2(gPix);

    float4 L = tex2D(VV_LocalA, uv);
    float localMean = L.r / max(L.b, 1e-4);   // local background (log2), highlights excluded

    // Local shadow lift: dark pixels only. Monotonic within the allowed strength range.
    float localLog = 0.0;
    if (EnableLocal)
    {
        localLog = clamp((log2(LocalTarget) - (localMean + gLog)) * LocalStrength, 0.0, log2(LocalMax));
        float gp = pow(saturate(Y * gPix), 1.0 / 2.2);
        localLog *= 1.0 - smoothstep(0.15, 0.6, gp);
    }

    // Clarity: deviation from the local background in log space (independent of global exposure)
    float clarityLog = 0.0;
    if (EnableClarity)
    {
        float lowContrast = saturate(1.0 - ad.g / ContrastRef);
        float amt = Clarity * (1.0 + RainBoost * lowContrast);
        float detail = clamp(logY - localMean, -1.5, 1.5);
        float gm = pow(saturate(Y * exp2(gPixLog + localLog)), 1.0 / 2.2);
        float mid = smoothstep(0.03, 0.18, gm) * (1.0 - smoothstep(0.70, 0.97, gm));
        clarityLog = detail * amt * mid;
    }

    float totalLog = gPixLog + localLog + clarityLog;
    float3 o = c * exp2(totalLog);

    return float4(saturate(o), totalLog);
}

// ============================================================================
// Pass 4: bloom
// ============================================================================

float3 ExpandHDR(float3 c)
{
    return c / (1.0 - min(Max3(c), 0.999) * BloomExpand);
}

float3 Threshold(float3 c, float T, float K)
{
    float br = Max3(c);
    float soft = clamp(br - T + K, 0.0, 2.0 * K);
    soft = soft * soft / (4.0 * K + 1e-5);
    return c * (max(soft, br - T) / max(br, 1e-5));
}

float KarisW(float3 c) { return 1.0 / (1.0 + Luma(c)); }

// 13-tap downsample (Jimenez 2014)
float3 Down13(sampler s, float2 uv, float2 t)
{
    float3 a = tex2D(s, uv + t * float2(-2, -2)).rgb;
    float3 b = tex2D(s, uv + t * float2( 0, -2)).rgb;
    float3 c = tex2D(s, uv + t * float2( 2, -2)).rgb;
    float3 d = tex2D(s, uv + t * float2(-2,  0)).rgb;
    float3 e = tex2D(s, uv).rgb;
    float3 f = tex2D(s, uv + t * float2( 2,  0)).rgb;
    float3 g = tex2D(s, uv + t * float2(-2,  2)).rgb;
    float3 h = tex2D(s, uv + t * float2( 0,  2)).rgb;
    float3 i = tex2D(s, uv + t * float2( 2,  2)).rgb;
    float3 j = tex2D(s, uv + t * float2(-1, -1)).rgb;
    float3 k = tex2D(s, uv + t * float2( 1, -1)).rgb;
    float3 l = tex2D(s, uv + t * float2(-1,  1)).rgb;
    float3 m = tex2D(s, uv + t * float2( 1,  1)).rgb;
    return (j + k + l + m) * 0.125
         + (a + b + d + e) * 0.03125 + (b + c + e + f) * 0.03125
         + (d + e + g + h) * 0.03125 + (e + f + h + i) * 0.03125;
}

// First level: pseudo-HDR expansion + Karis average (anti-flicker) + soft threshold
float4 PS_BloomPrefilter(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
#if VISTAV_STREAK
    if (!EnableBloom && !EnableStreak) return float4(0, 0, 0, 0);
#else
    if (!EnableBloom) return float4(0, 0, 0, 0);
#endif
    float2 t = BUFFER_PIXEL_SIZE;

    float3 a = ExpandHDR(tex2D(VV_Scene, uv + t * float2(-2, -2)).rgb);
    float3 b = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 0, -2)).rgb);
    float3 c = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 2, -2)).rgb);
    float3 d = ExpandHDR(tex2D(VV_Scene, uv + t * float2(-2,  0)).rgb);
    float3 e = ExpandHDR(tex2D(VV_Scene, uv).rgb);
    float3 f = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 2,  0)).rgb);
    float3 g = ExpandHDR(tex2D(VV_Scene, uv + t * float2(-2,  2)).rgb);
    float3 h = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 0,  2)).rgb);
    float3 i = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 2,  2)).rgb);
    float3 j = ExpandHDR(tex2D(VV_Scene, uv + t * float2(-1, -1)).rgb);
    float3 k = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 1, -1)).rgb);
    float3 l = ExpandHDR(tex2D(VV_Scene, uv + t * float2(-1,  1)).rgb);
    float3 m = ExpandHDR(tex2D(VV_Scene, uv + t * float2( 1,  1)).rgb);

    float3 g0 = (j + k + l + m) * 0.25;
    float3 g1 = (a + b + d + e) * 0.25;
    float3 g2 = (b + c + e + f) * 0.25;
    float3 g3 = (d + e + g + h) * 0.25;
    float3 g4 = (e + f + h + i) * 0.25;
    float w0 = KarisW(g0) * 0.5;
    float w1 = KarisW(g1) * 0.125;
    float w2 = KarisW(g2) * 0.125;
    float w3 = KarisW(g3) * 0.125;
    float w4 = KarisW(g4) * 0.125;
    float3 col = (g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4) / (w0 + w1 + w2 + w3 + w4);

    float4 ad = tex2Dlod(VV_Adapt, float4(0.5, 0.5, 0, 0));
    float T = BloomThreshold * (1.0 + Dayness(ad) * BloomDayThreshold);
    col = Threshold(col, T, BloomKnee * T / max(BloomThreshold, 1e-3));
    col *= 1.0 - HudMask(uv);   // HUD text and icons never glow
    return float4(max(col, 0.0), 1.0);
}

float4 PS_Down1(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(VV_B0, uv, VV_TEXEL(2)), 1); }
float4 PS_Down2(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(VV_B1, uv, VV_TEXEL(4)), 1); }
float4 PS_Down3(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(VV_B2, uv, VV_TEXEL(8)), 1); }
float4 PS_Down4(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(VV_B3, uv, VV_TEXEL(16)), 1); }
float4 PS_Down5(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(VV_B4, uv, VV_TEXEL(32)), 1); }
float4 PS_Down6(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(Down13(VV_B5, uv, VV_TEXEL(64)), 1); }

// 9-tap tent upsample
float3 Tent(sampler s, float2 uv, float2 t)
{
    float3 c = tex2D(s, uv).rgb * 4.0;
    c += (tex2D(s, uv + t * float2(-1, 0)).rgb + tex2D(s, uv + t * float2(1, 0)).rgb
        + tex2D(s, uv + t * float2(0, -1)).rgb + tex2D(s, uv + t * float2(0, 1)).rgb) * 2.0;
    c += tex2D(s, uv + t * float2(-1, -1)).rgb + tex2D(s, uv + t * float2(1, -1)).rgb
       + tex2D(s, uv + t * float2(-1,  1)).rgb + tex2D(s, uv + t * float2(1,  1)).rgb;
    return c / 16.0;
}

float4 PS_Up5(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(lerp(tex2D(VV_B5, uv).rgb, Tent(VV_B6, uv, VV_TEXEL(128)), BloomScatter), 1); }
float4 PS_Up4(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(lerp(tex2D(VV_B4, uv).rgb, Tent(VV_U5, uv, VV_TEXEL(64)),  BloomScatter), 1); }
float4 PS_Up3(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(lerp(tex2D(VV_B3, uv).rgb, Tent(VV_U4, uv, VV_TEXEL(32)),  BloomScatter), 1); }
float4 PS_Up2(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(lerp(tex2D(VV_B2, uv).rgb, Tent(VV_U3, uv, VV_TEXEL(16)),  BloomScatter), 1); }
float4 PS_Up1(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(lerp(tex2D(VV_B1, uv).rgb, Tent(VV_U2, uv, VV_TEXEL(8)),   BloomScatter), 1); }
float4 PS_Up0(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(lerp(tex2D(VV_B0, uv).rgb, Tent(VV_U1, uv, VV_TEXEL(4)),   BloomScatter), 1); }

// ============================================================================
// Pass 5: anamorphic streak (optional, compile-time)
// ============================================================================

#if VISTAV_STREAK
float3 DownH(sampler s, float2 uv, float tx)
{
    return (tex2D(s, uv + float2(-3.0 * tx, 0)).rgb + tex2D(s, uv + float2(-1.0 * tx, 0)).rgb
          + tex2D(s, uv + float2( 1.0 * tx, 0)).rgb + tex2D(s, uv + float2( 3.0 * tx, 0)).rgb) * 0.25;
}

float3 UpH(sampler s, float2 uv, float tx)
{
    return (tex2D(s, uv + float2(-tx, 0)).rgb + tex2D(s, uv).rgb * 2.0 + tex2D(s, uv + float2(tx, 0)).rgb) * 0.25;
}

float4 PS_Streak1(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    if (!EnableStreak) return float4(0, 0, 0, 0);
    float3 c = DownH(VV_B1, uv, VV_TEXEL(4).x);
    c *= smoothstep(StreakThreshold, StreakThreshold + 1.0, Max3(c));
    return float4(c, 1);
}
float4 PS_Streak2(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(DownH(VV_S1, uv, VV_TEXEL(8).x), 1); }
float4 PS_Streak3(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(DownH(VV_S2, uv, VV_TEXEL(16).x), 1); }
float4 PS_Streak4(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(DownH(VV_S3, uv, VV_TEXEL(32).x), 1); }
float4 PS_StreakU3(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(VV_S3, uv).rgb + UpH(VV_S4,  uv, VV_TEXEL(64).x), 1); }
float4 PS_StreakU2(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(VV_S2, uv).rgb + UpH(VV_SU3, uv, VV_TEXEL(32).x), 1); }
float4 PS_StreakU1(float4 p : SV_Position, float2 uv : TEXCOORD) : SV_Target { return float4(tex2D(VV_S1, uv).rgb + UpH(VV_SU2, uv, VV_TEXEL(16).x), 1); }
#endif

// ============================================================================
// Pass 5b: camera motion estimation (global block matching) + directional blur
// ============================================================================

#if VISTAV_MOTIONBLUR
// 1/32-res log luminance from the quarter-res analysis (each output texel covers 8x8 quarter texels)
float4 PS_MotionLuma(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 t = VV_TEXEL(4);
    float s = 0.0;
    [unroll]
    for (int y = 0; y < 4; y++)
    {
        [unroll]
        for (int x = 0; x < 4; x++)
            s += tex2Dlod(VV_Quarter, float4(uv + t * (float2(x, y) * 2.0 - 3.0), 0, 0)).a;
    }
    return float4(s / 16.0, 0, 0, 1);
}

// Each 8x8 tile = one candidate shift; each thread sums a strided subset of the matching grid.
// Truncated absolute difference keeps the static player / HUD from dominating the match.
float4 PS_MotionSAD(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float2 cell = floor(pos.xy);
    float2 cand = floor(cell / VV_MB_TILE);
    float2 sub = cell - cand * VV_MB_TILE;
    float2 shift = (cand - VV_MB_RANGE) * VV_TEXEL(32);

    float sum = 0.0;
    float wsum = 0.0;
    [loop]
    for (int n = 0; n < VV_MB_GY / VV_MB_TILE; n++)
    {
        [loop]
        for (int m = 0; m < VV_MB_GX / VV_MB_TILE; m++)
        {
            float2 gp = sub + float2(m, n) * VV_MB_TILE;
            float2 guv = 0.1 + 0.8 * (gp + 0.5) / float2(VV_MB_GX, VV_MB_GY);
            float2 cd = (guv - 0.5) * float2(BUFFER_ASPECT_RATIO, 1.0);
            // ignore HUD and the screen center (third-person character moves with the camera)
            float w = (1.0 - HudMask(guv)) * smoothstep(0.10, 0.16, length(cd));
            float a = tex2Dlod(VV_MotionCur, float4(guv, 0, 0)).r;
            float b = tex2Dlod(VV_MotionPrev, float4(guv - shift, 0, 0)).r;
            sum += w * min(abs(a - b), 1.0);
            wsum += w;
        }
    }
    return float4(sum, wsum, 0, 1);
}

float MotionCost(float2 c)
{
    float2 r = tex2Dlod(VV_SAD, float4((c + 0.5) / VV_MB_SIDE, 0, 3)).rg;
    return r.x / max(r.y, 1e-4);
}

float ParabolaOffset(float l, float c, float r)
{
    float d = l - 2.0 * c + r;
    float o = d > 1e-5 ? 0.5 * (l - r) / d : 0.0;
    return clamp(o, -0.5, 0.5);
}

float4 PS_MotionPick(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float best = 1e6;
    float2 bestC = float2(VV_MB_RANGE, VV_MB_RANGE);
    float mean = 0.0;
    [loop]
    for (int j = 0; j < VV_MB_SIDE; j++)
    {
        [loop]
        for (int i = 0; i < VV_MB_SIDE; i++)
        {
            float cost = MotionCost(float2(i, j));
            mean += cost;
            if (cost < best) { best = cost; bestC = float2(i, j); }
        }
    }
    mean /= VV_MB_SIDE * VV_MB_SIDE;

    // Sub-texel refinement (neighbors clamped to the search window)
    float2 lo = max(bestC - 1.0, 0.0);
    float2 hi = min(bestC + 1.0, VV_MB_SIDE - 1.0);
    float2 off;
    off.x = ParabolaOffset(MotionCost(float2(lo.x, bestC.y)), best, MotionCost(float2(hi.x, bestC.y)));
    off.y = ParabolaOffset(MotionCost(float2(bestC.x, lo.y)), best, MotionCost(float2(bestC.x, hi.y)));
    float2 s = bestC - VV_MB_RANGE + off;

    // Confidence: the best match must be clearly better than average; featureless frames get none
    float conf = 1.0 - smoothstep(0.35, 0.75, best / max(mean, 1e-4));
    conf *= smoothstep(0.01, 0.03, mean);
    float2 edge = abs(bestC - VV_MB_RANGE);
    conf *= max(edge.x, edge.y) >= VV_MB_RANGE ? 0.5 : 1.0;   // motion beyond the search range

    float4 cur = float4(s * VV_TEXEL(32), conf, 1.0);
    float4 prev = tex2Dlod(VV_MotionVecPrev, float4(0.5, 0.5, 0, 0));
    float a = prev.a < 0.5 ? 1.0 : 1.0 - MotionSmoothing;
    return lerp(prev, cur, a);
}

float4 PS_MotionVecStore(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return tex2Dlod(VV_MotionVec, float4(0.5, 0.5, 0, 0));
}

float4 PS_MotionLumaStore(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    return tex2D(VV_MotionCur, uv);
}

// Directional blur along the estimated camera motion, in linear light
float3 CameraMotionBlur(float2 vpos, float2 uv, float3 c, float hud)
{
    float3 result = c;
    float4 mv = tex2Dlod(VV_MotionVec, float4(0.5, 0.5, 0, 0));
    float2 vpx = mv.xy * BUFFER_SCREEN_SIZE;            // pixels per frame
    float speed = length(vpx);

    float2 cd = (uv - 0.5) * float2(BUFFER_ASPECT_RATIO, 1.0);
    float protect = max(hud, 1.0 - smoothstep(CenterProtect, CenterProtect * 1.6 + 1e-4, length(cd)));
    float len = min(max(speed - MotionDeadzone, 0.0) * MotionBlurAmount, MotionMaxLength);
    len *= mv.z * (1.0 - protect) * (EnableMotionBlur ? 1.0 : 0.0);

    [branch]
    if (len > 1.0)
    {
        float2 extent = vpx / max(speed, 1e-4) * len * BUFFER_PIXEL_SIZE;
        float jitter = Hash(vpos + 0.5) - 0.5;          // hides sample stepping
        float3 acc = 0;
        [unroll]
        for (int i = 0; i < 12; i++)
        {
            float t = (i + 0.5 + jitter) / 12.0 - 0.5;
            acc += tex2Dlod(VV_Scene, float4(uv + extent * t, 0, 0)).rgb;
        }
        result = acc / 12.0;
    }
    return result;
}
#endif

// ============================================================================
// Pass 6: composite + HUD text + tone
// ============================================================================

// Contrast-limited edge steepening for HUD text: result is clamped to the 3x3 min/max,
// so it can never create bright or dark halos (the usual cause of "glaring" sharpening).
float3 CrispenText(float2 uv, float3 cLin, float mask)
{
    float3 result = cLin;

    [branch]
    if (mask > 0.0 && TextCrisp > 0.0)
    {
        float2 t = BUFFER_PIXEL_SIZE;
        float c  = sqrt(Luma(cLin));
        float n0 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2(-1, -1)).rgb));
        float n1 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2( 0, -1)).rgb));
        float n2 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2( 1, -1)).rgb));
        float n3 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2(-1,  0)).rgb));
        float n4 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2( 1,  0)).rgb));
        float n5 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2(-1,  1)).rgb));
        float n6 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2( 0,  1)).rgb));
        float n7 = sqrt(Luma(tex2D(VV_Scene, uv + t * float2( 1,  1)).rgb));

        float mn = min(min(min(n0, n1), min(n2, n3)), min(min(n4, n5), min(n6, min(n7, c))));
        float mx = max(max(max(n0, n1), max(n2, n3)), max(max(n4, n5), max(n6, max(n7, c))));
        float blur = (n0 + n1 + n2 + n3 + n4 + n5 + n6 + n7 + c) / 9.0;

        float sharp = clamp(c + (c - blur) * 2.0 * TextCrisp, mn, mx);
        float edge = smoothstep(0.06, 0.25, mx - mn);     // only act on strong (text-like) edges
        float nc = lerp(c, sharp, edge * mask);

        result = cLin * (nc * nc) / max(c * c, 1e-6);
    }

    return result;
}

float3 HeatMap(float x)
{
    return saturate(float3(1.5 - abs(4.0 * x - 3.0), 1.5 - abs(4.0 * x - 2.0), 1.5 - abs(4.0 * x - 1.0)));
}

float4 PS_Final(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float3 orig = tex2D(ReShade::BackBuffer, uv).rgb;
    float4 ad = tex2Dlod(VV_Adapt, float4(0.5, 0.5, 0, 0));
    float hud = HudMask(uv);

    float3 c = tex2D(VV_Scene, uv).rgb;
#if VISTAV_MOTIONBLUR
    c = CameraMotionBlur(pos.xy, uv, c, hud);
#endif
    c = CrispenText(uv, c, hud);

    // Bloom
    float3 bloom = 0;
    if (EnableBloom)
    {
        bloom = tex2D(VV_U0, uv).rgb;
        float by = Luma(bloom);
        bloom *= by / (by + BloomHazeCut + 1e-6);
        bloom = lerp(dot(bloom, LUMA).xxx, bloom, BloomSaturation) * BloomTint * BloomIntensity;
        bloom *= lerp(NightBloom, 1.0, Dayness(ad));
    }
    float3 streak = 0;
#if VISTAV_STREAK
    if (EnableStreak)
        streak = tex2D(VV_SU1, uv).rgb * StreakTint * StreakIntensity * 0.25;
#endif

    c += bloom + streak;

    // Linear-light adjustments
    c *= exp2(Exposure);
    float3 wb = float3(1.0 + 0.10 * Temperature, 1.0 - 0.06 * TintGM, 1.0 - 0.10 * Temperature);
    c *= wb / Luma(wb);

    float m = Max3(c);
    c *= ShoulderExp(m, 0.80) / max(m, 1e-6);

    // Night glare reduction: dims only the brightest pixels at night.
    // Monotonic for NightPeak >= 0.75 (slope stays positive across the 0.40..1 ramp).
    float pk = Max3(c);
    float night = (1.0 - Dayness(ad)) * (1.0 - hud);
    c *= 1.0 - (1.0 - NightPeak) * smoothstep(0.40, 1.0, pk) * night;

    float3 g = LinearToSRGB(c);

    // Shadows / highlights (bell-shaped weights, peak at 1/3 and 2/3)
    float3 ws = g * (1.0 - g) * (1.0 - g) * 6.75;
    float3 wh = g * g * (1.0 - g) * 6.75;
    g = saturate(g + 0.2 * (Shadows * ws + Highlights * wh));

    // Gentle S-curve with shadow protection
    float3 s = g * g * (3.0 - 2.0 * g);
    float3 k = lerp(g, s, Contrast);
    g = lerp(k, max(k, g), ShadowProtect * (1.0 - smoothstep(0.0, 0.45, g)));

    // Vibrance / saturation
    float l = Luma(g);
    float sat = Max3(g) - Min3(g);
    g = lerp(l.xxx, g, (1.0 + Vibrance * (1.0 - sat)) * Saturation);

    // Split toning
    float sh = 1.0 - smoothstep(0.0, 0.5, l);
    float hi = smoothstep(0.5, 1.0, l);
    g *= lerp(float3(1.0, 1.0, 1.0), ShadowColor, sh * SplitTone);
    g *= lerp(float3(1.0, 1.0, 1.0), HighlightColor, hi * SplitTone);

    // Output levels
    g = OutputBlack + saturate(g) * (OutputWhite - OutputBlack);

    // Vignette
    float2 vd = (uv - 0.5) * float2(BUFFER_ASPECT_RATIO, 1.0);
    g *= 1.0 - Vignette * smoothstep(0.35, 1.1, length(vd));

    g = saturate(g);

    // ---- Debug views ----
    if (DebugView == 1)
    {
        if (uv.x < SplitPos) g = orig;
        if (abs(uv.x - SplitPos) < BUFFER_RCP_WIDTH * 1.5) g = float3(1.0, 0.8, 0.2);
    }
    else if (DebugView == 2)
    {
        float tl = tex2D(VV_Scene, uv).a;               // total gain (log2)
        float x = saturate(tl / 2.5 * 0.5 + 0.5);        // -2.5..+2.5 stops -> 0..1
        g = lerp(HeatMap(x), Luma(orig).xxx, 0.35);
    }
    else if (DebugView == 3)
    {
        g = LinearToSRGB(saturate(bloom + streak));
    }
    else if (DebugView == 4)
    {
        float w = tex2D(VV_Quarter, uv).b;              // highlight exclusion weight
        g = lerp(orig, float3(0.1, 0.4, 1.0), (1.0 - w) * 0.7);
        g = lerp(g, float3(1.0, 0.1, 0.1), hud * 0.45);
        // Meters (top-left):
        //   white   = global gain (0..4x, red tick = 1x)
        //   cyan    = frame contrast (0..4 stops)
        //   yellow  = daylight factor
        //   green   = camera motion confidence      (motion blur builds only)
        //   magenta = camera speed (0..64 px/frame) (motion blur builds only)
        float2 bp = uv * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
        if (bp.x > 20 && bp.x < 420 && bp.y > 20 && bp.y < 140)
        {
            float row = floor((bp.y - 20) / 24.0);
            float fx = (bp.x - 20) / 400.0;
            float val = 0.0;
            float3 col = float3(1, 1, 1);
            if (row < 0.5)      { val = exp2(ad.r) / 4.0; col = float3(1, 1, 1); }
            else if (row < 1.5) { val = ad.g / 4.0;       col = float3(0.2, 1, 1); }
            else if (row < 2.5) { val = Dayness(ad);      col = float3(1, 0.85, 0.2); }
#if VISTAV_MOTIONBLUR
            else
            {
                float4 mv = tex2Dlod(VV_MotionVec, float4(0.5, 0.5, 0, 0));
                if (row < 3.5) { val = mv.z;                                         col = float3(0.3, 1, 0.3); }
                else           { val = length(mv.xy * BUFFER_SCREEN_SIZE) / 64.0;    col = float3(1, 0.3, 1); }
            }
#endif
            g = fx < val ? col : float3(0.08, 0.08, 0.08);
            if (row < 0.5 && abs(fx - 0.25) < 0.003) g = float3(1, 0, 0);
        }
    }

    // Triangular dither: hides banding introduced by shadow lifting
    float fc = (float)FrameCount;
    float2 fo = float2(fc, floor(fc / 64.0));
    fo -= 64.0 * floor(fo / 64.0);                  // modulo 64 (ReShade FX has no fmod)
    float2 sp = pos.xy + fo * 17.0;
    float n = Hash(sp) + Hash(sp + 31.7) - 1.0;
    g += n / 255.0;

    return float4(g, 1.0);
}

// ============================================================================

technique VistaV <
    ui_label = "VistaV - Balance / Readability / Bloom";
    ui_label_zh = "VistaV - 均衡 / 可读性 / 泛光";
    ui_tooltip = "Anti eye-adaptation, local shadow lift, clarity, bloom, HUD text protection, tone.\nNo depth buffer needed. Place FIRST, before ColorMatrix and AdaptiveSharpen.";
    ui_tooltip_zh = "反自动曝光、局部暗部提亮、清晰度、泛光、HUD 文字保护、影调。\n不需要深度缓冲。请放在最前面，排在 ColorMatrix 和 AdaptiveSharpen 之前。";
>
{
    pass Prep        { VertexShader = PostProcessVS; PixelShader = PS_Prep;        RenderTarget = VV_QuarterTex; }
    pass Stats       { VertexShader = PostProcessVS; PixelShader = PS_Stats;       RenderTarget = VV_StatsTex; }
    pass Adapt       { VertexShader = PostProcessVS; PixelShader = PS_Adapt;       RenderTarget = VV_AdaptTex; }
    pass AdaptStore  { VertexShader = PostProcessVS; PixelShader = PS_AdaptStore;  RenderTarget = VV_AdaptPrevTex; }
    pass LocalDown   { VertexShader = PostProcessVS; PixelShader = PS_LocalDown;   RenderTarget = VV_LocalATex; }
    pass LocalBlurH  { VertexShader = PostProcessVS; PixelShader = PS_LocalBlurH;  RenderTarget = VV_LocalBTex; }
    pass LocalBlurV  { VertexShader = PostProcessVS; PixelShader = PS_LocalBlurV;  RenderTarget = VV_LocalATex; }
    pass Apply       { VertexShader = PostProcessVS; PixelShader = PS_Apply;       RenderTarget = VV_SceneTex; }

    pass BloomPre    { VertexShader = PostProcessVS; PixelShader = PS_BloomPrefilter; RenderTarget = VV_B0Tex; }
    pass Down1       { VertexShader = PostProcessVS; PixelShader = PS_Down1; RenderTarget = VV_B1Tex; }
    pass Down2       { VertexShader = PostProcessVS; PixelShader = PS_Down2; RenderTarget = VV_B2Tex; }
    pass Down3       { VertexShader = PostProcessVS; PixelShader = PS_Down3; RenderTarget = VV_B3Tex; }
    pass Down4       { VertexShader = PostProcessVS; PixelShader = PS_Down4; RenderTarget = VV_B4Tex; }
    pass Down5       { VertexShader = PostProcessVS; PixelShader = PS_Down5; RenderTarget = VV_B5Tex; }
    pass Down6       { VertexShader = PostProcessVS; PixelShader = PS_Down6; RenderTarget = VV_B6Tex; }
    pass Up5         { VertexShader = PostProcessVS; PixelShader = PS_Up5;   RenderTarget = VV_U5Tex; }
    pass Up4         { VertexShader = PostProcessVS; PixelShader = PS_Up4;   RenderTarget = VV_U4Tex; }
    pass Up3         { VertexShader = PostProcessVS; PixelShader = PS_Up3;   RenderTarget = VV_U3Tex; }
    pass Up2         { VertexShader = PostProcessVS; PixelShader = PS_Up2;   RenderTarget = VV_U2Tex; }
    pass Up1         { VertexShader = PostProcessVS; PixelShader = PS_Up1;   RenderTarget = VV_U1Tex; }
    pass Up0         { VertexShader = PostProcessVS; PixelShader = PS_Up0;   RenderTarget = VV_U0Tex; }

#if VISTAV_MOTIONBLUR
    pass MotionLuma      { VertexShader = PostProcessVS; PixelShader = PS_MotionLuma;      RenderTarget = VV_MotionCurTex; }
    pass MotionSAD       { VertexShader = PostProcessVS; PixelShader = PS_MotionSAD;       RenderTarget = VV_SADTex; }
    pass MotionPick      { VertexShader = PostProcessVS; PixelShader = PS_MotionPick;      RenderTarget = VV_MotionVecTex; }
    pass MotionVecStore  { VertexShader = PostProcessVS; PixelShader = PS_MotionVecStore;  RenderTarget = VV_MotionVecPrevTex; }
    pass MotionLumaStore { VertexShader = PostProcessVS; PixelShader = PS_MotionLumaStore; RenderTarget = VV_MotionPrevTex; }
#endif

#if VISTAV_STREAK
    pass Streak1     { VertexShader = PostProcessVS; PixelShader = PS_Streak1;  RenderTarget = VV_S1Tex; }
    pass Streak2     { VertexShader = PostProcessVS; PixelShader = PS_Streak2;  RenderTarget = VV_S2Tex; }
    pass Streak3     { VertexShader = PostProcessVS; PixelShader = PS_Streak3;  RenderTarget = VV_S3Tex; }
    pass Streak4     { VertexShader = PostProcessVS; PixelShader = PS_Streak4;  RenderTarget = VV_S4Tex; }
    pass StreakU3    { VertexShader = PostProcessVS; PixelShader = PS_StreakU3; RenderTarget = VV_SU3Tex; }
    pass StreakU2    { VertexShader = PostProcessVS; PixelShader = PS_StreakU2; RenderTarget = VV_SU2Tex; }
    pass StreakU1    { VertexShader = PostProcessVS; PixelShader = PS_StreakU1; RenderTarget = VV_SU1Tex; }
#endif

    pass Final       { VertexShader = PostProcessVS; PixelShader = PS_Final; }
}
