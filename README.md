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
  * **OlcRTC** — подписки через URI-протокол (`olcrtc://server/peer@host:port#key`), одиночные и множественные серверы. Первоисточники: [olcrtc](https://github.com/openlibrecommunity/olcrtc), [OlcRTC-OpenWRT](https://github.com/skorp505/OlcRTC-OpenWRT), [OlcRTC-OpenWRT](https://github.com/tankionline2005/OlcRTC-OpenWRT).
* Служба полностью переписана на ucode.
* Другие исправления и улучшения.

### Документация

Отдельной документации со всеми изменениями, нововведениями и инструкцией по настройке пока что не существует. Задать вопрос, сообщить о проблеме или обсудить проект можно в [Telegram-чате](https://t.me/forkop_chat) проекта.

Как альтернативу документации для быстрых персонализированных ответов используйте бесплатного, специально для этого созданного, AI-ассистента [@forkop_aibot](https://t.me/forkop_aibot).

### Поддержать проект

* 💳 **Карты РФ / СБП / Tinkoff Pay:** [Донат на CloudTips](https://pay.cloudtips.ru/p/385e5af2)
* 💎 **USDT (сеть TON):** `UQAOCDav39WJ2gvnzs9RQ_IsF2dcGrcpw4U0j6XGO7je7uwm`
* 🟢 **USDT (сеть TRC-20):** `TEMaZFyM8RQpkbd5LvB8CFJwxCyhHauKAe`
* 🪙 **USDT (сети ERC-20 / BEP-20 / Polygon / Monad):** `0xe8aabb21c320240fe45b6087e68c6fe40a92d8bf`
* 🟠 **USDT (сеть Solana):** `AhhUjTci9zDKQjUfgLacFR4LiHX9nmZud6DZ8YdbpjEB`
