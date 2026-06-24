# Zest
**Zest** is a super lightweight, completely free, and open-source live wallpaper application for macOS. 
I built Zest because I was tired of every live wallpaper utility needing a paid subscription, a upfront payment, or a limited free trial. Zest is 100% free, open-source, has zero paywalls, and uses minimal CPU and battery.
---
## Key Features
* **Battery & CPU Efficient**: Automatically pauses wallpaper playback when other windows cover the screen, when apps are fullscreen, when running on battery power, or when Low Power Mode is active.
* **Responsive Audio Fading**: Fades and mutes audio instantly when switching spaces or clicking the desktop background.
* **Universal Video Support**: Drag and drop WebM, WebP, MKV, FLV, or AVI files directly into the library—Zest transcodes them using a bundled `ffmpeg` pipeline.
* **Menu Bar Volume Slider**: Quickly adjust wallpaper volume via a slider embedded directly in your macOS menu bar.
* **macOS Sleep Protection**: Tears down and rebuilds video rendering layers completely on system sleep and wake to prevent frozen screens or audio driver loops.
---
## Requirements
* **Operating System**: macOS 13.0 (Ventura) or newer.
* **Hardware**: Apple Silicon (M1/M2/M3/M4) or Intel-based Macs.
---
## Installation
### Download pre-built DMG
1. Head over to the [Releases page](https://github.com/EduAlexxis/Zest/releases).
2. Download the latest `Zest.dmg`.
3. Open the DMG and drag **Zest** into your **Applications** folder.
---
## Building from Source
If you want to build or modify Zest yourself:
### Requirements
* **Xcode 15.0** or newer.
* **Swift 5.9** or newer.
### Build Steps
1. Clone this repository:
   ```bash
   git clone https://github.com/EduAlexxis/Zest.git
   cd Zest
   ```
2. Open the Xcode project:
   ```bash
   open Zest.xcodeproj
   ```
3. Select the **Zest** scheme, choose **My Mac** as the destination, and press **Cmd + R** to build and run.
---
## License
Zest is released under the permissive [MIT License](LICENSE). Feel free to use, copy, modify, or distribute it as you wish.
