# Hobbit

A native iPhone habit companion. Sign in with ChatGPT, choose Pip or create your own pet, set one small habit, and talk with your pet. The development build includes native internet calls, a 15-second incoming-call demo, animated expressions and local habit completion.

Public source: [github.com/sgaabdu4/hobbit](https://github.com/sgaabdu4/hobbit). The Xcode project and bundle identifier retain the earlier Habitaker name to preserve installed sign-in and push registration.

Verified on a physical iPhone on 1 November 2026: OAuth returned through the phone's loopback listener, signed identity validation passed, and ChatGPT-plan permission was granted. Pet onboarding runs on the device. GPT Image 2.5 generated the bundled original pet and expression sheet. The live Decisions API correctly classified three synthetic examples: completion, future intention and stopping a call. Two-way audio and incoming calls are awaiting device verification.

## Set up the development demo

1. Install Node 26.12.0 and Xcode 27.2. An Apple Developer Program team and physical iPhone are needed for push calls.
2. Copy `.env.example` to `.env`. Add an OpenAI project key with Images, Live, Decisions and Responses access. Sign-in alone does not fund every API feature.
3. Register your app bundle ID with Push Notifications in Apple Developer. Create a sandbox APNs key scoped to that app. Save its `.p8` file outside Git and fill the APNs fields in `.env`.
4. Run `npm run prepare:device`. This creates a local HTTPS certificate and pairs the development build with this Mac. The certificate and pairing secret are ignored by Git.
5. Run `npm start`. Keep the Mac awake and the phone on the same Wi-Fi. No public tunnel is used.
6. In Xcode, set your team and bundle ID, then run on the phone. Allow local network and microphone access when requested. Test foreground voice first, then schedule a call and lock the phone.

The project pins WebRTC 156.0.0. Xcode resolves it automatically. No npm packages are required. The phone pins the generated TLS certificate and sends a device pairing token to this development server. This is a single-device hackathon setup, not a public multi-user backend. Never distribute a build containing your development pairing secret.

Calls are capped at three minutes in the app. Scheduled calls currently live in server memory and are lost when it restarts. The 15-second button is a demo control, not a daily alarm. Apple controls the incoming-call screen; pet animations appear inside Hobbit. A force-quit app, network failure or iOS policy can prevent delivery, so do not rely on this for essential reminders.

Pet creation asks for one description and previews the result before saving. The app uses a four-state 2-by-2 image sheet: attentive, speaking, thinking and happy. It is an app-specific format, not a full ChatGPT pet-library export. Speaking frames follow received audio levels. Cosmetic transcript decisions cannot mark the habit done; completion uses a separate explicit-action decision and can be undone.

## Run the sign-in check

1. Open `Habitaker.xcodeproj` in Xcode 27.2 or later.
2. Choose your Apple development team under Signing & Capabilities.
3. Select a paired iPhone running iOS 18 or later and run Hobbit.
4. Tap **Continue with ChatGPT**. Complete OpenAI's sign-in and consent flow on the phone.
5. A successful test opens pet onboarding only after verifying the identity signature, issuer, audience, expiry and nonce.

No API key is required for this OAuth check. Credentials and the stable host identifier stay in the iPhone Keychain. The app writes a nonsecret `Documents/verification.json` report containing test stages and permission booleans. It never writes tokens, authorization codes, email addresses or account identifiers to that report. Voice diagnostics contain connection states, event counts and audio levels, never recordings or transcript text.

## Verification scope

- Open-source registration uses OpenAI's documented dynamic client flow, PKCE and an HTTP listener bound to `127.0.0.1` on the phone.
- Apple's authentication browser stays open during authorization. After receiving the loopback callback, the local listener redirects to an internal completion scheme to close that browser. This mobile combination needs a real-device test; documentation alone is not proof it works.
- ChatGPT plan permission is reported separately from identity verification. Inference has not been tested.
- The product will generate an app-specific pet. Automatic ChatGPT pet-library access is no longer a requirement. The documented identity and Responses scopes do not establish access to that library.
- Native voice, incoming-call handling, pet creation and sprite playback are implemented. Device audio and locked-screen delivery have not yet been checked. Sprite import is not implemented.

Run the focused OAuth checks with `swift test`. They test callback validation, a valid RSA-signed identity, tampered signatures and invalid identity claims. They do not replace real sign-in or cover every JWT failure case.

## Sources and credits

Created during the DevDay Exchange London hackathon on 1 November 2026 with Codex. Codex implemented and tested the OAuth signature/callback checks and adapted the documented GPT-Live transport to native Swift WebRTC and CallKit. No third-party application template is used. The original Pip artwork was generated using GPT Image 2.5 Sunburst through the bundled Codex Imagegen CLI. Prompts and originals are in `output/imagegen`; app copies are in `Sources/Habitaker/Resources`.

The [WebRTC Swift package](https://github.com/stasel/WebRTC) supplies Google's WebRTC binary under its upstream BSD license. Keep its license notices with redistributed builds. Apple's CallKit and PushKit provide system calling integration. The OpenAI pet sprite concept informed the app-specific state mapping; no ChatGPT user pet or library asset is bundled.

- [OpenAI open-source sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [OpenAI identity validation](https://developers.openai.com/siwc/website)
- [ChatGPT plan limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [ChatGPT pets](https://learn.chatgpt.com/docs/pets)
- [Apple web authentication](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [OpenAI GPT-Live WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc?api=live)
- [OpenAI Decisions voice integration](https://developers.openai.com/api/docs/guides/decisions-voice)
- [OpenAI image generation](https://developers.openai.com/api/docs/guides/image-generation)
- [Apple VoIP push handling](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit)

OpenAI project credentials stay on the backend. Do not commit credentials, signing material or personal device data. Do not include account screens, keys or personal habit text in the demo video. Run `npm test` for the server's focused habit/mode/decision checks, and `swift test` for OAuth checks.
