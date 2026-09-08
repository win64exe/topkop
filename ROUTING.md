# Маршрутизация трафика через qwdtt (WDTT) и OlcRTC

Topkop запускает qwdtt (WDTT) и OlcRTC как **standalone-туннели**: каждый
клиент поднимает собственный SOCKS5-порт (или TUN в режиме `rawtun`), а
**sing-box уже подключён к этим туннелям** — для секций с локальным
SOCKS5-эндпоинтом (`olcrtc` всегда, `wdtt` в режиме `socks`) автоматически
создаётся sing-box **socks-outbound**, условия секции (домены, WDTT community
lists, rule-sets, IP-списки) маршрутизируются через туннель, и доступен
**«прокси для браузера»** (per-section mixed proxy). В режиме `rawtun` qwdtt
по-прежнему перехватывает LAN-трафик самостоятельно (см. раздел 1.1).

---

## 1. qwdtt (WDTT) — 3 режима клиента

Клиент: `/usr/bin/qwdtt-client`, конфиг: `/etc/qwdtt/config.json`
(генерирует `providers/wdtt/runtime.uc` из секции action=`wdtt`).

Поле `qwdtt_mode` (в LuCI: **«режим клиента qwdtt»**):
`rawtun` | `vpn` | `socks`.

### 1.1. Режим `rawtun` — RAW-IP туннель (по умолчанию для OpenWrt)

Самый «прозрачный» режим: **весь трафик с LAN-интерфейса уходит в туннель
автоматически, без настройки прокси на клиентах** и без участия sing-box.

1. Клиент коннектится к TURN-релею (`peer`, например `olcrtc.931094.xyz:56000`)
   и отправляет `AUTH` + `GETCONF_RAW:device_id|password`.
2. Сервер отвечает `RAWCONF:ip|dns|mtu` — IP-адрес для туннеля назначает сервер.
3. Клиент создаёт TUN `qwdtt0` через `/dev/net/tun` и выполняет:

   ```
   ip addr replace <ip>/16 dev qwdtt0          # адрес из RAWCONF (напр. 10.70.0.2)
   ip link set dev qwdtt0 mtu <mtu> up
   ip route replace default dev qwdtt0 table 51820
   ip rule add iif <lan_interface> lookup 51820 priority 10000
   echo 1 > /proc/sys/net/ipv4/ip_forward
   ```

   где `lan_interface` по умолчанию `br-lan`.
4. Итог: правило `iif br-lan lookup 51820` отправляет **весь исходящий трафик
   с LAN** в отдельную таблицу маршрутизации `51820`, где default-маршрут ведёт
   в `qwdtt0` → и дальше по RTP-obfs-каналу на сервер.
5. При остановке клиента правила и интерфейс удаляются (`cleanup()`).

> ⚠️ Требование: сервер должен поддерживать протокол RAWCONF (серверы wdtt /
> qwdtt из первоисточников). Если сервер — это только OlcRTC/SOCKS5-TURN
> (без RAWCONF), TUN не поднимется (timeout ответа). Проверка в работе
> показала, что `olcrtc.931094.xyz:56000` отвечает на TURN/WG, но не на RAWCONF.

> 📌 Проверено на роутере: пока qwdtt работает в `socks`/`vpn`, TUN-интерфейсов
> нет вовсе (только `lo`, `eth0`, `eth1`, `br-lan`), правила `51820` нет.
> `/dev/net/tun` существует, так что `rawtun` возможен при подходящем сервере.

### 1.2. Режим `vpn` — userspace WireGuard (без локального SOCKS)

1. Клиент запрашивает у сервера WG-конфиг (`GETCONF:localPort|device|password`).
2. Сервер выдаёт WireGuard-настройки (Address `10.66.x.x/32`, Endpoint
   `127.0.0.1:9000` — TURN-мост).
3. В полной сборке клиент **сохраняет конфиг в `wg-turn.conf`** — для режима
   `vpn` (без `-mode socks`) сам WG не поднимает (поднимает внешний инструмент).
4. У режима `vpn` **нет локального SOCKS5-эндпоинта**, поэтому sing-box
   outbound для секции **не создаётся** и «прокси для браузера» недоступен.
   **Для работы прямо на роутере используйте режим `socks`** — там клиент сам
   поднимает userspace WG поверх TURN и открывает SOCKS5.

### 1.3. Режим `socks` — локальный SOCKS5 + userspace WireGuard ✅ (рабочий)

Лучший режим для проверки и интеграции с sing-box: клиент **сам поднимает
userspace WireGuard** (через `netstack`, без kernel-TUN) поверх TURN-моста и
открывает **локальный SOCKS5** на `socks_addr` (по умолчанию
`127.0.0.1:1080`; на роутере секция настроена на `127.0.0.1:1081`).

```
приложение/curl -x socks5h://127.0.0.1:1081
        → SOCKS5-сервер qwdtt (mode socks)
        → userspace WireGuard (10.66.0.3, endpoint 127.0.0.1:9000 — TURN)
        → TURN-релей olcrtc.931094.xyz:56000
        → VPS 157.254.131.11
```

Для этой секции sing-box автоматически создаёт outbound
`<имя_секции>-out` (socks → `socks_addr`), а сам клиент НЕ поднимает TUN
и не перехватывает LAN — трафик идёт через sing-box по условиям секции
(см. раздел 3).

DNS в режиме socks резолвится клиентом (netstack-резолвер), в config.json
задаётся `dns: yandex|cloudflare|...`.

---

## 2. OlcRTC — SOCKS5-туннель через WebRTC-канал

Клиент: `/usr/bin/olcrtc`, конфиг: `/etc/olcrtc/client.yaml`
(генерирует `/etc/init.d/olcrtc` из uci-конфига, который пишет
`providers/olcrtc/runtime.uc` из секции action=`olcrtc`).

OlcRTC **всегда работает как SOCKS5-прокси** на `socks_host:socks_port`
(по умолчанию `127.0.0.1:1080`):

```
приложение/curl -x socks5h://127.0.0.1:1080
        → SOCKS5-сервер olcrtc (127.0.0.1:1080)
        → WebRTC-канал (transport: datachannel | vp8channel | seichannel | videochannel)
          по carrier (jitsi/wbstream/livekit…) с комнатой room_id и ключом
        → VPS 157.254.131.11
```

Ключевые параметры из `olcrtc://`-ссылки:
- `olcrtc://wbstream?vp8channel<vp8-fps=60&vp8-batch=64>@room#key` →
  carrier=wbstream, transport=vp8channel, room, key, payload-опции (fps/batch).
- `olcrtc://jitsi?datachannel@https://conf.hyperia.space/room#key` →
  carrier=jitsi, transport=datachannel, URL комнаты, ключ.

Для секции sing-box автоматически создаёт outbound `<имя_секции>-out`
(socks → `socks_host:socks_port`). TUN OlcRTC не использует никогда.

Проверено на роутере: `curl -s -x socks5h://127.0.0.1:1080 http://api.ipify.org`
→ **`157.254.131.11`** ✅.

---

## 3. Как sing-box участвует в маршрутизации (актуально)

### 3.1. Что создаёт генератор для провайдерской секции

| Секция / режим | Локальный SOCKS5 | sing-box outbound | Mixed proxy | Условия секции в sing-box |
|---|---|---|---|---|
| `wdtt` **rawtun** | нет | **нет** (перехватка через TUN/51820) | нет | нет |
| `wdtt` **vpn** | нет | **нет** | нет | нет |
| `wdtt` **socks** | да (`socks_addr`) | да `<имя>-out` | да | да |
| `olcrtc` | да (`socks_host:socks_port`) | да `<имя>-out` | да | да |

В `generator.uc` (`add_outbound_for_section`, `add_route_for_section`):

- Для `action=wdtt` (режим `socks`) и `action=olcrtc` создаётся outbound:
  ```json
  { "type": "socks", "tag": "<имя>-out",
    "server": "127.0.0.1", "server_port": <порт клиента>, "version": "5" }
  ```
- Если локального SOCKS5 нет (rawtun/vpn) — outbound не создаётся, секция
  только управляет standalone-клиентом.
- `route.uc` (`target()`) разрешает `wdtt`/`olcrtc` как обычный
  «route → outbound» — секции участвуют в правилах наравне с connection-секциями.

### 3.2. Условия секции (домены, списки, rule-sets) маршрутизируются через туннель

`add_combined_route_for_section` для wdtt(socks)/olcrtc строит обычные
route-правила из условий секции (те же поля, что у connection-секций):

- **домены**: `domain`, `domain_suffix`, `domain_keyword`, `domain_regex`;
- **IP**: `ip_cidr`, `source_ip_cidr`, `fully_routed_ips`, `ports`;
- **rule-sets**: `rule_sets`, `rule_sets_with_subnets`, `domain_ip_lists`,
  а также **WDTT community lists** (`community_lists`).

Каждый community list (`telegram`, `youtube`, `meta`, …) подключается как
**remote rule-set sing-box** (бинарный `.srs` с
`https://github.com/itdoginfo/allow-domains/releases/latest/download/<имя>.srs`),
тег `<секция>-<имя>-community-ruleset`. Правило секции получает
`rule_set: [...]` и направляет совпавший трафик в `<имя>-out`.

**DNS**: для доменных/rule-set условий секции DNS-запросы маршрутизируются
через fakeip-сервер sing-box — резолв идёт через sing-box и согласован с
правилами секции (домены, попавшие под условия, резолвятся и ходят через
туннель).

**Куда применяются правила**: TPROXY (вся LAN — `tproxy-in`/`tproxy6-in`) +
входящий mixed proxy секции. Правила секции действуют для всего LAN-трафика,
совпавшего с условиями; mixed proxy гонит через туннель **весь** свой трафик.

### 3.3. «Прокси для браузера» (per-section mixed proxy)

Поле `mixed_proxy_enabled` (LuCI: Settings → **Enable Mixed Proxy**).
Требование: у секции должен быть локальный SOCKS5 (olcrtc — любой,
wdtt — только `qwdtt_mode=socks`), иначе генератор откажет
(`mixed proxy for action … requires a local SOCKS5 endpoint`).

При включении создаётся inbound:

```json
{ "type": "mixed", "tag": "<имя>-mixed-in",
  "listen": "<LAN IP роутера>", "listen_port": <mixed_proxy_port> }
```

+ правило `inbound: <имя>-mixed-in → outbound: <имя>-out`
(+ опционально `users: [{username, password}]` при `mixed_proxy_auth_enabled`).

Порт `mixed_proxy_port` обязателен (LuCI валидирует 1–65535) и должен быть
уникальным на роутере.

---

## 4. Порт-карта (проверено на роутере 10.57.31.230, релиз 1.0.23)

| Порт | Кто слушает | Что это |
|---|---|---|
| `127.0.0.1:1080` | `olcrtc` | SOCKS5-порт OlcRTC (секция `123`, `socks_port=1080`) |
| `127.0.0.1:1081` | `qwdtt-client` | SOCKS5-порт qwdtt (секция `qwdtt-test2`, `socks_addr=127.0.0.1:1081`) |
| `10.57.31.230:7891` | `sing-box` | mixed proxy секции `123` (olcrtc) |
| `10.57.31.230:7892` | `sing-box` | mixed proxy секции `qwdtt-test2` (wdtt socks) — **сейчас отключён** (`mixed_proxy_enabled='0'`) |
| `0.0.0.0:1602` | `sing-box` | TPROXY (v4+v6) |
| `127.0.0.42:53` | `sing-box` | DNS-in (dnsmasq → sing-box) |
| `10.57.31.230:9090` | `sing-box` | Clash API (external controller) |

TUN-интерфейсов в текущей конфигурации **нет** (см. раздел 1.1 — TUN появляется
только в режиме `rawtun`).

---

## 5. Цепочка «секция → конфиг → клиент»

### WDTT (qwdtt)
1. LuCI-секция `action=wdtt` + подписка `qwdtt://config?hashes=…&name=…&pass=…&peer=…&port=…&workers=…`
   (или список `.list`/`.hash`-файлов + поля peer/password/workers).
2. `providers/wdtt/runtime.uc` → парсит ссылку, собирает `config.json`
   (peer, hashes, password, device_id, workers, dns, obfs, captcha_mode,
   vk_auth, vk_anon_path, no_dtls, turn_tcp, tun_name, lan_interface,
   `qwdtt_mode`, `socks_addr`) → `/etc/qwdtt/config.json` →
   `restart /etc/init.d/qwdtt`.
3. `qwdtt-client` поднимает выбранный режим; в режиме `socks` sing-box
   получает outbound на `socks_addr` (раздел 3).

### OlcRTC
1. LuCI-секция `action=olcrtc` + подписка `olcrtc://…`.
2. `providers/olcrtc/runtime.uc` → парсит URI, пишет
   `uci set olcrtc.config.*` → `restart /etc/init.d/olcrtc`.
3. `/etc/init.d/olcrtc` генерирует `/etc/olcrtc/client.yaml` из uci
   (`socks.port` ← `socks_port` секции) → запускает `olcrtc`.
4. sing-box получает outbound на `socks_host:socks_port` (раздел 3).

---

## 6. Как пользоваться (актуальный способ)

### 6.1. Прокси для браузера через туннель

1. **Туннель** — секция `action=olcrtc` или `action=wdtt` (режим **socks**).
   Убедитесь, что клиент запущен и порт слушается:
   ```sh
   netstat -tlnp | grep -E "1080|1081"
   # tcp 127.0.0.1:1080  ← olcrtc
   # tcp 127.0.0.1:1081  ← qwdtt socks
   ```
2. В **Settings** секции включите **Enable Mixed Proxy**, задайте
   **Mixed Proxy Port** (например `7891`) и при необходимости Auth.
3. Примените секцию — sing-box перегенерирует конфиг и поднимет
   mixed inbound на `LAN-IP:порт`.
4. В браузере укажите прокси **SOCKS5 `<LAN IP роутера>:<порт>`** — весь
   трафик браузера идёт через туннель.

### 6.2. Условия (какие сервисы/домены идут через туннель)

Вкладка **Conditions** секции (для wdtt/olcrtc):

- **WDTT community lists** (`community_lists`): имена сервисов из
  itdoginfo/allow-domains. Допустимые id — **с подчёркиванием**:
  `telegram`, `meta`, `youtube`, `discord`, `tiktok`, `twitter`, `hdrezka`,
  `roblox`, `cloudflare`, `cloudfront`, `google_ai`, `google_play`, `hodca`,
  `anime`, `news`, `geoblock`, `block`, `porn`, `russia_inside`,
  `russia_outside`, `ukraine_inside`, `ads_hagezi_pro`, `supercell`, `github`,
  `hetzner`, `ovh`, `digitalocean` (подсказка в LuCI местами показывает
  старые дефисные имена `russia-inside` и т.п. — реально принимаются
  имена с подчёркиванием). Список подключается как remote rule-set `.srs`
  (раздел 3.2) — трафик этих сервисов с LAN идёт через туннель по TPROXY.
- **WDTT remote domain lists** (`remote_domain_list`): URL с доменными
  списками, которые загружает **сам клиент qwdtt** (опция wdtt-openwrt,
  `auto_update` — ежедневный cron). Это клиентские списки доменов для
  туннеля; в sing-box-правила секции они не попадают (в отличие от
  `community_lists`, которые являются и условиями sing-box).
- **Домены / IP / порты / rule-sets** — обычные поля условий секции.

> ⚠️ **Имя секции — только латиница, цифры и подчёркивание** (`A-Za-z0-9_`).
> Дефисы, точки, пробелы и кириллица в имени секции приводят к ошибке
> `Section name is not safe for sing-box config generation` — секция не
> попадёт в конфиг. Например, имя `vk-via-olcrtc` **не сработает**, а
> `vk_via_olcrtc` — работает.

> ⚠️ Для mixed proxy режим wdtt обязан быть `socks`, а порт клиента в
> `socks_addr` (wdtt) / `socks_port` (olcrtc) должен совпадать с тем,
> что реально слушает клиент.

### 6.3. Альтернатива: отдельная connection-секция с JSON outbound

Старый способ тоже работает: создайте секцию `action=connection` с JSON
outbound типа `socks` на порт клиента — тогда туннель используется как
обычный прокси по правилам этой секции (детуры, urltest, приоритеты):

```json
{"type":"socks","tag":"olcrtc","server":"127.0.0.1","server_port":1080,"version":"5"}
```

(в LuCI: Settings секции → «JSON outbound»; тег `tag` внутри JSON станет
именем outbound). Нужен только если требуется использовать туннель в
качестве детура/участника групп — для обычного «прокси для браузера»
и условий достаточно встроенных полей (разделы 6.1–6.2).

---

## 7. Как проверить, что туннель работает

```sh
# Через sing-box mixed proxy (как браузер):
curl -s -x socks5h://10.57.31.230:7891 --max-time 20 http://api.ipify.org   # olcrtc
curl -s -x socks5h://10.57.31.230:7892 --max-time 20 http://api.ipify.org   # wdtt socks (если включён mixed proxy)

# Напрямую через клиент:
curl -s -x socks5h://127.0.0.1:1080 --max-time 20 http://api.ipify.org      # olcrtc
curl -s -x socks5h://127.0.0.1:1081 --max-time 20 http://api.ipify.org      # qwdtt socks

# Без прокси (прямой IP провайдера):
curl -s --max-time 10 http://api.ipify.org
```

Успешным считается результат **`157.254.131.11`** (IP VPS) через туннели
и любой другой IP (ISP) без прокси. Диагностика TUN (только rawtun):
`ip -o link show | grep qwdtt`, `ip rule show`, `ip route show table 51820`.