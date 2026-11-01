# Hobbit demo

The [finished video](docs/demo.mp4) is 89 seconds, 1280 by 720. The creator's filmed skit plays beside the actual iPhone app, followed by a narrated product walkthrough. Unhinged contains strong language. The supplied performance is included by request; account pages, keys, device identifiers and unrelated background conversation are excluded.

1. **0–13.5 seconds:** “I was going to work out. Eventually.” A slow opening, the ringtone, a short pause, then Pip shouts “Off the bloody sofa! Push-ups. Now!” The startled reaction leads into action.
2. **13.5–23 seconds:** Press-ups with a motivational instrumental. No narration or coaching speech over the exercise.
3. **23–29 seconds:** The victory jump, tumbling confetti from both sides, a gold trophy and “Quest complete” reward. Let the laugh and victory sound land, then Pip gives a short goodbye. The native app's new reward plays alongside the skit.
4. **29–50 seconds:** Explain the main benefit: a pet calls at the time you set and helps you start. Choose Pip or create a pet.
5. **50–71 seconds:** Start with a small habit. Set a call time and coaching intensity. Show separate progress for each habit, then show pause controls in Settings.
6. **71–89 seconds:** Codex's debugging contribution and the closing line: “Less doomscrolling. More doing. Your excuses have a new enemy.”

The phone recordings were captured by native Xcode UI tests. Device Hub screen sharing was off because it conflicts with the iPhone microphone. Keep the Mac awake on the same network while the local development server runs. The skit and app walkthrough were recorded separately and edited together; this is not an uncut recording of one live phone session. The edit hides call transcripts that do not match the separately recorded pet voice. It does not replace them with invented app text. Production labels are omitted from the video; credits remain here.

Claude Opus 5.5 reviewed one-second storyboard frames, the timed transcript and the edit script. The review informed clearer benefit copy, narration matched to each screen, and removal of a paused “Saving your call…” frame. This was a review of frames and timing data, not direct listening to the audio. Product text fades in over 0.2 seconds. The opening keeps direct cuts for the scare and exercise.

The persistent daily scheduler and the Mac presentation trigger are separate features. No demo-call button appears in the app. The video shows an incoming call while the phone is awake, not locked-screen delivery. It does not claim ChatGPT pet-library access. The custom teal dragon was generated on the phone. The current atlas has four moods and four mouth/blink frames per mood.

The story voiceover was generated through the ElevenLabs CLI using Eleven v4 and the default George storyteller voice. It is a narrator, not a clone of the performer. The original celebration laughter remains. Pip's new push-ups command and farewell use the existing OpenAI drill-sergeant voice. The native recordings are silent; the ringtone, voice and congratulation were mixed into the edit. The training instrumental was generated through the ElevenLabs CLI with Music v2.5, without vocals or a reference song. The quiet walkthrough backing and victory chime are original synthesized sounds. The app reward uses a trophy, tumbling side-launched confetti, the real streak and a success haptic; it does not invent XP or a points system. The video does not claim that the spoken-completion check passed.

## Live skit and Mac trigger

Keep the Mac server running with `npm start`, and the paired iPhone on the same Wi-Fi. Leave Device Hub screen sharing off while the phone microphone is active. Open Hobbit with the incomplete habit “Do push-ups” selected and Unhinged mode saved.

From a separate Mac Terminal:

```bash
npm run demo:call -- --habit "Do push-ups" --delay 15
```

The phone rings 15 seconds later. `npm run demo:call -- --list` lists saved habits. To cancel, run `npm run demo:call -- --cancel CALL_ID` using the ID printed by the command. The executable `scripts/Call Hobbit.command` is a double-click alternative when only one habit exists.

One presenter slumps in a chair: “I am incredibly committed to improving myself. Starting Monday.” The other quietly triggers the call. Answer it and say, “I don't want to do push-ups.” Let Pip respond without talking over it. Stand up, do push-ups, tap “I did it”, and let the short goodbye finish. Say: “We made the reminder harder to ignore, and the next step easier to start.”

If the live connection stalls, immediately play the finished video. Do not spend presentation time debugging Wi-Fi. For a strict 90-second slot, play the video alone; the skit is an alternative, not an extra 30 seconds before it.
