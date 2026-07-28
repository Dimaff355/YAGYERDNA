# 15. Настройка сети конец-в-конец: от распаковки до «этаж работает»

> Файлы конфигураций: `iac/network/huawei/*.cfg`, `iac/network/usergate/bootstrap.md`.
> Адресный план: `iac/network/README.md`. Решения: `docs/03-network.md`, `docs/13-recommendation.md`.
>
> **Порядок развёртывания: ядро → периметр → этаж 1 (пилот) → этажи 2–5.**
> Не менять порядок: этажи без ядра мертвы, периметр без ядра не до чего маршрутизировать.

Предусловия: СКС смонтирована и сертифицирована (Fluke-протоколы), оптика этаж↔серверная прозвонена, в серверной есть питание ИБП. Инструмент админа: ноутбук с консольным кабелем USB→RJ45 (9600 8N1), терминал (minicom/PuTTY), TFTP-сервер (на ноуте, `atftpd`/`tftpd-hpa`) для переброски файлов.

---

## Шаг 0. Подготовка (0,5 дня)

- [ ] Распаковать, проверить комплектность и заводские версии VRP: `display version`. На S6730 должна быть ветка V200R022+; если старее — обновить **до** сборки стеков (прошивка через USB/TFTP, оба ядра — одинаковая версия, иначе iStack не соберётся).
- [ ] Сгенерировать секреты (admin-пароли, SNMP community, PSK) → в сейф паролей. В конфигах заменить все `<CHANGE_ME_...>`.
- [ ] Подготовить файлы этажей: `sed 's/FLOOR/1/g' access-floorN.cfg > access-floor1.cfg` … до floor5.
- [ ] Распечатать/держать открытыми: адресный план (`iac/network/README.md`), этот чек-лист.

## Шаг 1. Ядро: iStack из двух S6730 (день 1)

1. Оба ядра в стойке, **stack-кабели пока не подключены**. Консолью на каждом:
2. На core-01: секция 1 из `iac/network/huawei/core-01.cfg` (priority 150) → `save` → `reboot`.
3. На core-02: `iac/network/huawei/core-02.cfg` целиком (renumber 2, priority 100) → `save` → `reboot`.
4. Соединить кроссом: 100GE1/0/5↔100GE2/0/5, 100GE1/0/6↔100GE2/0/6.
5. **Проверка:**
   ```
   display stack
   ```
   Ожидаем: MemberID 1 — Master (Prio 150), MemberID 2 — Standby (Prio 100), оба `Ready`. Не `Down`/`Loading` дольше 5 минут.
6. Залить секцию 2 из `core-01.cfg` на master (вставка порциями по ~50 строк; после каждой порции — нет `Error:`). `save` → `y`, `y`.
7. **Проверки:**
   | Команда | Ожидаемый результат |
   |---|---|
   | `display vlan` | все VLAN 10..90, 998, 999 созданы |
   | `display ip interface brief` | все Vlanif — `up/up` (кроме транзитов до подключения) |
   | `display interface brief` | 100GE stack-порты up; 10GE x/0/1-5 — down (этажей ещё нет) — это норма |
   | `display current-configuration \| include CHANGE_ME` | пусто (все плейсхолдеры заменены) |
   | SSH с ноута (через mgmt-порт в VLAN 10) | пускает admin, только из 10.10.10.0/24 |

**Откат:** если стек не собрался — `display stack topology`, проверить domain (10, одинаковый), версии VRP, кабели. Разобрать стек: выключить standby, `reset saved-configuration`, reboot.

## Шаг 2. Периметр: кластер UserGate (день 2)

Идём строго по `iac/network/usergate/bootstrap.md`: зоны → кластер active/standby → 2 ISP с health-check → NAT → правила МЭ → VPN. Ключевые точки стыковки с Huawei:

- bond0 (LACP) на каждом узле NGFW → порты ядра 10GE x/0/20–21 (Eth-Trunk10, VLAN 998).
- **Проверки:**
  - На ядре: `display eth-trunk 10` — все 4 порта `Selected`, статус trunk up.
  - `ping 10.10.254.2` с ядра — отвечает VIP кластера.
  - `display ospf peer brief` — соседство с NGFW в `Full` (если OSPF на NGFW включён; иначе проверяем статику: `display ip routing-table` — default через 10.10.254.2).
  - С mgmt-ноута (VLAN 10): интернет есть, внешний IP = ISP-1; дёргаем ISP-1 → < 10 c перерыва, IP = ISP-2.

## Шаг 3. ToR 25G (серверный сегмент) — можно параллельно с шагом 2

ToR — зона ответственности лейна серверов; со стороны ядра всё уже готово (Eth-Trunk20/21, VLAN 50/60/999). Проверка со стороны ядра после подключения ToR: `display eth-trunk 20` / `display eth-trunk 21` — up; `display ospf peer brief` — соседи на Vlanif999.

## Шаг 4. Этаж 1 — пилот (день 3)

1. Три S5735 в IDF-1. На каждом консолью — секция 1 из `access-floor1.cfg` с нужным renumber/priority (1/150, 2/100, 3/50) → `save` → `reboot`.
2. Стек-кольцо: XGE1/0/3→XGE2/0/4, XGE2/0/3→XGE3/0/4, XGE3/0/3→XGE1/0/4.
3. `display stack` — 3 member'а, все Ready. Залить секцию 2 на master → `save`.
4. Оптика: XGE1/0/1 → ядро member 1 (10GE1/0/1), XGE2/0/1 → ядро member 2 (10GE2/0/1).
5. **Проверки (на этажном стеке):**
   | Команда | Ожидаемый результат |
   |---|---|
   | `display eth-trunk 1` | 2 порта `Selected`, LACP up |
   | `display lldp neighbor brief` | виден `crm-core-stack` на обоих XGE |
   | `display dhcp snooping` | enabled; uplink — trusted |
   | `display poe power-state` | PoE на портах enabled, бюджет в норме |
   | `ping 10.10.10.1` | шлюз ядра отвечает |
6. **Проверки (на ядре):** `display eth-trunk 1` — up; `display mac-address dynamic | include 20` — MAC'и клиентов появляются.
7. **Живой тест (обязательно):**
   - ПК в порт GE1/0/5: получает IP из 10.10.20.0/23 (через relay → DHCP 10.10.50.10), шлюз 10.10.20.1, интернет работает. `ipconfig /all` — сервер DHCP правильный (не «169.254.*»!).
   - Телефон Fanvil в тот же порт (ПК каскадом): телефон в VLAN 30 (видно в меню телефона / `display voice-vlan mac-address`), регистрируется на MikoPBX.
   - ТД UniFi в GE1/0/41: получает IP из MGMT, адоптится контроллером; клиент CORP-SSID → 10.10.40.x, GUEST → 10.10.41.x, гость до внутренних сетей **не достукивается** (правило 22 на UserGate).
   - Дёрнуть один из двух аплинков: связность этажа не пропадает (LACP).
8. Пилот живёт **минимум 2–3 рабочих дня** с реальными пользователями этажа 1. Собираем грабли, правим шаблон, только потом — шаг 5.

## Шаг 5. Этажи 2–5 (по 0,5–1 дню на этаж)

Повтор шага 4 по `access-floor2..5.cfg`. Особенность: этажи заселены — переезд рабочих мест со старых 2960-X делаем **вечером/ночью**, старый свитч не выключаем до подтверждения, что все порты переехали. После каждого этажа: живой тест как в шаге 4, п.7 (сокращённо: ПК + телефон + 1 ТД).

## Шаг 6. Финализация

- [ ] `save` везде; снять `display current-configuration` со всех стеков → в архив `backups/`.
- [ ] Zabbix: все устройства добавлены, SNMP-опрос зелёный, триггеры (порт down, PoE-бюджет, стек member down) проверены тестовым отключением.
- [ ] Старые 2960-X выведены (docs/03: временная роль до 2027).
- [ ] Финальный проход чек-листа приёмки периметра (`usergate/bootstrap.md`, п.9).

---

## Грабли Huawei VRP (собрано заранее, чтобы не наступать)

1. **`save` не сделан = конфига нет.** VRP не сохраняет running-config сам. После любой удачной проверки — `save`. Два подтверждения подряд — оба `y`.
2. **iStack не собирается:** в 90% случаев — разные версии VRP на member'ах или разный stack domain. `display stack topology` + `display version` на каждом. Renumber применяется **только после reboot** — до перезагрузки свитч остаётся member 1.
3. **Eth-Trunk по умолчанию в режиме manual load-balance, а не LACP.** Если забыть `mode lacp-static`, транк «поднимется» и без LACP-партнёра → петли/асимметрия. Проверка: `display eth-trunk N` — поле `WorkMode: LACP`, порты `Selected` (не `Unselect`).
4. **DHCP snooping: забыт `trusted` на аплинке** — клиенты получают 169.254.x.x. Симптом классический: на этаже «DHCP не работает», на ядре relay настроен. Проверка: `display dhcp snooping interface Eth-Trunk1` — trusted: yes.
5. **Voice VLAN не подхватывается телефоном:** нужен LLDP (по умолчанию **выключен** глобально — `lldp enable` обязательна) и телефон, умеющий LLDP-MED; для старых аппаратов — `voice-vlan legacy enable` (есть в шаблоне). Проверка: `display voice-vlan mac-address`.
6. **`port hybrid` vs `port link-type access`:** на hybrid-порту забудешь `port hybrid pvid vlan 20` — трафик уйдёт в VLAN 1. После заливки шаблона: `display port vlan` — сверить PVID по всем портам.
7. **STP BPDU-protection + телефон с встроенным свитчем:** если пользователь воткнул мини-свитч, порт уйдёт в error-down. Это фича, не баг: `display interface | include error-down`; вернуть: `shutdown`/`undo shutdown` после выяснения.
8. **SSH не пускает:** на VRP по умолчанию нет RSA-ключа хоста — если `stelnet server enable` ругается, сначала `rsa local-key-pair create` (2048). Также проверить `protocol inbound ssh` на VTY и ACL 2000.
9. **Вставка конфига в консоль «сыром» текстом ловит ошибки на длинных строках** — вставлять порциями, смотреть `Error:` после каждой. Не вставлять через telnet (обрывы) — только консоль или SSH.
10. **`interface 10ge 2/0/x` не существует, пока member 2 не в стеке** — команды для портов второго ядра дадут `Error: Wrong parameter`. Сначала `display stack`, потом секция 2.
11. **OSPF `silent-interface all`** глушит hello везде; забыть `undo silent-interface Vlanif998/999` — соседства не будет. Проверка: `display ospf peer brief` пуст → смотреть silent-interface.
12. **Прошивка через USB/TFTP прерывается на больших .cc** — копировать в flash локально (`dir`, сверить MD5 с сайта Huawei), `startup system-software <file>`, reboot. Обновлять по одному member'у стека с окном отката.
