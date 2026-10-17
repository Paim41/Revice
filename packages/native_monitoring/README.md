# Native monitoring bridge

Internal Android-only Flutter plugin. Registers `app.revice/monitoring` on every engine, including the WorkManager headless engine. Reads battery, data-filesystem capacity and general device metadata through public Android APIs. Preference methods store nonsensitive onboarding/reduced-motion flags.

The production app and integration tests are in `apps/android/revice_android`. The generated `example/` tree is not part of the production application or release artifacts.
