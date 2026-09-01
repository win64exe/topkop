#!/usr/bin/env ucode

let fs = require("fs");

// WDTT provider validator.
// WDTT (WireGuard-over-TURN Tunnel) — см. первоисточник:
//   https://github.com/xDarkOne/wdtt-openwrt
//   https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb
//
// Поддерживаемые форматы ссылок (из первоисточника):
//   hashes_url   http://SERVER:56090/TOKEN/links?n=4  (+ &slot=N)
//   hashes_file  /etc/wdtt/vk-calls.txt (локальный файл с токенами звонков)
//   peer         HOST:PORT (DTLS-эндпоинт сервера, напр. server:56000)
//   remote_domain_list  https://example.com/domains.txt
//   community_list      russia-inside, telegram, meta, youtube, ... (itdoginfo/allow-domains)

const WDTT_MODES = [ "selective", "lan-all", "full" ];
const WDTT_COMMUNITY_LISTS = split(getenv("WDTT_COMMUNITY_LISTS") || "russia-inside russia-outside ukraine telegram meta youtube discord tiktok twitter hdrezka roblox cloudflare cloudfront google_ai google_meet google_play hetzner ovh digitalocean anime news geoblock block porn hodca", " ");

function as_string(value) {
    return value == null ? "" : "" + value;
}

function write_json(value) {
    print(sprintf("%J", value), "\n");
}

function read_stdin() {
    let input = fs.open("/dev/stdin", "r");
    if (!input)
        return "";
    let data = input.read("all");
    input.close();
    return data == null ? "" : data;
}

function read_stdin_json() {
    try {
        return json(read_stdin());
    }
    catch (e) {
        return null;
    }
}

function valid_url(value) {
    return match(as_string(value), /^https?:\/\/[^ \t\r\n]+$/i) != null;
}

function valid_peer(value) {
    return match(as_string(value), /^[^ \t\r\n:]+:[0-9]{1,5}$/) != null;
}

function valid_number(value, min_value, max_value) {
    value = as_string(value);
    if (match(value, /^[0-9]+$/) == null)
        return false;
    let number = int(value, 10);
    return number >= min_value && number <= max_value;
}

// Декодирует percent-encoding (%2C -> ',', %3A -> ':', '+' -> ' ').
function url_decode(value) {
    value = as_string(value);
    let result = "";
    for (let i = 0; i < length(value);) {
        let ch = substr(value, i, 1);
        if (ch == "%" && i + 2 < length(value)) {
            let hex = substr(value, i + 1, 2);
            if (match(hex, /^[0-9a-fA-F]{2}$/) != null) {
                result += sprintf("%c", int(hex, 16));
                i += 3;
                continue;
            }
        }
        result += ch == "+" ? " " : ch;
        i++;
    }
    return result;
}

// Парсит qwdtt:// ссылку по формату qwdtt-android (SpaceNeuroX/proxy-turn-vk-android):
//   qwdtt://config?hashes=H1,H2,...&name=NAME&pass=PASS&peer=HOST:PORT&port=PORT&workers=N
// Поля (из SubscriptionImport.kt): name, peer (обязательный), hashes (через запятую,
// URL-encoded %2C), workers (default 9), port (default 9000), pass/password.
function parse_qwdtt_uri(value) {
    value = trim(as_string(value));
    if (match(value, /^qwdtt:(\/\/)?config(\?|$)/i) == null)
        return null;

    let query = replace(value, /^qwdtt:(\/\/)?config/i, "");
    query = replace(query, /^\?/, "");
    let params = {};
    for (let pair in split(query, "&")) {
        pair = as_string(pair);
        let eq = index(pair, "=");
        if (eq < 0)
            continue;
        let key = substr(pair, 0, eq);
        let val = url_decode(substr(pair, eq + 1));
        params[key] = val;
    }

    let peer = as_string(params.peer || "");
    let hashes = as_string(params.hashes || "");
    let name = as_string(params.name || "");
    let pass = as_string(params.pass || params.password || "");
    let workers = as_string(params.workers || "");
    let port = as_string(params.port || "");

    if (peer == "")
        return { valid: false, reason: "qwdtt:// URI is missing the peer=HOST:PORT parameter" };
    if (!valid_peer(peer))
        return { valid: false, reason: "qwdtt:// peer must be HOST:PORT (e.g. server:56000)" };
    if (workers != "" && !valid_number(workers, 1, 1024))
        return { valid: false, reason: "qwdtt:// workers must be a number between 1 and 1024" };
    if (port != "" && !valid_number(port, 1, 65535))
        return { valid: false, reason: "qwdtt:// port must be a number between 1 and 65535" };

    return {
        valid: true,
        peer,
        hashes,
        name,
        pass,
        workers,
        port
    };
}

function valid_mode(value) {
    for (let mode in WDTT_MODES)
        if (mode == as_string(value))
            return true;
    return false;
}

function valid_community_list(value) {
    for (let item in WDTT_COMMUNITY_LISTS)
        if (item == as_string(value))
            return true;
    return false;
}

function list_values(value) {
    if (type(value) == "array")
        return value;
    let result = [];
    for (let item in split(trim(as_string(value)), /[ \t\r\n]+/))
        if (item != "")
            push(result, item);
    return result;
}

function validation_result(valid, message, options) {
    let result = { valid: valid, message: as_string(message) };
    if (type(options) == "object")
        for (let key in options)
            result[key] = options[key];
    return result;
}

function validate_section(section) {
    let errors = [];

    let peer = as_string(section && section.peer || "");
    if (peer != "" && !valid_peer(peer))
        push(errors, "peer must be a HOST:PORT endpoint (e.g. server:56000)");

    let mode = as_string(section && section.mode || WDTT_MODES[0]);
    if (mode != "" && !valid_mode(mode))
        push(errors, "mode must be one of: selective, lan-all, full");

    let workers = as_string(section && section.workers || "");
    if (workers != "" && !valid_number(workers, 1, 1024))
        push(errors, "workers must be a number between 1 and 1024 (wdtt uses 9 workers per call-hash)");

    let max_hashes = as_string(section && section.max_hashes || "");
    if (max_hashes != "" && !valid_number(max_hashes, 1, 64))
        push(errors, "max_hashes must be a number between 1 and 64");

    let mtu = as_string(section && section.mtu || "");
    if (mtu != "" && !valid_number(mtu, 576, 1500))
        push(errors, "mtu must be a number between 576 and 1500");

    for (let link in list_values(section && section.subscription_links)) {
        link = as_string(link);
        if (link == "")
            continue;
        if (match(link, /^qwdtt:(\/\/)?config/i) != null) {
            let parsed = parse_qwdtt_uri(link);
            if (parsed == null || !parsed.valid)
                push(errors, (parsed && parsed.reason || "invalid qwdtt:// URI") + ": " + link);
        }
        else if (!valid_url(link) && !match(link, /^\/[^ \t\r\n]+$/))
            push(errors, "subscription link must be a wdtt hashes_url (http://SERVER:56090/TOKEN/links?n=4), a qwdtt:// config link (qwdtt://config?peer=...&hashes=...), a remote domain list URL (https://example.com/domains.txt) or a local file path (/etc/wdtt/vk-calls.txt): " + link);
    }

    for (let list_id in list_values(section && section.community_lists))
        if (list_id != "" && !valid_community_list(list_id))
            push(errors, "unknown WDTT community list '" + list_id + "'. Supported: " + join(", ", WDTT_COMMUNITY_LISTS));

    for (let url in list_values(section && section.remote_domain_list))
        if (url != "" && !valid_url(url))
            push(errors, "remote_domain_list entries must be http(s) URLs: " + as_string(url));

    return errors;
}

function validate_section_json() {
    let section = read_stdin_json();
    if (type(section) != "object") {
        write_json(validation_result(false, "expected a JSON section object"));
        return;
    }

    let errors = validate_section(section);
    if (length(errors) > 0)
        write_json(validation_result(false, join("; ", errors), { errors }));
    else
        write_json(validation_result(true, "WDTT section is valid"));
}

function module_exports() {
    return {
        validate_section,
        parse_qwdtt_uri,
        url_decode,
        valid_peer,
        valid_mode,
        valid_url,
        valid_community_list,
        modes: WDTT_MODES,
        community_lists: WDTT_COMMUNITY_LISTS
    };
}

if (sourcepath(1) != null && sourcepath(1) != "")
    return module_exports();

let mode = ARGV[0] || "";
if (mode == "validate-json")
    validate_section_json();
else {
    warn("Usage: providers/wdtt/validator.uc <validate-json>\n");
    exit(1);
}
