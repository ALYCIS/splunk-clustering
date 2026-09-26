# 08 — Questions / réponses d'entretien

Conseil : lis la question, **réponds à voix haute** avant de lire la réponse. Les réponses sont
volontairement courtes : c'est le format attendu à l'oral. Appuie-toi sur ton lab (« dans mon lab, j'ai… »).

---

## A. Pitch & architecture

**1. Présentez l'architecture d'une plateforme Splunk distribuée.**
> Trois tiers : **collecte** (UF, HF, SC4S, HEC), **indexation** (cluster d'indexeurs piloté par un
> Cluster Manager, RF/SF), **recherche** (Search Head Cluster d'au moins 3 membres alimenté par un
> Deployer). Plus des rôles de management : License Manager, Deployment Server pour les forwarders,
> Monitoring Console. Tout communique en REST sur 8089, les données en S2S 9997 ou HEC 8088.

**2. Expliquez le chemin d'un log de pare-feu jusqu'à l'écran de l'analyste.**
> FW → syslog 514/6514 → SC4S (identification du produit, index `netfw`, sourcetype `cisco:asa`) → HEC
> via LB → indexeur (typing, écriture dans un bucket hot, réplication vers RF-1 peers sur 9887) →
> l'analyste lance une recherche sur un SH → le SH demande la liste des peers au CM, distribue la
> recherche aux indexeurs (8089), fusionne les résultats → affichage.

**3. Pourquoi Kafka entre les applications et Splunk ?**
> Découplage (les équipes applicatives publient sans connaître Splunk), **tampon** en cas
> d'indisponibilité ou de maintenance Splunk (rétention de plusieurs jours), absorption des pics,
> multi-consommateurs (Splunk + datalake), rejeu possible.

**4. Pourquoi Logstash si Splunk sait parser ?**
> Transformations en amont (normalisation, enrichissement, suppression de champs, filtrage du DEBUG
> → économie de **licence**), routage multi-destinations, et c'est le consommateur Kafka naturel.
> Alternative : Splunk Connect for Kafka (sink Kafka Connect) si pas de transformation.

**5. Pourquoi SC4S plutôt qu'un rsyslog + UF ?**
> Solution supportée par Splunk, parsers maintenus pour des centaines de produits, sourcetypes
> conformes aux TA/CIM, conteneur immuable (upgrade = changement d'image), envoi HEC avec
> buffer disque, config minimale par variables d'environnement → facile à industrialiser.

## B. Splunk cœur

**6. Différence UF / HF ?**
> L'UF est un agent léger qui ne parse pas (sauf données structurées) ; le HF est un Splunk
> complet qui parse, filtre, route, masque, et héberge des add-ons de collecte (API, DB Connect).

**7. Qu'est-ce qu'un sourcetype et pourquoi est-il crucial ?**
> Il décrit le format de la donnée ; il pilote découpage, horodatage et extractions. Un mauvais
> sourcetype = dates fausses, événements fusionnés, CIM non respecté, détections SOC inopérantes.

**8. Index-time vs search-time ?**
> Index-time : line breaking, timestamp, TRANSFORMS (routage, nullQueue), SEDCMD → sur **indexeurs/HF**,
> irréversible, coûteux à changer. Search-time : EXTRACT, REPORT, FIELDALIAS, EVAL, LOOKUP → sur les
> **SH**, modifiable à chaud. On privilégie le search-time.

**9. Cycle de vie d'un bucket ?**
> hot → warm → cold → frozen (supprimé ou archivé) ; thawed pour la restauration. Paramètres :
> `maxDataSize`, `maxWarmDBCount`, `frozenTimePeriodInSecs`, `maxTotalDataSizeMB`, volumes.

**10. Comment définir la rétention d'un index à 1 an et 2 To max ?**
> `frozenTimePeriodInSecs = 31536000` et `maxTotalDataSizeMB = 2000000` ; la première des deux
> conditions atteinte gèle les buckets les plus anciens. Attention : c'est par peer.

**11. Précédence des fichiers de configuration ?**
> `system/local` > `apps/*/local` > `apps/*/default` > `system/default` (contexte global) ; au
> search-time, l'app courante prime. Sur un peer, `peer-apps` passe avant `apps`. On vérifie avec
> `splunk btool <conf> list --debug`.

**12. Comment dépanner une source qui n'arrive plus ?**
> Du plus proche de la source au plus loin : la source émet-elle (tcpdump) ? flux réseau ouvert ?
> SC4S/UF reçoit-il (logs, `splunk list forward-server`) ? `index=_internal host=<uf>` ? erreurs HEC
> (token, index inexistant) ? queues bloquées ? mauvaise date (événements « dans le futur ») ?

**13. Qu'est-ce que le HEC et comment le sécuriser ?**
> HTTP Event Collector, port 8088, authentification par **token** lié à des index autorisés.
> TLS obligatoire, un token par source/équipe, tokens dans Vault, restriction `indexes=`, LB avec
> health-check, *indexer acknowledgement* si garantie de livraison requise.

**14. Qu'est-ce que le CIM ?**
> Common Information Model : noms de champs et tags normalisés par domaine (Authentication,
> Network_Traffic…) pour que les corrélations (ES) fonctionnent quelle que soit la source. Les TA
> fournissent le mapping.

## C. Clustering

**15. RF et SF ?**
> RF = nombre de copies de chaque bucket, SF = nombre de copies recherchables (avec tsidx).
> RF=3/SF=2 : on tolère la perte de 2 peers sans perte de données, d'1 peer sans perte de recherchabilité.

**16. Que se passe-t-il quand un indexeur tombe ?**
> Le CM détecte l'absence de heartbeat (~60 s), réaffecte les primaires sur les copies
> recherchables restantes (cluster toujours *valid*), puis lance le **bucket fixup** pour recréer
> les copies manquantes. Les forwarders basculent automatiquement vers les autres peers.

**17. Pourquoi le maintenance mode ?**
> Pour éviter que le CM lance des fixups massifs (réplications inutiles) pendant un redémarrage
> ou une mise à jour planifiés. Il suspend aussi le roll des buckets hot.

**18. Comment déployer une conf sur les indexeurs d'un cluster ?**
> Jamais en local : dans `etc/manager-apps` du CM, puis `splunk validate cluster-bundle
> --check-restart` et `splunk apply cluster-bundle`. Le CM pousse le bundle dans `etc/peer-apps`
> et fait un rolling restart si nécessaire. Rollback : `splunk rollback cluster-bundle`.

**19. Et sur un SHC ?**
> Apps dans `etc/shcluster/apps` du Deployer, `splunk apply shcluster-bundle -target <membre>`.
> Les objets créés par les utilisateurs via l'UI sont répliqués entre membres automatiquement.

**20. Pourquoi 3 membres minimum dans un SHC ?**
> Élection du captain par consensus Raft : il faut une **majorité** ; avec 2 membres, la perte
> d'un seul bloque l'élection. 3 membres tolèrent 1 panne, 5 en tolèrent 2.

**21. Rôle du captain ?**
> Planifier et répartir les recherches planifiées, coordonner la réplication des artefacts et de
> la configuration, pousser les bundles reçus du deployer. Il est élu dynamiquement.

**22. Indexer discovery ?**
> Les forwarders demandent au CM la liste des peers (et leur poids selon l'espace disque) au lieu
> d'avoir une liste statique : ajout/retrait d'indexeurs sans toucher aux forwarders.

**23. Cluster multisite ?**
> Peers répartis par site, `site_replication_factor = origin:2,total:3`, `site_search_factor`,
> *search affinity* (les SH lisent en priorité leur site). Permet un PRA/PCA inter-datacenter.

**24. SmartStore ?**
> Buckets warm stockés sur un stockage objet S3-compatible, cache local sur les indexeurs.
> Découple calcul et stockage, réduit le coût disque, accélère l'ajout/retrait d'indexeurs.

**25. Ordre de mise à jour d'une plateforme ?**
> LM/CM (maintenance mode) → SHC (deployer puis membres) → indexeurs en rolling
> (`upgrade-init`, `offline`, upgrade, `upgrade-finalize`) → DS/HF → UF. Toujours DEV puis REC puis PROD,
> sauvegarde de `etc/` et du KV store avant.

## D. Ansible / AAP

**26. Qu'est-ce que l'idempotence ? Un exemple de piège avec Splunk ?**
> Rejouer un playbook donne le même état sans changement. Piège : Splunk **chiffre** `pass4SymmKey`
> au démarrage, donc un template qui réécrit la valeur en clair provoque un changement + restart à
> chaque exécution. Solution : écrire les secrets une seule fois (`force: false`) avec une variable
> explicite de rotation, ou passer par la CLI/REST avec un contrôle préalable.

**27. Comment faire un rolling restart avec Ansible ?**
> `serial: 1` sur le groupe, `delegate_to` le CM pour activer le maintenance mode, `splunk offline`,
> redémarrage, attente de l'état *Up* via l'API REST du CM (`uri` + `until`/`retries`), puis nœud suivant.
> Ou simplement la commande native `splunk rolling-restart cluster-peers` lancée par Ansible.

**28. Structure d'un rôle ?**
> `tasks/`, `handlers/`, `templates/`, `files/`, `defaults/` (surchargeable), `vars/` (prioritaire),
> `meta/` (dépendances). Un rôle par composant (splunk_indexer, sc4s, logstash…).

**29. Comment gérer plusieurs environnements ?**
> Mêmes rôles/playbooks, un inventaire par environnement (`inventories/dev|rec|prod`), variables
> dans `group_vars`, secrets Vault par chemin d'environnement, promotion par la CI.

**30. Différences AWX / AAP ?**
> AWX est l'upstream open source ; AAP est le produit supporté Red Hat : Controller, Automation Hub
> privé, Execution Environments certifiés, Event-Driven Ansible, gateway unifiée (2.5), support et cycle de vie.

**31. Qu'est-ce qu'un Execution Environment ?**
> Une image conteneur contenant ansible-core, les collections et les dépendances Python, construite
> avec `ansible-builder`, stockée dans un registry (Automation Hub / Artifactory). Garantit que le
> job tourne partout avec les mêmes versions.

**32. Job template vs workflow ?**
> Job template = un playbook + inventaire + credentials + variables. Workflow = graphe de job
> templates avec branches succès/échec, nœuds d'approbation, inventaire commun (ex. idxc → shc → ds → healthcheck).

**33. Comment la CI déclenche AAP ?**
> Appel API REST `POST /api/v2/job_templates/<id>/launch/` (ou `workflow_job_templates`) avec un
> token OAuth stocké dans Vault, extra_vars (environnement, version), puis suivi du statut (`--monitor`).

**34. Comment tester un playbook avant la prod ?**
> `ansible-lint`, `--syntax-check`, `--check --diff`, Molecule, exécution en DEV/REC, revue de MR.

## E. Vault / Artifactory

**35. Comment AAP récupère-t-il un secret dans Vault ?**
> Credential « HashiCorp Vault Secret Lookup » (auth AppRole ou certificat), lié au champ d'un
> autre credential (mot de passe machine, credential custom) : la valeur est lue au lancement du job,
> jamais stockée dans AAP. Autre option : lookup `community.hashi_vault` dans le playbook.

**36. AppRole ?**
> Méthode d'auth machine : `role_id` (identifiant, peu sensible) + `secret_id` (secret, TTL court,
> éventuellement *response wrapping*). Le token obtenu porte les policies du rôle.

**37. Seal / unseal ?**
> Au démarrage, Vault ne peut pas déchiffrer ses données : il faut reconstituer la clé maître
> (Shamir, N clés sur M) ou utiliser l'**auto-unseal** (KMS cloud, HSM, Transit d'un autre Vault).

**38. KV v1 vs v2 ?**
> v2 est versionné (historique, rollback, soft delete), chemins API `secret/data/...` et `secret/metadata/...`.

**39. Qu'est-ce que vous stockeriez dans Vault pour Splunk ?**
> Admin password, pass4SymmKey (idxc, shc, general), tokens HEC, `splunk.secret`, compte bind LDAP,
> certificats (via le moteur **PKI**), token API AAP, identifiants Artifactory et Kafka SASL.

**40. Rotation d'un token HEC sans perte ?**
> Créer le nouveau token (bundle), reconfigurer les clients (SC4S/Logstash) via Ansible, vérifier
> qu'il n'y a plus de trafic sur l'ancien (`_internal` HEC metrics), puis désactiver l'ancien.

**41. Pourquoi Artifactory ?**
> Source unique d'artefacts versionnés et immuables (binaires Splunk, apps, images, collections),
> accès sans Internet pour les serveurs, traçabilité (build info), promotion entre dépôts, rollback.

**42. Remote vs local vs virtual repository ?**
> Local = artefacts internes ; remote = cache proxy d'un dépôt public ; virtual = agrégat derrière une seule URL.

## F. Ingestion

**43. UDP ou TCP pour le syslog ?**
> UDP : universel, pas de back-pressure mais pertes possibles. TCP : fiable au transport, contrôle
> de flux. TLS (6514) : confidentialité. En prod SOC : TCP/TLS dès que l'équipement le permet.

**44. Comment rendre SC4S hautement disponible ?**
> Plusieurs instances derrière une VIP (keepalived) ou un LB L4 qui **préserve l'IP source**,
> buffer disque, supervision des métriques SC4S.

**45. Consumer group Kafka ?**
> Ensemble de consommateurs se partageant les partitions d'un topic ; une partition n'est lue que
> par un membre du groupe. Parallélisme max = nombre de partitions. Offsets commités par groupe.

**46. Qu'est-ce que le lag et que faire s'il augmente ?**
> Écart entre le dernier message produit et le dernier consommé. S'il monte : Logstash trop lent
> (filtres coûteux, JVM), HEC saturé (503), réseau. Actions : ajouter des instances Logstash (≤ nb
> partitions), optimiser les filtres, augmenter les workers/batch, vérifier les queues Splunk.

**47. Queue mémoire vs persistante dans Logstash ?**
> Mémoire : rapide mais perte des événements en vol au crash. Persistante (disque) : survit au
> redémarrage, absorbe les pics. Avec Kafka en amont, la mémoire est acceptable car on rejoue depuis l'offset.

**48. Comment superviser un pipeline Logstash ?**
> API `:9600/_node/stats/pipelines` (in/out, durée par plugin, queue), logs, un **heartbeat**
> envoyé dans Splunk + alerte si absent, lag Kafka, erreurs HEC côté Splunk.

## G. MCO / MCS

**49. Votre check du matin ?**
> Health report / MC, `cluster-status` (valid/complete), `shcluster-status` + KV store, licence,
> recherches skipped, queues bloquées, sources muettes, lag Kafka, jobs AAP en échec, disques.

**50. Recherches « skipped » : causes et remèdes ?**
> Trop de recherches planifiées simultanées par rapport aux quotas (cœurs CPU). Étaler les
> crons, `schedule_window`, optimiser (tstats, data models accélérés), ajuster `limits.conf`, ajouter des SH.

**51. Latence d'indexation élevée ?**
> Mesurer `_indextime - _time` par sourcetype. Horloge source fausse (NTP/TZ) ou vraie latence
> (queues bloquées, disque lent, pipeline surchargé, backlog Kafka).

**52. Comment gérez-vous un incident de licence ?**
> Identifier l'index/sourcetype/host responsable (`license_usage.log`), filtrer (nullQueue, drop
> Logstash), corriger la source bavarde, informer. Selon le type de licence, des dépassements répétés
> peuvent bloquer la recherche (anciens modèles / petites licences) ; sur les licences récentes le blocage
> ne s'applique plus mais le dépassement reste un sujet contractuel.

**53. Qu'est-ce que le MCS pour Splunk ?**
> Patchs de sécurité (advisories SVD), TLS partout, rotation des secrets/certificats, RBAC au
> moindre privilège, durcissement OS, audit (Vault, AAP, Splunk `_audit`), revue des apps tierces.

**54. Comment documentez-vous ?**
> **DAT** (architecture, flux, matrice des ports, dimensionnement, HA/PRA, sécurité), **DEX / procédures
> d'exploitation** (démarrage/arrêt, ajout de source, montée de version, incidents types), README dans
> les dépôts, runbooks liés aux alertes, changelog des versions déployées.

## H. Questions comportementales

**55. Racontez une automatisation dont vous êtes fier.** → Raconte ton lab : « reconstruction complète d'un
cluster Splunk + chaîne d'ingestion en 30 min par Ansible, secrets dans Vault, déploiement des apps
par workflow ». Structure STAR (Situation, Tâche, Action, Résultat).

**56. Un changement a cassé la prod, que faites-vous ?** → Stabiliser d'abord (rollback de l'artefact N-1 /
`rollback cluster-bundle`), communiquer, analyser la cause, corriger dans Git, renforcer la CI (test
qui aurait détecté le problème), post-mortem sans blâme.

**57. Comment priorisez-vous entre demandes projet et MCO ?** → Incidents production d'abord (impact SOC =
détection de sécurité), puis changements planifiés ; automatiser les tâches récurrentes pour libérer du temps.

---

## Questions à poser au client (montre ta séniorité)

- Volumétrie actuelle (Go/jour), nombre d'environnements, on-prem ou cloud, multisite ?
- Splunk Enterprise Security est-il utilisé ? Qui gère les use-cases de détection ?
- Version d'AAP, Execution Environments existants, qui gère la plateforme AAP ?
- Kafka est-il géré par une autre équipe ? Qui possède les pipelines Logstash ?
- Méthode de déploiement actuelle (manuelle, partiellement automatisée) et principaux irritants ?
- Organisation du run : astreinte, outil de ticketing, SLA ?
