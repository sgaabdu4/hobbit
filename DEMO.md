# Hobbit demo

The [finished video](docs/demo.mp4) is 68 seconds, 1280 by 720, with an audio track. It uses the real physical iPhone and the fictional test habit "Stretch for two minutes". No account pages, keys, device identifiers or private conversations are included.

1. **0–7 seconds:** Real pet selection screen and the problem Hobbit solves.
2. **7–15 seconds:** Habit, daily time and optional coaching intensity.
3. **15–22 seconds:** Today screen with one clear action.
4. **22–35 seconds:** Actual iPhone recording of ringing, then an animated live call. Xcode's screen recording has no audio; the video labels that limitation.
5. **35–48 seconds:** A separate GPT-Live audio test. A synthetic voice said "I don't want to do it" and the real custom voice answered with a smaller, forceful challenge. This is explicitly labelled as a separate API check, not synchronized phone audio. Strong language is labelled before the audio plays.
6. **48–56 seconds:** Real completion screen. Native tests verified relaunch persistence and undo.
7. **56–68 seconds:** Concrete Codex debugging examples, the three successful physical-device UI checks and the public repository.

The phone recording was captured by the `HobbitDemo` Xcode scheme. Device Hub screen sharing was off because it conflicts with the iPhone microphone. Keep the Mac awake on the same network while the local development server runs. The generated audio uses only a fictional test phrase; it contains no user recording.

The persistent daily scheduler and the 15-second test call are separate features. The demo shows a foreground call, not locked-screen delivery. It does not claim ChatGPT pet-library access or show phone-generated custom pets. The current atlas has four moods and four mouth/blink frames per mood. Check README verification scope before presenting any additional feature as tested.
