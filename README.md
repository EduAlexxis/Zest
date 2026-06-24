# Zest
I built Zest because I was tired of every live wallpaper app needing a paid subscription, a upfront payment, or a limited free trial. Zest is 100% free, open-source, has zero paywalls, and uses minimal CPU and battery.
---
## Key Features
* **Battery & CPU Efficient**: Automatically pauses wallpaper playback when other windows cover the screen, when apps are fullscreen, when running on battery power, or when Low Power Mode is active.
* **Responsive Audio Fading**: Fades and mutes audio instantly when switching spaces or clicking the desktop background.
* **Universal Video Support**: Drag and drop WebM, WebP, MKV, FLV, or AVI files directly into the library—Zest transcodes them using a bundled `ffmpeg` pipeline.
* **Menu Bar Volume Slider**: Quickly adjust wallpaper volume via a slider embedded directly in your macOS menu bar.
* **macOS Sleep Protection**: Tears down and rebuilds video rendering layers completely on system sleep and wake to prevent frozen screens or audio driver loops.
---

# Screenshots
<img width="800" height="600" alt="Screenshot 2026-06-23 at 11 30 37 PM" src="https://github.com/user-attachments/assets/a1aae2e1-7b46-45df-9786-c9a3ba346637" /> <img width="800" height="600" alt="Screenshot 2026-06-23 at 11 30 53 PM" src="https://github.com/user-attachments/assets/a071a7d1-1cf9-474e-982e-e34468a9ab82" /> <img width="800" height="600" alt="Screenshot 2026-06-23 at 11 30 53 PM" src="https://github.com/user-attachments/assets/12327f20-e073-4c3f-8eca-cce9a7da6926" /> <img width="800" height="600" alt="Screenshot 2026-06-23 at 11 30 10 PM" src="https://github.com/user-attachments/assets/f1935bfd-1802-4ba8-9ddd-ebc6b3b08db9" />



## Requirements
* **Operating System**: macOS 13.0 (Ventura) or newer.
* **Hardware**: Apple Silicon (M1/M2/M3/M4/M5) or Intel-based Macs.
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
