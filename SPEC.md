# ClipRecallBar — specification

**Tagline:** A keyboard-first clipboard history popup in your menu bar that filters as you type and pastes on Return.

**Category:** Clipboard

**Inspired by (paid):** Maccy ($9.99 one-time)

**Frameworks:** SwiftUI, AppKit, Carbon, ApplicationServices, ServiceManagement, UniformTypeIdentifiers

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. Maccy is a lightweight clipboard manager that lives in the menu bar. The Mac App Store edition sells for 9.99 dollars as a way to support development, and roundups from Cult of Mac and iGeeksBlog repeatedly recommend it as the simple, fast, keyboard-driven choice. People like that it opens instantly, searches as you type, and stays out of the way. Our clean-room version, ClipRecallBar, covers the same core need with original code and design.

Feature set. The app watches the general pasteboard and stores text, rich text converted to plain text, file URLs, and small images. It keeps up to a configurable number of entries, with a default of 200 and a range from 20 to 999. Duplicates are moved to the top instead of repeated. A global hotkey opens a floating panel with a search field focused. Typing filters the list using case-insensitive substring matching with simple fuzzy scoring. Arrow keys move the selection, Return pastes the selected entry into the previously active app, Option plus Return pastes as plain text, and Command plus the digits one through nine pastes the corresponding row directly. Delete removes an entry. Command plus P pins an entry so it survives clearing and sorts above the rest. A Clear All action asks for confirmation and keeps pinned entries.

UI spec. The app is a MenuBarExtra with a clipboard symbol. Clicking the icon or pressing the global hotkey, default Shift plus Command plus V, shows a borderless non-activating NSPanel centered near the mouse pointer, about 420 by 480 points. The top holds the search field. Below is a scrolling list where each row shows a type icon, a one-line preview truncated to 80 characters, the source app icon, and a relative time. The bottom bar shows the count and a gear button. Empty state: a centered message reading Nothing copied yet, with a hint to copy something. No-results state: No matches. The settings window has a Form with these fields: history size stepper, hotkey recorder, a toggle for Launch at login, a toggle for Play sound on copy, a toggle for Ignore items marked as concealed, a list of ignored apps by bundle identifier with add and remove buttons, and a Clear history button. Menu items in the status menu are Open History, Pause Capture (toggle), Settings, and Quit.

Technical approach. Poll NSPasteboard.general.changeCount every 0.4 seconds using a Timer on the main run loop and read new items when it changes. Identify the frontmost app with NSWorkspace to filter ignored bundle identifiers. Skip items carrying the community concealed and transient pasteboard types so password manager copies are never stored. Register the global hotkey with Carbon RegisterEventHotKey, which needs no permission. To paste, write the chosen entry to the pasteboard, hide the panel, reactivate the previous app, and post a synthetic Command plus V pair with CGEvent. This requires Accessibility permission, so check with AXIsProcessTrustedWithOptions at first launch, show a short explanation sheet, and open the Privacy and Security pane through the system settings URL scheme if the user agrees. Without permission, fall back to copying only and show a banner saying Copied, press Command V to paste. Persist history as JSON in Application Support inside an app folder, with images stored as PNG files referenced by name, and settings in UserDefaults through AppStorage. Launch at login uses SMAppService.mainApp register and unregister, and the toggle reflects the real status.

Edge cases and error handling. Cap each text entry at 1 megabyte and each image at 10 megabytes and silently skip larger ones. Handle empty or unreadable pasteboard types without crashing. If the JSON file is corrupt, move it aside with a dated suffix and start fresh. Debounce rapid copy bursts. Ignore the app's own writes by remembering the changeCount after a paste. If the hotkey is already taken, show an inline error in settings. Write files atomically and on a background queue, and prune orphaned image files at launch.
