# SC4S

- `local/context/splunk_metadata.csv` : surcharge de l'index / sourcetype par clé de source
  (format `clé,metadata,valeur`) — déployé par le rôle Ansible `sc4s` dans `/opt/sc4s/local/context/`.
- `env_file` : généré par Ansible (contient le token HEC venant de Vault) — voir `ansible/roles/sc4s/templates/env_file.j2`.
- Test : `bash tools/send_syslog.sh ing01`
