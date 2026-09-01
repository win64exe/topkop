# Маршрутизация трафика через qwdtt (WDTT) и OlcRTC

Topkop запускает qwdtt (WDTT) и OlcRTC как **standalone-туннели**: каждый
клиент поднимает собственный сетевой интерфейс/порт, а Topkop (sing-box + nft)
в проксировании этих потоков **не участвует** (в `generator.uc` для
`action=wdtt`/`action=olcrtc` sing-box-outbound не создаётся). Ниже — точная
схема для каждого протокола.

---

## 1. qwdtt (WDTT) — 3 режима клиента

Клиент: `/usr/bin/qwdtt-client`, конфиг: `/etc/qwdtt/config.json`
(генерирует `wdtt/runtime.uc` из секции, action=`wdtt`).

Поле `mode` (в LuCI: **«режим клиента qwdtt»**):
`rawtun` | `vpn` | `socks`.

### 1.1. Режим `rawtun` — RAW-IP туннель (по умолчанию для OpenWrt)

Самый «прозрачный» режим: **весь трафик с LAN-интерфейса уходит в туннель
автоматически, без настройки прокси на клиентах**.

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

### 1.2. Режим `vpn` — userspace WireGuard

1. Клиент запрашивает у сервера WG-конфиг (`GETCONF:localPort|device|password`).
2. Сервер выдаёт WireGuard-настройки (Address `10.66.x.x/32`, Endpoint
   `127.0.0.1:9000` — TURN-мост).
3. В полной сборке клиент **сохраняет конфиг в `wg-turn.conf`** — для режима
   `vpn` (без `-mode socks`) сам WG не поднимает (поднимает внешний инструмент).
   **Для работы прямо на роутере используйте режим `socks`** — там клиент сам
   поднимает userspace WG поверх TURN.

### 1.3. Режим `socks` — локальный SOCKS5 + userspace WireGuard ✅ (рабочий)

Лучший режим для проверки: клиент **сам поднимает userspace WireGuard**
(через `netstack`, без kernel-TUN) поверх TURN-моста, и открывает
**локальный SOCKS5** на `socks_addr` (по умолчанию `127.0.0.1:1080`,
в нашем тесте — `127.0.0.1:1081`).

```
приложение/curl -x socks5h://127.0.0.1:1081
        → SOCKS5-сервер qwdtt
        → userspace WireGuard (10.66.0.3, endpoint 127.0.0.1:9000 — TURN)
        → TURN-релей olcrtc.931094.xyz:56000
        → VPS 157.254.131.11
```

Проверено на роутере: `curl -x socks5h://127.0.0.1:1081 http://api.ipify.org`
→ **`157.254.131.11`** ✅.

DNS в режиме socks резолвится клиентом (netstack-резолвер), в config.json
задаётся `dns: yandex|cloudflare|...`.

---

## 2. OlcRTC — SOCKS5-туннель через WebRTC-канал

Клиент: `/usr/bin/olcrtc`, конфиг: `/etc/olcrtc/client.yaml`
(генерирует `/etc/init.d/olcrtc` из uci-конфига, который пишет
`olcrtc/runtime.uc` из секции action=`olcrtc`).

OlcRTC **всегда работает как SOCKS5-прокси**:

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

Проверено на роутере: `curl -x socks5h://127.0.0.1:1080 http://api.ipify.org`
→ **`157.254.131.11`** ✅.

---

## 3. Где трафик идёт мимо Topkop (важно понимать)

- Секции `action=wdtt` / `action=olcrtc` **не создают sing-box outbound**:
  sing-box-правила их не трогают, TPROXY на них не заворачивается.
  Эти секции только запускают standalone-клиент (SOCKS5-порт/TUN).
- Трафик попадает в туннель **только** одним из способов:
  1. **qwdtt rawtun** — прозрачно, правилом `iif br-lan lookup 51820`
     (требует сервер с RAWCONF);
  2. **qwdtt socks / olcrtc** — через локальный SOCKS5-порт
     (`127.0.0.1:1080` / `127.0.0.1:1081`), **но** вместо указания порта
     в каждом приложении правильнее подключить sing-box к этому порту —
     см. раздел 5 ниже: тогда маршрутизация идёт по вашим секциям,
     спискам и правилам, как для обычных прокси.

- Список портов на роутере (проверено):
  ```
  tcp 127.0.0.1:1080  ← olcrtc        (PID: /usr/bin/olcrtc client.yaml)
  tcp 127.0.0.1:1081  ← qwdtt socks   (PID: /usr/bin/qwdtt-client -config)
  ```

---

## 4. Цепочка «секция → конфиг → клиент»

### WDTT (qwdtt)
1. LuCI-секция `action=wdtt` + подписка `qwdtt://config?hashes=…&name=…&pass=…&peer=…&port=…&workers=…`
   (или список `.list`/`.hash`-файлов + поля peer/password/workers).
2. `providers/wdtt/runtime.uc` → парсит ссылку, собирает `config.json`
   (peer, hashes, password, device_id, workers, dns, obfs, captcha_mode,
   vk_auth, vk_anon_path, no_dtls, turn_tcp, tun_name, lan_interface, mode,
   socks_addr) → `/etc/qwdtt/config.json` → `restart /etc/init.d/qwdtt`.
3. `qwdtt-client` поднимает выбранный режим.

### OlcRTC
1. LuCI-секция `action=olcrtc` + подписка `olcrtc://…`.
2. `providers/olcrtc/runtime.uc` → парсит URI, пишет `uci set olcrtc.config.*`
   → `restart /etc/init.d/olcrtc`.
3. `/etc/init.d/olcrtc` генерирует `/etc/olcrtc/client.yaml` из uci → запускает
   `olcrtc`, открывает SOCKS5.

---

## 5. Как заставить sing-box подключаться к qwdtt/olcrtc (роутинг по спискам)

Сама по себе секция `action=wdtt`/`action=olcrtc` **не заворачивает трафик
в sing-box** — она лишь поднимает standalone-клиент с локальным SOCKS5-
портом. Чтобы sing-box ходил в туннель и маршрутизировал **по вашим секциям,
спискам и правилам** (как обычные прокси), нужно создать **отдельную секцию
`action=connection`** с JSON-outbound типа `socks`, указывающим на порт
клиента. Дальше все обычные механизмы маршрутизации (домены, IP-списки,
rule-sets, сообщества) работают как обычно.

### Схема (на примере OlcRTC, порт 1080)

```
LAN-клиент
   │
   ▼
Topkop TPROXY (nft) ──► sing-box
                              │ правило секции (домены/списки/rule-sets) совпало
                              ▼
                    SOCKS5 outbound ──► 127.0.0.1:1080 (olcrtc)
                                              │
                                              ▼
                                    WebRTC-канал → VPS 157.254.131.11
```

### Как настроить в LuCI

1. **Туннель** — секция `action=wdtt` (режим `socks`) или `action=olcrtc`.
   Убедитесь, что клиент запущен и порт слушается:
   ```sh
   netstat -tlnp | grep -E "1080|1081"
   # tcp 127.0.0.1:1080  ← olcrtc
   # tcp 127.0.0.1:1081  ← qwdtt socks
   ```

2. **Секция-проброс в sing-box** — создайте секцию `action=connection`
   (например, с именем `vk-via-olcrtc`) и добавьте JSON outbound:
   ```json
   {"type":"socks","tag":"olcrtc","server":"127.0.0.1","server_port":1080,"version":"5"}
   ```
   для qwdtt (socks) соответственно:
   ```json
   {"type":"socks","tag":"qwdtt","server":"127.0.0.1","server_port":1081,"version":"5"}
   ```
   (в LuCI: вкладка «Settings» секции → «JSON outbound» → «+ Add JSON
   outbound»; тег `tag` внутри JSON станет именем outbound в sing-box).

   > ⚠️ Порт SOCKS5 qwdtt/olcrtc по умолчанию мог быть изменён в настройках
   > тунельной секции (`socks_addr` для qwdtt, `socks_port` для olcrtc).
   > В JSON должен стоять **именно тот порт, который слушает клиент**.

3. **Правила/списки** — в той же секции `connection` задайте условия
   маршрутизации, как для обычных прокси-секций:
   - **Домены**: поле `domain` / `domain_suffix` / `domain_keyword`
     (например `vk.com`, `userapi.com`, ключевое слово `vkontakte`);
   - **IP-списки**: `ip_cidr` / `domain_ip_lists`;
   - **Rule-sets / сообщества**: `rule_sets`, `community_lists` — внешние
     списки (`.list`/`.hash`/`geosite`/`geoip`) обновляются и
     подключаются как `rule_set` в sing-box, как для обычных секций;
   - **Условия по клиенту**: `source_ip_cidr`, `interface`, порты и т.д.

4. Включите секцию и нажмите «Применить». sing-box перегенерирует конфиг:
   в `outbounds` появится SOCKS-outbound, в `route.rules` — правило
   секции с `outbound` на него. Проверка:
   ```sh
   # запрос, попадающий под правило секции, уходит в туннель
   curl -s --max-time 15 http://api.ipify.org          # прямой IP (мимо секции)
   ```
   а трафик, совпавший с правилом, пойдёт через outbound и вернётся
   с IP VPS (см. раздел «Как проверить»).

### Что это даёт

- **Одна точка маршрутизации**: туннель используется как любой другой
  прокси-сервер — по правилам секций, а не принудительно для всего LAN.
- **Селекторы/URLTest/детур**: из секции-проброса можно сделать детур
  (`Connect through` / `outbound_detour_section`) и комбинировать туннель
  с другими прокси, приоритетами и urltest-группами.
- **DNS-маршрутизация**: доменные правила секции работают и для DNS
  (resolver через тот же outbound), FakeIP/подмену DNS можно настраивать
  как обычно.
- **Не обязательно для rawtun**: в режиме `rawtun` qwdtt сам перехватывает
  весь LAN-трафик (`iif br-lan lookup 51820`), sing-box-проброс не нужен.

---

## 6. Как проверить, что туннель работает

```sh
# IP через OlcRTC
curl -s -x socks5h://127.0.0.1:1080 --max-time 15 http://api.ipify.org
# → 157.254.131.11

# IP через qwdtt (socks)
curl -s -x socks5h://127.0.0.1:1081 --max-time 15 http://api.ipify.org
# → 157.254.131.11
```

Успешным считается результат `157.254.131.11` (IP VPS) через оба туннеля.