# Alert presets write concrete values; the daemon never sees a preset

Relaxed, Balanced (default) and Strict compute thresholds from the Mac's cores, memory and boot volume in the app, and write the concrete numbers to the daemon's `settings.json`; Custom means the user edited a value. The daemon stays simple and its behaviour does not change when hardware is detected differently. CPU stays in % of one core in storage (a preset writes share × cores), and the allowed ranges scale with the machine so every preset is valid. Values are calibrated on recorded history. Spec §9.
