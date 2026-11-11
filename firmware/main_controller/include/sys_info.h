#pragma once

// Best-effort chip-level metrics exposed in status payloads.
// Returns NAN when the value cannot be read (sensor missing, no link, etc.).

float chipTemperatureCelsius();