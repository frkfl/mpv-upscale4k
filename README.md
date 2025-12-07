<p align="center">
  <img src="https://en.wikipedia.org/wiki/Mpv_(media_player)#/media/File:Mpv_logo_(official).png" alt="mpv logo" width="90" height="90"/>
</p>

<h1 align="center">🎞️ The best 4K possible for mpv, whatever the source</h1>

<p align="center">
  <em>Rebuilding lost analog beauty, lost digital crispness — not hallucinating digital sharpness.</em>
</p>

<p align="center">
  <a href="https://mpv.io/"><img src="https://img.shields.io/badge/mpv-gpu--next-blueviolet?style=flat-square" alt="mpv gpu-next"/></a>
  <img src="https://img.shields.io/badge/shaders-GLSL-orange?style=flat-square" alt="GLSL"/>
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20Windows-lightgrey?style=flat-square" alt="platform"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License"/></a>
</p>

---

### 🧭 Overview

The **Best 4K for mpv, whatever the source** is a complete solution to drag & drop to upscale to 4K from any sources. No setting required. No tuning. Throw it your worst.

It is a collection of GLSL shaders and profiles for **mpv** that reconstruct perceptual video quality from **240p to 1080p sources** — turning noisy, compressed footage into a **stable, filmic 4K experience** as much as possible, extracting the most information possible from each pixel. The configuration files take care of selecting the right process, cleaning process are auto-tuned.

In addition to a classic Neural upscaler, this project:
- Restores texture and tone without fabricating detail  
- Uses entropy, color fidelity, and analog simulation
- Fix analog problems like chroma bleeding and many other
- Provide a full chain of numerical restoration tuned for each resolution
- Runs fully in real time on modern GPUs (tested on RTX 3080)

The result will depends on the source material, but every source will get every hint of information squeeze to give the best details in 4K

Expect
- Surpringly watchable old camera records
- Excellent rendering from 720p, with no blur a little artifact, but not that detailed
- Almost 4K full quality from an average/mediocrer 1080p video

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

## Core principles
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

# ⚙️ Installation

## Prerequisites

Install **mpv**: https://mpv.io/installation/

## Add / Install this project

Clone **or** copy this project into your mpv configuration directory.

| OS           | Installation                                                                                         |
| :----------- | :--------------------------------------------------------------------------------------------------- |
| **Windows**  | Copy all the project files into `%APPDATA%\mpv\` (usually `C:\Users\<YourName>\AppData\Roaming\mpv\`) |
| **macOS**    | Copy all the project files into `~/.config/mpv`                                                      |
| **Linux**    | Copy all the project files into `~/.config/mpv`                                                      |

> **Important:**  
> Copy the **contents** of the project into the mpv folder, not the folder itself.  
> The final layout should look like:
>
> - `mpv/mpv.conf`
> - `mpv/shaders/...`
> - `mpv/shaders-dl/...`
> - `mpv/profiles/...`
>
> **Not**: `mpv/mpv-upscale4k/mpv.conf`

## Add / Install this project (power users)

On Linux (and other Unix-like systems), you can clone directly into your mpv config dir:

```bash
git clone https://github.com/frkfl/mpv-upscale4k ~/.config/mpv 
```

---

Got it, let’s make it feel like a real README section, not a Q&A block.

Here’s a cleaner, narrative-style version you can drop in:

## ▶️ How to use

Once the files are in your mpv config folder, you just play videos with mpv as usual.  
The restoration / upscaling runs automatically.

### Opening a video

**Windows**

- Open **Explorer** and locate your video file.
- Right-click the file → **Open with** → **mpv**  
  (or drag the file onto `mpv.exe` / an mpv shortcut).

**macOS**

- Drag the video file onto the **mpv** app (in Dock or Applications), or
- Use Terminal:
  ```bash
  mpv /path/to/your_video.mp4
  ```

**Linux**

Well, you already know, don't you? mpv as a player and let's roll.
Have fun with ~/.config/mpv if you want.


### Toggling the processing

The video processing is enabled by default.
While a video is playing, you can enable/disable the processing:

* Press **`Ctrl + S`** to **turn processing off** and see plain mpv scaling.
* Press **`Ctrl + S`** again to **turn processing back on**.

This lets you instantly compare:

* the original player output, and
* what this project reconstructs in motion.


---

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

480.conf
Patient VHS era deterministic noise reduction.
Digital hammering with filters until it looks correct.

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

 - Fullest 480p Analog/early digital restoration
 - Feeding information from analog for later digital shader (Neural!!)
 - Lua / Python auto-profile by quality scoring
 - Per-scene adaptive tone mapping
 - Real-time tweak OSC overlay
 - Comparison suite (before/after stills)
 - Publish demo clips (open domain footage)


---

## Compatibility

# Hardware

## Geforce 3080 RTX

This is simply the GPU I am using.
For HD content, it is extremely light, in memory, I get 10% use of the GPU. I tested the code once on a 1070 GTX, no problems.
For old VHS-like video, it is much heavier. 20~30% range.
But there is no AI, so no problem with a 2070 I would assume.

## No heavy process

So there is almost nothing heavy in the code. Nothing in the code I wrote.
Most code are pixel per pixel work, parallelized in the GPU : Even 4K work is super fast.

3 things are heavy:

1 - FSRCNXX is heavy.

It is the "AI upscaler". But there is nothing AI in it.
A neural network (they are sometimes called AI) trained on a tons of videos and that gave a list of magic numbers.
Like : 0.0075713125988841, use that here in your calculation. It's a very topic on itself.

These numbers used in mathematical calculations (matrices) to give the best improvement.
So the number are hard coded, there is no AI looking at your picture.
But it is a multi pass, complex, heavy on math process.


So it is hard to guarantee anything else than that it works on my PC lol
I have a Geforce RTX 3080. 

2 - Nlmeans is heavy

It is a quality improver. How to make the picture cleaner without making it weird, with block, or blur.
And I nead it for low resolution video. But I have a trick, I apply in intermediary resolution : 1080p

3 - My own code.

So far, nothing is really heavy, each shader is often 0.5ms.
But I already have 20 shaders. That's why it's heavy. So many things to fix.

Did you know that old sources have signal interference in the cable between color and light?
Well, that's why the colors come out disgusting.
It can be detected and partially fixed. But it's a few passes, you get more in the 1~3ms territory.
And you have like 40 ms to generate a frame. And you would rather do it in 10 ms so that you don't need a Geforce 3080 running at 100%.

# Processing

## Analog Repair

Brings the raw analog frame to “coherent but still low-frequency noisy.” It removes phase jitter, ringing, and line noise at native pixel geometry.

### Analog-domain repairs

This is the full analog defect spectrum that actually exists in VHS, DV, VCD, and early digital transfers.
Only used for resolution around 480p. It is fairly neutral for non analog sources (a DVD VOB).
But I don't really see the point of risking a 1080p picture with analog fixes.

| Problem                             | Physical origin                   | Status                                         |
| ----------------------------------- | --------------------------------- | --------------------------------------------------------------- |
| Y/C subcarrier phase drift          | Analog bandwidth + delay mismatch | ✅ Corrected (directional realignment `shift_px`, `k_strength`)  |
| One-way chroma bleed                | Filter asymmetry in tape playback | ✅ Modeled by sign(Gy * ΔC), directional and weighted            |
| Cross-talk Y↔C energy               | Shared signal path interference   | ✅ Rebalanced via α/β feedback                                   |
| Temporal flicker (luma gain wobble) | AGC instability, tape modulation  | ✅ Stabilized via deterministic EMA-like temporal smoothing      |
| Shadow color cast / chroma noise    | Subcarrier amplitude loss         | ✅ Neutralized by tone gate + chroma attenuation below threshold |
| Chroma loss near highlights         | Phase saturation in bright Y      | ✅ Compensated by soft knee + upper contrast rolloff             |
| Texture erosion                     | Bleed and protection interplay    | ✅ Prevented via HF preservation path and `Protect` gating       |

### Analog-domain improvements

These are improvements that are less deterministic. More a by-product of analog support flaws than a mathematical fix.
But it is deterministic enough to be activate if needed only, and universal for analog videos.

| Stage                                | Physical origin                                                                 | Deterministic correction                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **1. Auto dering detector**          | Subcarrier ringing and high-frequency chroma echo from Y/C separation filters   | ✅ Detects oscillation in Cb/Cr across ±2 px → applies directional 1D Gaussian dering (≈20 %) |
| **2. Auto chroma gain compensation** | AGC cross-coupling between luma and chroma amplifiers causing hue drift         | ✅ Measures chroma amplitude vs luma → applies proportional gain flattening via `gain_corr`   |
| **3. Auto unclip detector**          | ADC headroom loss: crushed blacks and clipped whites from limited dynamic range | ✅ Detects local min/max bounds → restores detail with soft power-curve unclip (0.88 / 1.05)  |

## Analog/Digital Structure Repair

Reconstructs local contrast and geometry after the front-end is stable. Still spatially tied to 480 p sampling.

### Temporal Structural Stabilizer

| Stage                                | Physical origin                                                                 | Deterministic correction                                                                     |
| ------------------------------------ | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **1. Upscale**                       | The analog fix did its best. We need more pixel to temporize                    | ✅ Spline upscale                                                                            |
| **2. Temporal Structural Stabilizer**| Frame individually look better. In motion, the picture is unstable.             | ✅ unifies frame-to-frame micro-variance in that sub-pixel domain                            |

## Colors

That is a big differentiator with current solutions.
Videos have a real problems with colors. It is not just about "put some AI and sharpening".

### Better colors

The picture is originally limited range. Broken by compression. Wrongly written in the metadata.

| Stage                                | Goal                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------- |
| **1. Aut Color Matrix**             | Correct colors when the metadata is wrong, normalize.                           |
| **2. Color Expang log**             | Push the limited range to full, more color to play with, real black&white       |
| **3. OK LabCH Vibrance**            | A very documented method to give some natural vibrance on colors                |
| **4. Chroma Pop**                   | It is like above, but more deterministic. Easier to adjust a popping color      |
| **5. Shadow Lift**                  | Reduce the impact of shadows on lum for details                                 |

### Totally, let’s make a clean, paste-ready version you can drop straight into your README.

Here’s a compact version that keeps the intent, the tech bits, and the good-faith disclaimer.

---

### 🎭 Face fidelity & skin tones

Human vision is brutally sensitive to faces.
If skin tones are wrong, hair shimmers, or noses and mouths have halos, the whole image feels **uncanny**—even if everything else looks “sharper.”

This project treats faces as **sacred**:

* no plastic / wax skin
* no fake HDR “Instagram face”
* no dark skin vanishing into shadows
* no pale skin turning into glowing paper next to a white wall

A single generic “skin curve” doesn’t work in practice:

* light skin tends to blend into bright backgrounds
* darker skin gets crushed into black in low-key scenes
* everyone drifts toward the same safe orange/peach midtone

To avoid that, there’s a dedicated `skin_universal.glsl` shader, run with **multiple presets** for broad tone clusters (very fair, light-warm, olive, tan, brown, deep brown, etc.). The goal is not to stylize people, but the opposite:

> give each skin tone enough headroom, contrast, and subtlety
> that faces look like *themselves* again, under whatever broken light and compression survived.

If a shot ends up with:

* believable skin,
* stable hair,
* no shimmering around nose and mouth,

then I accept losing some fake “wow” sharpness elsewhere.
Real faces > perfect pixels.

### ⚠️ Good faith & limitations

This is written by one person, with one pair of eyes and a limited test set.

I’ve put real work into making different skin tones look **true** under the same pipeline, not flattened into one “generic” look. That includes separate tuning for several tone clusters so:

* light skin doesn’t vanish into walls,
* darker skin doesn’t disappear in shadows,
* everyone keeps their own undertones and reflectance.

That said, it’s not perfect and it’s not universal. Cameras, lighting, makeup, grading, and compression can all interact in weird ways.
7 skin tones is about 7 times more than any other attempt. It is a gigantic work. But 7... let's be real, we are 7 billions

If you notice your own skin tone—or someone you care about—looking wrong under this pipeline, please treat that as a **bug**, not “how it is.” If you can, open an issue with a frame or a small clip. The intent is **respectful reconstruction**, and I’m very open to adjusting the math when it fails real people.

# Vulkan 

Setting vulkan is very simple. It is a GLSL engine for our shader.
In lay terms, it is the language to work on the picture.

What is a bit tricky is that the GLSL version is provided by the vulkan implementation in the GPU driver installation.
So in 2 years it could break. Already, there is a big divide 330/450.
But, fortunately, in practice, 330 or 450 should be higly compatible as we mostly code in very stable, and use only a handful of 2D primitives that are higly compatible.
At home I work with 450. So I rely on you to tell me if something is off. You should really get deep issues if it does not work : black screen, horrible colors, white noise.

## 📜 License

All shaders and configs are released under the MIT License.
You may freely copy, modify, and redistribute — credit appreciated but not required.

---

## 💡 Credits

Shader math inspired by FSRCNNX, SSimSuperRes, and Björn Ottosson’s OkLab.
Tone and color methodology co-developed with ChatGPT-5 experimental research assistance.
Tested on RTX 3080 / mpv-gpu-next Vulkan backend, tuned for 24 fps cinematic sources.
