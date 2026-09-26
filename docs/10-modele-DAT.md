# 10 — Trame de DAT et de procédure d'exploitation

La fiche de poste demande de « rédiger de la documentation technique (DAT, procédures
d'exploitation) ». Voici les trames à connaître ; savoir **ce qu'on y met** suffit en entretien.

## 1. DAT — Dossier d'Architecture Technique (plateforme Splunk)

1. **Objet et périmètre** — environnements couverts (DEV / REC / PROD), exclusions.
2. **Contexte et exigences**
   - Fonctionnelles : sources à collecter, cas d'usage SOC, rétention légale par type de log.
   - Non fonctionnelles : volumétrie (Go/j, EPS), disponibilité cible, RPO/RTO, performances de recherche, sécurité.
3. **Architecture logique** — schéma des tiers (collecte, ingestion, indexation, recherche, management) et de la chaîne CI/CD.
4. **Architecture physique** — serveurs, dimensionnement (vCPU/RAM/disques/IOPS), OS, zones réseau, sites.
5. **Matrice des flux** — source, destination, port, protocole, chiffrement, justification (cf. [01 §4.1](01-architecture-globale.md)).
6. **Composants et versions** — Splunk, SC4S, Kafka, Logstash, AAP, Vault, Artifactory ; apps / TA installés.
7. **Stockage et rétention** — index, volumes hot/warm/cold, `frozenTimePeriodInSecs`, archivage, calcul de capacité.
8. **Haute disponibilité et PRA** — RF/SF, SHC, multisite, redondance SC4S/Logstash/Kafka, LB ; scénarios de panne.
9. **Sécurité** — authentification (LDAP/SAML), rôles et accès aux index, TLS/PKI, gestion des secrets (Vault), durcissement, journalisation d'audit.
10. **Industrialisation** — dépôts Git, pipeline CI, Artifactory, AAP (job templates, workflows), gestion des environnements.
11. **Exploitation** — supervision (MC, alertes), sauvegardes, montée de version, gestion des licences.
12. **Annexes** — conventions de nommage (index, apps `org_*`, sourcetypes), glossaire, références.

## 2. Procédure d'exploitation — modèle

```
Titre        : Ajout d'une nouvelle source syslog
Référence    : PEX-SPL-012        Version : 1.2        Auteur / Valideur / Date
Objet        : Raccorder un nouvel équipement réseau à Splunk via SC4S
Prérequis    : ouverture de flux (équipement -> VIP SC4S 514/tcp ou 6514), index existant,
               TA du produit présent sur les SH et indexeurs
Impact       : aucun (pas de redémarrage Splunk ; restart SC4S < 5 s si conf modifiée)
Étapes       :
  1. Vérifier si SC4S reconnaît nativement le produit (doc SC4S "Sources")
  2. Si besoin : MR sur ingestion/sc4s (splunk_metadata.csv / port dédié)
  3. Si nouvel index : MR sur splunk-apps/manager-apps/org_all_indexes
  4. Pipeline CI vert -> lancement workflow AAP "Ingestion - deploy" puis "Splunk - deploy apps"
  5. Configurer l'équipement (IP VIP, port, format)
Contrôles    : index=<idx> sourcetype=<st> earliest=-15m | stats count by host
               vérifier _time vs _indextime, extraction des champs CIM
Retour arrière : revert de la MR + relance du workflow (artefact N-1)
Contacts     : équipe réseau, équipe SOC
```

## 3. Autres procédures à prévoir
- Démarrage / arrêt ordonné de la plateforme.
- Rolling restart et montée de version (Splunk, SC4S, Logstash, Kafka).
- Ajout / retrait d'un indexeur, d'un membre SHC.
- Rotation des secrets (pass4SymmKey, tokens HEC, secret_id AppRole) et renouvellement des certificats.
- Restauration de données archivées (thaw).
- Gestion d'incident : source muette, queues bloquées, cluster non valide, SHC sans captain, KV store en échec, lag Kafka.
- Sauvegarde / restauration de la configuration et du KV store.
