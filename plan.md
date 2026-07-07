# Fifi macOS Clipboard Manager: Agent Development Plan

## Project Identity

- Product name: Fifi
- macOS bundle identifier: `com.leafiy.fifi`
- Platform: macOS
- Implementation language: Swift
- UI stack: SwiftUI preferred, AppKit allowed where required for menu-bar, global hotkeys, popup positioning, paste behavior, and clipboard integration
- Distribution target: native macOS app
- Product goal: a very fast, low-resource clipboard history manager with a flat, searchable history list

## Product Positioning

Fifi is a native macOS clipboard manager inspired by Maccy and Clipy, but it must avoid two major issues:

- It must not become resource-heavy when clipboard history grows large.
- It must not rely on folders or complex grouping for everyday selection.

The core interaction model is:

1. The app records clipboard history in the background.
2. The user presses a customizable global shortcut.
3. A quick picker opens at the current mouse position.
4. The user searches or navigates the flat list.
5. The selected item is copied or pasted immediately.

## Non-Negotiable Requirements

- The app must be native Swift on macOS.
- The app must use bundle identifier `com.leafiy.fifi`.
- The app must be optimized for low idle memory and low CPU usage.
- The app must not load the entire clipboard history into memory on startup.
- The app must use a flat history list by default.
- The app must not implement Clipy-style folder/group navigation in V1.
- File clipboard entries must be stored as references or links, not copied file payloads.
- The quick picker must support search.
- The quick picker must open near the current mouse position.
- Users must be able to configure ignored apps and ignored text regex rules.

## Architecture Direction

### Suggested App Modules

- `ClipboardMonitor`
  - Poll or observe `NSPasteboard.general.changeCount`.
  - Detect new clipboard items.
  - Normalize clipboard contents into internal history models.
  - Avoid recording app-generated restores or duplicate writes.

- `ClipboardClassifier`
  - Classify clipboard entries as text, rich text, URL, image, color, file, or unknown.
  - Detect HEX colors from text values.
  - Extract metadata such as source app, capture time, size, dimensions, UTI/type identifiers, and file path.

- `HistoryStore`
  - Persist metadata in SQLite.
  - Support pagination and lazy loading.
  - Support deduplication.
  - Support cleanup by count, age, and storage size.
  - Keep pinned/favorite entries from automatic cleanup.

- `BlobStore`
  - Store large image payloads outside SQLite.
  - Store thumbnails separately.
  - Store file clipboard entries as references only.

- `SearchIndex`
  - Provide fast text search over history.
  - Prefer SQLite FTS for text, URL, filename, path, and source app search.
  - Support incremental search in the picker.

- `IgnoreRules`
  - Store ignored app bundle identifiers.
  - Store ignored regex rules.
  - Evaluate rules before writing clipboard history.

- `HotKeyManager`
  - Register a configurable global hotkey.
  - Trigger the quick picker.

- `QuickPicker`
  - Open at the current mouse position.
  - Render a virtualized or lazy list of history items.
  - Support keyboard navigation and search.
  - Support item selection, deletion, pinning, and copy/paste actions.

- `Settings`
  - Manage hotkey, retention, storage, privacy, ignore rules, launch at login, and UI behavior.

## Storage Strategy

Use SQLite for structured metadata and search indexes.

Suggested tables:

- `clipboard_items`
  - `id`
  - `content_hash`
  - `type`
  - `preview_text`
  - `source_app_name`
  - `source_app_bundle_id`
  - `created_at`
  - `updated_at`
  - `last_used_at`
  - `use_count`
  - `is_pinned`
  - `is_favorite`
  - `blob_path`
  - `thumbnail_path`
  - `file_reference`
  - `metadata_json`

- `clipboard_items_fts`
  - full-text index for searchable fields

- `ignore_apps`
  - ignored app names and bundle identifiers

- `ignore_regex_rules`
  - enabled regex rules and labels

- `settings`
  - user preferences

Large payload rules:

- Text can be stored directly in SQLite when reasonably sized.
- Very large text may be stored in a blob file with indexed preview text.
- Images should be stored outside SQLite.
- Thumbnails should be generated and cached lazily.
- File entries should store path/bookmark/reference metadata only.

## V1 Scope

### V1 Product Goal

Deliver a fast and usable clipboard manager with history capture, search, mouse-position quick picker, configurable storage, and ignore rules.

### V1 Clipboard Capture

- [x] Monitor clipboard changes.
- [x] Save plain text entries.
- [x] Save rich text metadata when available.
- [x] Save URL entries.
- [x] Save image entries.
- [x] Detect HEX color values in text entries.
- [x] Save file entries as references only.
- [x] Add visible type indicators for unknown clipboard data.
- [x] Deduplicate repeated entries by content hash.
- [x] Move duplicate entries to the top instead of creating duplicate rows.
- [x] Record source app name and bundle identifier when possible.
- [x] Record created and updated timestamps.

### V1 Preview

- [x] Show text preview with truncation.
- [x] Show URL preview with domain and full URL.
- [x] Show image thumbnail.
- [x] Show image dimensions when available.
- [x] Show color swatch for HEX color values.
- [x] Show file icon, filename, and path for file entries.
- [x] Show fallback icon and type label for unknown entries.
- [x] Show source app and capture time.

### V1 Quick Picker

- [x] Add customizable global hotkey.
- [x] Open picker near current mouse location.
- [x] Show recent history in a flat list.
- [x] Support keyboard up/down navigation.
- [x] Support Enter to select item.
- [x] Support Esc to close picker.
- [x] Support mouse selection.
- [x] Support delete action for selected item.
- [x] Support pin/favorite action for selected item.
- [x] Add setting for selection behavior:
  - paste immediately
  - copy only

### V1 Search

- [x] Add search field inside picker.
- [x] Search text content.
- [x] Search URLs.
- [x] Search file names and file paths.
- [x] Search source app names.
- [x] Search case-insensitively.
- [ ] Keep search responsive for thousands of entries.

### V1 Storage and Cleanup

- [x] Store metadata in SQLite.
- [x] Store image blobs outside SQLite.
- [x] Store thumbnails outside SQLite.
- [x] Add configurable maximum history count.
- [x] Add configurable retention days.
- [x] Add configurable maximum storage size.
- [x] Run cleanup in the background.
- [x] Never block picker opening on cleanup.
- [x] Do not load full history into memory at startup.

### V1 Ignore Rules

- [x] Add ignored app list.
- [x] Support ignored app bundle identifiers.
- [x] Add ignored text regex rules.
- [x] Do not persist entries matching ignored app rules.
- [x] Do not persist entries matching ignored regex rules.
- [x] Add temporary pause recording action.
- [x] Add pause/resume from menu bar.

### V1 Menu Bar and Settings

- [x] Add menu-bar app icon.
- [x] Add menu item to open picker.
- [x] Add menu item to pause/resume recording.
- [x] Add menu item to clear history.
- [x] Add menu item to open settings.
- [x] Add menu item to quit app.
- [x] Add launch at login setting.
- [x] Add hotkey setting.
- [x] Add history retention settings.
- [x] Add ignore app and regex settings.

### V1 Performance Targets

- [ ] Picker opens in under 50ms in normal usage.
- [ ] Search responds in under 100ms for thousands of entries.
- [ ] Idle CPU usage stays near zero.
- [ ] Idle memory remains low.
- [ ] App does not retain full image payloads in memory.
- [ ] Large history does not noticeably slow app launch.

### V1 Acceptance Criteria

- [ ] Copying text, image, color text, URL, and file entries creates history records.
- [ ] Pressing the global hotkey opens the picker at the mouse position.
- [ ] The user can search history and select an item quickly.
- [ ] The selected item can be copied back to the clipboard.
- [ ] The selected item can optionally be pasted into the active app.
- [ ] Ignored apps are not recorded.
- [ ] Regex-matched text is not recorded.
- [ ] Thousands of history records remain searchable without UI stutter.
- [ ] Images do not cause high persistent memory usage.

## V2 Scope

### V2 Product Goal

Add power-user features, privacy controls, advanced search, better previews, and optional sync while preserving V1 performance.

### V2 Advanced Search

- [x] Add type filters: text, image, URL, color, file, unknown.
- [x] Add date filters.
- [x] Add source app filters.
- [x] Add optional regex search mode.
- [x] Add fuzzy search ranking.
- [x] Add most-used ranking.
- [x] Add recent/frequent/favorites view modes.

### V2 Enhanced Preview

- [x] Add larger preview panel.
- [x] Add Quick Look support for files.
- [x] Add image full preview.
- [x] Add copy color as HEX.
- [x] Add copy color as RGB.
- [x] Add copy color as HSL.
- [x] Add copy URL without tracking parameters.
- [x] Add copy text as plain text.
- [x] Add reveal file in Finder action.
- [x] Add open URL action.

### V2 Privacy and Security

- [x] Add built-in sensitive content detection.
- [x] Optionally ignore passwords.
- [x] Optionally ignore API keys and tokens.
- [x] Optionally ignore credit card numbers.
- [x] Optionally ignore verification codes.
- [x] Add private mode where entries are not written to disk.
- [x] Add optional encrypted history storage.
- [x] Add auto-delete for sensitive entries.
- [x] Add per-app privacy presets.

### V2 Workflow Improvements

- [x] Add quick actions per clipboard type.
- [x] Add configurable numeric shortcuts for top results.
- [x] Add custom picker width and height.
- [x] Add configurable row density.
- [x] Add light, dark, and system appearance setting.
- [x] Add import/export settings.
- [x] Add history backup and restore.

### V2 Smart Organization Without Groups

- [x] Add favorites view.
- [x] Add recent view.
- [x] Add frequent view.
- [x] Add type-filtered views.
- [x] Avoid folder hierarchy.
- [x] Avoid group tree navigation.
- [x] Keep navigation flat, search-first, and fast.

### V2 Sync

> Deferred by request. Everything in V2 except this Sync section is implemented. CloudKit/CKSyncEngine is viable for a Developer ID app but requires a paid Apple Developer account, an iCloud container + entitlements, and an embedded provisioning profile (build/release-pipeline work), so sync is intentionally postponed.

- [ ] Evaluate iCloud sync.
- [ ] Add optional sync for text entries.
- [ ] Avoid syncing large images by default.
- [ ] Add sync conflict handling.
- [ ] Add setting to disable sync completely.
- [ ] Make sync opt-in only.

### V2 Reliability

- [x] Add database migration system.
- [x] Add database corruption detection.
- [x] Add crash-safe database writes.
- [x] Add fallback for undecodable clipboard data.
- [x] Add diagnostics export for debugging.
- [x] Add automated tests for storage, search, ignore rules, and deduplication.

### V2 Acceptance Criteria

- [x] User can filter and search history more precisely than V1.
- [x] User can enable privacy protections for sensitive content.
- [x] User can use favorites and smart views without managing groups.
- [ ] Optional sync does not compromise performance or privacy.
- [x] Very large history remains fast and memory-efficient.

## Implementation Notes for Agent

- Prefer simple, measurable performance improvements over broad abstractions.
- Keep V1 small and complete before starting V2 features.
- Do not introduce folder/group UX unless explicitly requested later.
- Use pagination for history queries.
- Use lazy thumbnail loading.
- Avoid keeping `NSImage` or raw image data in long-lived memory.
- Treat paste automation carefully because macOS accessibility permissions may be required.
- Keep settings explicit and reversible.
- Prefer tested storage/search logic over UI-only progress.

## Suggested Milestones

### Milestone 1: App Skeleton

- [x] Create native macOS Swift project.
- [x] Set bundle identifier to `com.leafiy.fifi`.
- [x] Add menu-bar app lifecycle.
- [x] Add settings window shell.
- [x] Add global hotkey registration.
- [x] Add empty picker window at mouse position.

### Milestone 2: Clipboard History Core

- [x] Implement clipboard monitor.
- [x] Implement content classifier.
- [x] Implement SQLite history store.
- [x] Implement deduplication.
- [x] Implement basic text, URL, image, color, and file recording.

### Milestone 3: Picker and Search

- [x] Render recent history list.
- [x] Add previews by type.
- [x] Add keyboard navigation.
- [x] Add item selection behavior.
- [x] Add search backed by SQLite/FTS.

### Milestone 4: Settings and Ignore Rules

- [x] Add hotkey settings.
- [x] Add retention settings.
- [x] Add ignored app settings.
- [x] Add ignored regex settings.
- [x] Add pause/resume recording.

### Milestone 5: Performance and QA

- [ ] Test with thousands of text entries.
- [ ] Test with many images.
- [ ] Measure launch time.
- [ ] Measure picker open latency.
- [ ] Measure idle CPU and memory.
- [ ] Fix slow queries and memory retention.
- [ ] Validate cleanup behavior.

## Out of Scope for V1

- Cloud sync
- OCR
- AI summarization
- Complex grouping
- Plugin system
- Cross-device clipboard
- Team/shared clipboard history
- Browser extension
