# Clipboard Manager TODO

## V1: Fast Native Clipboard History

### Product Scope
- [x] Build a native macOS clipboard manager using Swift.
- [x] Keep the app lightweight, fast, and menu-bar based.
- [x] Use a flat history list instead of folders or groups.
- [x] Prioritize keyboard-driven usage and fast search.

### Clipboard Capture
- [x] Watch macOS clipboard changes.
- [x] Save clipboard history for plain text.
- [x] Save clipboard history for rich text when available.
- [x] Save clipboard history for URLs.
- [x] Save clipboard history for images.
- [x] Detect HEX colors in text clipboard entries.
- [x] Save file clipboard entries as file references only.
- [x] Add clear type indicators for unsupported or unknown clipboard data.
- [x] Deduplicate repeated clipboard entries.
- [x] Move duplicated entries to the top instead of storing copies.

### Preview
- [x] Show text preview with truncation.
- [x] Show URL preview with domain and full URL.
- [x] Show image thumbnail preview.
- [x] Show image dimensions and approximate size.
- [x] Show color swatch for HEX color values.
- [x] Show file icon, filename, and path for file entries.
- [x] Show source app and capture time for each entry.

### Quick Popup
- [x] Add customizable global hotkey.
- [x] Open popup at the current mouse position.
- [x] Show recent clipboard history in the popup.
- [x] Support keyboard navigation.
- [x] Support Enter to select an item.
- [x] Support Esc to close the popup.
- [x] Support mouse selection.
- [x] Add setting for select behavior: paste immediately or copy only.

### Search
- [x] Add search field inside the popup.
- [x] Search text clipboard entries.
- [x] Search URLs.
- [x] Search file names and paths.
- [x] Search by source app.
- [x] Make search case-insensitive.
- [ ] Keep search responsive with large history.

### Storage
- [x] Store history metadata in SQLite.
- [x] Store large image data outside SQLite.
- [x] Store image thumbnails separately.
- [x] Add configurable max history count.
- [x] Add configurable retention period.
- [x] Add configurable max storage size.
- [x] Add background cleanup for old entries.
- [x] Never load the full history into memory at startup.

### Ignore Rules
- [x] Add ignored app list.
- [x] Add ignored text regex rules.
- [x] Do not save clipboard entries that match ignore rules.
- [x] Add temporary pause recording action.
- [x] Add menu-bar toggle for pause/resume.

### Basic Management
- [x] Delete a single history item.
- [x] Clear all history.
- [x] Clear history by type.
- [x] Pin or favorite an item.
- [x] Keep pinned items from automatic cleanup.
- [x] Add menu-bar settings entry.
- [x] Add launch at login setting.

### Performance Targets
- [ ] Popup opens in under 50ms in normal usage.
- [ ] Search responds in under 100ms for large history.
- [ ] Idle memory usage remains low.
- [ ] Clipboard monitoring uses minimal CPU.
- [x] History list uses lazy loading or virtualization.

### V1 Acceptance Criteria
- [ ] User can copy text, images, colors, URLs, and files and see them in history.
- [ ] User can open history with a global hotkey at the mouse position.
- [ ] User can search and select a previous clipboard item quickly.
- [ ] User can ignore selected apps and regex-matched content.
- [ ] App remains responsive with thousands of clipboard entries.
- [ ] App does not aggressively retain large image data in memory.


## V2: Power Features and Polish

### Advanced Search
- [ ] Add type filters: text, image, URL, color, file.
- [ ] Add date filters.
- [ ] Add source app filters.
- [ ] Add optional regex search mode.
- [ ] Add fuzzy search ranking.
- [ ] Add most-used ranking option.

### Enhanced Preview
- [ ] Add large preview panel.
- [ ] Add Quick Look support for files.
- [ ] Add image full preview.
- [ ] Add copy color as HEX, RGB, HSL.
- [ ] Add copy URL without tracking parameters.
- [ ] Add copy text as plain text.

### Privacy and Security
- [ ] Add built-in sensitive content detection.
- [ ] Optionally ignore passwords, tokens, API keys, credit cards, and verification codes.
- [ ] Add private mode where clipboard entries are not written to disk.
- [ ] Add encrypted history storage option.
- [ ] Add auto-delete sensitive entries after a short delay.
- [ ] Add per-app privacy presets.

### Workflow Improvements
- [ ] Add quick actions per clipboard type.
- [ ] Add configurable number shortcuts for top results.
- [ ] Add custom popup size and position behavior.
- [ ] Add configurable row density.
- [ ] Add light/dark/system appearance setting.
- [ ] Add import/export settings.
- [ ] Add backup and restore for history.

### Smart Organization Without Groups
- [ ] Add favorites view.
- [ ] Add recent view.
- [ ] Add frequent view.
- [ ] Add type-filtered views.
- [ ] Avoid folder/group hierarchy.
- [ ] Keep navigation flat and search-first.

### Sync and Portability
- [ ] Evaluate iCloud sync.
- [ ] Add optional sync for text entries.
- [ ] Avoid syncing large images by default.
- [ ] Add conflict handling for synced history.
- [ ] Add setting to disable sync entirely.

### Reliability
- [ ] Add crash recovery for database writes.
- [ ] Add database migration system.
- [ ] Add storage corruption detection.
- [ ] Add safe fallback if clipboard data cannot be decoded.
- [ ] Add diagnostics export for debugging.

### V2 Acceptance Criteria
- [ ] User can filter and search history more precisely.
- [ ] User can enable privacy protections for sensitive content.
- [ ] User can use favorites and smart views without managing groups.
- [ ] App remains fast with very large history.
- [ ] Optional sync does not compromise performance or privacy.
