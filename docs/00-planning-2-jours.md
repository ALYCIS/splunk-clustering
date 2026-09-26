# Planning de préparation — 2 jours

Objectif : à la fin, être capable de **dessiner l'architecture au tableau**, d'expliquer
**chaque flux (qui parle à qui, sur quel port, pour quoi)**, et de raconter
**une vraie expérience de lab** (« je l'ai monté, voilà ce qui a cassé et comment j'ai corrigé »).

Principe : on alterne **théorie courte → pratique immédiate**. Le lab est lancé tôt
(les téléchargements / installations tournent pendant qu'on lit).

---

## Jour 1 — Splunk de zéro jusqu'au cluster

| Horaire | Activité | Support |
|---|---|---|
| 08:30 – 09:00 | Créer un compte splunk.com, télécharger Splunk Enterprise 9.x `.tgz` (Linux) + Universal Forwarder. Créer les VM Proxmox (template cloud-init). | [07-lab-proxmox](07-lab-proxmox.md) §1-2 |
| 09:00 – 10:00 | **Vue d'ensemble de la mission** : lire l'architecture globale, recopier le schéma à la main. | [01-architecture-globale](01-architecture-globale.md) |
| 10:00 – 12:00 | **Fondamentaux Splunk** : composants, index, buckets, pipeline d'ingestion, `.conf`, précédence, btool. | [02-splunk-fondamentaux](02-splunk-fondamentaux.md) |
| 12:00 – 13:00 | *Pratique* : installer **un Splunk standalone à la main** (sans Ansible) sur une VM, créer un index, envoyer un fichier, faire 10 recherches SPL. | [02](02-splunk-fondamentaux.md) §9 |
| 14:00 – 16:00 | **Clustering** : indexer cluster (CM, peers, RF/SF, bundle), SHC (deployer, captain, KV store). | [03-splunk-clustering](03-splunk-clustering.md) |
| 16:00 – 18:30 | *Pratique* : lancer `ansible-playbook playbooks/site.yml --tags splunk` → cluster d'indexeurs + SHC. Vérifier dans le Monitoring Console. Casser un indexeur, observer la « bucket fixup ». | [07](07-lab-proxmox.md) §4-5 |
| 18:30 – 19:00 | Relire l'aide-mémoire, noter ses questions. | [09-aide-memoire](09-aide-memoire.md) |

## Jour 2 — Ingestion, industrialisation, exploitation, entretien

| Horaire | Activité | Support |
|---|---|---|
| 08:30 – 10:00 | **Chaîne d'ingestion** : Syslog, SC4S, Kafka, Logstash, HEC, LB. | [04-ingestion](04-ingestion-sc4s-kafka-logstash.md) |
| 10:00 – 11:30 | *Pratique* : déployer SC4S + Kafka + Logstash + HAProxy, envoyer des logs de test (`tools/`), les retrouver dans Splunk. | [07](07-lab-proxmox.md) §6 |
| 11:30 – 13:00 | **CI/CD** : GitLab CI, Artifactory, AAP (AWX), Vault. Comprendre le cycle « commit → prod ». | [05-cicd](05-cicd-aap-artifactory-vault.md) |
| 14:00 – 15:30 | *Pratique* : Vault (KV v2 + AppRole), lookup depuis Ansible, dépôt d'une app dans Artifactory, déploiement via le playbook `deploy_bundles.yml`. (AWX si le temps le permet.) | [07](07-lab-proxmox.md) §7-8 |
| 15:30 – 16:30 | **MCO / MCS** : supervision, incidents types, rolling restart, upgrade, maintenance mode. *Pratique* : `playbooks/rolling_restart.yml`. | [06-mco-mcs](06-mco-mcs-exploitation.md) |
| 16:30 – 17:00 | Documentation : parcourir la trame de DAT (savoir en parler). | [10-modele-DAT](10-modele-DAT.md) |
| 17:00 – 18:30 | **Préparation entretien** : questions/réponses à voix haute, pitch de 2 min, dessin d'archi en 5 min. | [08-questions-entretien](08-questions-entretien.md) |

---

## Si tu manques de temps (version « survie », 6 h)

1. [01-architecture-globale](01-architecture-globale.md) — 1 h (le plus important)
2. [02](02-splunk-fondamentaux.md) §1 à §6 + [03](03-splunk-clustering.md) §1 à §4 — 2 h
3. [04](04-ingestion-sc4s-kafka-logstash.md) + [05](05-cicd-aap-artifactory-vault.md) résumés — 1 h
4. [08-questions-entretien](08-questions-entretien.md) — 2 h

## Les 10 phrases à savoir dire sans hésiter

1. « Un **indexer cluster** est piloté par un **Cluster Manager** ; il garantit *RF* copies brutes et *SF* copies recherchables de chaque bucket. »
2. « La configuration des indexeurs clusterisés ne se fait **jamais en local** : on la pousse depuis `etc/manager-apps` du CM avec `splunk apply cluster-bundle`. »
3. « Côté recherche, un **SHC** de 3 membres minimum élit un **captain** (Raft) ; les apps sont poussées par le **Deployer** (`etc/shcluster/apps`). »
4. « Les **forwarders** sont gérés par le **Deployment Server** (`serverclass.conf`) ; ils envoient en S2S sur **9997** avec load-balancing automatique, idéalement via *indexer discovery*. »
5. « **SC4S** est un syslog-ng conteneurisé fourni par Splunk : il reçoit en 514/6514, identifie la source, attribue *sourcetype* / index et envoie en **HEC** (8088). »
6. « **Kafka** découple producteurs et consommateurs, sert de tampon en cas d'indisponibilité de Splunk ; **Logstash** consomme les topics, transforme, puis envoie en HEC. »
7. « Les secrets (pass4SymmKey, tokens HEC, mot de passe admin) sont dans **Vault** ; AAP les récupère au runtime via un *credential lookup*, jamais en clair dans Git. »
8. « Les binaires Splunk, les apps packagées et les collections Ansible sont dans **Artifactory** : versionnés, traçables, déployables sans Internet. »
9. « Une **mise à jour** se fait dans l'ordre : License Manager / CM → Search Heads → Indexeurs (rolling, maintenance mode) → forwarders. »
10. « Le **Monitoring Console** et les index internes (`_internal`, `_introspection`, `_audit`) sont la base de la supervision MCO. »
