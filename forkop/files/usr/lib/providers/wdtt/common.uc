#!/usr/bin/env ucode

let constants = require("core.constants");
let validator_module = null;

const LIB_DIR = getenv("FORKOP_LIB") || "/usr/lib/forkop";

function validator() {
    if (validator_module == null)
        validator_module = require("providers.wdtt.validator");
    return validator_module;
}

function config(ctx) {
    let runtime_constants = (ctx && ctx.constants) || constants;
    let lib_dir = (ctx && ctx.lib_dir) || LIB_DIR;

    return {
        kind: "wdtt",
        action: "wdtt",
        config_path: getenv("WDTT_CONFIG") || runtime_constants.WDTT_CONFIG,
        service_init: getenv("WDTT_SERVICE_INIT") || runtime_constants.WDTT_SERVICE_INIT,
        binary: getenv("WDTT_BIN") || runtime_constants.WDTT_BIN,
        genlists_bin: getenv("WDTT_GENLISTS_BIN") || runtime_constants.WDTT_GENLISTS_BIN,
        resolve_bin: getenv("WDTT_RESOLVE_BIN") || runtime_constants.WDTT_RESOLVE_BIN,
        state_dir: getenv("WDTT_STATE_DIR") || runtime_constants.WDTT_STATE_DIR,
        default_peer: getenv("WDTT_DEFAULT_PEER") || runtime_constants.WDTT_DEFAULT_PEER,
        default_workers: getenv("WDTT_DEFAULT_WORKERS") || runtime_constants.WDTT_DEFAULT_WORKERS,
        default_max_hashes: getenv("WDTT_DEFAULT_MAX_HASHES") || runtime_constants.WDTT_DEFAULT_MAX_HASHES,
        default_mode: getenv("WDTT_DEFAULT_MODE") || runtime_constants.WDTT_DEFAULT_MODE,
        default_mtu: getenv("WDTT_DEFAULT_MTU") || runtime_constants.WDTT_DEFAULT_MTU,
        default_refresh: getenv("WDTT_DEFAULT_REFRESH") || runtime_constants.WDTT_DEFAULT_REFRESH,
        community_lists: getenv("WDTT_COMMUNITY_LISTS") || runtime_constants.WDTT_COMMUNITY_LISTS,
        package_name: "wdtt",
        runtime_path: lib_dir + "/providers/wdtt/runtime.uc",
        config_name: "wdtt",
        status_label: "wdtt",
        check_prefix: "wdtt"
    };
}

return {
    config,
    validator
};
