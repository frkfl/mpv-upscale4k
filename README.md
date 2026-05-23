<p align="center">
  <img src="https://commons.wikimedia.org/wiki/File:Mpv_logo_(official).png" alt="mpv logo" width="90" height="90"/>
</p>

<h1 align="center">🎞️ 4K Upscaler for all sources</h1>

<p align="center">
  <a href="https://mpv.io/"><img src="https://img.shields.io/badge/mpv-gpu--next-blueviolet?style=flat-square" alt="mpv gpu-next"/></a>
  <img src="https://img.shields.io/badge/shaders-GLSL-orange?style=flat-square" alt="GLSL"/>
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20Windows-lightgrey?style=flat-square" alt="platform"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License"/></a>
</p>

---

### 🧭 Overview

It is a collection of GLSL shaders and profiles for **mpv** that upscale to 4K.

Depending on the original quality and resolution, they goal vary between

- A more watchable experience when the source is so bad that 4K would full-screen normally hurts the result
- A good, detailed experience in 4K as the the source gets closer to a good Full HD video.

---

## ⚙️ Installation

### Prerequisites

Install **mpv**: https://mpv.io/installation/

### Download the project

Go to the release page, download Assets → Source Code (zip)
https://github.com/frkfl/mpv-upscale4k/releases

### Add / Install this project

Clone **or** copy this project into your mpv configuration directory.

| OS          | Installation                                                                                          |
| :---------- | :---------------------------------------------------------------------------------------------------- |
| **Windows** | Copy all the project files into `%APPDATA%\mpv\` (usually `C:\Users\<YourName>\AppData\Roaming\mpv\`) |
| **macOS**   | Copy all the project files into `~/.config/mpv`                                                       |
| **Linux**   | Copy all the project files into `~/.config/mpv`                                                       |

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

### Add / Install this project (power users)

On Linux (and other Unix-like systems), you can clone directly into your mpv config dir:

```bash
git clone https://github.com/frkfl/mpv-upscale4k ~/.config/mpv
```

---

## ▶️ How to use

Once the files are in your mpv config folder, you just play videos with mpv as usual.  
The restoration / upscaling runs automatically.

### Opening a video

| OS          | How to open a video with mpv                                                                                                 |
| :---------- | :--------------------------------------------------------------------------------------------------------------------------- |
| **Windows** | Open **Explorer** → find your video → right-click → **Open with → mpv** (or drag the file onto `mpv.exe` / an mpv shortcut). |
| **macOS**   | Drag the video file onto the **mpv** app (Dock / Applications), or run `mpv /path/to/file.mp4` in Terminal.                  |
| **Linux**   | From a terminal: `mpv your_video_file.mkv`, or in your file manager: right-click → **Open With → mpv**.                      |

### Toggling the processing

The video processing is enabled by default.
While a video is playing, you can enable/disable the processing:

- Press **`Ctrl + S`** to **turn processing off** and see plain mpv scaling.
- Press **`Ctrl + S`** again to **turn processing back on**.

This lets you instantly compare:

- the original player output
- the result of this project improvements

## 📜 License

All shaders and configs are released under the MIT License.
You may freely copy, modify, and redistribute — credit appreciated but not required.

---

## 💡 Credits

Shader math inspired by FSRCNNX, SSimSuperRes, and Björn Ottosson’s OkLab.
Tone and color methodology co-developed with ChatGPT-5 experimental research assistance.
Tested on RTX 3080 / mpv-gpu-next Vulkan backend, tuned for 24 fps cinematic sources.
