# Byepasser

**Notes that say bye.**

A beautiful, minimalist, production-ready Flutter iOS app where every note is strictly ephemeral. Notes auto-delete after their chosen lifetime. 100% on-device using Hive — no accounts, no cloud, no Firebase.

## Features

- **Ephemeral by design** — every note has a lifetime from 5 minutes to 30 days.
- **A Puff** — instant short-lived notes (5-30 min) with special frosted + animated puff visuals and "Burn Now". A friendlier way to quickly release a thought.
- **Live countdowns** — per-second updates when under 1 hour.
- **Dying Soon** section + full board grid (responsive 1-2 columns).
- **Full editor** with basic Markdown preview, optional title, 8 color tags.
- **Extend once** (exactly once per note), Copy, Share (iOS sheet).
- **5 gorgeous themes** + Follow System + 8 accent colors + 3 card styles (Glassmorphic / Minimal / Elevated) with real iOS blur via BackdropFilter.
- **Rich settings** — default lifetimes, notifications (24h/1h), auto-copy 5 min before death, haptics, animation speed, export JSON, "Nuke all notes" emergency button.
- **Local notifications** via flutter_local_notifications.
- **Auto cleanup** of expired notes on every launch + periodic sweep.
- **Joyful, calm, addictive** Apple Notes + Bear + Linear inspired design using CupertinoPageScaffold + large titles.

## Tech

- Flutter 3.24+ (Dart 3.11+)
- iOS 15.0+
- hive + hive_flutter (manual TypeAdapters — no build_runner required)
- hooks_riverpod + flutter_hooks
- flutter_markdown, share_plus, flutter_local_notifications, path_provider, intl, uuid
- Pure local storage

## Project Structure

```
lib/
├── main.dart
├── models/          # Note, AppSettings (+ manual Hive adapters)
├── providers/       # Riverpod state (notes, settings, derived lists)
├── services/        # HiveStore, NotificationService, HapticsService, ExportService
├── screens/         # AppShell, HomeScreen, NoteEditorScreen, SteamReleaseScreen (the Puff mode), SettingsScreen
├── theme/           # ByepasserTheme + ByepasserColors ThemeExtension (5 themes + accents + card styles)
├── utils/           # lifetime helpers
├── widgets/         # NoteCard, LifetimeSlider, SteamParticles (visuals for puffs), Countdown, etc.
```

## Run

```bash
flutter pub get
flutter run
```

For iOS only (already configured):

```bash
flutter build ios --no-codesign
```

## App Icon

See `docs/app_icon_prompt.md` for the exact prompt used to generate the icon (simple white speech bubble with a small clock on a calm background).

## Tagline

> Notes that say bye.
```

## License

Private / personal project.
