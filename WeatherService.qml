pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Current weather from Open-Meteo (free, no key) for the notch and bar pill
// when nothing is playing. The place is the city in Islet's settings, else
// DankMaterialShell's weather location — never looked up from your IP.
Singleton {
    id: root

    readonly property var o: Config.opts
    readonly property bool enabled: o.weatherEnabled

    // Coordinates: "lat,lon"
    property string coords: ""
    property string place: ""
    property bool ready: false
    property real temp: 0
    property int code: 0
    property bool day: true
    readonly property string unit: o.weatherUnit === "f" ? "°F" : "°"
    readonly property string tempText: ready ? `${Math.round(temp)}${unit}` : ""
    readonly property string icon: iconFor(code, day)
    readonly property string description: describe(code)

    // WMO weather codes → Material Symbols icon.
    function iconFor(c, isDay) {
        if (c === 0)
            return isDay ? "clear_day" : "clear_night";
        if (c <= 2)
            return isDay ? "partly_cloudy_day" : "partly_cloudy_night";
        if (c === 3)
            return "cloud";
        if (c <= 48)
            return "foggy";
        if (c <= 67 || (c >= 80 && c <= 82))
            return "rainy";
        if (c <= 77 || c === 85 || c === 86)
            return "weather_snowy";
        return "thunderstorm";
    }

    function describe(c) {
        return c === 0 ? "Clear" : c <= 2 ? "Partly cloudy" : c === 3 ? "Cloudy" : c <= 48 ? "Fog" : c <= 57 ? "Drizzle" : c <= 67 ? "Rain" : c <= 77 ? "Snow" : c <= 82 ? "Showers" : c <= 86 ? "Snow showers" : "Thunderstorm";
    }

    function request(url, cb) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {}
            cb(xhr.status, data);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // Find the place, then the weather.
    function refresh() {
        if (!enabled)
            return;
        const city = o.weatherCity.trim();
        if (city !== "") {
            request(`https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(city)}`, (code, d) => {
                const r = d?.results?.[0];
                if (code !== 200 || !r) {
                    ready = false;
                    place = "";
                    return;
                }
                place = r.name;
                coords = `${r.latitude},${r.longitude}`;
                fetchWeather();
            });
        } else {
            place = "";
            coords = dmsSession.coords;
            fetchWeather();
        }
    }

    function fetchWeather() {
        const [lat, lon] = coords.split(",");
        if (!lat || !lon) {
            ready = false;
            return;
        }
        const unit = o.weatherUnit === "f" ? "fahrenheit" : "celsius";
        request(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code,is_day&temperature_unit=${unit}`, (code, d) => {
            const c = d?.current;
            if (code !== 200 || !c)
                return;
            temp = c.temperature_2m;
            root.code = c.weather_code;
            day = c.is_day === 1;
            ready = true;
        });
    }

    // DankMaterialShell's weather location, if it has one.
    FileView {
        id: dmsSession
        readonly property string coords: {
            try {
                return JSON.parse(text()).weatherCoordinates ?? "";
            } catch (e) {
                return "";
            }
        }
        path: `${Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"}/DankMaterialShell/session.json`
        watchChanges: true
        onFileChanged: reload()
        onCoordsChanged: if (root.o.weatherCity.trim() === "")
            root.refresh()
    }

    // Weather changes slowly: every 30 minutes, and right away on new settings.
    Timer {
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        interval: 30 * 60 * 1000
        onTriggered: root.refresh()
    }
    Connections {
        target: Config
        function onEdited(key) {
            if (key.startsWith("weather"))
                cityDebounce.restart();
        }
    }
    Timer {
        id: cityDebounce
        interval: 800
        onTriggered: root.refresh()
    }
}
