# Post-submission application check

Date: 1 November 2026. The submitted version is [f1eae14](https://github.com/sgaabdu4/hobbit/tree/f1eae143d51db27d430450af559fae99f6ae0160). This audit and its fixes are separate from that submission.

Tests used a physical iPhone 13 with iOS 27.0.1, Xcode 27.2 and Node 26.12.0. The phone used the paired development server on the same Wi-Fi network. Device Hub screen sharing stayed off during microphone tests.

## Results

| Check | Result | Evidence and scope |
| --- | --- | --- |
| Saved ChatGPT sign-in | Passed | The app restored the account and reported a verified identity and ChatGPT plan permission. Fresh browser consent was not repeated. |
| Multiple habits | Passed | A second habit had separate progress, survived a restart, and was removed through both confirmation steps. The first habit remained. |
| Completion and undo | Passed | Button completion showed the reward, survived a restart and could be undone. |
| Spoken completion | Passed | Real microphone input reached Live. Completion was saved. The closing audio finished before the system call ended. |
| Spoken hang-up | Passed | A spoken request triggered the closing line and ended the system call. This passed after the phone was placed beside the Mac speaker. Earlier attempts did not pass. |
| Coaching | Passed | Eight real Decisions checks separated reluctance, stop requests and completion. A Live speech test challenged reluctance and gave a small first step. |
| Interrupted call | Passed | The app was terminated during a connected call. After reopening, it started a new call without waiting for the old server connection to expire. |
| Daily reminder | Passed | A temporary habit used the normal daily scheduler. Its incoming call was answered while the habit editor was open. The call screen appeared, voice connected and completion worked. The temporary habit was then removed. |
| Spoken habit draft | Passed | Responses extracted a chosen time, a suggested time and a corrected time. Drafting did not save a schedule. |
| Generated pet | Passed | The phone generated a teal dragon, previewed angry and talking states, saved it and restored it after relaunch. Pip was selected again. |
| Sprite review | Passed with limits | All 16 frames were inspected on dark olive and cream backgrounds. The app uses audio level to move the mouth. It does not match individual speech sounds. Generated artwork still needs the preview step. |
| Fonts and layout | Passed on this phone | Manrope and DM Sans loaded. Today, the habit editor and Settings were inspected. Main navigation and controls fit without scrolling. |
| Server validation | Passed | Tests checked paired HTTPS, rejection of an invalid pairing token, invalid input, habit editing, progress storage, duplicate prevention and undo. |
| Local secrets | Passed for the checks run | A key-pattern scan checked working files and 185 historical Git blobs. It found no matching keys. The environment file, pairing configuration and signing material remain outside Git. This is not a full security review. |
| Offline recovery | Passed | With the server stopped, completion survived an app restart. After reconnection, the server saved it to disk. The test restored the previous completion state. |
| Settings | Passed | Motion preference survived relaunch. Pause, resume and an unchanged edit kept a New York reminder time while the phone used London time. Empty-habit saving was blocked. Cancel kept the saved habit. The original settings were restored. |

The first daily-reminder test failed because it queried Apple's call application before that application had a window. The waiting logic was corrected and the repeated test passed. Failed runs remain in local audit records. They are not counted as successful tests.

## Fixes

- Today now shows actionable call and connection errors. It no longer labels an unavailable next-call date as a paused schedule.
- Pausing and editing a habit preserve its saved time and time zone. The editor displays the saved zone.
- The phone remembers its own voice connection until cleanup succeeds. Reopening can release a connection left by an interrupted app. The server also clears the matching incoming-call state.
- An incoming call dismisses the habit editor so it cannot cover the call screen.
- A new habit does not inherit an old suggested-time hint.
- Cancelled voice setup cannot start a new audio meter after cancellation.
- Accessibility labels distinguish a saved custom pet from Pip.

## Not checked or not included

- Fresh sign-in with another account, account switching and account deletion.
- Full lock-screen presentation, Focus modes, silent mode, reboot delivery and delivery after a force-quit.
- Other iPhone sizes, large accessibility text sizes, Bluetooth routes and long-duration use.
- Inference charged to the ChatGPT plan. Live, Images, Decisions and Responses tests used the configured project key.
- A public, multi-user backend or App Store distribution. Calls still require the development Mac to be awake and reachable.
- A coin shop, pet accessories, one-time appointments and ChatGPT pet-library access. These are outside the shipped daily-habit journey.

## Repeat the checks

Run `swift test` and `npm test` for the offline suites. Use the `HobbitUITests` scheme on an already signed-in iPhone for routine interface checks.

The review request records the final unit, interface and native analysis results.

The `HobbitSpokenStop`, `HobbitPetCreation` and `HobbitIncomingDemo` schemes use paid APIs. Spoken checks print a marker when they are ready for a synthetic phrase. Keep the phone near the audio source. The incoming check needs a scheduled call from the paired server.

The `HobbitOffline` scheme deliberately tests a server outage. Stop the development server after `HOBBIT_READY_TO_STOP_SERVER`. Restart it after `HOBBIT_READY_TO_RESTART_SERVER`. The test then checks recovery and prints `HOBBIT_COMPLETION_SYNCED` before restoring the earlier completion state.

Use `-collect-test-diagnostics never` to avoid collecting a full device diagnostic package. Screenshots and local reports are retained under the ignored `.local` directory. Do not publish device reports without checking them for private data.
