pragma Singleton
import QtQuick
import Quickshell

// The notch's language (Config `language`): English or Bahasa Indonesia.
// Text is written as both, side by side: Lang.t("No classes", "Tidak ada
// jadwal"). Bindings that call it follow a change of language.
Singleton {
    readonly property string code: Config.opts.language === "id" ? "id" : "en"
    readonly property bool id: code === "id"

    function t(en, id) {
        return code === "id" ? id : en;
    }

    // "KKA · in 5 min" / "KKA · mulai 5 mnt lagi", for something at `at` (ms).
    function startsIn(title, at, now) {
        const m = Math.max(1, Math.ceil((at - now) / 60000));
        return t(`${title} · in ${m} min`, `${title} · mulai ${m} mnt lagi`);
    }
    // "3 due today" / "3 tenggat hari ini".
    function dueToday(n) {
        return t(`${n} due today`, `${n} tenggat hari ini`);
    }
    // "3 due" / "3 tenggat".
    function due(n) {
        return t(`${n} due`, `${n} tenggat`);
    }
    // "just now" / "baru saja", "4 min ago" / "4 mnt lalu".
    function ago(ms, now) {
        const m = Math.round((now - ms) / 60000);
        return m < 1 ? t("just now", "baru saja") : t(`${m} min ago`, `${m} mnt lalu`);
    }
    readonly property var months: id ? ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"] : ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var days: id ? ["MINGGU", "SENIN", "SELASA", "RABU", "KAMIS", "JUMAT", "SABTU"] : ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
}
