#include "settings.h"

#include <system_error>

#include "json.h"
#include "store.h"

namespace fs = std::filesystem;

namespace shunti {

bool load_settings(const fs::path& p, Settings& s) {
    s = Settings();
    std::string text;
    if (!read_file(p, text)) return false;
    json::Value v;
    if (!json::Parser(text).parse(v) || v.type != json::Value::Object) return false;
    auto str = [&](const char* k, std::string& out) {
        const json::Value* x = v.get(k);
        if (x && x->type == json::Value::String) out = x->str;
    };
    auto boolean = [&](const char* k, bool& out) {
        const json::Value* x = v.get(k);
        if (x && x->type == json::Value::Bool) out = x->b;
    };
    str("theme", s.theme);
    boolean("space_fullwidth", s.space_fullwidth);
    boolean("digits_fullwidth", s.digits_fullwidth);
    boolean("live", s.live);
    boolean("live_commit", s.live_commit);
    boolean("live_display", s.live_display);
    boolean("ctrl_space", s.ctrl_space);
    str("model", s.model);
    if (const json::Value* x = v.get("punct"); x && x->type == json::Value::Number) s.punct = int(x->num) & 3;
    return true;
}

bool save_settings(const fs::path& p, const Settings& s) {
    auto b = [](bool x) { return x ? "true" : "false"; };
    std::string o = "{\n";
    o += "  \"theme\": " + json::quote(s.theme) + ",\n";
    o += std::string("  \"space_fullwidth\": ") + b(s.space_fullwidth) + ",\n";
    o += "  \"punct\": " + std::to_string(s.punct) + ",\n";
    o += std::string("  \"digits_fullwidth\": ") + b(s.digits_fullwidth) + ",\n";
    o += std::string("  \"live\": ") + b(s.live) + ",\n";
    o += std::string("  \"live_commit\": ") + b(s.live_commit) + ",\n";
    o += std::string("  \"live_display\": ") + b(s.live_display) + ",\n";
    o += std::string("  \"ctrl_space\": ") + b(s.ctrl_space) + ",\n";
    o += "  \"model\": " + json::quote(s.model) + "\n";
    o += "}\n";
    return write_file_atomic(p, o);
}

const char* model_file_name(const std::string& model) {
    if (model == "light") return "kkc_model_light.bin";
    if (model == "high") return "kkc_model_high.bin";
    return "kkc_model.bin";
}

bool SettingsFile::refresh() {
    std::error_code ec;
    fs::file_time_type t = fs::last_write_time(path_, ec);
    bool exists = !ec;
    if (loaded_ && (!exists || t == stamp_)) return false;
    loaded_ = true;
    stamp_ = t;
    load_settings(path_, s_);
    return true;
}

}  // namespace shunti
