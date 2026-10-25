// The look every deskw widget shares, from DMS's plugin_settings.json
// ("deskwStyle", written by StyleSettings.qml on any widget's settings
// page). Pure, so `node --test tests/` covers it.
export function styleFrom(settings) {
    const s = settings?.deskwStyle ?? {};
    const pct = Number(s.opacity);
    return {
        glass: s.style === "glass",
        opacity: Number.isFinite(pct) ? Math.min(100, Math.max(10, pct)) / 100 : 0.55,
        blur: s.blur ?? true,
        border: s.border ?? true
    };
}
