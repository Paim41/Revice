# Telemetry contract v1

All capacities are bytes. Battery voltage is millivolts, temperature is Celsius and percentage is 0–100. Unsupported readings are null, never invented zeros. `observedAt` is the device observation time in UTC ISO 8601. `receivedAt` is reserved for the future gateway and must be server generated. Local readings are not synchronized telemetry and have no server receipt time.

Storage describes the Android data filesystem, not marketed flash capacity. Used bytes are total minus available-to-app bytes, including reserved space unavailable to apps.

Device IDs will be random installation IDs at enrollment; hardware identifiers are not collected. Phase 2 adds authenticated device envelopes, sequence IDs and server validation before ingestion exists.
