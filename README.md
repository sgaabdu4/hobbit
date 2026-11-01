# Hobbit

Hobbit is an iPhone habit app. Your pet calls at the time you set and helps you start your habit. Complete the habit to save your progress and receive a reward.

Sign in with ChatGPT. Choose Pip or create a pet. Speak or type your first habit, then check the details before you save it. You can add more habits. Each habit has its own call time, coaching mode and progress.

Choose Gentle, Aggressive or Unhinged. These modes change the voice and the pet's expression. You can pause calls or undo a completion.

The Today, Habits and Settings tabs remain visible on the main screens. These screens fit the tested iPhone without vertical scrolling. The habit list uses separate pages. Settings contains pet selection, motion settings, call controls and permissions. The app uses a dark olive background with Manrope and DM Sans fonts.

Public source: [github.com/sgaabdu4/hobbit](https://github.com/sgaabdu4/hobbit). The Xcode project and bundle identifier still use the earlier Habitaker name. This keeps the existing sign-in and push registration valid.

https://github.com/user-attachments/assets/8564c067-6dad-494c-b28f-bfcb4b5a2fc8

[Download the 89-second demo](docs/demo.mp4) or [watch on YouTube](https://youtu.be/9JupHPWnTk4). The film shows a person scrolling on a phone, receiving a call and doing push-ups. The real iPhone app appears beside the film. ElevenLabs provides the narration and training music. OpenAI provides the drill-sergeant voice. Completion shows confetti, a trophy and the saved streak. The iPhone also gives a short vibration. See [demo notes and credits](DEMO.md) for the recording details.

<img src="docs/screenshots/pet.png" alt="Choose Pip or create a pet" width="220"> <img src="docs/screenshots/ringing.png" alt="Pip ringing on the iPhone" width="220"> <img src="docs/screenshots/completion.png" alt="Saved habit completion" width="220">

We tested the app on a physical iPhone on 1 November 2026. Sign-in, identity checks and ChatGPT plan permission passed. Pet setup ran on the iPhone. GPT Image 2.5 generated the included pet artwork and expressions.

Voice logs confirmed microphone input, received audio, transcript events and loudspeaker output. The tester heard the pet. A scheduled push started a voice call after a command to lock the iPhone. We did not record the system lock screen.

## Set up the development demo

You need Node 26.12.0, Xcode 27.2, an Apple Developer Program team and a physical iPhone.

1. Copy `.env.example` to `.env`.
2. Add an OpenAI project key with Images, Live, Decisions and Responses access to `.env`.
3. Register your app bundle ID with Push Notifications in Apple Developer.
4. Create a sandbox Apple Push Notification service (APNs) key for that app.
5. Save the `.p8` file outside Git.
6. Set the APNs fields in `.env`.
7. Run `npm run prepare:device`.
8. Run `npm start`.
9. Set your development team and bundle ID in Xcode.
10. Run the app on the iPhone.
11. Allow local network and microphone access when the iPhone requests them.
12. Test a voice call with the app open.
13. Schedule a call.
14. Lock the iPhone to test the incoming call.

Keep the Mac awake. Keep the iPhone on the same Wi-Fi network. ChatGPT sign-in does not pay for every API feature.

Xcode downloads the required WebRTC version, 156.0.0. The server needs no npm packages.

The preparation command creates a local HTTPS certificate and a pairing secret. Git excludes both files. The iPhone checks this certificate and sends the pairing token to the server. The connection does not use a public tunnel.

This development setup supports one iPhone. It is not a public server for multiple users. Do not distribute an app build that contains your development pairing secret.

## Calls and pets

Calls stop after three minutes. The server saves habits, time zones, pause settings and completed days in `.local/schedule.json`. These records remain after a server restart. The app also keeps the history from the earlier version with one habit.

Call times must be at least five minutes apart. The schedule uses each habit's time zone and includes daylight-saving changes. The server skips calls missed while the Mac is asleep. It does not make all missed calls when the Mac wakes.

The separate 15-second test call is temporary. A server restart removes it. Keep the Mac awake and the server running for daily calls. Apple controls the incoming-call screen. The animated pet appears inside Hobbit.

When the app recognizes completion or a request to end the call, it stops the live response. It plays one short closing line in the selected voice, then ends the system call. The **End** button ends the call immediately.

To generate the closing lines, run `node --env-file=.env scripts/create-call-endings.mjs`. This command uses paid GPT-Live generation and the configured custom Unhinged voice.

Pet creation asks for a creature, color and optional details. You can preview the pet before you save it. There is no file import step.

New pets use a transparent PNG sprite sheet with four rows and four columns. The rows show calm, stern, furious and happy expressions. The columns show a closed mouth, a small mouth opening, a wide mouth opening and a blink. Earlier custom pets with two rows and two columns still work.

The mouth moves with the level of received audio. The movement does not match individual speech sounds. Blinks and body movement obey the Reduce Motion setting.

Decisions about the pet's expression cannot complete a habit. Completion requires a separate decision about an explicit action or a tap on **I did it**. You can undo completion.

The [Hobbit pet skill](.agents/skills/hobbit-pets/SKILL.md) explains how to generate, check and add pets. It does not depend on ChatGPT Work's pet creation skill.

For spoken setup, GPT-Live collects the request. GPT-6 Luna uses the Responses API to fill a draft. You can edit the draft. The app schedules no call until you confirm it.

To create a custom Unhinged voice:

1. Enable Voices read/write access on the project key.
2. Run `npm run create:voice` once.
3. Restart the server.

The command creates an original synthetic voice and saves its ID under `.local`. The design prompt is in `server/voice-design.mjs`. To use an existing authorized voice, set `OPENAI_UNHINGED_VOICE_ID`.

Without a custom voice, Aggressive and Unhinged use Vesper. Gentle uses Marin. Voice delivery varies. Listen to a test call to check it.

## Run the sign-in check

1. Open `Habitaker.xcodeproj` in Xcode 27.2 or later.
2. Choose your Apple development team under Signing & Capabilities.
3. Select a paired iPhone with iOS 18 or later.
4. Run Hobbit.
5. Tap **Continue with ChatGPT**.
6. Complete OpenAI's sign-in and consent screens on the iPhone.

The app checks the identity signature, issuer, audience, expiry and nonce. If these checks pass, it opens pet setup.

This OAuth sign-in check needs no API key. The iPhone Keychain stores credentials and the stable host identifier.

The app saves test stages and permission results in `Documents/verification.json`. This report contains no tokens, authorization codes, email addresses or account identifiers. Voice logs contain connection states, event counts and audio levels. They contain no speech recordings or transcript text.

## Verification scope

See the [post-submission application check](AUDIT.md) for the latest device results, fixes and remaining limits. The submitted version is preserved in Git history.

- **Sign-in:** Registration uses OpenAI's documented dynamic client flow and PKCE. An HTTP listener uses `127.0.0.1` on the iPhone. Apple's authentication browser stays open during authorization. The listener receives the callback, then redirects to an internal completion scheme to close the browser. This sequence passed on the physical iPhone.
- **Session renewal:** Testing found an expired sign-in session. The app now uses the rotating refresh token to renew the session. It checks the new identity and saves the replacement credentials in Keychain.
- **Habits:** Native interface tests passed for typed setup, daily call storage, completion, restart persistence, undo, pet selection and habit editing. A second habit had separate progress. It remained after an app restart. Two confirmation steps removed it without a change to the first habit. The bottom tabs and Settings controls needed no scrolling.
- **Calls:** The Mac command triggered a real incoming call. The iPhone test answered it, connected to Live voice and completed the habit. Logs confirmed that the closing line finished before the system call ended. Foreground voice and loudspeaker output also passed. The post-submission audit passed spoken completion, spoken hang-up and a call from the normal daily scheduler.
- **Pets:** Generation, angry expressions and talking previews passed on the iPhone. Received speech opened Pip's mouth. The ringing animation continued until audio started. Logs confirmed that the ringtone started and stopped. The post-submission audit saved a generated pet and restored it after an app restart.
- **Design:** The iPhone loaded Manrope and DM Sans. We inspected recordings of the dark Today, call and completion screens.
- **Coaching:** A test sent synthetic speech saying “I don't want to do it” through GPT-Live. It used Unhinged mode and the custom voice. Pip challenged the delay and gave a ten-second first step. Eight live Decisions checks distinguished reluctance, a request to stop and completion.

The following limits remain:

- ChatGPT plan permission and identity verification are separate checks. Inference paid through the ChatGPT plan has not been tested.
- Hobbit generates its own pets. It does not use the ChatGPT pet library. The documented identity and Responses permissions do not establish access to that library.
- Lock-screen presentation has not been checked from start to finish.

Run `swift test` to check OAuth, daily completion, streak changes and mouth animation logic. Run `npm test` to check habits, decision separation and schedules across clock changes.

The `HobbitUITests` Xcode scheme runs interface checks on an iPhone that is already signed in. The `HobbitDemo` scheme runs a paid live voice check and keeps the screen recording.

Run `node --env-file=.env scripts/check-coaching.mjs` for the eight paid Decisions checks. To test a live spoken response, add the path to a synthetic recording as an argument. Use mono PCM16LE audio at 24 kHz. The script saves the response audio under `.local`.

Use synthetic speech saying “I don't want to do it.” Do not use a private conversation. These live checks are separate from offline continuous integration (CI) tests.

## Sources and credits

We built Hobbit with Codex during the DevDay Exchange London hackathon on 1 November 2026. Codex wrote and tested the OAuth signature and callback checks. It adapted the documented GPT-Live connection for native Swift, WebRTC and CallKit. We used no third-party app template.

Calls first connected without audible speech. Codex added logs without speech recordings and found that WebRTC had selected the earpiece. It changed the audio settings to use the loudspeaker. A second iPhone test confirmed loudspeaker output and live audio events.

The script `scripts/generate-ringback.py` creates the original double-ring sound. It uses no third-party recording. The app repeats this sound during connection. The sound stops when speech starts or the call ends.

OpenAI prompt-to-voice created the custom drill-sergeant voice. Its description and sample script are in `server/voice-design.mjs`. We used no recording or imitation of a real person. Each developer must create a voice or supply an authorized voice ID.

GPT Image 2.5 Sunburst generated the orange Pip sprite sheet and app icon from the approved original design. We used the Codex Imagegen command-line tool. Codex's built-in image tool generated an earlier draft.

Prompts and original artwork are in `output/imagegen`. App copies are in `Sources/Habitaker/Resources`. Manrope and DM Sans come from the [Google Fonts repository](https://github.com/google/fonts). Their SIL Open Font Licenses are in `Sources/Habitaker/Resources/Fonts`.

The [WebRTC Swift package](https://github.com/stasel/WebRTC) supplies Google's WebRTC binary under its BSD license. Keep its license notices when you distribute app builds. Apple's CallKit and PushKit connect Hobbit to system calling features. OpenAI's pet sprite concept helped define Hobbit's animation states. The app includes no ChatGPT user pet or pet library asset.

- [OpenAI open-source sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [OpenAI identity validation](https://developers.openai.com/siwc/website)
- [ChatGPT plan limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [ChatGPT pets](https://learn.chatgpt.com/docs/pets)
- [Apple web authentication](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [OpenAI GPT-Live WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc?api=live)
- [OpenAI Decisions voice integration](https://developers.openai.com/api/docs/guides/decisions-voice)
- [OpenAI image generation](https://developers.openai.com/api/docs/guides/image-generation)
- [Apple VoIP push handling](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit)

Keep OpenAI project credentials on the server. Do not commit credentials, signing files or personal device data. Exclude account screens, keys and private habit text from demo recordings.
