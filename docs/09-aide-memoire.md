# 09 — Aide-mémoire (à imprimer)

## Chemins Splunk
| Chemin | Contenu |
|---|---|
| `/opt/splunk` | `$SPLUNK_HOME` (UF : `/opt/splunkforwarder`) |
| `etc/system/local/` | Conf locale de l'instance (éviter d'y mettre des choses) |
| `etc/apps/<app>/{default,local}` | Apps |
| `etc/manager-apps/` | **CM** : bundle à pousser aux peers |
| `etc/peer-apps/` | **Peer** : bundle reçu du CM (ne pas éditer) |
| `etc/shcluster/apps/` | **Deployer** : bundle pour le SHC |
| `etc/deployment-apps/` | **DS** : apps pour les forwarders |
| `etc/auth/splunk.secret` | Clé de chiffrement des mots de passe dans les .conf |
| `var/lib/splunk/<index>/{db,colddb,thaweddb}` | Buckets (`$SPLUNK_DB`) |
| `var/log/splunk/splunkd.log` | Log principal |

## CLI Splunk
```bash
splunk start|stop|restart|status
splunk btool <conf> list [stanza] --debug        # conf effective
splunk btool check                               # erreurs de syntaxe
splunk show cluster-status [--verbose]           # CM
splunk validate cluster-bundle --check-restart   # CM
splunk apply cluster-bundle --answer-yes         # CM
splunk show cluster-bundle-status                # CM
splunk rollback cluster-bundle                   # CM
splunk enable|disable|show maintenance-mode      # CM
splunk rolling-restart cluster-peers             # CM
splunk offline [--enforce-counts]                # peer
splunk show shcluster-status [--verbose]         # membre SHC
splunk apply shcluster-bundle -target https://sh01:8089 --answer-yes   # Deployer
splunk rolling-restart shcluster-members         # membre SHC
splunk transfer shcluster-captain -mgmt_uri https://sh02:8089
splunk resync shcluster-replicated-config        # membre désynchronisé
splunk show kvstore-status / splunk backup kvstore
splunk reload deploy-server                      # DS
splunk list deploy-clients                       # DS
splunk list forward-server                       # UF : indexeurs actifs/inactifs
splunk add forward-server idx01:9997             # UF
splunk set deploy-poll ds01:8089                 # UF
splunk list inputstatus                          # état des inputs (fichiers lus...)
splunk http-event-collector list -uri https://localhost:8089
splunk diag                                      # archive de support
```

## Ports
`8000` web · `8089` REST/mgmt · `9997` S2S · `8088` HEC · `9887` réplication idx · `9200` réplication SHC (choisi) · `8191` KV store ·
`514/601/6514` syslog · `9092/9093` Kafka · `9600` Logstash API · `8200` Vault · `8081/8082` Artifactory · `443` AAP · `22` SSH

## SPL de supervision
```spl
| tstats count where index=* by index sourcetype                          # que reçoit-on ?
| tstats latest(_time) as last where index=* by host | eval age=now()-last # sources muettes
index=_internal source=*metrics.log group=queue blocked=true | stats count by host name
index=_internal sourcetype=splunkd log_level=ERROR | stats count by component | sort -count
index=_internal sourcetype=scheduler status=skipped | stats count by savedsearch_name reason
index=_internal source=*license_usage.log type=Usage | stats sum(b) as bytes by idx | eval GB=round(bytes/1024/1024/1024,2)
index=_internal component=HttpInputDataHandler log_level=ERROR           # erreurs HEC
index=_introspection sourcetype=splunk_resource_usage component=Hostwide  # CPU/RAM
index=* | eval lag=_indextime-_time | stats p95(lag) by sourcetype        # latence
| rest /services/cluster/manager/peers splunk_server=local | table label status   # (sur le CM)
```

## Ansible
```bash
ansible-inventory --graph
ansible all -m ping
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --check --diff --limit idx01
ansible-playbook site.yml --tags sc4s -v
ansible-playbook site.yml --start-at-task "Mode peer + port de réplication"
ansible-vault encrypt|view|edit secrets.yml
ansible-lint playbooks/ roles/
ansible-builder build -t ee-splunk:1.0          # Execution Environment
```

## Vault
```bash
vault status | vault operator unseal | vault login
vault kv put|get|patch|metadata get secret/splunk/prod
vault policy write|read <name>
vault auth enable approle ; vault write auth/approle/role/<r> token_policies=...
vault read auth/approle/role/<r>/role-id ; vault write -f auth/approle/role/<r>/secret-id
vault write pki/issue/<role> common_name=idx01.example.local
vault operator raft snapshot save backup.snap
```

## Kafka
```bash
kafka-topics.sh --bootstrap-server b:9092 --list | --describe --topic t
kafka-console-consumer.sh --bootstrap-server b:9092 --topic t --from-beginning --max-messages 5
kafka-consumer-groups.sh --bootstrap-server b:9092 --describe --group logstash-splunk     # LAG
kafka-consumer-groups.sh ... --reset-offsets --to-datetime 2025-01-01T00:00:00.000 --execute  # rejeu
```

## Logstash
```bash
/usr/share/logstash/bin/logstash --config.test_and_exit -f pipeline.conf --path.settings /etc/logstash
curl -s localhost:9600/_node/stats/pipelines?pretty
curl -s localhost:9600/_node/hot_threads?pretty
journalctl -u logstash -f ; tail -f /var/log/logstash/logstash-plain.log
```

## SC4S
```bash
systemctl status sc4s ; podman logs -f SC4S
podman exec SC4S syslog-ng-ctl stats
cat /opt/sc4s/env_file
echo "<134>test" | nc -u -w0 sc4s01 514
```

## HEC
```bash
curl -k https://lb:8088/services/collector/health
curl -k https://lb:8088/services/collector/event -H "Authorization: Splunk $T" \
     -d '{"event":"x","index":"app","sourcetype":"test"}'
```
