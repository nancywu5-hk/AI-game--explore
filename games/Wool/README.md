<!-- Header Section -->
<div align="center">

# 🧶 Wool - Mobile Platformer

![Godot Engine](https://img.shields.io/badge/Godot-4.x-blue?style=for-the-badge&logo=godot-engine&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Mobile%20%7C%20Web%20%7C%20Windows-green?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-In%20Development-orange?style=for-the-badge)

<br/>

<!-- Dynamic Build Status Badges -->
![Web Build](https://img.shields.io/endpoint?url=https%3A%2F%2Feliassteffen.github.io%2FWool%2Fbadges%2Fweb.json)
![Windows Build](https://img.shields.io/endpoint?url=https%3A%2F%2Feliassteffen.github.io%2FWool%2Fbadges%2Fwindows.json)

<br/>

### [👉 Play the Live Demo! 👈](https://eliassteffen.github.io/Wool/demo)

<br/>

A mobile platformer game developed with **Godot 4.x** as part of a university project at FH Münster. Play as Wool, navigate through challenging levels, swing on hooks, and avoid enemies like Eagles and Fish!

</div>

---

## 🎮 Game Description

A high-quality 2D mobile platformer featuring:

- **🏃 Character Control**: Fluid Jump, Hook, and Swing mechanics.
- **🦅 Dynamic Enemies**: Surviving encounters with Eagles (flying) and Fish (jumping).
- **🔊 Immersive Audio**: 3D-positioned sound effects with dynamic volume based on visibility and proximity.
- **📱 Mobile Optimized**: Designed for landscape mobile play (2532×1170).

---

## 🚀 Getting Started

### Prerequisites

| Software | Version | Link |
| :--- | :--- | :--- |
| **Godot Engine** | 4.x (Standard) | [Download](https://godotengine.org/download) |

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/EliasSteffen/Wool.git
   ```

2. Open **Godot Engine**, click **Import**, and navigate to the cloned directory.

3. Select `project.godot` and click **Import & Edit**.

---

## 🕹️ Controls

| Action | Input |
| :--- | :--- |
| **Jump / Interact** | `Spacebar` / Left Mouse Click / Touch |
| **Hook / Swing** | Automatic when near a hook point |

---

## 🛠️ Project Structure

```
assets/       Game assets (sprites, audio, fonts)
scenes/       Game scenes (.tscn)
  levels/     Playing fields
  characters/ Character prefabs (Wool, Enemies)
  ui/         Menus and HUD
scripts/      GDScript logic
  globals/    Autoloaded singletons (AudioManager, GameManager)
  characters/ Character behavior
www/          Marketing website (deployed alongside the demo)
```

---

## 📦 Exporting

The project is pre-configured for Web and Windows export.

1. In Godot, go to **Project → Export…**
2. Select a preset (Web / Windows Desktop).
3. Click **Export Project…** and choose a destination.

CI/CD via GitHub Actions exports automatically on every push to `main` and deploys to [GitHub Pages](https://eliassteffen.github.io/Wool).

---

## 👥 Contributors

| Name | Role |
| :--- | :--- |
| **E. Steffen** | Game development, project setup, CI/CD |
| **Mischa** | Game development |

---

## 📄 License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE) for details.
