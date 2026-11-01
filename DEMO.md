# Hobbit demo

The [finished video](docs/demo.mp4) is 89 seconds, 1280 by 720, with recorded voices throughout. It uses real iPhone screens and fictional habits. No account pages, keys, device identifiers or private conversations are included. Unhinged contains strong language.

1. **0–9 seconds:** “I downloaded five habit trackers. My only streak is ignoring them.” Hobbit calls you.
2. **9–31 seconds:** Choose a pet, generate a creature, set a habit, time and coaching intensity.
3. **31–38 seconds:** Real incoming call triggered from the Mac, with Hobbit's original ringtone.
4. **38–57 seconds:** “I do not want to do it.” Pip's actual recorded Unhinged response. The human concedes that even their imaginary pet has had enough.
5. **57–63 seconds:** “I did it.” Real button-completion footage, brief congratulation and call ending.
6. **63–73 seconds:** Multiple habits and Settings, without scrolling.
7. **73–89 seconds:** Codex's contribution, speaker-routing debugging and the closing line.

The phone recording was captured by the `HobbitDemo` Xcode scheme. Device Hub screen sharing was off because it conflicts with the iPhone microphone. Keep the Mac awake on the same network while the local development server runs. The generated audio uses only a fictional test phrase; it contains no user recording.

The persistent daily scheduler and the Mac presentation trigger are separate features. No demo-call button appears in the app. The video shows an incoming call while the phone is awake, not locked-screen delivery. It does not claim ChatGPT pet-library access. The custom teal dragon was generated on the phone. The current atlas has four moods and four mouth/blink frames per mood.

The narrator and lazy human are original synthetic voices. The Unhinged clip is an actual GPT-Live response to synthetic input, presented in a clearly labelled animated cutaway. The native screen recordings are silent; the ringtone and congratulation are the same original audio assets used by the app, added in the edit. The quiet backing track is an original synthesized bass-and-percussion pattern, with no sampled music. The video demonstrates completion by tapping “I did it”; it does not claim that the spoken-completion check passed.

## Live skit and Mac trigger

Keep the Mac server running with `npm start`, and the paired iPhone on the same Wi-Fi. Leave Device Hub screen sharing off while the phone microphone is active. Open Hobbit with the incomplete habit “Stretch for two minutes” selected and Unhinged mode saved.

From a separate Mac Terminal:

```bash
npm run demo:call -- --habit "Stretch for two minutes" --delay 15
```

The phone rings 15 seconds later. `npm run demo:call -- --list` lists saved habits. To cancel, run `npm run demo:call -- --cancel CALL_ID` using the ID printed by the command. The executable `scripts/Call Hobbit.command` is a double-click alternative when only one habit exists.

One presenter slumps in a chair: “I am incredibly committed to improving myself. Starting Monday.” The other quietly triggers the call. Answer it and say, “I don't want to stretch.” Let Pip respond without talking over it. Stand up, stretch, tap “I did it”, and let the short goodbye finish. Say: “We made the reminder harder to ignore, and the next step easier to start.”

If the live connection stalls, immediately play the finished video. Do not spend presentation time debugging Wi-Fi. For a strict 90-second slot, play the video alone; the skit is an alternative, not an extra 30 seconds before it.
