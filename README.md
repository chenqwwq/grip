# Grip

Grip is a macOS task capture app built with SwiftUI, SwiftData, EventKit, and
OpenAI-compatible LLM APIs. It helps turn screenshots, clipboard content, and
manual input into local tasks, then syncs them with Apple Reminders.

## Features

- Create tasks from a selected screen region.
- Create tasks from clipboard text.
- Create and edit tasks manually.
- Parse LLM JSON responses, including JSON inside Markdown code fences.
- Parse due dates in day and minute precision formats.
- Sync tasks to Apple Reminders.
- Optionally sync completion state back from Reminders.
- Switch between system, blue-white, and dark appearances.
- Store API keys in Keychain.

## Requirements

- macOS with Xcode installed.
- Xcode command line tools.
- Apple Reminders access for sync.
- Screen Recording permission for screenshot capture.
- An OpenAI-compatible API endpoint and model.

## Build

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -scheme Grip -destination 'platform=macOS'
```

## Test

```bash
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme Grip -destination 'platform=macOS'
```

The test suite covers task create/edit/delete flows, LLM JSON parsing, date
parsing, Reminders sync behavior, log path handling, and appearance mode
configuration.

## Configuration

Open `Grip Settings` in the app to configure:

- Text and image model API URL, model name, and API key.
- Reminders sync mode.
- Bidirectional completion sync.
- App appearance.
- File logging.

API keys must be stored in Keychain. Do not commit API keys to source code,
logs, UserDefaults, or test fixtures.

## Permissions

Grip may request:

- Screen Recording permission, used to capture selected screen regions.
- Reminders permission, used to create and update Apple Reminders.
- User-selected file read/write permission, used for custom log locations.

## Repository Notes

- The main app source lives in `Grip/`.
- Business tests live in `GripTests/`.
- The shared Xcode scheme lives under `Grip.xcodeproj/xcshareddata/`.
- Local Xcode state and macOS metadata are ignored by `.gitignore`.

