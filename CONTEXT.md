# Fifi

A macOS clipboard-history manager. The user summons a picker window, searches captured clipboard items, and sends one back to the pasteboard or pastes it directly.

## Language

**Detail Toggle**:
A per-detail visibility switch (source, size, time, image resolution), all on by default. A toggle hides its detail everywhere the Picker shows it — history rows and the preview panel alike.
_Avoid_: Metadata switch

**Row Details**:
The secondary line of per-item facts shown under a row's preview: source, size, time, image resolution. Visibility is governed per-detail by Detail Toggles.
_Avoid_: Metadata line, subtitle

**State Indicator**:
A per-item status icon on the details line — pinned (favorite) or memory-only (private mode). Item state, not a Row Detail: never hidden by Detail Toggles. The line collapses only when it has no details and no indicators.
_Avoid_: Detail icon

**Source**:
The app a clipboard item was captured from. Its visibility toggle is the pre-existing "Show app source" setting, now grouped with the other Row Details toggles.
_Avoid_: Origin, source app toggle (as a separate concept)

**Size**:
The magnitude of an item's content (大小), uniform across types: character count for text, byte size for images and files. One detail, one toggle — never split by item type.
_Avoid_: Character count (字数), image size (图像大小), file size — as separate toggleable concepts
