# Topkop (Forkop Plus)

[![Star](https://img.shields.io/github/stars/win64exe/topkop?style=social)](https://github.com/win64exe/topkop/stargazers)
[![Releases](https://img.shields.io/github/v/release/win64exe/topkop?label=releases)](https://github.com/win64exe/topkop/releases)

> **Topkop — это форк [Forkop](https://github.com/ushan0v/forkop)** (бывший Podkop Plus) с дополнительной интеграцией протоколов **WDTT** и **OlcRTC**.

### Установка

```sh
sh <(wget -O - https://raw.githubusercontent.com/win64exe/topkop/main/install.sh)
```

<details>
<summary><sub>Альтернативный способ установки</sub></summary>

```sh
sh <(wget -O - https://raw.githubusercontent.com/win64exe/topkop/main/install.sh)
```

</details>

### Что нового в этом форке

* Поддержка подписок.
* Поддержка sing-box extended и транспорта XHTTP.
* Обновлённый LuCI-интерфейс.
* Расширенное управление секциями.
* Новые условия маршрутизации.
* Возможность поднять собственный VPN/proxy-сервер.
* Менеджер обновлений и установки компонентов.
* Встроенный мониторинг соединений.
* Расширенные настройки URLTest-групп.
* Автоматический выбор узла по приоритету.
* Каскадные подключения.
* Маршрутизация DNS-запросов через прокси.
* Резервные DNS-серверы.
* Отдельные DNS-серверы для выбранных доменов.
* Поддержка IPv6.
* Действие Bypass с полным обходом sing-box.
* Интеграция Zapret, Zapret2 и ByeDPI как отдельных действий секции.
* Интеграция **WDTT** и **OlcRTC** как отдельных действий секции с поддержкой подписок:
  * **WDTT** — подписки на списки хэшей DPI (`wdtt://`, `http(s)://` ссылки на `.list`/`.hash` файлы, ссылки сообществ). Первоисточники: [wdtt-openwrt](https://github.com/xDarkOne/wdtt-openwrt), [WDTT-Cudy-TR3000-256mb](https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb).
  * **WDTT: обход капчи VK** — три способа: авторежим `rjs` (Go v2 Smart Captcha, [captcha_v2.go](https://github.com/SpaceNeuroX/qwdtt-openwrt/blob/main/client/captcha_v2.go) из [qwdtt-openwrt](https://github.com/SpaceNeuroX/qwdtt-openwrt)); ручной `wv` (WebView, токен подаётся через файл `/var/run/qwdtt/captcha.token` — по механизму [watcher.go](https://github.com/RSokolovRS/WDTT-Cudy-TR3000-256mb/blob/main/etc/qwdtt/watcher.go) из RSokolovRS/WDTT-Cudy-TR3000-256mb и [CaptchaWebViewManager.kt](https://github.com/SpaceNeuroX/proxy-turn-vk-android) из Android-приложения); аккаунт-режим `vk_creds_file` (creds VK-аккаунта, [vk_account.go](https://github.com/SpaceNeuroX/qwdtt-openwrt/blob/main/client/vk_account.go)). Статус капчи и ввод токена — на Дашборде (виджет «Капча VK»).
  * **OlcRTC** — подписки через URI-протокол (`olcrtc://server/peer@host:port#key`), одиночные и множественные серверы. Первоисточники: [olcrtc](https://github.com/openlibrecommunity/olcrtc), [OlcRTC-OpenWRT](https://github.com/skorp505/OlcRTC-OpenWRT), [OlcRTC-OpenWRT](https://github.com/tankionline2005/OlcRTC-OpenWRT).
* Служба полностью переписана на ucode.
* Имена туннелей в дашборде и в пикере «Сетевой интерфейс» соответствуют именам секций.
* Пакеты в релизах именуются по конвенции OpenWrt с суффиксом архитектуры: `topkop_<версия>_all.ipk` и `topkop_<версия>_noarch.apk` (ipk — для opkg, apk — для OpenWrt 25.x).
* Защита от гонки при перезапуске qwdtt (конфликт UDP-порта 9000 больше не блокирует поднятие SOCKS5-listener).
* Другие исправления и улучшения.

### Системные требования

Протестировано на роутерах x86_64 (OpenWrt 24.10 / 25.x, apk) и ARM (AArch64). Реальное потребление ОЗУ (RSS, замерено на роутере):

| Конфигурация | ОЗУ | Диск |
|---|---|---|
| topkop + sing-box + olcrtc | ~75–80 МБ | ~79 МБ |
| topkop + sing-box + qwdtt (12 воркеров) | ~60–65 МБ | ~65 МБ |

* **Минимум: 128 МБ RAM** — оба сценария помещаются (плюс базовая система ~15–20 МБ), но впритык.
* **Рекомендуется: 256+ МБ RAM** для комфортного запаса; на 512 МБ (как в тестах) запас большой.
* **CPU:** достаточно 1 ядра (load ~0.2 в простое); для активного трафика (видео, торренты) желательно 2+ ядра.
* Настройка `workers` клиента qwdtt по умолчанию подбирается под число ядер; для одного пользователя на 1 ядре достаточно 9–12.

### Документация

Отдельной документации со всеми изменениями, нововведениями и инструкцией по настройке пока что не существует. Задать вопрос, сообщить о проблеме или обсудить проект можно в [Telegram-чате](https://t.me/forkop_chat) проекта.

Как альтернативу документации для быстрых персонализированных ответов используйте бесплатного, специально для этого созданного, AI-ассистента [@forkop_aibot](https://t.me/forkop_aibot).

### Поддержать проект

* 💳 **Карты РФ / СБП / Tinkoff Pay:** [Донат на CloudTips](https://pay.cloudtips.ru/p/385e5af2)
* 💎 **USDT (сеть TON):** `UQAOCDav39WJ2gvnzs9RQ_IsF2dcGrcpw4U0j6XGO7je7uwm`
* 🟢 **USDT (сеть TRC-20):** `TEMaZFyM8RQpkbd5LvB8CFJwxCyhHauKAe`
* 🪙 **USDT (сети ERC-20 / BEP-20 / Polygon / Monad):** `0xe8aabb21c320240fe45b6087e68c6fe40a92d8bf`
* 🟠 **USDT (сеть Solana):** `AhhUjTci9zDKQjUfgLacFR4LiHX9nmZud6DZ8YdbpjEB`
