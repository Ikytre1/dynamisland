<div align="center">

# 🏝️ Dynamisland

**A lightweight Dynamic Island for Wayland (Niri & Hyprland), built with QuickShell and QML.**

[![Wayland](https://img.shields.io/badge/Wayland-Niri%20%7C%20Hyprland-blueviolet?style=for-the-badge&logo=wayland)](https://wayland.freedesktop.org/)
[![QuickShell](https://img.shields.io/badge/Built%20with-QuickShell-008080?style=for-the-badge)](https://outfoxxed.me/quickshell/)
[![Qt/QML](https://img.shields.io/badge/UI-QML-green?style=for-the-badge&logo=qt)](https://www.qt.io/)
[![Status](https://img.shields.io/badge/Status-v1.0-orange?style=for-the-badge)]()

</div>

---

## 📌 Overview

**Dynamisland** is a standalone, widget extracted from [iNiR](https://github.com/snowarch/iNiR)'s pill turning it into a dynamic island with several key tweaks:

- **iOS-like UI Look:** iOS's dynamic island based appareance with refined visual polish.
- **Sub-Island Integration:** Secondary island component (currently active during media playback).
- **Standalone Setup:** Decoupled from iNiR to run seamlessly on both **Niri** and **Hyprland** (adaptation is curently being worked on).
- **Laptop Adaptation:** Designed mainly for laptops,some feature are more integrated with, but everything works the same with all kind of linux systems

It was designed to minimize required dependencies as much as possible.
>  **Note:** THIS IS NOT FINAL RELEASE. Built with a bit of vibe-coding for this v1.0 release. It's lightweight, holds up great for daily use, and minor UI glitches are actively being ironed out.



## Features

- **Light & Fast:** Minimal resource usage with quick QML rendering.
- **Native Wayland Support:** Designed for Niri and Hyprland layer-shell.
- **Notifications:** Notifications are displayed directly inside the dynamic island
- **Sub-Island Support:** Dedicated secondary island mode for active media playback.
- **LocalSend Integration:** LocalSend support for sharing files just by dragging and dropping file in the island

---

## Project Structure

```text
Dynamisland/
├── GlobalStates.qml    # Global state management
├── shell.qml           # Main entry point
├── modules/            # Island widgets
├── pill/               # Core pill UI, animations & sub-island logic
└── services/           # Backend services
```

---

## Preview

https://github.com/user-attachments/assets/bf66b471-a9f4-4581-b0ab-1fd993bfad4e


https://github.com/user-attachments/assets/57756f99-73d7-459b-a99f-71a053355748


https://github.com/user-attachments/assets/3ba6eb76-badf-4d9c-b50b-83481e7a4c49


https://github.com/user-attachments/assets/caebd7ca-01ab-4fe1-b718-997cc187592f

---


## Prerequisites
**Quickshell :**
```bash
# Official repo
sudo pacman -S quickshell

# Or via AUR (Git version)
yay -S quickshell-git
```
## Installation
```bash
git clone https://github.com/Ikytre1/dynamisland.git
cd dynamisland
./install.sh
```
(the script will auto-detect your config and automatically apply an auto exec for your compositor)

## Usage
If not already launched after the installation, just check if  everything's here :
```bash
ls ~/.config/quickshell/
# You should see a "dynamisland" folder. IF NOT:
cp -r ~/dynamisland/  ~/.config/quickshell/
```
To launch it, type :
```bash
qs -c dynamisland
```
You'll notice the island on your screen. Even though there isn't any settings window, you can manually edit values in :
```bash
~/.config/dynamisland/config.json
```
And you should be ready to go!

## About LocalSend 
To use LocalSend, you **DO NOT** need it installed on your system; its features are already natively implemented within the dynamic island! 

Just take a file and drag it into the island and select your device (both need to be on the same network)
> **REMEMBER :** As a first release, it's not perfect don't expect a result of a whole team work, i did this only by myself and it's my first repo. But i spent a lot of time to optimize it. Any issues or improvements requests are welcome!
