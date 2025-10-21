<p align="center">
  <img src="https://en.wikipedia.org/wiki/Mpv_(media_player)#/media/File:Mpv_logo_(official).png" alt="mpv logo" width="90" height="90"/>
</p>

<h1 align="center">🎞️ Analog Restoration Chain for mpv</h1>

<p align="center">
  <em>Rebuilding lost analog beauty — not hallucinating digital sharpness.</em>
</p>

<p align="center">
  <a href="https://mpv.io/"><img src="https://img.shields.io/badge/mpv-gpu--next-blueviolet?style=flat-square" alt="mpv gpu-next"/></a>
  <img src="https://img.shields.io/badge/shaders-GLSL-orange?style=flat-square" alt="GLSL"/>
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20Windows-lightgrey?style=flat-square" alt="platform"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License"/></a>
</p>

---

### 🧭 Overview

The **Analog Restoration Chain** is a collection of GLSL shaders and profiles for **mpv** that reconstruct perceptual video quality from **240p to 1080p sources** — turning noisy, compressed footage into a **stable, filmic 4K experience**.

In addition to a classic Neural upscaler, this project:
- Restores texture and tone without fabricating detail  
- Uses entropy, color fidelity, and analog simulation  
- Runs fully in real time on modern GPUs (tested on RTX 3080)

---

# 🎞️ Analog Restoration Chain for mpv
### *Rebuilding lost image quality through patient, layered refinement.*

---

## 📜 Overview
This project provides a collection of GLSL shaders and mpv profiles designed to **restore perceptual quality** to low-resolution, heavily compressed video (480p or less) — without hallucinating fake detail.  
It works by **deconstructing compression artifacts**, **restoring analog structure**, and **re-stitching tone, color, and texture** into a stable, film-like result.

Think: *a good DVD player feeding a high-end CRT — but in 4K.*

---

## 🧩 Design Philosophy
> “Don’t reinvent pixels — let them remember how they used to look.”

### Core principles
1. **No recreation, only reconstruction**  
   Filters derive structure from artifact patterns, not neural guesswork.
2. **Entropy before collapse**  
   Controlled grain and CRT emulation break compression regularities.
3. **Layered linearity**  
   All passes operate in float-linear (RGBA16F) space to avoid posterization.
4. **Perceptual correction, not perfection**  
   A slightly soft, coherent image is preferable to brittle digital sharpness.
5. **Temporal calm**  
   A single stabilizer (TXAA-lite, temporal blend, or sharpen-decay) maintains visual stability.

---


---

## ⚙️ Installation WIP

1. Clone or copy this repository into your mpv configuration directory:  
   ```bash
   git clone https://github.com/<yourname>/mpv-analog-restoration-chain ~/.config/mpv

2. Todo

## 🧠 Pipeline Overview

| Stage                       | Intent                                                 | Typical Tools                                              |
| :-------------------------- | :----------------------------------------------------- | :--------------------------------------------------------- |
| **1. Normalize**            | Fix SD colorimetry (BT.601) and expand contrast safely | `eq`, `colormatrix`, `lift_shadows`                        |
| **2. Early upscale**        | Rebuild geometry without aliasing                      | `KrigBilateral`, `FSRCNNX`, `SSimSuperRes`                 |
| **3. Analog prepass**       | Add grain / CRT to reintroduce natural entropy         | `crt_natural`, `micro_entropy_grain`                       |
| **4. SSIM collapse**        | Downscale to 720p “master” to fuse structure           | mpv’s `scale=ssim`                                         |
| **5. Cleanup & re-upscale** | Remove residue, denoise, rebuild 4K                    | `nlmeans_light`, `masked_sharpen`                          |
| **6. Temporal balance**     | TXAA-lite stabilization                                | `temporal_sharpen`, `smaa`                                 |
| **7. Color refinement**     | Adaptive vibrance + skin tone control                  | `vibrance_oklab`, `chroma_pop`, `skin_tone_tamer_adaptive` |
| **8. Final polish**         | Subtle CRT, film-like grain                            | `crt_natural`, `temporal_blue_grain`                       |


## 🔬 Profiles

240p.conf

For 240p–360p analog or VHS-era material.
Performs double upscale, heavy artifact smoothing, and pre-collapse CRT.

480.conf

720p
Balanced reconstruction, medium entropy, adaptive sharpening, and color pop.

1080.conf

Web 900p and higher sources needing clarity without oversharpening.
Light reconstruction, stronger micro-contrast, and specular protection.

---

## 🎛️ Tuning Tips

| Desired effect      | Change                                          |
| ------------------- | ----------------------------------------------- |
| Softer motion       | `temporal_sharpen.motion_sense=0.9`             |
| Crisper stills      | `masked_sharpen.strength=0.34`                  |
| Milder CRT          | `crt_natural.mask_strength=0.14`                |
| More vivid color    | `vibrance_oklab.vibrance=0.14`                  |
| Preserve film grain | lower `micro_entropy_grain.strength` to `0.006` |

---

## 🧪 Roadmap

 - Lua / Python auto-profile by quality scoring
 - Per-scene adaptive tone mapping
 - Real-time tweak OSC overlay
 - Comparison suite (before/after stills)
 - Publish demo clips (open domain footage)


---

## 📜 License

All shaders and configs are released under the MIT License.
You may freely copy, modify, and redistribute — credit appreciated but not required.

---

## 💡 Credits

Shader math inspired by FSRCNNX, SSimSuperRes, and Björn Ottosson’s OkLab.
Tone and color methodology co-developed with ChatGPT-5 experimental research assistance.
Tested on RTX 3080 / mpv-gpu-next Vulkan backend, tuned for 24 fps cinematic sources.