# ![QuizSight icon](QuizSightMenuBarColor.png) QuizSight

**QuizSight** is a small experimental macOS menu-bar application that lets you select a portion of your screen and request an AI explanation or suggested answer for study and practice questions. It does **not** click, select, or submit anything in the browser.

> **Version 3.6 · Source release.** Test the application on a Mac before distributing a binary release. AI suggestions may be wrong. Only use in assessments where assistance is permitted.

## Features

- **Capture a question:** Click the menu-bar icon, then drag to select the question and its answer options.
- **Get an AI suggestion:** The selected region is sent to the OpenAI API for an answer and a brief explanation.
- **Review results quickly:** Hover over the icon to see a summary, then click the preview for the full answer, explanation and model-reported confidence.
- **Handle different question formats:** Supports multiple questions, labelled or unlabelled options, and questions without answer choices.
- **Keep track of progress:** Menu-bar indicators show when a capture is being analysed and when a result is ready.
- **Stay in control:** Start a new capture or open the details from the menu; QuizSight does not interact with your browser.

## Requirements

- macOS with the Apple Swift compiler (Xcode or Apple Command Line Tools).
- OpenAI API key and an API account with available usage/billing. This is **separate** from ChatGPT subscriptions.
- Screen Recording permission in **System Settings → Privacy & Security**.
- Internet access to call the OpenAI Responses API.

## Install from source

1. Install Apple's Command Line Tools if you do not already have Xcode or the tools installed:

   ```bash
   xcode-select --install
   ```

2. Clone the repository and enter its directory:

   ```bash
   git clone https://github.com/joaolpgomes87/quiz-sight.git
   cd quiz-sight
   ```

3. Build and launch the application:

   ```bash
   bash start.command
   ```

   The first time you start a capture, enter your OpenAI API key when prompted; it will not be displayed as you type.
4. Grant screen-recording permission when prompted in **System Settings → Privacy & Security**, then reopen the app if needed.
5. For later launches, open `QuizSight.app` directly or run `open QuizSight.app` from the project directory. You do not need to rebuild each time.

QuizSight stores your API key in macOS Keychain and sends it to OpenAI over HTTPS to authenticate API requests. If a key from an earlier version exists in `~/.quizlens_api_key`, QuizSight moves it to Keychain on the first capture and removes the old file after saving it successfully. If removal fails, delete the old file manually. The `OPENAI_API_KEY` environment variable takes priority when available to the app. **Never commit or share your key.**

### Updating a local build

Run `bash start.command --rebuild` while QuizSight is closed. Rebuilding an ad-hoc signed macOS application may cause macOS to ask for screen capture permission again. For general distribution, use a stable Developer ID signature and notarization rather than distributing the ad-hoc build.

## Privacy / security

- Only the screen **region you choose** is captured on demand; capture is not continuous.
- Captures are temporarily written to a private folder and removed after use. On launch and before a capture, QuizSight also removes its leftover temporary captures older than 24 hours.
- The selected image is sent over HTTPS to the OpenAI API for analysis; it therefore leaves your Mac. **Avoid selecting passwords, personal records, private messages, or protected information.**
- The request uses `store: false` and doesn't programmatically interact with Moodle or any other website.
- API calls incur usage-based costs. Outputs are suggestions, not guaranteed correct answers.
- API keys are stored in macOS Keychain unless supplied through the `OPENAI_API_KEY` environment variable.

### Improving answer quality

Capture the complete question and all answer options, and make sure the text is large and clear. QuizSight sends the screenshot as a lossless PNG at high image detail. Review the explanation and verify important answers independently; the model's confidence is not a guarantee of correctness.

QuizSight defaults to `gpt-5.4-mini`. To try a different image-capable model available to your OpenAI API account, put its model ID in `~/.quizlens_model` and relaunch the app. Model availability, speed and API costs vary; compare results on the same practice questions before choosing one.

## Development and tests

- `main.swift` — AppKit menu-bar UI, screen region capture, API request.
- `QuizModels.swift` — model and JSON parsing.
- `tests/QuizModelsTests.swift` — five lightweight cross-platform parsing tests.
- `QuizSightMenuBarColor.png` — colourful, alpha-transparent menu-bar logo.
- `QuizSight-Icon.png` and `QuizSight.icns` — Finder / application icons.

Run parser tests (from a Mac or a system with the Swift compiler):

```bash
swiftc QuizModels.swift tests/QuizModelsTests.swift -o /tmp/quizsight-model-tests
/tmp/quizsight-model-tests
```

## License

Code and artwork included here are offered under the [MIT License](LICENSE). Review the license choice before publishing if you prefer different redistribution terms.
