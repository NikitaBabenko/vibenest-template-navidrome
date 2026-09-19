# VibeNest Template: Navidrome

Thin VibeNest deployment adapter for [Navidrome](https://github.com/navidrome/navidrome), a personal music server.

The adapter keeps the upstream application unmodified and pins the production image to `deluan/navidrome:0.64.0`. It adds a small, authenticated upload portal on the **same VibeNest server**, so a Free user does not need a second File Browser project:

- Navidrome: `/` on public port `4533`;
- music uploads: `/music-upload/`, username `admin`, password from the generated `ADMIN_PASSWORD` project variable;
- persistent Navidrome state: `/data`;
- persistent shared music library: `/music`;
- Navidrome mounts `/music` read-only; only the upload service can write it;
- command execution in File Browser is disabled;
- all long-running containers run without Linux capabilities and with `no-new-privileges`.

## Free-tier posture

VibeNest Free currently provides 256 MB RAM, 0.5 vCPU and 4 GB SSD. This adapter uses conservative defaults, but **Free suitability must be proven by runtime measurements before the public template claims it**.

The production compose explicitly caps the three running services at 256 MiB / 0.5 CPU in total (Navidrome 176 MiB / 0.35 CPU, uploads 48 MiB / 0.10 CPU, gateway 32 MiB / 0.05 CPU). These limits also apply on a larger plan until you adjust the compose in your own fork; upgrading hardware alone does not remove the adapter caps.

The intended Free path is direct play:

1. Prefer MP3, AAC, Opus or another codec supported by the listening client.
2. Leave the client/player bitrate at unlimited and do not select a transcoder.
3. The server allows at most one concurrent transcode as a safety ceiling, cancels it when the client disconnects, and keeps only a 32 MB transcoding cache.

The `ND_ENABLETRANSCODINGCONFIG=false` setting disables editing transcoder commands in the web UI for security; it is not a global transcoding-off switch. A client can still request transcoding, which may exceed the Free CPU budget. The catalog page must say this plainly.

The 4 GB disk limit includes the music library, database, artwork cache and container writable layers. This is suitable only for a small personal library. Keep backups outside the instance.

## Smoke checklist

1. Deploy with build pack `docker-compose`, compose file `/docker-compose.yml`, internal port `4533`.
2. Open `/` and create the first Navidrome administrator.
3. Open `/music-upload/`, sign in as `admin`, and upload a small, redistributable audio fixture.
4. Wait for the watcher or scanner, then play the track with the player bitrate set to unlimited.
5. Confirm the Navidrome log records direct/raw streaming (`transcoding=false`).
6. Measure aggregate RAM and CPU at idle, during the first scan, during direct play, and during one bounded transcode attempt.
7. Restart and redeploy; confirm the admin account, upload login, library, playlist/history state and audio file persist.
8. Confirm the public proof instance exposes no default credentials and carries `X-Robots-Tag: noindex, nofollow`.

The repository CI performs a bounded 256 MB compose smoke before VibeNest runtime validation. It uploads a generated two-second WAV through the real `/music-upload/` API, creates the first Navidrome admin, scans and direct-plays the file byte-for-byte, creates a playlist, restarts the stack, and verifies all state persists. CI evidence is preparatory only; it does not justify a public Free claim without measurements on VibeNest.

### CI evidence snapshot

[GitHub Actions run 35430863475](https://github.com/NikitaBabenko/vibenest-template-navidrome/actions/runs/35430863475) passed on 2026-09-19 for commit `b32f1cfd3bf2c5e2e867a40e13b2446c8952edf3` under the compose limits of 256 MB RAM and 0.5 vCPU. The sampler observed:

- maximum combined sampled memory: 60.1 MiB;
- maximum combined sampled CPU: 36.8% of one core;
- Navidrome first import: one WAV track in 904.7 ms;
- restart recovery: the administrator, upload login, music file, database and playlist all remained available.

These are short GitHub-hosted CI observations, not production VibeNest peaks. A public Free-tier recommendation remains blocked until the same workload, plus an explicit bounded transcode check and a redeploy persistence check, passes on VibeNest.

## Pinned components and licenses

- Navidrome `0.64.0` (multi-arch digest `sha256:a384948b…`) — GPL-3.0: https://github.com/navidrome/navidrome/tree/v0.64.0
- File Browser `2.63.23` (multi-arch digest `sha256:a469ea07…`) — Apache-2.0: https://github.com/filebrowser/filebrowser/tree/v2.63.23
- nginx `1.31.6-alpine3.24` (multi-arch digest `sha256:adad2ae9…`) — BSD-2-Clause: https://nginx.org/LICENSE
- Alpine `3.24.2` — distribution packages retain their respective licenses.

This repository contains deployment configuration only. Product source, notices and licenses remain with their upstream projects.
