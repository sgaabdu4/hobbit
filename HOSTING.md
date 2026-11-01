# Hosted calls

Hobbit can run on an always-on Linux server. The iPhone then uses public HTTPS over Wi-Fi or mobile data. The development Mac is needed only to build or install a new iPhone version.

This remains a private, single-phone deployment. Do not distribute the paired app binary to other users. The pairing secret gives access to the saved habits and paid API functions.

## Server

Build the included Dockerfile with Node 26.12.0. Run one instance behind a trusted HTTPS reverse proxy. Do not publish the container's plain HTTP port to the internet.

Set these values outside Git:

- `HOBBIT_HOSTED=true`
- `HOBBIT_DATA_DIR` pointing to the mounted persistent directory
- `HOBBIT_DEVICE_SECRET` containing the phone's pairing secret
- `OPENAI_API_KEY` and, if used, `OPENAI_UNHINGED_VOICE_ID`
- `APNS_KEY_FILE` pointing to a mounted private key, or `APNS_KEY_P8` supplied through a secret manager
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID` and `APNS_ENVIRONMENT`

Use `sandbox` for a development-signed iPhone app and `production` for a distribution-signed app. The push environment must match the installed app. Keep habits and device registration on persistent storage. They are stored as `schedule.json` and `device.json`.

`GET /healthz` is a public process health check. All functional routes require the pairing token. The authenticated `/health` route reports configuration and device registration; a successful call is still needed to verify the credentials.

Deploy through GitHub Actions. The included workflow accepts only an owner-triggered run and uses a temporary deployment runner. The operator stages a reviewed release and credentials on the host first. Its temporary SSH key is restricted to that release's deployment command. The runner handles one job, then is removed. No application or signing keys go into the Actions log or image.

The deployment script uses a non-root container, a read-only root filesystem, resource limits and automatic restart. It runs the server tests before switching the container. It keeps the previous container for recovery. Back up the data directory separately. A single server is not a high-availability service; outages can still cause a missed call.

## iPhone

Set `HOBBIT_SERVER_URL` to the HTTPS base address. A path prefix is supported. Run `node --env-file=.env scripts/prepare-hosted-device.mjs` after the server is ready. The script checks pairing and configuration before changing the ignored device configuration. Rebuild and install the iPhone app.

Hosted connections use normal certificate validation. Local development connections keep their certificate pin. Open the installed app once to register its push token, and allow microphone access before testing a locked call.

Stop the old Mac server after confirming that the hosted server has the right habit and phone registration. Keeping both schedulers running can cause duplicate calls.

## Locked-call check

1. Use a saved habit to schedule a test call from the separate command-line tool.
2. Lock the iPhone before the reminder arrives.
3. Confirm that Apple's incoming-call screen appears.
4. Answer while locked and check both directions of audio.
5. Say that the habit is complete or ask to end the call.
6. Confirm that the closing line finishes and the system call ends.
7. Repeat on mobile data with the Mac server stopped.

The local voice report records whether protected data was unavailable when the call arrived and when it was answered. This helps distinguish a locked call from a background call. It stores no speech recording or transcript.

The phone must have internet access. Apple's Focus settings, connectivity, force-quit behavior and device restart state can affect delivery. An unanswered call ends after 45 seconds. These conditions must be tested separately; a passed foreground call does not prove them.
