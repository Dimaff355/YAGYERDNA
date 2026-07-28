# iac/ansible — каркас конфигурации инфраструктуры

> Код — на этапе внедрения (`docs/11-rollout.md`, этапы 3–4). Здесь — утверждённая структура.

```
ansible/
├── README.md                — этот файл
├── requirements.yml         — коллекции (community.general, ansible.posix и т.д.)
├── ansible.cfg
├── inventories/
│   ├── prod/
│   │   ├── hosts.yml        — ноды Proxmox, ВМ инфра-сервисов, сетевые железки
│   │   └── group_vars/      — переменные по ролям (all, proxmox, infra_vms, network)
│   └── dev/
├── playbooks/
│   ├── site.yml             — полная сборка инфраструктуры
│   ├── proxmox-cluster.yml  — кластер + Ceph
│   ├── infra-services.yml   — ALD Pro, Zabbix, GLPI, Keycloak, Nextcloud, MikoPBX, PBS
│   ├── network.yml          — конфигурация ядра/доступа (по моделям из docs/03)
│   └── backup.yml           — политики PBS, S3-синк
├── roles/
│   ├── common/              — базовая настройка ВМ (пакеты, агенты Zabbix/GLPI, ssh)
│   ├── proxmox_node/
│   ├── ceph/
│   ├── zabbix_server/
│   ├── glpi/
│   ├── nextcloud/
│   ├── mikopbx/
│   ├── aldpro/
│   ├── keycloak/
│   ├── pbs/                 — Proxmox Backup Server
│   └── linux_desktop/       — post-install рабочих мест Linux (через ansible-pull)
└── docs/                    — runbook: как поднять всё с нуля
```

Принципы:
- Всё, что можно описать кодом, описывается кодом — ручных «помню, что крутил» не существует.
- Секреты — только через OpenBao (см. `../terraform/README.md`) или ansible-vault на переходный период.
- Рабочие места Linux — ansible-pull из этой репы (см. `docs/05-workplaces.md`).
- Сетевые железки: конфиги генерируются из шаблонов + золотые конфиги в git.
