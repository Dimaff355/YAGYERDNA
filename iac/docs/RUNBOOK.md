# RUNBOOK: от голого железа до работающей инфраструктуры

> Отвечает на вопрос «что именно делает код и в каком порядке».
> Принцип: что можно автоматизировать — автоматизировано; что нельзя — описано как ручной шаг с точными командами. Почему что-то ручное — указано.

## Этап A. Голое железо → Proxmox на 4 нодах (РУЧНОЙ, ~2 часа)

Почему ручной: установка гипервизора на bare metal — это PXE или флешка + IPMI. У нас нет PXE-инфраструктуры на старте (она сама появляется на этапе B). Автоматизировать можно через iLO/iDRAC API (Redfish) — отдельная автоматизация, на будущее.

1. Создать загрузочную флешку Proxmox VE 8.x ISO.
2. Установить на каждую ноду (2×960GB SSD в ZFS mirror — выбирается инсталлятором).
3. При установке задать: hostname pve-01..04, IP 10.10.20.11–14/24, gw 10.10.20.1.
4. Через IPMI/iLO включить: Redfish API, SNMP на Zabbix (после этапа B).

## Этап B. Ansible: базовая настройка нод + кластер + Ceph (~30 мин)

Запускается с любой машины админа:

```bash
cd iac/ansible
pip install ansible
ansible-galaxy collection install -r requirements.yml

# Проверка связности
ansible proxmox_nodes -m ping -u root -k

# 1) Базовая настройка ОС на нодах (NTP, пакеты, репозитории)
ansible-playbook playbooks/site.yml --tags common -u root -k

# 2) Создание кластера + установка Ceph + OSD
ansible-playbook playbooks/proxmox-cluster.yml -u root -k
```

Что делает `proxmox-cluster.yml` (по шагам, всё идемпотентно):
- роль `proxmox_node`: репозиторий no-subscription, пакеты, сетевые мосты vmbr0/vmbr1, IOMMU
- `pvecm create` на pve-01, остальные `pvecm add` — кластер
- `pveceph install`, mon×3, mgr, OSD на 6 NVMe каждой ноды

## Этап C. Cloud-init шаблон ВМ (РУЧНОЙ скрипт, ~10 мин)

Почему не Ansible: шаблон создаётся один раз, команды специфичны (qm + wget образа); скрипт честнее, чем роль из одного использования.

```bash
# на pve-01:
bash iac/ansible/scripts/create-pve-template.sh
# создаёт VM 9000 (Debian 12 cloud, qemu-guest-agent, sysadmin+ssh-key)
```

## Этап D. OpenTofu: инфра-ВМ декларативно (~15 мин)

```bash
cd iac/terraform/envs/prod
cp terraform.tfvars.example terraform.tfvars  # вписать endpoint + ssh key
export TF_VAR_proxmox_api_token="root@pam!tofu=xxxxx"  # токен из OpenBao
tofu init
tofu plan   # увидите 8 ВМ: zabbix, glpi, nextcloud, keycloak, gitlab, awx, 2×mikopbx
tofu apply
```

Результат: 8 ВМ из шаблона 9000 на Ceph, с IP из docs/03, cloud-init (пользователь sysadmin, ssh-ключ).

## Этап E. Ansible: софт на ВМ (~1–2 часа)

```bash
cd iac/ansible
ansible infra_vms -m ping
ansible-playbook playbooks/site.yml   # common на всех + сервисы по хостам
```

Что делает site.yml:
- `common` на ВСЕХ хостах: NTP, zabbix-agent, ssh-харденинг
- `zabbix_server` только на zabbix-01 (server+frontend+PostgreSQL)
- дальше по мере готовности ролей: glpi, nextcloud, keycloak, pbs (playbooks/backup.yml)

## Этап F. Рабочие станции (этап 5 rollout)

Linux-десктопы подтягивают конфигурацию сами (ansible-pull из этой репы) — роль `linux_desktop`: Р7-Офис, браузер, GLPI-агент, киоск для колл-центра. Windows — отдельная история (MDT/WDS, см. docs/05).

## Что осознанно НЕ автоматизировано (и почему)

| Шаг | Почему ручной |
|---|---|
| Установка PVE на bare metal | Нет PXE до момента, когда поднята инфраструктура; Redfish-автоматизация — фаза 2 |
| Настройка коммутаторов ядра/доступа | Зависит от выбранного вендора (решение на совещании); шаблоны — после закупки |
| Заведение DNS-зон, почты, SIP | Требуют аккаунтов/договоров у провайдеров |
| Секреты | OpenBao поднимается вручную первым, дальше всё берёт из него |
