# splunk-apps — la configuration Splunk « as code »

| Répertoire | Déployé sur | Par | Commande déclenchée |
|---|---|---|---|
| `manager-apps/` | Cluster Manager `etc/manager-apps/` → tous les indexeurs `etc/peer-apps/` | `playbooks/deploy_bundles.yml --tags idxc` | `splunk apply cluster-bundle` |
| `shcluster-apps/` | Deployer `etc/shcluster/apps/` → membres du SHC `etc/apps/` | `--tags shc` | `splunk apply shcluster-bundle` |
| `deployment-apps/` | Deployment Server `etc/deployment-apps/` → forwarders `etc/apps/` | `--tags ds` | `splunk reload deploy-server` |

Règles :
- Une app = un besoin, préfixe `org_` (convention des *Splunk base configs*).
- **Aucun secret dans Git** : les fichiers contenant tokens HEC / pass4SymmKey (`org_hec_inputs/local/inputs.conf`,
  `org_all_forwarder_outputs/local/outputs.conf`) sont générés par Ansible depuis Vault.
- Index-time (props/transforms de parsing, indexes.conf) → `manager-apps` ;
  search-time (KV_MODE, FIELDALIAS, dashboards, alertes, rôles) → `shcluster-apps`.
- Pas de commentaire en fin de ligne dans les `.conf`.
- La CI vérifie chaque app (`btool check`, AppInspect) avant publication dans Artifactory.
