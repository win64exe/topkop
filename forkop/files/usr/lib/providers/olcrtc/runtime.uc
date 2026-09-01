#!/usr/bin/env ucode
// OlcRTC provider runtime.
// Управляет standalone-клиентом OlcRTC из секций forkop с action=olcrtc.
// Принимает подписки в форматах первоисточника (docs/uri.md, docs/sub.md):
//   olcrtc://<Provider>?<Transport>@<RoomID>#<Key>$<MIMO>  — одиночный сервер
//   https://host/sub                                       — sub.md-подписка
// Разрешает параметры подключения и пишет /etc/config/olcrtc, после чего
// /etc/init.d/olcrtc генерирует /etc/olcrtc/client.yaml и запускает клиент.

let fs = require("fs");
let uci_core = require("core.uci");
let validator_module = null;

const CONFIG_NAME = getenv("FORKOP_CONFIG_NAME") || "forkop";
const LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";

const OLCRTC_CONFIG = getenv("OLCRTC_CONFIG") || "/etc/olcrtc/client.yaml";
const OLCRTC_BIN = getenv("OLCRTC_BIN") || "/usr/bin/olcrtc";
const OLCRTC_SERVICE_INIT = getenv("OLCRTC_SERVICE_INIT") || "/etc/init.d/olcrtc";
const OLCRTC_DEFAULT_SOCKS_HOST = getenv("OLCRTC_DEFAULT_SOCKS_HOST") || "127.0.0.1";
const OLCRTC_DEFAULT_SOCKS_PORT = getenv("OLCRTC_DEFAULT_SOCKS_PORT") || "1080";
const OLCRTC_DEFAULT_DNS = getenv("OLCRTC_DEFAULT_DNS") || "8.8.8.8:53";
const OLCRTC_DEFAULT_PROVIDER = getenv("OLCRTC_DEFAULT_PROVIDER") || "jitsi";
const OLCRTC_DEFAULT_TRANSPORT = getenv("OLCRTC_DEFAULT_TRANSPORT") || "datachannel";
const SUBSCRIPTION_TIMEOUT_SECONDS = "20";

function as_string(value) {
    return value == null ? "" : "" + value;
}

function bool_value(value) {
    value = lc(as_string(value));
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

function write_json(value) {
    print(sprintf("%J", value), "\n");
}

function shell_quote(value) {
    return "'" + replace(as_string(value), /'/g, "'\\''") + "'";
}

function command_from_args(args) {
    let parts = [];
    for (let arg in args)
        push(parts, shell_quote(arg));
    return join(" ", parts);
}

function command_output(command) {
    let pipe = fs.popen(command, "r");
    if (!pipe)
        return "";
    let data = pipe.read("all");
    let status = pipe.close();
    if (status != 0 || data == null)
        return "";
    return as_string(data);
}

function command_output_from_args(args) {
    return command_output(command_from_args(args));
}

function command_success_from_args(args) {
    return system(command_from_args(args) + " >/dev/null 2>&1") == 0;
}

function log_message(message, level) {
    level = as_string(level || "info");
    command_success_from_args([ "logger", "-t", "forkop", "[" + level + "] " + as_string(message) ]);
}

function object_or_empty(value) {
    return type(value) == "object" ? value : {};
}

function array_or_empty(value) {
    return type(value) == "array" ? value : [];
}

function option(section, key, fallback) {
    if (fallback == null)
        fallback = "";
    let value = object_or_empty(section)[key];
    if (value == null)
        return fallback;
    if (type(value) == "array")
        return join(" ", value);
    return as_string(value);
}

function bool_option(section, key, fallback) {
    let value = object_or_empty(section)[key];
    return value == null ? !!fallback : bool_value(value);
}

function list_option(section, key) {
    let value = object_or_empty(section)[key];
    if (value == null)
        return [];
    if (type(value) == "array")
        return value;
    value = trim(as_string(value));
    return value == "" ? [] : split(value, " ");
}

function section_name(section) {
    return as_string(object_or_empty(section)[".name"]);
}

function uci_sections(type_name) {
    return uci_core.section_objects(CONFIG_NAME, as_string(type_name));
}

function validator() {
    if (validator_module == null)
        validator_module = require("providers.olcrtc.validator");
    return validator_module;
}

function enabled_olcrtc_sections() {
    let result = [];
    for (let section in uci_sections("section"))
        if (bool_option(section, "enabled", true) && option(section, "action", "") == "olcrtc")
            push(result, section);
    return result;
}

function enabled_rule_count() {
    return length(enabled_olcrtc_sections());
}

function provider_available() {
    return fs.stat(OLCRTC_BIN) != null;
}

function service_init_exists() {
    return fs.stat(OLCRTC_SERVICE_INIT) != null;
}

function service_running() {
    return service_init_exists() && command_success_from_args([ OLCRTC_SERVICE_INIT, "status" ]);
}

function service_enabled() {
    return service_init_exists() && command_success_from_args([ OLCRTC_SERVICE_INIT, "enabled" ]);
}

function yaml_quote(value) {
    return "'" + replace(as_string(value), /'/g, "''") + "'";
}

function uci_set_quote(value) {
    return shell_quote(as_string(value));
}

// Скачивает URL (curl → wget → uclient-fetch), возвращает содержимое или "".
function fetch_url(url) {
    let tmp = "/tmp/forkop-olcrtc-sub";
    if (command_success_from_args([ "curl", "-fsSL", "--max-time", SUBSCRIPTION_TIMEOUT_SECONDS, "-o", tmp, as_string(url) ]))
        return fs.readfile(tmp) || "";
    if (command_success_from_args([ "wget", "-q", "-T", SUBSCRIPTION_TIMEOUT_SECONDS, "-O", tmp, as_string(url) ]))
        return fs.readfile(tmp) || "";
    if (command_success_from_args([ "uclient-fetch", "-q", "-T", SUBSCRIPTION_TIMEOUT_SECONDS, "-O", tmp, as_string(url) ]))
        return fs.readfile(tmp) || "";
    return "";
}

// Достаёт первую olcrtc:// строку из sub.md-подписки.
function first_uri_from_subscription(data) {
    for (let line in split(as_string(data), "\n")) {
        line = trim(as_string(line));
        if (match(line, /^olcrtc:\/\//) != null)
            return line;
    }
    return "";
}

// Разрешает параметры подключения для секции:
// 1) берёт первую подписку (olcrtc:// URI или sub.md URL);
// 2) переопределяет поля, заданные в секции вручную.
function resolve_connection(section) {
    let links = list_option(section, "subscription_links");
    let parsed = null;
    let used_link = "";
    let subscription_refresh = "";
    let subscription_name = "";

    for (let link in links) {
        link = as_string(link);
        if (link == "")
            continue;
        if (match(link, /^olcrtc:\/\//) != null) {
            parsed = validator().parse_uri(link);
            used_link = link;
            break;
        }
        if (match(link, /^https?:\/\//i) != null) {
            let data = fetch_url(link);
            if (data == "") {
                log_message("Failed to fetch OlcRTC subscription " + link, "warn");
                continue;
            }
            let uri = first_uri_from_subscription(data);
            if (uri == "") {
                log_message("OlcRTC subscription " + link + " contains no olcrtc:// entries", "warn");
                continue;
            }
            parsed = validator().parse_uri(uri);
            if (parsed != null && parsed.valid) {
                // глобальные поля подписки #name: / #refresh:
                for (let line in split(data, "\n")) {
                    line = trim(as_string(line));
                    if (subscription_name == "" && match(line, /^#name:[ \t]*/) != null)
                        subscription_name = trim(replace(line, /^#name:[ \t]*/, ""));
                    if (subscription_refresh == "" && match(line, /^#refresh:[ \t]*/) != null)
                        subscription_refresh = trim(replace(line, /^#refresh:[ \t]*/, ""));
                }
            }
            used_link = link;
            break;
        }
    }

    if (parsed == null || !parsed.valid) {
        let reason = parsed && parsed.reason ? parsed.reason : "no usable olcrtc:// URI or sub.md subscription link";
        return { valid: false, reason: reason, used_link: used_link };
    }

    return {
        valid: true,
        provider: option(section, "provider", parsed.provider),
        transport: option(section, "transport", parsed.transport),
        room_id: option(section, "room_id", parsed.room_id),
        crypto_key: option(section, "crypto_key", parsed.crypto_key),
        mimo: parsed.mimo,
        used_link: used_link,
        subscription_name: subscription_name,
        subscription_refresh: subscription_refresh
    };
}

function write_olcrtc_config(section, connection) {
    let name = section_name(section);
    let socks_host = option(section, "socks_host", OLCRTC_DEFAULT_SOCKS_HOST);
    let socks_port = option(section, "socks_port", OLCRTC_DEFAULT_SOCKS_PORT);
    if (match(socks_port, /^[0-9]+$/) == null || int(socks_port, 10) < 1 || int(socks_port, 10) > 65535)
        socks_port = OLCRTC_DEFAULT_SOCKS_PORT;

    let commands = [
        "uci set olcrtc.config.carrier=" + uci_set_quote(connection.provider),
        "uci set olcrtc.config.transport=" + uci_set_quote(connection.transport),
        "uci set olcrtc.config.room_id=" + uci_set_quote(connection.room_id),
        "uci set olcrtc.config.key=" + uci_set_quote(connection.crypto_key),
        "uci set olcrtc.config.socks_host=" + uci_set_quote(socks_host),
        "uci set olcrtc.config.socks_port=" + uci_set_quote(socks_port),
        "uci set olcrtc.config.dns=" + uci_set_quote(option(section, "dns_server", OLCRTC_DEFAULT_DNS)),
        "uci set olcrtc.config.socks_user=" + uci_set_quote(option(section, "socks_user", "")),
        "uci set olcrtc.config.socks_pass=" + uci_set_quote(option(section, "socks_pass", ""))
    ];

    for (let command in commands)
        command_success_from_args([ "sh", "-c", command ]);

    command_success_from_args([ "uci", "commit", "olcrtc" ]);
    log_message("OlcRTC section '" + name + "' written to /etc/config/olcrtc (source: " + connection.used_link + ")", "info");
}

function start_runtime() {
    let sections = enabled_olcrtc_sections();
    if (length(sections) == 0) {
        if (service_init_exists())
            command_success_from_args([ OLCRTC_SERVICE_INIT, "stop" ]);
        return;
    }

    if (!provider_available()) {
        log_message("OlcRTC is not installed (missing " + OLCRTC_BIN + "). Install it first (luci-app-olcrtc / OlcRTC-OpenWRT). Aborted.", "fatal");
        exit(1);
    }

    if (!service_init_exists()) {
        log_message("OlcRTC service init script " + OLCRTC_SERVICE_INIT + " is missing. Aborted.", "fatal");
        exit(1);
    }

    // Несколько секций action=olcrtc не поддерживаются — используем первую включённую.
    let section = sections[0];
    if (length(sections) > 1)
        log_message("Multiple action=olcrtc sections are enabled; only '" + section_name(section) + "' is applied", "warn");

    let connection = resolve_connection(section);
    if (!connection.valid) {
        log_message("OlcRTC section '" + section_name(section) + "' has no valid subscription: " + connection.reason + ". Aborted.", "fatal");
        exit(1);
    }

    write_olcrtc_config(section, connection);
    command_success_from_args([ OLCRTC_SERVICE_INIT, "restart" ]);
}

function stop_runtime() {
    if (service_init_exists())
        command_success_from_args([ OLCRTC_SERVICE_INIT, "stop" ]);
}

function status_json() {
    let sections = enabled_olcrtc_sections();
    let configured = length(sections) > 0;
    let provider = provider_available();
    let init_exists = service_init_exists();
    let running = service_running();
    let enabled = service_enabled();
    let ready = configured && provider && init_exists && running;

    let message = "olcrtc provider status is normal";
    if (configured && !provider)
        message = "action=olcrtc is configured, but OlcRTC is not installed (missing " + OLCRTC_BIN + ")";
    else if (configured && !init_exists)
        message = "action=olcrtc is configured, but the OlcRTC service " + OLCRTC_SERVICE_INIT + " is missing";
    else if (configured && !running)
        message = "action=olcrtc is configured, but the olcrtc service is not running";

    write_json({
        installed: provider,
        configured,
        enabled_rule_count: length(sections),
        service_enabled: enabled,
        service_running: running,
        config_path: OLCRTC_CONFIG,
        binary: OLCRTC_BIN,
        service_init: OLCRTC_SERVICE_INIT,
        ready,
        status_message: message
    });
}

function check_json() {
    write_json({
        olcrtc_installed: provider_available(),
        olcrtc_config_path: OLCRTC_CONFIG
    });
}

let mode = ARGV[0] || "";

if (mode == "start-runtime")
    start_runtime();
else if (mode == "stop-runtime")
    stop_runtime();
else if (mode == "status")
    status_json();
else if (mode == "check")
    check_json();
else if (mode == "installed" || mode == "provider-available")
    exit(provider_available() ? 0 : 1);
else if (mode == "enabled-rule-count")
    print(enabled_rule_count(), "\n");
else {
    warn("Usage: providers/olcrtc/runtime.uc <start-runtime|stop-runtime|status|check|installed|enabled-rule-count>\n");
    exit(1);
}
