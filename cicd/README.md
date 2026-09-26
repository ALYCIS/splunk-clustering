# CI/CD

| Fichier | Rôle |
|---|---|
| `gitlab/.gitlab-ci.yml` | Pipeline de référence : lint → validation Splunk → package → Artifactory → lancement du workflow AAP |
| `aap/awx-instance.yml` | Instance AWX (awx-operator sur k3s) pour le lab |
| `aap/configure_controller.yml` | Tous les objets AAP en code : organisation, credentials (dont lookup Vault), projet, inventaire, job templates, planification, workflow |

Cycle complet : voir [docs/05-cicd-aap-artifactory-vault.md](../docs/05-cicd-aap-artifactory-vault.md).

> Simplification du lab : `deploy_bundles.yml` copie les apps depuis le checkout Git du projet AAP.
> En mission, la variante courante est de télécharger l'archive `app-<app_version>.tgz` depuis
> Artifactory (artefact immuable, déjà validé par la CI) — c'est ce qui garantit que ce qui part
> en PROD est exactement ce qui a été testé en REC, et permet le rollback vers N-1.
