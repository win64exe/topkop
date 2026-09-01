#!/usr/bin/env ucode

let constants = require("core.constants");
let validator_module = null;

const LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";

function validator() {
    if (validator_module == null)
        validator_module = require("providers.olcrtc.validator");
    return validator_module;
}

function config(ctx) {
    let runtime_constants = (ctx && ctx.constants) || constants;
    let lib_dir = (ctx && ctx.lib_dir) || LIB_DIR;

    return {
        kind: "olcrtc",
        action: "olcrtc",
        config_path: getenv("OLCRTC_CONFIG") || runtime_constants.OLCRTC_CONFIG,
        binary: getenv("OLCRTC_BIN") || runtime_constants.OLCRTC_BIN,
        service_init: getenv("OLCRTC_SERVICE_INIT") || runtime_constants.OLCRTC_SERVICE_INIT,
        state_dir: getenv("OLCRTC_STATE_DIR") || runtime_constants.OLCRTC_STATE_DIR,
        default_socks_host: getenv("OLCRTC_DEFAULT_SOCKS_HOST") || runtime_constants.OLCRTC_DEFAULT_SOCKS_HOST,
        default_socks_port: getenv("OLCRTC_DEFAULT_SOCKS_PORT") || runtime_constants.OLCRTC_DEFAULT_SOCKS_PORT,
        default_dns: getenv("OLCRTC_DEFAULT_DNS") || runtime_constants.OLCRTC_DEFAULT_DNS,
        default_provider: getenv("OLCRTC_DEFAULT_PROVIDER") || runtime_constants.OLCRTC_DEFAULT_PROVIDER,
        default_transport: getenv("OLCRTC_DEFAULT_TRANSPORT") || runtime_constants.OLCRTC_DEFAULT_TRANSPORT,
        package_name: "olcrtc",
        runtime_path: lib_dir + "/providers/olcrtc/runtime.uc",
        config_name: "olcrtc",
        status_label: "olcrtc",
        check_prefix: "olcrtc"
    };
}

return {
    config,
    validator
};
