# OctoCmd

<img width="1240" alt="tentacle" src="https://user-images.githubusercontent.com/613943/234757831-b20ffa07-d49c-4a5b-b850-48147310d29e.png">

A blazingly fast productivity tool for macOS. Switch apps, search screen text, and navigate windows without leaving your keyboard.

## What is this?

**OctoCmd** is an open-source productivity suite, inspired by [rcmd](https://lowtechguys.com/rcmd/) and [Vimium](https://vimium.github.io/). It evolves beyond a simple app switcher into a comprehensive keyboard-driven navigation tool.

## Key Features

- **App Switcher:** Blazingly fast app switching using the first letter of the application name.
- **Search Mode:** Search for any text visible on your screen and click it instantly.
- **Link Hints:** Keyboard-driven clicking for buttons, links, and UI elements (Vimium-style).
- **Scroll Mode:** Navigate and scroll through windows using `j`/`k` or arrow keys.
- **App Groups:** Group related applications together to activate them with a single keystroke.
- **Pinning:** Keep your most-used apps always visible in the switcher.
- **Electron Support:** Enhanced accessibility for Electron apps like Slack, Discord, and VS Code.

## How to use?

### App Switching
At any time, hit the **Right Command** <kbd>⌘</kbd> key to bring up the main screen. From here, press any letter to jump to the corresponding application.

- <kbd>Right ⌘ + C</kbd> for **Google Chrome**
- <kbd>Right ⌘ + F</kbd> for **Firefox**
- <kbd>Right ⌘ + I</kbd> for **IntelliJ IDEA**

### Search Mode
Hit <kbd>⇧ + Space</kbd> (default) to enter Search Mode. Type any text you see on the screen to highlight it.
- Press <kbd>Enter</kbd> to click on the selected result.
- Use <kbd>AA</kbd>, <kbd>AB</kbd>, etc., hints to jump directly to clickable elements.

### Scroll Mode
Hit <kbd>⌃ + S</kbd> (default) to enter Scroll Mode. The active scrollable area will be highlighted with a blue border.
- Use <kbd>j</kbd>/<kbd>k</kbd> or <kbd>↑</kbd>/<kbd>↓</kbd> to scroll.
- Use <kbd>h</kbd>/<kbd>l</kbd> or <kbd>←</kbd>/<kbd>→</kbd> for horizontal scrolling.
- Press <kbd>Tab</kbd> to cycle between different scrollable areas in the window.

### Navigation
Within the OctoCmd window, use these shortcuts to switch pages:
- <kbd>⌘ + 1</kbd>: Active Apps
- <kbd>⌘ + 2</kbd>: Skipped Apps
- <kbd>⌘ + 3</kbd>: App Groups
- <kbd>⌘ + 4</kbd>: Settings

Hit <kbd>ESC</kbd> to dismiss the window or <kbd>⌘ + Q</kbd> to quit.

## Settings
OctoCmd is highly customizable. You can change activation shortcuts for all modes in the **Settings** tab (<kbd>⌘ + 4</kbd>). Double-click on any shortcut to record a new one.
