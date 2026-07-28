# 16. Поднятие вычислительных сервисов: от кластера до «всё в мониторинге»

> Вход: кластер Proxmox+Ceph поднят по `iac/docs/RUNBOOK.md` этапы A–D
> (4 ноды, Ceph HEALTH_OK, 8 ВМ из OpenTofu созданы).
> Выход: все инфра-сервисы работают, SSO настроено, бэкапы идут, всё в Zabbix.
>
> Принцип тот же, что в RUNBOOK: что автоматизировано — команда;
> что руками — точный чек-лист и причина, почему не автоматизировано.

## 0. Pre-flight (5 мин)

```bash
# на pve-01
ceph -s                       # HEALTH_OK или WARN только по PG
qm list                       # 8 ВМ из RUNBOOK этап D запущены
cd iac/ansible
ansible infra_vms -m ping     # все ВМ отвечают по SSH (sysadmin + ключ)
```

Если Ceph пул ещё не создан (site.yml --limit proxmox_nodes не прогоняли):

```bash
ansible-playbook playbooks/site.yml --limit proxmox_nodes -u root -k
# роль ceph: пул ceph-rbd size=3 min=2 pg_num=256 + storage в Proxmox + ceph -s
```

Проверка: в веб-морде Proxmox → Datacenter → Storage есть `ceph-rbd`; диски ВМ лежат на нём.

## Порядок поднятия сервисов (важно!)

**Keycloak → Zabbix → GLPI → Nextcloud → MikoPBX → PBS.**

Логика: SSO нужен остальным сервисам для входа (Keycloak первым);
мониторинг — вторым, чтобы каждый следующий сервис сразу попадал в наблюдение;
PBS — последним, т.к. бэкапить нужно уже настроенные ВМ, а не пустые.

---

## Шаг 1. Keycloak (~20 мин, Ansible + 15 мин руками)

```bash
ansible-playbook playbooks/site.yml --limit keycloak-01
```

Автоматизировано: docker-стек (keycloak + postgres), импорт realm `crmfactory`
с OIDC-клиентами grafana/nextcloud/glpi/gitlab, health-check.

**Руками (и почему):**
1. `https://keycloak-01:8080/admin` → сменить пароль admin, завести его в OpenBao. *(Установочный пароль из env — временный.)*
2. Realm crmfactory → Clients → каждый клиент → перегенерировать secret, сохранить в OpenBao. *(Дефолтные секреты из defaults — плейсхолдеры.)*
3. User federation → LDAP к ALD Pro — **после** поднятия домена (docs/08, отдельный этап). Параметры — комментарий в `roles/keycloak/tasks/main.yml`. *(ALD Pro ещё не существует.)*

**Проверка:** `curl http://10.10.30.14:8080/realms/crmfactory/.well-known/openid-configuration` → JSON; логин в admin-консоль.

## Шаг 2. Zabbix (~15 мин, Ansible)

```bash
ansible-playbook playbooks/site.yml --limit zabbix-01
```

**Руками:** импорт шаблонов (Linux by Zabbix agent, Proxmox VE по SNMP/HTTP, MikoPBX),
настройка Telegram-алертов (токен из OpenBao), заведение хостов. *(Хосты появляются постепенно;
авто-регистрация агентов настроена ролью common — большинство заведётся само.)*

**Проверка:** zabbix-frontend открывается, хосты `pve-01..04`, ВМ — зелёные.

## Шаг 3. GLPI (~20 мин, Ansible + 20 мин руками)

```bash
ansible-playbook playbooks/site.yml --limit glpi-01
```

Автоматизировано: MariaDB + nginx + php-fpm, GLPI 10 распакован, vhost.

**Руками:**
1. `http://10.10.30.12` → мастер установки (проверка требований → БД: host localhost, user glpi, пароль из OpenBao/env). *(Мастер интерактивный, состояние БД не контролируется Ansible.)*
2. Удалить `install/install.php`, сменить пароли glpi/post-tech/tech/normal.
3. LDAP к ALD Pro — после домена (плейсхолдер в `roles/glpi/tasks/main.yml`).
4. GLPI-agent: Linux — уже в роли `linux_desktop`; Windows — MSI через GPO позже.

**Проверка:** логин в GLPI; первый GLPI-agent с тестового десктопа присылает инвентарь.

## Шаг 4. Nextcloud + OnlyOffice (~25 мин, Ansible + 15 мин руками)

```bash
ansible-playbook playbooks/site.yml --limit nextcloud-01
```

Автоматизировано: docker-стек (nextcloud:stable + postgres + redis + onlyoffice),
trusted_domains, env с паролями.

**Руками:**
1. Первый вход admin → сменить пароль.
2. Приложение «ONLYOFFICE connector» → адрес `http://10.10.30.13:8081`, JWT из env. *(Связка nextcloud↔onlyoffice настраивается в UI коннектора.)*
3. OIDC: приложение «OpenID Connect Login» → issuer `https://keycloak.<domain>/realms/crmfactory`, client `nextcloud`, secret из OpenBao (шаг 1.2).
4. LDAP к ALD Pro — после домена.

**Проверка:** вход через OIDC-кнопку; создание/редактирование .docx в браузере через OnlyOffice.

## Шаг 5. MikoPBX (~30 мин/нода, Ansible + 1–2 часа руками)

```bash
ansible-playbook playbooks/site.yml --limit mikopbx
```

Автоматизировано: подготовка ВМ (диск записей /dev/sdb → /storage/records),
установка официальным скриптом, конфиги-плейсхолдеры (2 SIP-транка с failover,
очередь колл-центра, запись), cron-бэкап конфига.

**Руками (самый «ручной» сервис — реквизиты появляются только после договоров):**
1. Веб-морда `https://10.10.40.11/admin-cabinet` → сменить пароль.
2. Вписать реальные SIP-реквизиты провайдеров №1 и №2 (транки-плейсхолдеры из роли — OFFLINE до этого).
3. Маршрутизация исходящих: failover provider1 → provider2; входящие → очередь callcenter.
4. Завести операторов (внутренние номера 2xx), добавить в очередь.
5. **Тест failover:** отключить транк №1 → исходящий звонок уходит через №2.
6. mikopbx-02: Restore из бэкапа конфига 01 (System → Backup/Restore). *(Живой failover между нодами — фаза 2, нужен floating IP.)*

**Проверка:** звонок «город → очередь → оператор», запись появилась в /storage/records;
звонок «оператор → город» через транк №1 и (при отключённом №1) через №2.

## Шаг 6. PBS (~30 мин, Ansible + 20 мин руками)

```bash
# СНАЧАЛА: впиши реальные by-id дисков в inventories/prod/group_vars/backup_servers.yml!
ansible-playbook playbooks/backup.yml -u root -k
```

Автоматизировано: PBS из pbs-no-subscription, ZFS RAIDZ2 на 12 дисков, datastore `main`,
prune (daily 7 / weekly 4 / monthly 12) + GC, S3-sync второй копии в Yandex Cloud (rclone + timer),
заготовка под LTO (комментарии в роли — после закупки автолоадера).

**Руками:**
1. В веб-морде каждой pve-ноды: Datacenter → Storage → Add → Proxmox Backup Server
   (server: 10.10.20.21, datastore: main, fingerprint из PBS → Dashboard). *(Требует API-токена PBS — создаётся в UI.)*
2. Datacenter → Backup → расписание: еженочно 01:00, все инфра-ВМ, режим snapshot.
3. Первый бэкап вручную → Verify job → проверить восстановление одной ВМ в sandbox. *(Тест восстановления — единственная настоящая проверка бэкапа.)*
4. S3-sync: проверить `journalctl -u pbs-s3-sync.service`, в бакете `crm-backups-offsite` появились объекты.

**Проверка:** `proxmox-backup-manager datastore status main`; тест-restore ВМ стартует; S3-синк отработал без ошибок.

## Финал: всё в мониторинге

- Zabbix: хосты keycloak-01, glpi-01, nextcloud-01, mikopbx-01/02, pbs-01 — зелёные (агент из common).
- Дашборд Grafana «для руководства» (docs/09) — OIDC-вход через Keycloak (клиент grafana из шага 1).
- Telegram-алерты: тестовый триггер (отключить zabbix-agent на тестовой ВМ) → сообщение в группу дежурных.

**Итого:** шаги 1–2 + Ansible-часть 3–6 ≈ 2 часа автоматики; ручные донастройки ≈ 4–5 часов,
разнесённые по этапам rollout (SIP-реквизиты, LDAP, тест-restore — когда появятся договоры и домен).
