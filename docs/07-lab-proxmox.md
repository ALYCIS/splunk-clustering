# 07 — Monter le lab sur Proxmox

## 1. Topologie du lab

Deux profils selon les ressources de ton cluster Proxmox.

### Profil « complet » (≈ 40 Go RAM) — reproduit l'architecture de la mission

| VM | Rôles | vCPU | RAM | Disque | IP (exemple) |
|---|---|---:|---:|---:|---|
| `cm01` | Cluster Manager + License Manager + Monitoring Console | 2 | 4 Go | 30 Go | 10.10.10.10 |
| `idx01..03` | Indexeurs (peers) | 2 | 4 Go | 60 Go | 10.10.10.11-13 |
| `sh01..03` | Search Head Cluster | 2 | 4 Go | 30 Go | 10.10.10.21-23 |
| `dep01` | SHC Deployer + Deployment Server | 1 | 2 Go | 20 Go | 10.10.10.20 |
| `ing01` | SC4S (podman) + Kafka (KRaft) + Logstash + HAProxy (LB HEC) | 4 | 8 Go | 40 Go | 10.10.10.30 |
| `ops01` | Vault + Artifactory OSS + (optionnel) AWX sur k3s + Gitea/GitLab | 4 | 12 Go | 60 Go | 10.10.10.40 |
| `lnx01` | Client : Universal Forwarder + générateur de logs | 1 | 1 Go | 10 Go | 10.10.10.50 |

### Profil « léger » (≈ 20 Go RAM)
- `cm01` (CM+LM+MC+Deployer+DS), `idx01..03` (RF=2/SF=2 possible avec 2), **un seul** `sh01`
  (pas de SHC, mettre `shc_enabled: false`), `ing01`, `ops01` sans AWX.

OS conseillé : **Rocky Linux 9 / AlmaLinux 9** (proche de RHEL en entreprise) ou Ubuntu 22.04/24.04.

## 2. Préparer les VM (template cloud-init)

Sur un nœud Proxmox :
```bash
wget https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2
qm create 9000 --name rocky9-tpl --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
qm importdisk 9000 Rocky-9-GenericCloud-Base.latest.x86_64.qcow2 local-lvm
qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
qm set 9000 --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0
qm set 9000 --ciuser ansible --sshkeys ~/.ssh/id_ed25519.pub --ipconfig0 ip=dhcp
qm template 9000
```
Puis cloner (script [`tools/proxmox_create_vms.sh`](../tools/proxmox_create_vms.sh)) :
```bash
bash tools/proxmox_create_vms.sh    # adapte BRIDGE, STORAGE, GW, et la liste des VM en tête du script
```

Ajoute les noms dans le DNS ou dans `/etc/hosts` de ta machine d'administration
(le rôle `splunk_common` remplit `/etc/hosts` sur toutes les VM).

## 3. Machine de contrôle Ansible

```bash
python3 -m venv ~/venv-ansible && source ~/venv-ansible/bin/activate
pip install ansible-core ansible-lint yamllint hvac
cd ansible
ansible-galaxy collection install -r requirements.yml
# Déposer les binaires dans ansible/files/ (ou dans Artifactory, cf. §7)
#   splunk-9.x.x-xxxx-Linux-x86_64.tgz
#   splunkforwarder-9.x.x-xxxx-Linux-x86_64.tgz
vi inventories/lab/hosts.yml          # IP de tes VM
vi inventories/lab/group_vars/all/main.yml   # version Splunk, nom du tgz
ansible all -m ping
```

## 4. Secrets : d'abord sans Vault, puis avec

Au début, les secrets viennent de `inventories/lab/group_vars/all/secrets.yml` (copie de
`secrets.yml.example`, **ignoré par Git**, idéalement chiffré avec `ansible-vault encrypt`).
Une fois Vault en place (§7), passe `secrets_backend: hashicorp_vault` : les mêmes variables sont
alors lues dans Vault.

## 5. Déploiement de Splunk

```bash
# Tout le socle Splunk : OS, install, LM, CM, peers, SHC, deployer, DS, MC
ansible-playbook playbooks/site.yml --tags splunk

# Vérifications
ansible cluster_manager -b -m shell -a "/opt/splunk/bin/splunk show cluster-status -auth admin:'{{ splunk_admin_password }}'" -e @inventories/lab/group_vars/all/secrets.yml
```
Puis Web : `http://sh01:8000` (et `http://cm01:8000` → *Settings → Indexer clustering*).

**Exercices** :
1. Arrêter `idx02` (`systemctl stop Splunkd`) → observer sur le CM le cluster passer *non complete*, les fixups, puis redémarrer.
2. Ajouter un index dans `splunk-apps/manager-apps/org_all_indexes/local/indexes.conf` → `ansible-playbook playbooks/deploy_bundles.yml --tags idxc` → vérifier sur un peer (`/opt/splunk/etc/peer-apps/`).
3. Ajouter un dashboard dans `splunk-apps/shcluster-apps/org_soc_dashboards` → `--tags shc`.
4. `ansible-playbook playbooks/rolling_restart.yml` en observant le CM.
5. Transférer le captain SHC : `splunk transfer shcluster-captain -mgmt_uri https://sh03:8089`.

## 6. Chaîne d'ingestion

```bash
ansible-playbook playbooks/site.yml --tags ingestion   # HAProxy + SC4S + Kafka + Logstash
ansible-playbook playbooks/site.yml --tags uf          # UF sur lnx01, piloté par le DS

# Tests
bash ../tools/send_syslog.sh ing01                     # messages syslog variés → SC4S
bash ../tools/produce_kafka.sh ing01                   # messages JSON → Kafka → Logstash
```
Dans Splunk :
```spl
index=netfw OR index=osnix OR index=netops earliest=-15m | stats count by index, sourcetype, host
index=app sourcetype=app:json | table _time host level msg
index=main sourcetype="sc4s:events"
| tstats count where index=* by index sourcetype
```
Exercices : arrêter les indexeurs 5 min pendant l'injection Kafka → le lag monte → redémarrer → le lag se résorbe, **aucune perte** (`stats count`).

## 7. Vault + Artifactory

```bash
ansible-playbook playbooks/site.yml --tags ops         # Vault (conteneur, mode serveur raft 1 nœud) + Artifactory OSS
# Initialisation Vault (une fois) :
ssh ops01 && sudo -i
alias vault='podman exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN vault vault'
vault operator init -key-shares=1 -key-threshold=1    # NOTER unseal key + root token
vault operator unseal <key>
export VAULT_TOKEN=<root token>
# Reprendre les secrets déjà utilisés par le lab (sinon Vault en génère de nouveaux) :
export ADMIN_PASSWORD='...' IDXC_KEY='...' SHC_KEY='...' HEC_SC4S='...' HEC_LOGSTASH='...'
bash /opt/vault/bootstrap.sh                           # KV v2, secrets du lab, policy, AppRole, audit
```
Puis dans `group_vars/all/main.yml` :
```yaml
secrets_backend: hashicorp_vault
vault_addr: http://ops01:8200
```
et exporter `ANSIBLE_HASHI_VAULT_ROLE_ID` / `ANSIBLE_HASHI_VAULT_SECRET_ID` (affichés par le bootstrap). Relancer
`ansible-playbook playbooks/site.yml --check --diff` : aucun changement → les secrets Vault sont bien les mêmes.

Artifactory OSS : `http://ops01:8082` (admin / password à changer). Créer un repo **Generic**
`splunk-generic`, y déposer les `.tgz` Splunk, puis `splunk_download_from: artifactory` dans l'inventaire.

> Artifactory OSS n'a que les dépôts *Generic/Maven/Gradle* : pour un registry Docker dans le lab, utilise
> un registry `registry:2` ou Nexus OSS. En entreprise, Artifactory Pro/Enterprise gère tout.

## 8. AWX (AAP open source) — optionnel mais très utile pour l'entretien

```bash
# Sur ops01 (≥ 4 vCPU / 8 Go dispo)
curl -sfL https://get.k3s.io | sh -
git clone https://github.com/ansible/awx-operator.git && cd awx-operator
git checkout <dernier tag>   # ex. 2.19.1
export NAMESPACE=awx && make deploy
kubectl apply -f /path/to/repo/cicd/aap/awx-instance.yml -n awx
kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 -d
```
Puis configurer AWX **en code** : `ansible-playbook cicd/aap/configure_controller.yml` (organisation, projet Git,
inventaire, credentials Vault, job templates, workflow). Reproduire le cycle : commit → pipeline → job AWX.

Pour Git + CI dans le lab : **GitLab CE** (≥ 4 Go RAM) ou **Gitea + act_runner** (très léger). Le fichier
[`cicd/gitlab/.gitlab-ci.yml`](../cicd/gitlab/.gitlab-ci.yml) sert de référence.

## 9. Nettoyage / reconstruction

Tout est reproductible : `qm destroy` des VM, re-clonage, `ansible-playbook playbooks/site.yml`.
C'est **l'argument n°1 à raconter en entretien** : « mon lab se reconstruit entièrement en ~30 min par Ansible ».
