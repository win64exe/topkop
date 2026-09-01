#!/usr/bin/env ucode
// WDTT provider runtime.
// Управляет standalone-клиентом WDTT (WireGuard-over-TURN Tunnel) из секций
// forkop с action=wdtt. Записывает /etc/config/wdtt (первоисточник:
// https://github.com/xDarkOne/wdtt-openwrt) и перезапускает сервис.

let fs = require("fs");
let uci_core = require("core.uci");
let runtime_constants = require("singbox.constants");
let validator_module = null;

const CONFIG_NAME = getenv("FORKOP_CONFIG_NAME") || "forkop";
const LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";

const WDTT_CONFIG = getenv("WDTT_CONFIG") || "/etc/config/wdtt";
const WDTT_SERVICE_INIT = getenv("WDTT_SERVICE_INIT") || "/etc/init.d/wdtt-client";
const WDTT_GENLISTS_BIN = getenv("WDTT_GENLISTS_BIN") || "/usr/sbin/wdtt-genlists";
const WDTT_RESOLVE_BIN = getenv("WDTT_RESOLVE_BIN") || "/usr/sbin/wdtt-resolve";
const WDTT_DEFAULT_PEER = getenv("WDTT_DEFAULT_PEER") || "YOUR_SERVER:56000";
const WDTT_DEFAULT_WORKERS = getenv("WDTT_DEFAULT_WORKERS") || "36";
const WDTT_DEFAULT_MAX_HASHES = getenv("WDTT_DEFAULT_MAX_HASHES") || "4";
const WDTT_DEFAULT_MODE = getenv("WDTT_DEFAULT_MODE") || "selective";
const WDTT_DEFAULT_MTU = getenv("WDTT_DEFAULT_MTU") || "1280";
const WDTT_DEFAULT_REFRESH = getenv("WDTT_DEFAULT_REFRESH") || "15m";

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
        validator_module = require("providers.wdtt.validator");
    return validator_module;
}

function enabled_wdtt_sections() {
    let result = [];
    for (let section in uci_sections("section"))
        if (bool_option(section, "enabled", true) && option(section, "action", "") == "wdtt")
            push(result, section);
    return result;
}

function enabled_rule_count() {
    return length(enabled_wdtt_sections());
}

function first_http_url(values) {
    for (let value in values)
        if (match(as_string(value), /^https?:\/\//i) != null)
            return as_string(value);
    return "";
}

function first_local_file(values) {
    for (let value in values)
        if (match(as_string(value), /^\//) != null)
            return as_string(value);
    return "";
}

// Первая qwdtt:// config ссылка из списка подписок.
function first_qwdtt_link(values) {
    for (let value in values)
        if (match(as_string(value), /^qwdtt:(\/\/)?config/i) != null)
            return as_string(value);
    return "";
}

// Записывает прямые VK-хэши из qwdtt:// ссылки в локальный файл (wdtt hashes_file).
function write_qwdtt_hashes_file(hashes_value) {
    let hashes = [];
    for (let item in split(as_string(hashes_value), /[ \t\r\n,]+/))
        if (as_string(item) != "")
            push(hashes, as_string(item));
    if (length(hashes) == 0)
        return "";

    let path = getenv("WDTT_HASHES_FILE") || "/etc/wdtt/vk-calls.txt";
    let content = join("\n", hashes) + "\n";
    if (!command_success_from_args([ "mkdir", "-p", "/etc/wdtt" ]))
        return "";

    let tmp_path = path + ".tmp";
    let handle = fs.open(tmp_path, "w");
    if (!handle)
        return "";
    handle.write(content);
    handle.close();
    if (!command_success_from_args([ "mv", tmp_path, path ]))
        return "";

    log_message("WDTT: wrote " + length(hashes) + " VK hashes from qwdtt:// link to " + path, "info");
    return path;
}

function provider_available() {
    return fs.stat(WDTT_CONFIG) != null;
}

function service_init_exists() {
    return fs.stat(WDTT_SERVICE_INIT) != null;
}

function service_running() {
    return service_init_exists() && command_success_from_args([ WDTT_SERVICE_INIT, "status" ]);
}

function service_enabled() {
    return service_init_exists() && command_success_from_args([ WDTT_SERVICE_INIT, "enabled" ]);
}

function lan_mac_address() {
    for (let iface in [ "br-lan", "lan", "eth0", "eth1" ]) {
        let address = trim(command_output_from_args([ "cat", "/sys/class/net/" + iface + "/address" ]));
        if (match(address, /^[0-9a-fA-F:]{17}$/) != null)
            return replace(lc(address), /:/g, "");
    }
    return "";
}

function uci_set_quote(value) {
    return shell_quote(as_string(value));
}

function write_wdtt_config(section) {
    let name = section_name(section);
    let subscription_links = list_option(section, "subscription_links");
    let hashes_url = option(section, "hashes_url", first_http_url(subscription_links));
    let hashes_file = option(section, "hashes_file", first_local_file(subscription_links));

    // qwdtt:// config ссылка: peer/pass/workers/port из ссылки, прямые хэши — в файл.
    let qwdtt_link = first_qwdtt_link(subscription_links);
    let qwdtt = "";
    if (qwdtt_link != "") {
        qwdtt = validator().parse_qwdtt_uri(qwdtt_link);
        if (qwdtt == null || !qwdtt.valid) {
            log_message("WDTT: invalid qwdtt:// link in section '" + name + "': " + (qwdtt && qwdtt.reason || "parse failed"), "error");
            qwdtt = "";
        }
        else if (qwdtt.hashes != "") {
            let written = write_qwdtt_hashes_file(qwdtt.hashes);
            if (written != "")
                hashes_file = written;
        }
    }

    let device_id = as_string(option(section, "device_id", ""));
    if (device_id == "")
        device_id = lan_mac_address();

    // Если qwdtt:// ссылка несёт прямые хэши, а max_hashes в секции не задан —
    // используем ровно столько, сколько хэшей в ссылке.
    let max_hashes = option(section, "max_hashes", WDTT_DEFAULT_MAX_HASHES);
    if (qwdtt && qwdtt.hashes != "" && option(section, "max_hashes", "") == "")
        max_hashes = "" + length(split(as_string(qwdtt.hashes), /[, \t\r\n]+/));

    let commands = [];
    let sets = {
        enabled: bool_option(section, "enabled", true) ? "1" : "0",
        peer: option(section, "peer", qwdtt && qwdtt.peer || WDTT_DEFAULT_PEER),
        password: option(section, "password", qwdtt && qwdtt.pass || ""),
        device_id: device_id,
        max_hashes: max_hashes,
        workers: option(section, "workers", qwdtt && qwdtt.workers || WDTT_DEFAULT_WORKERS),
        mode: option(section, "mode", WDTT_DEFAULT_MODE),
        mtu: option(section, "mtu", WDTT_DEFAULT_MTU),
        refresh: option(section, "refresh", WDTT_DEFAULT_REFRESH),
        auto_update: bool_option(section, "auto_update", true) ? "1" : "0",
        block_doh: bool_option(section, "block_doh", false) ? "1" : "0",
        block_ipv6: bool_option(section, "block_ipv6", false) ? "1" : "0"
    };

    if (qwdtt && qwdtt.port != "")
        sets.listen = "127.0.0.1:" + qwdtt.port;

    if (hashes_url != "")
        sets.hashes_url = hashes_url;
    if (hashes_file != "")
        sets.hashes_file = hashes_file;

    for (let key in sets)
        push(commands, "uci set wdtt.settings." + key + "=" + uci_set_quote(sets[key]));

    for (let key in [ "community_list", "remote_domain_list", "local_domain_list", "remote_subnet_list", "local_subnet_list", "fully_routed_ip" ]) {
        let values = list_option(section, key);
        push(commands, "uci -q delete wdtt.settings." + key);
        for (let value in values)
            push(commands, "uci add_list wdtt.settings." + key + "=" + uci_set_quote(value));
    }

    for (let command in commands)
        command_success_from_args([ "sh", "-c", command ]);

    command_success_from_args([ "uci", "commit", "wdtt" ]);
    log_message("WDTT section '" + name + "' written to " + WDTT_CONFIG, "info");
}

function start_runtime() {
    let sections = enabled_wdtt_sections();
    if (length(sections) == 0) {
        if (provider_available()) {
            command_success_from_args([ "uci", "set", "wdtt.settings.enabled=0" ]);
            command_success_from_args([ "uci", "commit", "wdtt" ]);
            if (service_init_exists())
                command_success_from_args([ WDTT_SERVICE_INIT, "stop" ]);
        }
        return;
    }

    if (!provider_available()) {
        log_message("WDTT is not installed (missing " + WDTT_CONFIG + "). Install it first (install.sh --with-wdtt or luci-app-wdtt). Aborted.", "fatal");
        exit(1);
    }

    // Несколько секций action=wdtt не поддерживаются — используем первую включённую.
    let section = sections[0];
    if (length(sections) > 1)
        log_message("Multiple action=wdtt sections are enabled; only '" + section_name(section) + "' is applied", "warn");

    write_wdtt_config(section);

    command_success_from_args([ "uci", "set", "wdtt.settings.enabled=1" ]);
    command_success_from_args([ "uci", "commit", "wdtt" ]);

    if (service_init_exists())
        command_success_from_args([ WDTT_SERVICE_INIT, "restart" ]);
    else
        log_message("WDTT service init script " + WDTT_SERVICE_INIT + " is missing", "fatal");

    // Обновляем список обходимых доменов/подсетей (nft set wdtt_dst4).
    if (fs.stat(WDTT_GENLISTS_BIN) != null)
        command_success_from_args([ WDTT_GENLISTS_BIN ]);
    if (fs.stat(WDTT_RESOLVE_BIN) != null)
        command_success_from_args([ WDTT_RESOLVE_BIN ]);
}

function stop_runtime() {
    if (!provider_available())
        return;
    command_success_from_args([ "uci", "set", "wdtt.settings.enabled=0" ]);
    command_success_from_args([ "uci", "commit", "wdtt" ]);
    if (service_init_exists())
        command_success_from_args([ WDTT_SERVICE_INIT, "stop" ]);
}

function status_json() {
    let sections = enabled_wdtt_sections();
    let configured = length(sections) > 0;
    let provider = provider_available();
    let init_exists = service_init_exists();
    let running = service_running();
    let enabled = service_enabled();
    let ready = configured && provider && init_exists && running;

    let message = "wdtt provider status is normal";
    if (configured && !provider)
        message = "action=wdtt is configured, but WDTT is not installed (missing " + WDTT_CONFIG + ")";
    else if (configured && !init_exists)
        message = "action=wdtt is configured, but the WDTT service " + WDTT_SERVICE_INIT + " is missing";
    else if (configured && !running)
        message = "action=wdtt is configured, but the wdtt-client service is not running";
    else if (!configured && !provider)
        message = "WDTT is not installed; action=wdtt is unavailable";

    write_json({
        installed: provider,
        configured,
        enabled_rule_count: length(sections),
        service_enabled: enabled,
        service_running: running,
        config_path: WDTT_CONFIG,
        service_init: WDTT_SERVICE_INIT,
        ready,
        status_message: message
    });
}

function check_json() {
    write_json({
        wdtt_installed: provider_available(),
        wdtt_config_path: WDTT_CONFIG
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
    warn("Usage: providers/wdtt/runtime.uc <start-runtime|stop-runtime|status|check|installed|enabled-rule-count>\n");
    exit(1);
}
