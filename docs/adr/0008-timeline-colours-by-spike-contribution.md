# Timeline colours go to the apps that cause the spikes

The chart colours five apps; the rest is Other. Ranking by range average hid the app behind a short spike, which is what users look for. Apps are ranked by their contribution weighted by each bucket's excess over the median bucket total; a flat range falls back to the average. Each app keeps a stored colour slot (`appColorSlots`, newest 256 apps) so its colour is the same on every screen; on a collision the smaller app key keeps the slot. Decisions D18, D22.
