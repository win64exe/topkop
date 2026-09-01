#!/usr/bin/env ucode
// OlcRTC provider validator.
// OlcRTC (OpenLibreCommunity RTC) — TCP-over-WebRTC туннель. См. первоисточник:
//   https://github.com/openlibrecommunity/olcrtc (docs/uri.md, docs/sub.md)
//   https://github.com/skorp505/OlcRTC-OpenWRT
//
// Поддерживаемые форматы ссылок (из первоисточника):
//   Одиночный сервер: olcrtc://<Provider>?<Transport><key=value&...>@<RoomID>#<Key>$<MIMO>
//     olcrtc://jitsi?datachannel@https://meet.example.org/myroom#<64-hex>$RU / olc free sub
//   Подписка (sub.md): https://host/sub — plain-text файл со строками olcrtc://
//     и полями #name:, #refresh:, ##name:, ##comment: и т.д.
//   Провайдеры: jitsi, telemost, wbstream
//   Транспорты: datachannel, vp8channel, seichannel, videochannel

const OLCRTC_PROVIDERS = [ "jitsi", "telemost", "wbstream" ];
const OLCRTC_TRANSPORTS = [ "datachannel", "vp8channel", "seichannel", "videochannel" ];

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

function list_values(value) {
    if (type(value) == "array")
        return value;
    let result = [];
    for (let item in split(trim(as_string(value)), /[ \t\r\n]+/))
        if (item != "")
            push(result, item);
    return result;
}

function valid_url(value) {
    return match(as_string(value), /^https?:\/\/[^ \t\r\n]+$/i) != null;
}

function valid_number(value, min_value, max_value) {
    value = as_string(value);
    if (match(value, /^[0-9]+$/) == null)
        return false;
    let number = int(value, 10);
    return number >= min_value && number <= max_value;
}

function valid_hex_key(value) {
    value = as_string(value);
    return value == "" || (match(value, /^[0-9a-fA-F]{64}$/) != null);
}

function string_ends_with(value, suffix) {
    value = as_string(value);
    suffix = as_string(suffix);
    return length(value) >= length(suffix) && substr(value, length(value) - length(suffix)) == suffix;
}

// Парсит olcrtc:// URI по формату docs/uri.md:
//   olcrtc://<Provider>?<Transport><key=value&...>@<RoomID>#<Key>$<MIMO>
function parse_uri(value) {
    value = as_string(value);
    if (match(value, /^olcrtc:\/\//) == null)
        return null;

    let rest = replace(value, /^olcrtc:\/\//, "");
    let mimo = "";
    let crypto_key = "";
    let hash_pos = index(rest, "#");
    if (hash_pos >= 0) {
        let tail = substr(rest, hash_pos + 1);
        rest = substr(rest, 0, hash_pos);
        let dollar_pos = index(tail, "$");
        if (dollar_pos >= 0) {
            mimo = substr(tail, dollar_pos + 1);
            tail = substr(tail, 0, dollar_pos);
        }
        crypto_key = tail;
        if (match(crypto_key, /^[0-9a-fA-F]{64}$/) == null)
            return { valid: false, reason: "crypto key must be 64 hex chars in olcrtc:// URI" };
    }

    let at_pos = index(rest, "@");
    if (at_pos < 0)
        return { valid: false, reason: "olcrtc:// URI is missing @<RoomID>" };
    let room_id = substr(rest, at_pos + 1);
    let head = substr(rest, 0, at_pos);
    if (room_id == "")
        return { valid: false, reason: "olcrtc:// URI has empty RoomID" };

    let provider = "";
    let transport = "";
    let payload = "";
    let question_pos = index(head, "?");
    if (question_pos < 0) {
        provider = head;
    }
    else {
        provider = substr(head, 0, question_pos);
        let transport_part = substr(head, question_pos + 1);
        let payload_pos = index(transport_part, "<");
        if (payload_pos >= 0 && string_ends_with(transport_part, ">")) {
            payload = substr(transport_part, payload_pos + 1, length(transport_part) - payload_pos - 2);
            transport = substr(transport_part, 0, payload_pos);
        }
        else {
            transport = transport_part;
        }
    }

    if (provider == "")
        return { valid: false, reason: "olcrtc:// URI has empty Provider" };
    if (transport == "")
        return { valid: false, reason: "olcrtc:// URI has empty Transport" };

    let provider_ok = false;
    for (let item in OLCRTC_PROVIDERS)
        if (item == provider)
            provider_ok = true;
    if (!provider_ok)
        return { valid: false, reason: "unknown olcrtc provider '" + provider + "'. Supported: " + join(", ", OLCRTC_PROVIDERS) };

    let transport_ok = false;
    for (let item in OLCRTC_TRANSPORTS)
        if (item == transport)
            transport_ok = true;
    if (!transport_ok)
        return { valid: false, reason: "unknown olcrtc transport '" + transport + "'. Supported: " + join(", ", OLCRTC_TRANSPORTS) };

    return {
        valid: true,
        provider,
        transport,
        room_id,
        crypto_key,
        mimo,
        payload
    };
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

    let provider = as_string(section && section.provider || "");
    if (provider != "") {
        let provider_ok = false;
        for (let item in OLCRTC_PROVIDERS)
            if (item == provider)
                provider_ok = true;
        if (!provider_ok)
            push(errors, "provider must be one of: " + join(", ", OLCRTC_PROVIDERS));
    }

    let transport = as_string(section && section.transport || "");
    if (transport != "") {
        let transport_ok = false;
        for (let item in OLCRTC_TRANSPORTS)
            if (item == transport)
                transport_ok = true;
        if (!transport_ok)
            push(errors, "transport must be one of: " + join(", ", OLCRTC_TRANSPORTS));
    }

    if (!valid_hex_key(section && section.crypto_key || ""))
        push(errors, "crypto_key must be a 64-character hex string (openssl rand -hex 32)");

    let socks_port = as_string(section && section.socks_port || "");
    if (socks_port != "" && !valid_number(socks_port, 1, 65535))
        push(errors, "socks_port must be a number between 1 and 65535");

    let dns_server = as_string(section && section.dns_server || "");
    if (dns_server != "" && match(dns_server, /^[^ \t\r\n]+:[0-9]{1,5}$/) == null)
        push(errors, "dns_server must be a HOST:PORT (e.g. 8.8.8.8:53)");

    for (let link in list_values(section && section.subscription_links)) {
        link = as_string(link);
        if (link == "")
            continue;
        if (match(link, /^olcrtc:\/\//) != null) {
            let parsed = parse_uri(link);
            if (parsed == null || !parsed.valid)
                push(errors, (parsed && parsed.reason || "invalid olcrtc:// URI") + ": " + link);
        }
        else if (!valid_url(link)) {
            push(errors, "subscription link must be an olcrtc:// URI or an http(s) sub.md subscription URL: " + link);
        }
    }

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
        write_json(validation_result(true, "OlcRTC section is valid"));
}

function module_exports() {
    return {
        validate_section,
        parse_uri,
        valid_hex_key,
        providers: OLCRTC_PROVIDERS,
        transports: OLCRTC_TRANSPORTS
    };
}

if (sourcepath(1) != null && sourcepath(1) != "")
    return module_exports();

let mode = ARGV[0] || "";
if (mode == "validate-json")
    validate_section_json();
else {
    warn("Usage: providers/olcrtc/validator.uc <validate-json>\n");
    exit(1);
}
