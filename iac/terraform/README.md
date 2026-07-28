# iac/terraform — каркас (OpenTofu)

> В РФ реестр провайдеров HashiCorp заблокирован → используем **OpenTofu** (открытый форк Terraform) + зеркало провайдеров (Yandex Cloud). Код — на этапе внедрения.

Зона ответственности (то, что описывается декларативно):
- **Облачная часть:** S3-бакеты под второй слой бэкапов (Yandex Cloud / VK Cloud), DNS-записи, почтовые MX/SPF/DKIM — через провайдеры OpenTofu.
- **Proxmox:** провайдер `bpg/proxmox` — декларативное создание инфра-ВМ (Zabbix, GLPI, Nextcloud, MikoPBX и т.д.) поверх кластера из `../ansible`.

```
terraform/
├── README.md            — этот файл
├── versions.tf          — версии OpenTofu и провайдеров, зеркала
├── backend.tf           — state в S3 (с блокировкой) или local на переходный период
├── modules/
│   ├── proxmox_vm/      — типовая ВМ: образ cloud-init, ресурсы, теги
│   ├── s3_backup/       — бакет + lifecycle-политики + версионирование
│   └── dns/             — зоны и записи
├── envs/
│   ├── prod/
│   └── dev/
└── docs/
```

Секреты: **OpenBao** (форк Vault) — токены Proxmox API, ключи S3, пароли сервисов. Ничего секретного в репе.
