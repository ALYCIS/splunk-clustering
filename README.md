# Splunk industrialisé (CI/CD · Ansible/AAP · SC4S · Kafka · Logstash · Vault · Artifactory)

Kit de préparation **en 2 jours** pour une mission de renfort Splunk / DevOps :
comprendre l'architecture, savoir comment chaque composant parle aux autres,
et l'avoir **monté soi-même sur un cluster Proxmox**.

> Tu ne connais rien à Splunk ? Lis dans cet ordre, puis déroule le lab.

| # | Document | Contenu | Temps |
|---|----------|---------|-------|
| 0 | [docs/00-planning-2-jours.md](docs/00-planning-2-jours.md) | Le programme heure par heure | 5 min |
| 1 | [docs/01-architecture-globale.md](docs/01-architecture-globale.md) | **La vue d'ensemble de la mission** + flux + matrice des ports | 1 h |
| 2 | [docs/02-splunk-fondamentaux.md](docs/02-splunk-fondamentaux.md) | Splunk de zéro : composants, index, buckets, .conf, SPL | 2 h |
| 3 | [docs/03-splunk-clustering.md](docs/03-splunk-clustering.md) | Indexer cluster, Search Head Cluster, bundles, RF/SF | 2 h |
| 4 | [docs/04-ingestion-sc4s-kafka-logstash.md](docs/04-ingestion-sc4s-kafka-logstash.md) | Chaîne d'ingestion Syslog → SC4S / Kafka → Logstash → HEC | 1 h 30 |
| 5 | [docs/05-cicd-aap-artifactory-vault.md](docs/05-cicd-aap-artifactory-vault.md) | Git → CI → Artifactory → AAP → Splunk, secrets Vault | 1 h 30 |
| 6 | [docs/06-mco-mcs-exploitation.md](docs/06-mco-mcs-exploitation.md) | Supervision, incidents, mises à jour, runbooks | 1 h |
| 7 | [docs/07-lab-proxmox.md](docs/07-lab-proxmox.md) | **Montage du lab** pas à pas | ~1 jour |
| 8 | [docs/08-questions-entretien.md](docs/08-questions-entretien.md) | 60+ questions / réponses d'entretien | 1 h |
| 9 | [docs/09-aide-memoire.md](docs/09-aide-memoire.md) | Cheat-sheet commandes CLI, SPL, chemins, ports | à imprimer |
| 10 | [docs/10-modele-DAT.md](docs/10-modele-DAT.md) | Trame de DAT + procédure d'exploitation | 20 min |

## Arborescence du dépôt

```
.
├── docs/                    # Cours + préparation entretien
├── ansible/                 # "Industrialisation" : tout le lab est déployé par Ansible
│   ├── ansible.cfg
│   ├── inventories/lab/     # Inventaire Proxmox + variables (group_vars)
│   ├── playbooks/           # site.yml, déploiement bundles, rolling upgrade, MCO...
│   └── roles/               # splunk_common, cluster_manager, indexer, shc, sc4s, logstash...
├── splunk-apps/             # "Configuration as code" : les apps Splunk versionnées
│   ├── manager-apps/        #   -> poussées aux indexeurs par le Cluster Manager
│   ├── shcluster-apps/      #   -> poussées aux Search Heads par le Deployer
│   └── deployment-apps/     #   -> poussées aux forwarders par le Deployment Server
├── ingestion/               # SC4S, Kafka, Logstash, HAProxy (LB HEC)
├── cicd/                    # Pipeline GitLab CI + objets AAP/AWX (config as code)
└── tools/                   # Générateurs de logs de test, scripts de vérification
```

## L'architecture en une image

```mermaid
flowchart LR
  subgraph Sources
    NET[Équipements réseau<br/>FW, switch, proxy]
    SRV[Serveurs Linux/Windows]
    APP[Applications]
  end

  subgraph Ingestion
    SC4S[SC4S<br/>syslog-ng conteneur]
    KAFKA[(Kafka<br/>topics)]
    LS[Logstash<br/>pipelines]
    LB[HAProxy<br/>LB HEC :8088]
  end

  subgraph Splunk["Plateforme Splunk"]
    CM[Cluster Manager<br/>+ License Mgr + MC]
    IDX1[Indexer 1]
    IDX2[Indexer 2]
    IDX3[Indexer 3]
    DEP[Deployer<br/>+ Deployment Server]
    SH1[SH 1]
    SH2[SH 2]
    SH3[SH 3]
  end

  subgraph CICD["Chaîne CI/CD"]
    GIT[Git<br/>GitLab]
    CI[CI : lint / tests / package]
    ART[(Artifactory)]
    AAP[AAP / AWX<br/>playbooks Ansible]
    VAULT[(HashiCorp Vault)]
  end

  NET -- syslog 514/6514 --> SC4S
  SRV -- UF S2S 9997 --> IDX1 & IDX2 & IDX3
  APP -- producer --> KAFKA
  KAFKA -- consumer --> LS
  SC4S -- HEC https --> LB
  LS -- HEC https --> LB
  LB -- 8088 --> IDX1 & IDX2 & IDX3
  IDX1 <-- réplication 9887 --> IDX2 <-- 9887 --> IDX3
  CM -. bundle 8089 .-> IDX1 & IDX2 & IDX3
  DEP -. bundle 8089 .-> SH1 & SH2 & SH3
  SH1 & SH2 & SH3 -- recherche distribuée 8089 --> IDX1 & IDX2 & IDX3

  GIT --> CI --> ART
  CI -- API job launch --> AAP
  AAP -- récupère artefacts --> ART
  AAP -- récupère secrets --> VAULT
  AAP -- SSH --> CM & DEP & SC4S & LS
```

Démarrage rapide du lab : voir [docs/07-lab-proxmox.md](docs/07-lab-proxmox.md).
