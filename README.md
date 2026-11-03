# Database DevOps — configuración utilizada

Actualizado al 3 de noviembre de 2026, a partir de los archivos y la conversación de la implementación.

- **001 confirmado:** creación de DEVOPS_CHANGE_DEMO y repetición con Run: 0 / Previously run: 1.
- **002 preparado y corregido:** añade ESTADO. El último log aportado falló al analizar un XML sin cierre de changeSet. El changelog local ya está corregido; no se recibió confirmación de ejecución exitosa posterior.
- Esta actualización no hace push, no sincroniza la VM y no modifica los artefactos Inline ni ATP.

La guía completa está en [CONFIGURACION_COMPLETA_OCI_DATABASE_DEVOPS.md](CONFIGURACION_COMPLETA_OCI_DATABASE_DEVOPS.md). La sección 10.0 cubre preparación de paquetes y la sección 28 contiene la segunda prueba/corrección con todos los comandos.

## Archivos y uso

- build_spec.yaml: Managed Build; empaquetado genérico sin Python.
- db/changelog.xml: entrada Liquibase con changesets 001 y 002, separados y cerrados.
- db/changes/001_create_devops_demo.sql: creación de tabla aplicada.
- db/changes/002_add_estado.sql: ALTER TABLE para ESTADO; ejecución exitosa pendiente de evidencia.
- scripts/verify.sql: comprobación original de 001; no se añadió un bloque PL/SQL por 002.
- pipelines/01-network-probe.yaml: Inline database-network-probe.
- pipelines/02-dbtools-login.yaml: Inline database-dbtools-login.
- pipelines/03-verify-package.yaml: Inline verify-migration-package-spec.
- pipelines/04-apply-migrations.yaml: Inline apply-database-migrations-spec, diagnóstico y resumen VERBOSE conservados.
- infra/dynamic-group-rules.txt: dos reglas de DG-DEVOPS-SVC.
- infra/devops-policy.txt: sentencias IAM utilizadas.
- infra/database-user.sql: alta/grants/cuota como ADMIN; no ejecutar sobre usuario ya creado.
- docs/automatic-deployment.md: prueba documental del trigger.
- .gitattributes y .gitignore: formato y exclusiones.

Los cuatro Command specification usan Allow parameterization desactivado. El General artifact database-migration-package usa versión ${PACKAGE_VERSION} y parametrización activada.

## Entornos

El clon mostrado posteriormente en VS Code está en /home/opc/Database-DevOps de la VM. Las instrucciones iniciales indicaban /home/opc/projects/Database-DevOps; usar la ruta real devuelta por git rev-parse --show-toplevel.

Este workspace Windows es una copia organizada y no una descarga en vivo de OCI ni de la VM. El .git local sigue sin commits; no se hizo publicación desde Windows.

## Pendientes

- Confirmar el éxito de 002 después de corregir el XML.
- Aprobación independiente: por ahora solo existe la cuenta del autor.
- Certificar trigger y protección de main con la configuración/origen de ejecución en consola.
- Sustituir la verificación específica de demostración por comprobaciones generales cuando se prepare la entrega al cliente; ese cambio aún no se implementó.
- Rollback operativo y dashboard.

No hay instaladores de mejoras ni dependencia de Python en el flujo. Java/SQLcl/OCI CLI se utilizan desde Shell administrada; no requieren instalación en la VM para este diseño. No guardar passwords, Auth Tokens, claves ni wallets en el workspace.
