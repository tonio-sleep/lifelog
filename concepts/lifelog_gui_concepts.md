# Lifelog - 10 Whole-Application GUI Layout Concepts

Design tokens (all concepts): background `#f5f1e8`, card `#fcf9f2`, text `#1f1c18`, muted `#6a635a`, primary `#25211d`, accent `#a84f3a`, border `#e0d8c9`. Titles in Georgia serif; body in system-ui sans-serif. Spacing base 8px; card radius 12px; no emojis, no decorative gradients except subtle linear gradients on hero cards.

Navigation labels (all concepts): Today, Past, Journal, Trackers, Places, Timeline, Memories, Photos, Music, Insights, Search, Settings. Groups: Daily (Today, Past, Timeline), Capture (Journal, Photos, Music), Track (Trackers, Places, Memories), Find (Search, Insights), System (Settings).

Sample "today" used throughout: Sunday, 15 November 2026. Sample records: journal entries "Morning walk to the river" (08:48), "Coffee and reading" (09:50), "Evening note" (21:10); tracker records Shower (07:32), Coffee 2, Water 1.2 L, Mood 4/5, Reading 45 min; places Home (07:42-08:10), River path (08:35-09:05), Cafe (09:20-10:05); music 47 scrobbles, top artist "The xx"; photos 6 captured.

---

## 1. Three-Pane Archive

Fixed left navigation, a scrollable record list in the middle, and a live inspector on the right. The list and inspector stay in sync with selection, so browsing never loses context.

**Shell layout**
- Left nav: 220px fixed, groups collapsible, active row highlighted with accent left border.
- Middle list: 340px, virtualised, shows date, title, source badge, and 2-line preview.
- Right inspector: flex (min 420px), renders the selected record in full.
- Top bar: 48px, breadcrumb + global search input (320px) + sync status pill.
- Breakpoints: >=1100px three panes; 900-1099px two panes (list + inspector, nav collapses to 64px icon rail); <900px single pane with bottom nav and full-screen detail pushed on selection.

**Regions and content**
- Nav group "Daily" expanded by default; others collapsed.
- Middle list header shows section title, count, and sort/filter chips.
- Inspector shows record fields, attachments, related records, and edit/delete actions in a 16px-spaced column.
- Empty state: centred muted text plus a single primary "Add" button.

**Interactive regions**
- Hover a list row: reveals quick actions (open, pin, delete) and a 200ms thumbnail preview for photos.
- Selection: clicking a row updates inspector without route change; arrow keys move selection; Enter opens full editor.
- Tabs inside inspector: Details, Related, History.

**Why it helps tracking:** keeps the list visible while inspecting, so cross-checking a tracker value against a journal entry takes one click instead of two screens.

```
+------------------------------------------------------------------+
| Lifelog          Search...                Sync OK    [Settings]   |
+----------+----------------+---------------------------------------+
| Daily    | Today (12)     |  Inspector                            |
|  Today   | 08:48 Morning  |  Morning walk to the river            |
|  Past    |      walk...   |  08:48  River path                    |
|  Timeline| 09:50 Coffee   |  Body: Crisp air, fog on the water...  |
| Capture  |      and...    |  Tags: walk, river                    |
|  Journal | 21:10 Evening  |  Related: Place River path, Photo 3    |
|  Photos  |      note      |  [Edit] [Delete]                      |
|  Music   |                |                                       |
| Track    |                |                                       |
|  Trackers|                |                                       |
|  Places  |                |                                       |
|  Memories|                |                                       |
| Find     |                |                                       |
|  Search  |                |                                       |
|  Insights|                |                                       |
| System   |                |                                       |
|  Settings|                |                                       |
+----------+----------------+---------------------------------------+
```

---

## 2. Top Bar Atlas

All navigation lives in a 56px top bar with grouped dropdowns. Content gets the full window width; an optional 380px detail drawer slides in from the right when a record is selected.

**Shell layout**
- Top bar: 56px, logo (left), grouped nav dropdowns (Daily, Capture, Track, Find), search (280px), settings and lock icons (right).
- Content: full width, max content width 1280px centred, 24px gutters.
- Detail drawer: 380px, slides over content with scrim on mobile, pushes content on desktop >=1280px.
- Mobile: top bar collapses to 48px with hamburger; nav becomes a full-screen drawer.

**Regions and content**
- Section pages render as a 12-column responsive grid of cards.
- Today page: hero date card (full width), then 3 columns: timeline preview, tracker summary, places visited; below: music summary and daily recap.
- Dropdown menus list destinations with keyboard shortcuts (Cmd/Ctrl+1..9).

**Interactive regions**
- Hover a nav group: dropdown opens after 120ms; arrow keys navigate.
- Selecting any record opens the detail drawer; Esc closes it and restores focus to the triggering card.
- Drawer tabs: Details, Related, Edit.

**Why it helps tracking:** full-width grids fit more of a day on one screen, so a daily review needs less scrolling.

```
+------------------------------------------------------------------+
| Lifelog  Daily v  Capture v  Track v  Find v     [Search 280px]    |
+------------------------------------------------------------------+
| Sunday, 15 November 2026                                         |
| +-------------------+ +-------------------+ +-------------------+  |
| | Timeline preview  | | Trackers          | | Places visited    |  |
| | 08:48 Morning...  | | Shower yes        | | Home 07:42-08:10  |  |
| | 09:50 Coffee...   | | Coffee 2          | | River 08:35-09:05 |  |
| +-------------------+ +-------------------+ +-------------------+  |
| +-------------------+ +---------------------------------------+  |
| | Music: 47 scrob.  | | Daily recap: 3 entries, 6 photos       |  |
| +-------------------+ +---------------------------------------+  |
+------------------------------------------------------------------+
```

---

## 3. Collapsible Ledger

A sidebar that is either 240px expanded or 64px collapsed, with a toggle in the header. The rest of the window is a two-column content area: a 40% list pane and a 60% detail pane that can be hidden.

**Shell layout**
- Sidebar: 240px expanded / 64px collapsed, transition 180ms, state persisted.
- Content split: 40% / 60% when detail is open; single column at 100% when collapsed via toggle.
- Top of content: 40px section title row with view switcher (List / Grid / Calendar).
- Mobile: sidebar becomes a bottom sheet; content is single column with a sticky bottom "View details" bar.

**Regions and content**
- Collapsed sidebar shows icons only with tooltips; group headers become small caps labels.
- List pane: compact rows with 8px vertical padding, source icon, title, timestamp.
- Detail pane: sticky header with title and actions; scrollable body.

**Interactive regions**
- Hover sidebar icon in collapsed state: tooltip with label and shortcut.
- Drag the split divider (desktop) between 30% and 70% to resize; double-click resets to 40/60.
- Pin a record: keeps detail pane open while navigating sections.

**Why it helps tracking:** the resizable split lets a long journal entry and its related tracker records share one screen without either being cramped.

```
+----+--------------------------------+------------------------------+
| L  | Today                          | Detail                       |
| 240| 08:48 Morning walk to the river| Morning walk to the river    |
|    | 09:50 Coffee and reading       | 08:48  River path            |
| D  | 21:10 Evening note             | Body text...                 |
| C  | --- Trackers ---               | Related: Place, Photo 3      |
| T  | Shower 07:32  yes              |                              |
| F  | Coffee 2                       |                              |
| S  | Water 1.2 L                    |                              |
+----+--------------------------------+------------------------------+
```

---

## 4. Mobile Drawer + Bottom Nav

Mobile-first shell: a 56px app bar, a 4-item bottom navigation bar for the most-used destinations, and a drawer holding all twelve. On desktop it scales to a 220px sidebar with the same drawer contents.

**Shell layout**
- Mobile: app bar 56px (title + search icon + settings icon); bottom nav 64px with 4 tabs (Today, Timeline, Journal, Search) plus a central 56px quick-add FAB.
- Drawer: 280px, grouped destinations, account/lock footer.
- Desktop (>=900px): sidebar 220px replaces drawer; bottom nav hidden; FAB becomes a 40px button in the top bar.
- Tablet (600-899px): navigation rail 72px with labels on selection; drawer available via hamburger.

**Regions and content**
- Today page is a single scrollable column: date header, then stacked cards (timeline preview, trackers, places, music).
- Detail screens push full screen with a back arrow; swipe from left edge goes back.
- Quick-add FAB opens a bottom sheet with the 11 capture types in a 2-column grid.

**Interactive regions**
- Long-press bottom nav tab: shows a 4-item recent-records popover.
- Swipe a list row left to reveal edit/delete; swipe right to pin.
- Pull to refresh on Today re-runs the daily summary.

**Why it helps tracking:** the FAB and 4-tab bar put capture and the daily view one tap away on a phone, which is where most logging happens.

```
Mobile:
+----------------------------------+
| Lifelog            [search][set] |
+----------------------------------+
| Sunday, 15 November 2026         |
| +------------------------------+ |
| | Timeline preview             | |
| | 08:48 Morning walk...       | |
| +------------------------------+ |
| | Trackers                    | |
| | Shower yes  Coffee 2        | |
| +------------------------------+ |
+----------------------------------+
| [Today][Timeline][Journal][Search]  (+) |
+----------------------------------+
```

---

## 5. Dashboard Grid

An icon rail on the left and a bento-style 12-column grid on the right. Each destination is a live card on Today, and any card can be expanded into its full view in place.

**Shell layout**
- Icon rail: 72px, icons with labels below, grouped by small caps headers.
- Main: 12-column grid, 24px gutters, cards span 3, 4, 6, or 12 columns.
- Today layout: hero card (12 col) "Sunday, 15 November 2026"; timeline (6), trackers (3), places (3); music (4), photos (4), recap (4).
- Detail view replaces the grid with a single 10-column content column plus a 2-column mini-map/related rail.

**Regions and content**
- Cards show live counts and the top 3 items; "Open" link in card footer.
- Hovering a card lifts it 2px and shows a subtle border in accent.
- Insights cards render a 7-day sparkline.

**Interactive regions**
- Click card title: expands card to full section in place with a 200ms morph.
- Drag cards (desktop) to reorder the dashboard; layout persisted per device.
- Right-click a card: pin to top, hide, or change size.

**Why it helps tracking:** the at-a-glance counts (shower yes, coffee 2, 6 photos) make gaps in a day visible without opening any section.

```
+--+--------------------------------------------------------------+
|  | Sunday, 15 November 2026                                      |
|D | +-------------------------------+ +-----------+ +-----------+ |
|a | | Timeline preview              | | Trackers  | | Places    | |
|i | | 08:48 Morning walk...         | | Shower yes| | Home      | |
|l | | 09:50 Coffee and reading      | | Coffee 2  | | River     | |
|y | +-------------------------------+ +-----------+ +-----------+ |
|  | +-----------+ +-----------+ +--------------------------------+ |
|C | | Music 47  | | Photos 6  | | Daily recap: 3 entries...      | |
|a | +-----------+ +-----------+ +--------------------------------+ |
+--+--------------------------------------------------------------+
```

---

## 6. Tabbed Workspace

A browser-style tab strip across the top holds open records and sections. The left sidebar is collapsed by default to 64px and expands on hover, maximising horizontal space for tabs and content.

**Shell layout**
- Tab strip: 40px, scrollable, closable tabs with section icon + title + dirty dot; "+" opens a new tab with a destination picker.
- Sidebar: 64px collapsed, expands to 220px on hover or pin; transition 150ms.
- Content: tab body fills remaining space; each tab keeps its own scroll position and form state.
- Mobile: tabs become a horizontal scrollable chip row under the app bar; sidebar is a drawer.

**Regions and content**
- Tab types: section tabs (Today, Timeline...) and record tabs (a specific journal entry or place).
- A tab can be pinned; pinned tabs show only an icon.
- Overflow menu lists all open tabs with search.

**Interactive regions**
- Middle-click or Ctrl+click a nav item: opens in a new tab.
- Drag tabs to reorder; drop on another tab to split into two columns (desktop).
- Hover sidebar: expands; moving away collapses unless pinned.

**Why it helps tracking:** keeping a journal entry open beside its related place or tracker record removes navigation round-trips during review.

```
+------------------------------------------------------------------+
| [Today x] [Journal: Morning walk x] [Place: River path x]  [+]   |
+--+---------------------------------------------------------------+
|  | Morning walk to the river                                     |
|64| 08:48  River path                                            |
|  | Body: Crisp air, fog on the water...                          |
|  | Related places: River path   Related photos: 3                |
|  | [Edit] [Duplicate] [Delete]                                    |
+--+---------------------------------------------------------------+
```

---

## 7. Split Timeline + Inspector

The screen is split vertically: a chronological timeline on the left (45%) and a contextual inspector on the right (55%). A filter bar sits above both. Built for the Timeline destination but reusable for any day.

**Shell layout**
- Filter bar: 48px, date picker, source toggles (Journal, Tracker, Place, Music, Photo, Manual), search input.
- Left pane: 45%, virtualised timeline grouped by hour with sticky hour headers.
- Right pane: 55%, inspector showing the selected event's source record and neighbours.
- Bottom (mobile): timeline full screen; inspector is a bottom sheet at 40% height, draggable to 90%.
- Desktop split divider draggable between 35% and 60%.

**Regions and content**
- Timeline rows: time, icon, title, source label, confidence badge for inferred events.
- Inspector: "What happened around this time" list (events within +/-30 min) plus the full source record.
- Hover a timeline row: highlights corresponding item in inspector's neighbour list.

**Interactive regions**
- Selection: clicking an event updates inspector and scrolls neighbour list; j/k move selection.
- Toggle a source filter: timeline re-flows with a 120ms fade; counts update in filter bar.
- Double-click an event: opens its editor in a modal.

**Why it helps tracking:** seeing an event next to everything else that happened within 30 minutes makes reconstructing a day far faster than opening each record alone.

```
+------------------------------------------------------------------+
| Date: 15 Nov 2026   [Journal][Tracker][Place][Music][Photo]  Q    |
+---------------------------+--------------------------------------+
| 08:35  Arrived River path | Selected: 08:48 Morning walk          |
| 08:48  Morning walk (J)   | Journal entry                         |
| 09:20  Arrived Cafe       | Body: Crisp air...                    |
| 09:50  Coffee and reading | Related: River path, Photo 3          |
| 10:05  Left Cafe          | Nearby: 08:35 arrived, 09:20 left     |
+---------------------------+--------------------------------------+
```

---

## 8. Focus Mode

Minimal chrome: the selected record or day fills the window. Navigation is a floating command bar summoned with Cmd/Ctrl+K or a swipe from the left edge. Designed for writing and reviewing without distraction.

**Shell layout**
- Content: 100% of window, max text width 720px centred for reading/writing; media grids use up to 1120px.
- Floating command bar: 48px pill, bottom-centre, contains search, quick-add, section switcher, and lock.
- Hidden nav: slides in as a 260px overlay from the left on gesture/shortcut; scrim dismisses.
- Status: a 24px top strip shows date, sync status, and tracking status; auto-hides after 3s of inactivity.

**Regions and content**
- Today in focus mode: a single vertical narrative of the day, entries and events interleaved, with inline tracker chips.
- Journal editor: full-screen, autosave indicator top-right, word count bottom-left.
- All destructive actions require the command bar's "..." menu.

**Interactive regions**
- Cmd/Ctrl+K: opens command palette with fuzzy search across sections and records.
- Swipe from left edge (mobile) or press Esc: closes overlays and returns to content.
- Hover bottom 8px: reveals the floating command bar if hidden.

**Why it helps tracking:** removing sidebars and counts reduces friction when capturing a quick entry, which is the moment tracking usually fails.

```
+------------------------------------------------------------------+
| (status strip auto-hides)                                         |
|                                                                   |
|        Sunday, 15 November 2026                                   |
|                                                                   |
|        08:48  Morning walk to the river                            |
|        Crisp air, fog on the water.                                |
|        [Photo 1] [Photo 2] [Photo 3]                              |
|                                                                   |
|        09:50  Coffee and reading                                   |
|        ...                                                        |
|                                                                   |
|                   ( ) search  (+) add  (sec) sections  (lock)      |
+------------------------------------------------------------------+
```

---

## 9. Icon Rail + Panels

A 56px icon rail on the far left. Sections open as slide-over panels (320px) from the right or left, layering over a persistent main view. The main view defaults to Today and never fully disappears.

**Shell layout**
- Icon rail: 56px, icons only, tooltips on hover, grouped by 4px dividers.
- Main view: fills remaining space, defaults to Today summary.
- Panel: 320px slide-over from the right for section lists; a second panel can stack (640px total) for detail.
- Mobile: icon rail becomes a bottom bar of 5 icons (Today, Timeline, Journal, Search, More); panels become full-screen pushes.

**Regions and content**
- Selecting a nav icon opens or focuses its panel; selecting again closes it.
- Panels are independently scrollable and keep state when closed.
- Main view dims slightly (opacity 0.88) when a panel is open on desktop <1280px.

**Interactive regions**
- Hover icon: tooltip with label and unread/changed dot.
- Drag panel edge to resize between 280px and 480px.
- Clicking outside a panel closes the topmost panel; Esc closes all.

**Why it helps tracking:** the persistent Today view underneath means a quick capture never loses the day's context.

```
+--+------------------------------------------+------------------+
|  | Today (persistent)                       | Journal panel    |
|56| Sunday, 15 November 2026                  | Morning walk...  |
|  | 3 entries, 4 tracker records              | Coffee and...    |
|  | 2 places, 47 scrobbles                    | Evening note     |
|  |                                          | [+ New entry]    |
+--+------------------------------------------+------------------+
```

---

## 10. Floating Dock Workspace

No fixed sidebars. Content fills the window. A floating dock at the bottom holds grouped destination icons; section content opens in floating, draggable, resizable windows over the base Today view.

**Shell layout**
- Base view: Today summary fills the window.
- Dock: 64px tall pill, bottom-centre, 12 icons in 4 groups separated by 8px gaps; auto-hides after 4s of inactivity, reappears on mouse move.
- Windows: 480x640 default, draggable, resizable (min 320x400), snap to grid; multiple can be open and tiled.
- Mobile: dock becomes a 56px bottom bar with 5 icons and a "More" sheet; windows become full-screen sheets.

**Regions and content**
- Each window has a title bar with section name, pin, minimise, close.
- Today base view remains visible behind windows at 80% opacity when a window is focused.
- A window manager menu (dock long-press) lists open windows and layouts.

**Interactive regions**
- Drag dock icons onto the canvas to open a window at that position.
- Double-click a window title bar to maximise; drag to a screen edge to snap (desktop).
- Right-click dock: save current window layout as a named workspace.

**Why it helps tracking:** arranging a map, a timeline, and a journal entry side by side supports cross-referencing a single day without tab switching.

```
+------------------------------------------------------------------+
|                                                                   |
|   Today base view: Sunday, 15 November 2026                       |
|                                                                   |
|        +-------------------+   +-------------------+              |
|        | Timeline window   |   | Journal window    |              |
|        | 08:48 Morning...  |   | Morning walk...   |              |
|        | 09:50 Coffee...   |   | ...               |              |
|        +-------------------+   +-------------------+              |
|                                                                   |
|              [D]  [C]  [T]  [F]  [S]  (floating dock)             |
+------------------------------------------------------------------+
```

---

## Comparison table

| Concept | Space efficiency | Browsing speed | Mobile suitability | Learning curve | Best for |
|---|---|---|---|---|---|
| 1. Three-Pane Archive | High (desktop) | High | Low | Low | Desktop-heavy reviewers |
| 2. Top Bar Atlas | High | Medium | Medium | Low | Dashboard-style daily review |
| 3. Collapsible Ledger | High | High | Medium | Medium | Resizable reading + detail |
| 4. Mobile Drawer + Bottom Nav | Medium | High (mobile) | High | Low | Phone-first capture |
| 5. Dashboard Grid | Medium | Medium | Medium | Low | At-a-glance day status |
| 6. Tabbed Workspace | High | High | Low | Medium | Multi-record comparison |
| 7. Split Timeline + Inspector | Medium | High | Medium | Low | Timeline reconstruction |
| 8. Focus Mode | Very high | Medium | High | Low | Distraction-free capture |
| 9. Icon Rail + Panels | High | Medium | Medium | Medium | Keeping Today visible |
| 10. Floating Dock Workspace | Medium | High | Low | High | Power users, multi-window |

Notes: "Space efficiency" measures how much content is visible without scrolling on a 1440x900 window. "Browsing speed" measures clicks to move between records. Mobile suitability reflects how naturally the shell adapts below 900px. Learning curve reflects how much discovery is needed before productive use.