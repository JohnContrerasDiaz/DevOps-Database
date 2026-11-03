# Configuración completa y reconstrucción de OCI DevOps para cambios Oracle Database

Fecha de consolidación inicial: 30 de octubre de 2026. Actualización de archivos y estado: 3 de noviembre de 2026. Región: Chicago, us-chicago-1. Zona horaria del usuario: America/Bogota. Los logs aportados usan UTC, indicado con Z.

## 1. Propósito, alcance y lectura obligatoria

Este documento reconstruye la configuración que permitió versionar un DDL en OCI Code Repository, generar un paquete inmutable, transferir sus identificadores automáticamente y aplicar el cambio mediante SQLcl/Liquibase en una Autonomous ATP con endpoint privado. Incluye consola, VM Linux, IAM, red, credenciales protegidas, archivos completos, comandos, explicaciones, pruebas y errores corregidos.

La base de evidencia es la conversación de esta implementación, los comandos y contenidos recuperados de su historial, los archivos locales y los logs/capturas aportados por el usuario. No se ha consultado en vivo la tenancy para exportar todos sus recursos. Donde el historial no contiene un valor concreto, se indica expresamente. No se inventan OCID de pipelines, IP privadas corregidas, formas/capacidades ni nombres de gateways.

**No ejecutar el documento entero sobre la instalación que ya funciona.** Las secciones de creación son para reconstrucción desde cero. En la instalación existente se reutilizan los recursos y se revisan sus campos. CREATE USER no es idempotente; el DDL de demostración lo ejecuta Liquibase. No volver a ejecutarlo manualmente.

La estructura final del workspace local se documenta como una copia organizada de configuración y evidencia, no como una exportación automática de OCI ni como el clon autoritativo de la VM. Los YAML Inline fueron copiados a consola durante el trabajo. Cambiar un YAML local no actualiza OCI hasta editar el artefacto correspondiente.

Ruta operativa corregida según la captura posterior de VS Code: /home/opc/Database-DevOps. Las primeras instrucciones proponían /home/opc/projects/Database-DevOps; los comandos de esta versión usan la ruta mostrada posteriormente. Confirmar con git rev-parse --show-toplevel. La preparación de paquetes para una VM nueva está en §10.0 y la prueba 002/corrección XML está en §28.

### 1.1. Qué quedó demostrado y qué no

| Elemento | Evidencia / estado |
|---|---|
| Shell administrada, DNS y TCP | Prueba de red exitosa. El primer hostname aportado fue luego corregido; el login/DDL final comprueba el destino definitivo. |
| Database Tools / conexión atp-devops-demo | Validación satisfactoria como DEVOPS_DEMO en la base correcta. |
| Lectura de metadata y secretos por resource principal | DBTOOLS_LOGIN_OK:DEVOPS_DEMO y DBTOOLS_LOGIN_PROBE_SUCCEEDED. |
| Build genérico sin Python | Exportación de SOURCE_COMMIT, PACKAGE_VERSION y PACKAGE_SHA256 y publicación exitosa. |
| Transferencia build → deployment | Verificación de paquete satisfactoria y ejecuciones completas de cuatro etapas. |
| Aplicación DDL y registro Liquibase | Éxito del 29-10-2026; MIGRATION_001_VERIFIED y DATABASE_MIGRATION_SUCCEEDED. |
| Repetición sin reaplicar | Log del 30-10-2026: Run: 0, Previously run: 1, Filtered out: 0, cuatro etapas exitosas. |
| Trigger Push/main y protección main | Se dio el procedimiento y se recibió una corrida posterior a otro commit. No se aportó export/captura final del trigger ni el origen del build; confirmar campos en consola para acreditar disparo automático y protección, no deducirlos solo del log. |
| Aprobación independiente | Pendiente: el usuario confirmó que por ahora solo tiene su cuenta. No configurar una aprobación mínima que nadie pueda satisfacer. |
| Rollback | Explicado; no implementado ni ejecutado como pipeline separado. |
| Dashboard / alertas | Explicados; no implementados en esta sesión. |
| Segundo changeset 002 | SQL y changelog preparados; el 02-11 falló un XML sin cierre. Corrección completa conservada localmente. Éxito posterior pendiente de evidencia. |
| Procedimientos y parámetros | Explicados como opciones, no aplicados en esta demostración. |
| Nube + on-premise | Objetivo general del cliente. Solo se probó la ATP indicada; no afirmar validación de otras bases/redes. |

### 1.2. Dónde se ejecuta cada actividad

| Entorno | Uso |
|---|---|
| Consola OCI | Creación/edición de red, IAM, Database Tools, secretos, DevOps, artefactos y trigger. |
| VM Linux vm-oke-mintic, usuario opc | Clon Git, edición de archivos, ramas, commits y push. |
| Shell administrada de OCI DevOps | OCI CLI, SQLcl, creación de wallet temporal, comprobaciones y aplicación de DDL. Se aprovisiona un contenedor por etapa. |
| Laptop / SQL Developer | Administración del usuario Oracle y comprobaciones SQL. Requiere conectividad privada, mediante VPN o Bastion. |
| Workspace Windows de este documento | Copias de configuración para identificar, revisar y copiar. No reemplaza al clon Linux ni ejecuta ATP. |

No se instaló Java, SQLcl ni Python en la VM para lograr el flujo. Git estaba disponible. SQLcl 26.2.1 fue observado en el runtime Shell administrado.

## 2. Arquitectura y recursos

~~~text
VM Linux: /home/opc/Database-DevOps
    └─ push rama feature → PR → merge main
        └─ OCI Code Repository: Database-Changes
            └─ build: database-migrations-build
                ├─ package-migrations (Managed Build)
                ├─ publish-migration-package (Deliver Artifacts)
                └─ trigger-database-deployment (Trigger Deployment)
                    └─ deployment: database-dev-connectivity
                        ├─ check-atp-private-connectivity
                        ├─ check-atp-dbtools-login
                        ├─ verify-migration-package
                        └─ apply-database-migrations
                            ├─ OCI CLI → Database Tools metadata
                            ├─ OCI CLI → Vault secrets
                            ├─ Artifact Registry → paquete exacto
                            └─ SQLcl/Liquibase → ATP privada / DEVOPS_DEMO
~~~

El build no aplica SQL: produce un paquete. El deployment no clona automáticamente Git: descarga la versión publicada. Database Tools permite reutilizar metadata y referencias a secretos; SQLcl se conecta directamente a la ATP desde la Shell, no a través del endpoint privado del servicio Database Tools.

### 2.1. Identificadores aportados

Los OCID identifican recursos y no son contraseñas; se incluyen porque fueron suministrados. En otra tenancy se sustituyen por sus equivalentes. Nunca copiar OCID de ejemplos a políticas de otro ambiente.

| Recurso | Valor |
|---|---|
| Dominio IAM | Default |
| Región | us-chicago-1 / Chicago |
| Compartment DevOps | DATABASE-DEVOPS |
| Compartment DevOps OCID | ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa |
| Compartment de red OCID | ocid1.compartment.oc1..aaaaaaaa2sjgd3dlxfmlmxkowtir2vykrws75bjrg6kinussk7mo4phax7ba |
| Nombre del compartment de red | No quedó registrado inequívocamente; localizar la VCN por el OCID del compartment. |
| Proyecto correcto | DevOpsDatabase |
| Proyecto OCID | ocid1.devopsproject.oc1.us-chicago-1.amaaaaaacj6z5kiadfgmhcio5vgtmw6f4e4h6yjrgvqj3tvfw3hkgdjuohia |
| Repositorio fuente | Database-Changes |
| Repositorio fuente OCID | ocid1.devopsrepository.oc1.us-chicago-1.amaaaaaacj6z5kiaohsszchamumzvk6dfzjdlrpmofwj42lfzziw242lq7ba |
| Grupo dinámico reutilizado | Default/DG-DEVOPS-SVC |
| VCN | VCN-CARPETA-CIUDADANA |
| Subred ATP | SUBNET-DATABASE / 10.0.0.0/24 |
| Subred Shell y Database Tools | SUBNET-DEVOPS / 10.0.1.0/24, regional y privada |
| ATP display name | DEVOPSDATABASE1 |
| ATP OCID | ocid1.autonomousdatabase.oc1.us-chicago-1.anxxeljscj6z5kiad56thabmpbfo6fn3tzc3re4vpk7foajnizwwaljxlrxa |
| Nombre de base devuelto por validación | GD75A6D1A297495_DEVOPSDATABASE1 |
| Versión informada | Oracle AI Database 26ai, 23.26.4.1.0 |
| Host definitivo | uepanbou.adb.us-chicago-1.oraclecloud.com |
| Servicio | gd75a6d1a297495_devopsdatabase1_low.adb.oraclecloud.com |
| Autenticación / puerto | mTLS, TCPS / 1522 |
| Usuario y esquema | DEVOPS_DEMO |
| Database Tools connection | atp-devops-demo |
| Connection OCID | ocid1.databasetoolsconnection.oc1.us-chicago-1.amaaaaaacj6z5kiayoiodu263eacr6dshwagahee5jvjq7hn2ohayunv2hhq |
| Database Tools private endpoint | DEVOPSDATABASE-Private-Endpoint |
| Endpoint OCID | ocid1.databasetoolsprivateendpoint.oc1.us-chicago-1.amaaaaaacj6z5kiav3fh4stp3fyjwdkjtggvrfv53pqlvhdgotysxqqkkbyq |
| Vault | DatabaseDevOps-Vault |
| Vault OCID | ocid1.vault.oc1.us-chicago-1.ijvoec64aaewu.abxxeljsnqrsufbt6ttawvgxwnb7q7yivb4qiihtfmbmz2v6jjtynfggroka |
| Password secret | DEVOPS-DEMO-USER |
| Password secret OCID | ocid1.vaultsecret.oc1.us-chicago-1.amaaaaaacj6z5kiadwexzpdzyukjfbv67l6ou3xwtk63kqt6y6cco2kryzoa |
| SSO wallet secret real | WALLET-SECRET |
| Wallet secret OCID | ocid1.vaultsecret.oc1.us-chicago-1.amaaaaaacj6z5kialvko46bdcpbkpxmjmf27zobxgo5o5d3xqyg4ezxxkxpq |
| Artifact Registry repository | database-migrations, inmutable |
| Registry OCID | ocid1.artifactrepository.oc1.us-chicago-1.0.amaaaaaacj6z5kiagpfcblufsym7iv4schnzbe7ja5ks47wrflm6ipvb5vca |
| DevOps General artifact | database-migration-package |
| DevOps artifact OCID | ocid1.devopsdeployartifact.oc1.us-chicago-1.amaaaaaacj6z5kia3awzdnb65t2wa4u6eeqji37dlxfdyxbxvzkvuw3kllja |
| Path del artefacto | database/migrations.tar.gz |

URL HTTPS de clonación:

~~~text
https://devops.scmservice.us-chicago-1.oci.oraclecloud.com/namespaces/ax8e72q8tlee/projects/DevOpsDatabase/repositories/Database-Changes
~~~

El hostname no es el nombre visible de la ATP. uepanbou es su componente de hostname; el recurso visible es DEVOPSDATABASE1.

No usar MinTic-DevOps-Project del compartment MINTIC-CARPETA-CIUDADANA: fue una confusión inicial corregida, no pertenece a este flujo.

## 3. Prerrequisitos y creación inicial de recursos base

VCN, subredes, NAT, Service Gateway, ATP y VM ya existían cuando se avanzó con la implementación. Los siguientes pasos indican los requisitos y cómo localizarlos/reproducirlos; no son una afirmación de que se observara cada clic de su creación.

### 3.1. Compartment, proyecto, notificaciones y repositorio

1. En la consola seleccionar Chicago.
2. Identity & Security → Compartments: localizar DATABASE-DEVOPS o crearlo dentro de su padre autorizado para una instalación nueva.
3. Developer Services → DevOps → Projects → Create project.
4. Nombre: DevOpsDatabase; compartment: DATABASE-DEVOPS.
5. Si el formulario exige Notification topic, seleccionar uno existente o crear el topic indicado por la organización. Nombre/OCID y suscripciones utilizados no fueron aportados. No confundir un topic seleccionado con una suscripción confirmada.
6. Crear y abrir el proyecto.
7. Revisar Logging / Enable log: habilitar el log del proyecto y seleccionar/crear el Log Group cuando la consola lo solicite. El nombre, OCID y retención exactos del Log Group no se registraron.
8. En Code Repositories → Create repository: nombre Database-Changes, alojado en OCI, compartment DATABASE-DEVOPS.
9. Abrir el repositorio y copiar Clone → HTTPS. La URL final figura en §2.
10. Usar la rama main. El repositorio observado tenía el commit inicial e064658 sin archivos, no era una importación con código previo.

Los logs fueron confirmados como habilitados. No reconstruir un proyecto duplicado para modificar un pipeline.

### 3.2. ATP

En Oracle Database → Autonomous Database localizar DEVOPSDATABASE1. En una reconstrucción nueva seleccionar workload Transaction Processing, el compartment indicado y acceso mediante private endpoint en la VCN/subred correspondientes.

Confirmar modo mTLS y descargar el wallet desde Database Connection usando la contraseña de descarga que se defina localmente. CPU, almacenamiento, modelo de cómputo, autoescalado, contraseña ADMIN, OCID de la clave Vault e IP final del endpoint no fueron suministrados. No asignar valores ficticios a esos campos.

El descriptor definitivo debe copiarse desde Database Connection → mTLS → servicio _low. El patrón usado es:

~~~text
(description=
 (retry_count=20)(retry_delay=3)
 (address=(protocol=tcps)(port=1522)(host=uepanbou.adb.us-chicago-1.oraclecloud.com))
 (connect_data=(service_name=gd75a6d1a297495_devopsdatabase1_low.adb.oraclecloud.com))
 (security=(ssl_server_dn_match=yes))
)
~~~

Conservar siempre el descriptor real de la ATP; no construir un servicio a partir del nombre visible. No dejar una barra invertida antes de .adb si solo era un escape del texto copiado. No desactivar SSL_SERVER_DN_MATCH.

## 4. Red: rutas, DNS y Security Lists

### 4.1. Localizar la asociación real

1. Networking → Virtual Cloud Networks → VCN-CARPETA-CIUDADANA.
2. Subnets → SUBNET-DEVOPS: verificar que sea regional y privada.
3. Abrir sus enlaces de Route Table, Security Lists y DHCP Options.
4. No basta con crear reglas en una lista no asociada: el usuario confirmó las asociaciones correctas.
5. Revisar SUBNET-DATABASE de la misma forma.
6. El runtime de Shell crea una VNIC en SUBNET-DEVOPS. No requiere un servidor Linux persistente allí para ejecutar SQLcl.
7. No se seleccionaron NSG para las etapas del laboratorio. Si una instalación aplica NSG, sus reglas deben permitir también el tráfico requerido.

### 4.2. Rutas de SUBNET-DEVOPS

| Destino / tipo | Target type | Target |
|---|---|---|
| All ORD Services In Oracle Services Network / Service | Service Gateway | Gateway de la VCN |
| 0.0.0.0/0 / CIDR | NAT Gateway | NAT de la VCN |

En Route table → Add Route Rules crear las reglas que falten. En Service Gateways abrir el gateway y confirmar All ORD Services In Oracle Services Network y tráfico no bloqueado. En NAT Gateway confirmar estado y tráfico permitido.

Una salida en Security List autoriza tráfico, pero no crea una ruta. La descarga de la imagen del contenedor falló antes de SQLcl cuando la salida a Registry era inadecuada. Revisar el destino All ORD Services, no limitar la ruta solo a Object Storage.

Dentro de la VCN la comunicación entre subredes usa el enrutamiento local de la VCN; no se envía la conexión ATP por NAT. Los nombres de Route Tables, gateways, DHCP options y sus OCID no quedaron registrados.

### 4.3. SL-DATABASE observada

Ingress, reglas stateful (Stateless = No):

| Source | Protocolo | Source ports | Destination ports |
|---|---|---|---|
| 10.0.1.0/24 | TCP | All | 1521 |
| 10.0.1.0/24 | TCP | All | 1522 |

Egress: destination 0.0.0.0/0, TCP, todos los puertos, stateful.

El flujo probado usa 1522. La regla 1521 existía; se documenta porque fue aportada, no porque sea necesaria para esta conexión mTLS.

### 4.4. SL-DEVOPS observada

Ingress: source 10.0.0.0/24, All Protocols, stateful.

Egress, stateful:

| Destination | Protocolo | Puertos |
|---|---|---|
| 0.0.0.0/0 | TCP | Todos |
| All ORD Services In Oracle Services Network | All Protocols | Todos |

Las reglas son el estado del laboratorio. No presentarlas como un diseño de mínimo privilegio de producción. En particular el ingreso amplio en SL-DEVOPS no es una instrucción para abrir un servicio de Shell entrante.

### 4.5. DNS y hostname corregido

La primera prueba resolvió p2q0oapn.adb.us-chicago-1.oraclecloud.com a 10.0.0.102. El usuario luego corrigió el destino a uepanbou.adb.us-chicago-1.oraclecloud.com. **No reutilizar aquella IP histórica sin volver a resolver el destino correcto.**

El YAML 01-network-probe.yaml consolidado usa el hostname definitivo. El login y DDL posteriores sí probaron la ATP correcta. DNS debe estar disponible desde la subred de Shell; las configuraciones DHCP/resolver concretas no fueron exportadas.

## 5. Acceso administrativo desde SQL Developer en laptop

Este acceso sirve para preparar DEVOPS_DEMO y comprobar SQL; el pipeline no depende de que la laptop permanezca conectada.

El wallet no proporciona conectividad de red. Se necesita VPN/FastConnect con rutas apropiadas o una sesión de port forwarding de OCI Bastion. El usuario confirmó conexión satisfactoria, pero no aportó el OCID de Bastion/sesión ni su comando SSH definitivo.

### 5.1. Procedimiento de Bastion comunicado

1. Identity & Security → Bastion → Create bastion.
2. Compartment DATABASE-DEVOPS, nombre propuesto bastion-database-devops.
3. VCN VCN-CARPETA-CIUDADANA; target subnet SUBNET-DEVOPS.
4. CIDR allowlist: IP pública de salida de la laptop /32. Si hay VPN corporativa, usar su IP real de salida.
5. En la laptop, solo si no existe ya la clave elegida, generar:

~~~powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\oci-bastion-devops"
~~~

Genera el par de claves local. La pública .pub se entrega a la sesión; la privada nunca se sube al repo ni se comparte. No sobrescribir una clave existente.

6. Create session → SSH port forwarding session; nombre propuesto atp-sqldeveloper.
7. Target IP: IP privada ACTUAL de uepanbou, tomada de los detalles de ATP. Puerto 1522.
8. Cargar la clave pública y crear la sesión.
9. Cuando esté Active, copiar el SSH command de la consola. Sustituir privateKey por la ruta privada local y localPort por 1522.
10. Ejecutarlo en PowerShell y mantener la sesión abierta. El comando incluye el OCID de sesión y host de Bastion reales; no se inventan aquí.
11. Si se usa la solución de resolución local comunicada, abrir como administrador C:\Windows\System32\drivers\etc\hosts y agregar temporalmente:

~~~text
127.0.0.1 uepanbou.adb.us-chicago-1.oraclecloud.com
~~~

La resolución dirige el hostname al puerto local manteniendo el hostname del descriptor para TLS. Requiere túnel local 1522 activo y libre. Retirar la entrada al terminar o antes de conectarse por VPN directa. No copiar el hostname antiguo p2q0oapn.

12. SQL Developer → New connection: usuario ADMIN, Role Default, tipo Cloud Wallet, ZIP del wallet correcto, alias _low, password ADMIN local.
13. Test → Success → Connect.
14. Crear una segunda conexión del mismo tipo como DEVOPS_DEMO después de preparar el usuario.
15. Verificar:

~~~sql
SELECT USER, SYS_CONTEXT('USERENV', 'DB_NAME') AS DB_NAME
FROM DUAL;
~~~

La conexión ADMIN se usa para grants; el pipeline usa DEVOPS_DEMO.

## 6. Usuario Oracle y permisos finales

Archivo completo reproducible: infra/database-user.sql (contenido íntegro en el anexo de archivos).

En SQL Developer como ADMIN crear el usuario solo en una instalación nueva:

~~~sql
CREATE USER DEVOPS_DEMO
IDENTIFIED BY "REEMPLAZAR_POR_PASSWORD_LOCAL";

GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE,
      CREATE VIEW, CREATE TRIGGER TO DEVOPS_DEMO;

ALTER USER DEVOPS_DEMO QUOTA 20M ON DATA;
~~~

Sustituir la contraseña localmente. No guardarla en Markdown/Git, logs o capturas. No ejecutar la creación en un usuario que ya existe. La cuota de 20M es la usada para la demostración y debe reevaluarse para más objetos/datos.

| Permiso | Función en esta prueba |
|---|---|
| CREATE SESSION | Abrir sesión en Oracle. |
| CREATE TABLE | Tabla de aplicación y tablas de seguimiento. |
| CREATE PROCEDURE | Permite procedimientos, funciones y paquetes del propio esquema; se añadió durante diagnóstico. |
| CREATE VIEW | Objetos auxiliares de SQLcl/Liquibase, incluida la vista de detalles. |
| CREATE TRIGGER | Trigger auxiliar de SQLcl/Liquibase. |
| QUOTA 20M ON DATA | Espacio de datos del esquema; no es un permiso IAM. |

Se concedieron primero SESSION/TABLE; luego PROCEDURE, y finalmente VIEW/TRIGGER. El éxito se consiguió tras completar esos permisos y retirar una tabla creada manualmente. No se capturó la sentencia exacta del ORA-01031 anterior; no atribuirlo retrospectivamente a una sentencia específica como un hecho observado.

Verificar como ADMIN:

~~~sql
SELECT USERNAME, ACCOUNT_STATUS
FROM DBA_USERS
WHERE USERNAME = 'DEVOPS_DEMO';

SELECT PRIVILEGE
FROM DBA_SYS_PRIVS
WHERE GRANTEE = 'DEVOPS_DEMO'
ORDER BY PRIVILEGE;

SELECT TABLESPACE_NAME, MAX_BYTES
FROM DBA_TS_QUOTAS
WHERE USERNAME = 'DEVOPS_DEMO';
~~~

Verificar como DEVOPS_DEMO:

~~~sql
SELECT USER,
       SYS_CONTEXT('USERENV','CURRENT_SCHEMA') AS CURRENT_SCHEMA,
       SYS_CONTEXT('USERENV','DB_NAME') AS DB_NAME
FROM DUAL;

SELECT PRIVILEGE
FROM SESSION_PRIVS
WHERE PRIVILEGE IN (
  'CREATE SESSION','CREATE TABLE','CREATE PROCEDURE','CREATE VIEW','CREATE TRIGGER'
)
ORDER BY PRIVILEGE;
~~~

DBA_SYS_PRIVS muestra concesiones directas; SESSION_PRIVS muestra privilegios efectivos de la sesión. No confundir privilegios Oracle con las políticas IAM del pipeline.

## 7. Vault, wallet y Database Tools

### 7.1. Vault y secretos

El Vault real es DatabaseDevOps-Vault. Si ya existe, reutilizarlo. En una instalación nueva:

1. Identity & Security → Vault → Create Vault, compartment DATABASE-DEVOPS.
2. Crear/seleccionar una clave de cifrado compatible con Secrets en estado habilitado. Su nombre/OCID no quedó registrado.
3. Crear el secreto DEVOPS-DEMO-USER con la contraseña EXACTA de DEVOPS_DEMO, sin comillas agregadas ni saltos de línea.
4. El formulario de Database Tools también permite crear el secreto de contraseña seleccionando Vault y clave. Usar un solo secreto para esa credencial.
5. Descargar el ZIP del wallet de la ATP correcta y extraer cwallet.sso en una ubicación temporal protegida.
6. Crear/seleccionar el secreto de contenido SSO a través del formulario de Database Tools, formato Oracle auto-login wallet, cargando cwallet.sso. El nombre final real es WALLET-SECRET.
7. No guardar el ZIP completo como contenido SSO para este script. El login probe rechaza archivos que empiezan por PK. El script decodifica una sola vez el content base64 retornado por Secret Bundle.
8. Confirmar que la versión CURRENT contiene la contraseña/wallet correctos. No imprimir su contenido.

El nombre DEVOPS-DEMO-WALLET apareció como propuesta inicial, pero la conexión aportada referencia WALLET-SECRET; no crear otro secreto solo para igualar aquel nombre.

No se usó bucket de Object Storage. Las credenciales se recuperan de Vault mediante los OCID obtenidos de Database Tools.

### 7.2. Private endpoint de Database Tools

ATP ya tiene su endpoint privado. Database Tools requiere otro endpoint para entrar en la VCN:

1. Developer Services → Database Tools → Private endpoints, o Create private endpoint dentro del formulario de conexión.
2. Compartment DATABASE-DEVOPS.
3. Nombre real DEVOPSDATABASE-Private-Endpoint; nombre propuesto anterior pe-dbtools-devops no es el nombre definitivo.
4. Seleccionar ATP DEVOPSDATABASE1 si el formulario permite Select database.
5. VCN VCN-CARPETA-CIUDADANA; subred SUBNET-DEVOPS en el compartment de red.
6. Crear y esperar Active.
7. Revisar Reverse Connection Source IPs si hay timeout. No se registraron sus IP finales.
8. Asegurar acceso de esas IP al endpoint ATP en 1522. La regla 10.0.1.0/24 cubre las IP que pertenezcan a esa subred.

Este endpoint sirve a Database Tools para validar/usar su conexión. La Shell SQLcl usa su propia VNIC y el descriptor ATP.

### 7.3. Crear atp-devops-demo

Database Tools → Connections → Create connection:

| Campo | Valor |
|---|---|
| Name | atp-devops-demo |
| Compartment | DATABASE-DEVOPS |
| Database details | Select database |
| Database cloud service | Oracle Autonomous AI Database |
| Database | DEVOPSDATABASE1 |
| Username | DEVOPS_DEMO |
| Authentication type | Password based |
| Password secret | DEVOPS-DEMO-USER |
| Runtime identity | Authenticated principal |
| Connection string | Descriptor mTLS _low, host uepanbou, puerto 1522 |
| Access via private network | Activado |
| Private endpoint | DEVOPSDATABASE-Private-Endpoint |
| SSL wallet format | Oracle auto-login wallet, SSO |
| Wallet content secret | WALLET-SECRET, contenido cwallet.sso |
| Proxy authentication | None |

No seleccionar None en SSL para este flujo. El descriptor automático inicial usaba 1521 y hubo ORA-18714; reemplazarlo por el descriptor mTLS real en 1522 antes de validar.

Guardar y ejecutar Validate connection. Se observó:

~~~text
Validated connection to database
Database name: GD75A6D1A297495_DEVOPSDATABASE1
Database version: 23.26.4.1.0
Current schema: DEVOPS_DEMO
Session user: DEVOPS_DEMO
Authentication method: PASSWORD
~~~

Database Tools Identity Status = Unavailable en Authenticated principal no impidió esta prueba; esa identidad de base específica requiere Resource Principal runtime identity en la conexión. No cambiamos ese campo para resolver el flujo.

## 8. IAM: un grupo dinámico y la política consolidada

### 8.1. Grupo dinámico

Identity & Security → Domains → Default → Dynamic groups → DG-DEVOPS-SVC → Edit matching rules.

Seleccionar **Match any rules defined below**. Introducir DOS reglas independientes: una para devopsdeploypipeline y otra para devopsbuildpipeline, según infra/dynamic-group-rules.txt.

No copiar un ANY anidado con dos ALL dentro de un único campo: ese editor lo rechazó. No crear DG-DEVOPS-BUILD; fue una propuesta rechazada por el usuario. Se reutiliza el grupo existente.

Guardar y permitir que IAM propague los cambios antes de evaluar una prueba fallida inmediata.

### 8.2. Política

Identity & Security → Policies → seleccionar root o el ancestro común a los compartments DevOps/red → editar la política existente. Nombre real de la política no registrado. Usar el editor manual y añadir las sentencias completas de infra/devops-policy.txt.

No borrar enunciados ajenos del tenant. Si el editor recibe solo sentencias, no pegar las líneas de comentario del archivo.

| Recurso/permiso | Motivo |
|---|---|
| manage devops-family | Operaciones de DevOps, repositorios/artefactos y disparo de deployment del laboratorio. |
| manage compute-container-instances / compute-containers | Aprovisionamiento de Shell administrada. |
| use vnics / subnets / dhcp-options / network-security-groups | VNIC y red en el compartment donde reside la VCN. |
| read database-tools-connections filtrado por connection OCID | Leer la metadata de la conexión existente. |
| read secret-bundles filtrado por dos secret OCID | Recuperar CURRENT de contraseña y wallet. |
| manage generic-artifacts | Publicar nuevas versiones del paquete y permitir su lectura. use no bastó para crear versiones nuevas. |

La política read de conexión y secretos usa el nombre DATABASE-DEVOPS tal como se dio en la configuración; el resto usa compartment id. Los OCID de secretos proceden de los enlaces aportados por el usuario, no de recursos inventados.

Al compartir el grupo, build y deployment reciben los permisos de sus políticas, incluidos los de secretos; el build no los utiliza. Es el diseño de laboratorio solicitado, no una separación final de identidades de producción.

### 8.3. De dónde procede la autenticación

OCI CLI en la Shell usa --auth resource_principal y región us-chicago-1. La identidad es el pipeline, no la laptop ni un archivo ~/.oci/config del usuario. No se instaló una API key personal en el runtime.

El resource principal autoriza lectura de configuración/secretos. Después SQLcl autentica a Oracle como DEVOPS_DEMO usando PASSWORD + mTLS. No asumir que OCI_CLI_AUTH configura por sí sola un CONNECT OCI nativo de SQLcl.

## 9. Primer deployment: prueba de red y login

### 9.1. Crear pipeline

Developer Services → DevOps → Projects → DevOpsDatabase → Deployment pipelines → Create pipeline:

- Name: database-dev-connectivity.
- Description inicial: prueba de conectividad privada ATP.
- Compartment del proyecto: DATABASE-DEVOPS.

El nombre se conservó al añadir aplicación de DDL. No crear otro pipeline solo porque el nombre diga connectivity.

### 9.2. Crear los artefactos de instrucciones

En DevOpsDatabase → Artifacts → Add artifact:

| Name | Type | Source | Archivo local | Allow parameterization |
|---|---|---|---|---|
| database-network-probe | Command specification | Inline | pipelines/01-network-probe.yaml | Desactivado / NONE |
| database-dbtools-login | Command specification | Inline | pipelines/02-dbtools-login.yaml | Desactivado / NONE |

Abrir cada archivo, copiar TODO su YAML en Value/Inline y guardar. El primer YAML ya contiene el hostname final; no conservar el placeholder.

### 9.3. Primera etapa Shell

En el pipeline, + → Add stage → Integrations – Shell → Next:

| Campo | Configuración |
|---|---|
| Name | check-atp-private-connectivity |
| Command specification artifact | database-network-probe |
| Container compartment | DATABASE-DEVOPS |
| Availability domain | Una disponible en Chicago; selección exacta no registrada. |
| Shape / OCPU / memoria | Se indicó conservar el predeterminado; valores efectivos no capturados. |
| VCN | VCN-CARPETA-CIUDADANA |
| Subnet | SUBNET-DEVOPS |
| NSG | Sin seleccionar |
| Timeout de referencia | 300 segundos |

Cambiar el selector de compartment al de red al buscar la VCN, sin cambiar el compartment de ejecución de la instancia.

Ejecutar manualmente solo en esta fase inicial, nombre probe-atp-001 / probe-atp-correct según la sesión. Esperar NETWORK_PROBE_OK. getent confirma DNS; /dev/tcp confirma TCP, no valida por sí solo mTLS, usuario ni SQL.

### 9.4. Segunda etapa Shell

Después de la primera: + → Add stage → Shell.

- Name check-atp-dbtools-login.
- Artifact database-dbtools-login.
- Misma VCN, subred, compartment, AD, shape y NSG que la etapa anterior.
- Timeout de referencia 600 segundos; el comando usa 480 y la llamada SQLcl 180.

Ejecutar y buscar:

~~~text
DBTOOLS_LOGIN_OK:DEVOPS_DEMO
DBTOOLS_LOGIN_PROBE_SUCCEEDED
~~~

La ejecución probe-dbtools-login-003 terminó exitosa el 28-10-2026 con dos etapas. El contenido final del archivo evita el lector de password interactivo de SQLcl/JLine.

Cuando se agregan las etapas de paquete, ya no lanzar el deployment final sin parámetros: UNSET se rechaza intencionadamente. El punto normal de entrada pasa a ser el build/trigger.

## 10. VM Linux y autenticación Git

### 10.0. Preparación de una VM Oracle Linux desde cero

Esta sección completa el prerrequisito que faltaba en la primera guía. **No afirma que esos comandos se hayan ejecutado históricamente:** Git ya estaba instalado y la VM reportó Java/SQLcl ausentes. No es necesario instalar Java/SQLcl/OCI CLI en la VM para este diseño, porque se ejecutan en la Shell administrada de OCI.

En una VM nueva se necesita acceso SSH, salida a repositorios Oracle Linux y HTTPS al repositorio Git OCI. Instalar paquetes exige sudo. Consultar primero:

~~~bash
cat /etc/os-release
uname -m
dnf repolist
rpm -q git openssh-clients ca-certificates libxml2
~~~

- dnf repolist lista repositorios habilitados; no instala nada.
- rpm -q consulta paquetes instalados. Un paquete ausente produce un mensaje/código distinto de cero; no es un fallo de OCI.
- No ejecutar una actualización global del sistema como requisito de esta prueba.

Para una VM nueva, instalar las herramientas de trabajo:

~~~bash
sudo dnf install -y git openssh-clients ca-certificates libxml2
~~~

git proporciona el control de versiones; openssh-clients incluye cliente SSH; ca-certificates aporta confianza TLS del sistema; libxml2 proporciona xmllint en Oracle Linux 9 para comprobar el XML localmente. -y acepta la transacción de instalación. DNF puede actualizar un paquete ya instalado si hay una versión posterior disponible. En una VM existente, instalar solo los que falten conforme a su gestión de parches.

Si xmllint no se encuentra tras la instalación, comprobar qué paquete lo proporciona antes de intentar otro nombre:

~~~bash
command -v git
git --version
ssh -V
command -v xmllint
xmllint --version
dnf provides '*/xmllint'
~~~

La validación de estructura que se recomienda antes de publicar un changelog es:

~~~bash
xmllint --nonet --noout db/changelog.xml
echo $?
~~~

Ejecutar dentro del clon. --nonet evita acceso de red; --noout no imprime el XML. Cero indica XML bien formado. No se usa --schema: esta prueba no valida el XSD ni comprueba permisos/DDL ni sustituye lb validate.

Herramientas estándar usadas por los ejemplos o por el empaquetado, para una VM mínima donde se quiera reproducir esos comandos localmente:

~~~bash
sudo dnf install -y bash coreutils findutils tar gzip grep gawk diffutils
~~~

| Paquete | Ejemplos de herramientas |
|---|---|
| bash | Shell, condicionales y /dev/tcp |
| coreutils | cat, printf, mkdir, mktemp, base64, sha256sum, timeout, sort, cut |
| findutils | find, xargs |
| tar / gzip | Crear, listar y extraer paquetes tar.gz |
| grep / gawk | Buscar contenido y filtrar salida |
| diffutils | Comparaciones de archivos |

Estos paquetes suelen estar en el sistema. El build y los scripts de aplicación se ejecutan en runners administrados, no por instalar estas herramientas en la VM. Consultar la versión real del runtime; no instalar paquetes dentro de una etapa existente sin necesidad.

**Java opcional, fuera del camino necesario de esta implementación:**

Solo si posteriormente se decide ejecutar herramientas Java directamente en una VM, se puede preparar un JDK compatible con esa herramienta. En Oracle Linux 9 con AppStream habilitado, el siguiente ejemplo instala OpenJDK 17 de desarrollo:

~~~bash
dnf list available java-17-openjdk-devel
sudo dnf install -y java-17-openjdk-devel
java -version
javac -version
jar --version
~~~

No ejecutar ese bloque para resolver la prueba de columna ni el error XML: no lo requieren. El paquete de desarrollo aporta javac/jar además de java. Si conviven varias versiones, revisar alternatives antes de cambiar la predeterminada. La compatibilidad exacta de un SQLcl que se instale localmente debe verificarse para la versión descargada; no se instaló ni se necesita SQLcl local en el flujo probado.

No hay comando de instalación de Python como dependencia del cliente. Tampoco se instala OCI CLI en la VM: el runtime Shell ya lo proporciona con resource principal.

Referencias: [Git en Oracle Linux](https://docs.oracle.com/en/learn/ol-git-start/), [instalación de paquetes con DNF](https://docs.oracle.com/en/operating-systems/oracle-linux/software-management/sfw-mgmt-InstallSoftwareonEnterpriseLinux.html), [OpenSSH clients](https://docs.oracle.com/en/operating-systems/oracle-linux/openssh/openssh-InstallingtheOpenSSHClientPackages.html), [Java en Oracle Linux 9](https://docs.oracle.com/en/operating-systems/oracle-linux/9/relnotes9.0/ol9-NewFeaturesandChanges.html), [runtime Shell OCI](https://docs.oracle.com/en-us/iaas/Content/devops/using/shellruntime_details.htm).

### 10.1. Estado observado

~~~text
Usuario/host: opc@vm-oke-mintic
Sistema: Oracle Linux Server 9.8
Arquitectura: x86_64
Git: 2.52.0
Directorio inicial: /home/opc
Java y sql: no encontrados en VM
~~~

Comprobaciones ejecutadas:

~~~bash
cat /etc/os-release
uname -m
git --version
command -v java
command -v sql
pwd
~~~

cat muestra el SO; uname -m arquitectura; git --version versión; command -v busca ejecutables en PATH; pwd directorio actual. El intento histórico "java version" devolvió command not found. Si se instala Java en otro contexto el argumento de versión es -version, pero aquí no fue necesario instalarlo.

### 10.2. Auth Token OCI

Perfil de usuario → User settings → Auth tokens → Generate token.

- Descripción usada en la instrucción: Git VM Database DevOps.
- Guardar el valor en el gestor de contraseñas. OCI no vuelve a mostrarlo.
- HTTPS Git usa el Auth Token como password, no la contraseña de consola.
- Usuario que funcionó: minticCCDtrial/Default/john.contreras.diaz@oracle.com.
- Respetar la tenancy/usuario reales; no derivar la capitalización del namespace Object Storage.
- No incorporar el token a la URL ni al shell history.

### 10.3. Clonar una sola vez

En la VM, usuario opc, sin sudo:

~~~bash
cd /home/opc

git -c credential.helper= clone \
  https://devops.scmservice.us-chicago-1.oci.oraclecloud.com/namespaces/ax8e72q8tlee/projects/DevOpsDatabase/repositories/Database-Changes \
  Database-DevOps

cd /home/opc/Database-DevOps

git config --local user.name "TU NOMBRE"
git config --local user.email "TU CORREO"
git config --local core.autocrlf false

pwd
git remote -v
git status --short --branch
git log -5 --oneline
git ls-tree -r --name-only HEAD
~~~

Sustituir TU NOMBRE/TU CORREO por la identidad del autor, no por credenciales. cd cambia al directorio padre del clon; mkdir -p, cuando se usa en otros bloques, crea carpetas ausentes. clone descarga el repo y lo nombra Database-DevOps. La opción -c credential.helper= solo para ese comando desactiva helpers y obliga a autenticar. --local limita la configuración al clon. core.autocrlf false evita conversiones automáticas globales de finales de línea; .gitattributes fija LF para los tipos usados.

remote -v muestra URL fetch/push sin token embebido. status muestra rama/archivos. log muestra commits. ls-tree muestra solo archivos versionados en el commit, no archivos locales sin commit.

Se observó e064658 Initial Commit sin archivos. main seguía origin/main.

### 10.4. Caché de credenciales por ocho horas

Configuración que solucionó la autenticación repetida:

~~~bash
git config --local --replace-all credential.helper ''
git config --local --add credential.helper 'cache --timeout=28800'
git pull --ff-only origin main
~~~

El helper vacío reinicia la lista heredada para este repo; --add agrega la caché en memoria. 28800 segundos = 8 horas. La primera operación pide username/token; después los reutiliza hasta expirar o terminar el daemon/reiniciar. No usa credential.helper store en texto plano.

A partir de aquí **no usar** git -c credential.helper= pull/push: esa opción desactivaría la caché para esa operación.

Comandos normales:

~~~bash
git pull --ff-only origin main
git fetch origin
git push
~~~

pull --ff-only actualiza sin crear un merge local inesperado; falla si hay divergencia. fetch descarga referencias sin integrar. push envía la rama con upstream.

Para vaciar voluntariamente la caché:

~~~bash
git credential-cache exit
~~~

Esto puede afectar otras operaciones de Git que compartan ese daemon del usuario.

## 11. Archivos fuente iniciales y primer PR

### 11.1. Crear rama y carpetas

~~~bash
cd /home/opc/Database-DevOps
git switch -c feature/initial-db-migration
mkdir -p db/changes scripts
~~~

switch -c crea una rama desde el commit actual y cambia a ella. Las carpetas separan changelog/DDL de comprobaciones. No hace falta una rama por archivo: una rama agrupa un cambio lógico.

### 11.2. Crear archivos completos

Usar los bloques cat/heredoc del anexo §25 para .gitattributes, .gitignore, db/changelog.xml, db/changes/001_create_devops_demo.sql y scripts/verify.sql. Son los contenidos recuperados del procedimiento que se publicó en la VM.

El patrón de escritura es:

~~~bash
cat > ruta/archivo <<'EOF'
CONTENIDO COMPLETO DEL ARCHIVO
EOF
~~~

cat con redirección > escribe/reemplaza el archivo; el heredoc con EOF entre comillas evita que Bash expanda $variables, sustituciones y barras del contenido. No pegar literalmente CONTENIDO COMPLETO: usar el bloque de cada archivo del anexo.

Los contenidos son:
- .gitattributes: formato LF.
- .gitignore: exclusión de credenciales, wallets y outputs.
- db/changelog.xml: originalmente changeset 001, sqlFile relativo y rollback explícito DROP TABLE. El anexo actual incluye también 002, añadido después; para reconstruir exclusivamente la primera prueba utilizar solo el bloque 001. El documento distingue esa secuencia histórica de la versión actual de archivo.
- 001_create_devops_demo.sql: tabla con ID, DESCRIPTION y CREATED_AT.
- verify.sql: comprueba usuario/esquema, tres columnas y registro EXECUTED; emite MIGRATION_001_VERIFIED.

### 11.3. Revisar y publicar

~~~bash
git add .gitattributes .gitignore db/changelog.xml \
  db/changes/001_create_devops_demo.sql scripts/verify.sql

git diff --cached --check
git diff --cached --stat
git diff --cached

git commit -m "Add initial Oracle database migration and verification"
git push -u origin feature/initial-db-migration
~~~

add selecciona explícitamente archivos para el commit, evitando incluir secretos accidentales. --cached examina el staging. --check detecta errores de whitespace; no valida SQL/XML. --stat resume archivos/líneas. commit crea una versión local; push -u publica y configura upstream.

El primer push histórico llevó -c credential.helper= porque la caché aún no estaba configurada; el comando anterior ya refleja la corrección definitiva.

### 11.4. PR y merge en consola

DevOpsDatabase → Code Repositories → Database-Changes → Pull Requests → Create pull request:

- Source: feature/initial-db-migration.
- Destination: main.
- Título de referencia: Primera migración controlada de base de datos.
- Descripción: Agrega DDL de demostración, changelog Liquibase y verificación posterior. Sin cambios aplicados todavía en ATP.

Revisar Differences, Commits y Pull request info → Merge checks. La consola mostró no approval rules y no conflicts. Add self and approve estaba deshabilitado. El usuario solo tenía su cuenta. Merge estaba habilitado y se utilizó para la demostración sin aprobación independiente.

Merge no equivale a PR: el PR es la propuesta/discusión/revisión; merge es la integración de la rama al destino. El PR debe conservarse como evidencia aun después de borrar una rama.

Sincronizar:

~~~bash
git switch main
git pull --ff-only origin main
git log -3 --oneline
git ls-tree -r --name-only HEAD
git status --short --branch
~~~

Resultado observado: 81e4012 merge, bf690cf cambio inicial y e064658 inicial. Árbol limpio con cinco archivos.

## 12. Artifact Registry: repositorio inmutable

Developer Services → Containers & Artifacts → Artifact Registry → Create repository:

| Campo | Valor |
|---|---|
| Name | database-migrations |
| Compartment | DATABASE-DEVOPS |
| Description | Paquetes de migraciones Oracle Database generados desde Git |
| Immutable artifacts | Activado |

Crear y copiar el OCID del §2. No es un bucket ni el repositorio Git: almacena paquetes binarios. Inmutabilidad impide sobrescribir una misma combinación path + versión; cada build genera una versión diferente.

## 13. Build specification y mejora final

### 13.1. Historial de incorporación

Primero se creó feature/build-migration-package y un build_spec.yaml que copiaba explícitamente el SQL 001. Se fusionó hacia main. Después se simplificó con feature/workflow-improvements, reemplazando el archivo por el build genérico sin Python.

El workspace conserva solo el build final en la raíz, build_spec.yaml. La copia anterior pipelines/build-spec-no-python.yaml era un nombre local de entrega, no el nombre buscado por OCI; se eliminó su duplicación.

### 13.2. Crear/publicar el build final desde Linux

En una reconstrucción nueva puede incluirse el build final en el primer PR; no es necesario reproducir ramas históricas solo para obtener el mismo estado. Para actualizar una instalación con main limpio:

~~~bash
cd /home/opc/Database-DevOps
git switch main
git pull --ff-only origin main
git status --short --branch
git switch -c feature/workflow-improvements
~~~

Crear build_spec.yaml con el bloque íntegro del anexo. Revisar y publicar:

~~~bash
git diff --check
git diff -- build_spec.yaml
git add build_spec.yaml
git commit -m "Package all versioned database changes and export release metadata"
git push -u origin feature/workflow-improvements
~~~

Crear PR feature/workflow-improvements → main, revisar solo el cambio deseado y hacer merge. Luego:

~~~bash
git switch main
git pull --ff-only origin main
git ls-tree -r --name-only HEAD
git log -3 --oneline
git status --short --branch
~~~

No ejecutar ese switch -c si la rama ya existe sin decidir si se debe reutilizar; un error de rama existente no justifica forzar/resetear el clon.

### 13.3. Función del build final

1. Cambia a OCI_PRIMARY_SOURCE_DIR.
2. Lee OCI_PRIMARY_SOURCE_COMMIT_HASH y comprueba formato SHA y coincidencia con git rev-parse HEAD.
3. Forma PACKAGE_VERSION con commit + sufijo de OCI_BUILD_RUN_ID.
4. git archive toma db/ y scripts/ del commit, no archivos sin versionar.
5. Extrae el contenido en un directorio temporal.
6. Comprueba db/changelog.xml y scripts/verify.sql no vacíos y rechaza symlinks.
7. Genera release.txt con commit, build_run y package_version.
8. Genera SHA256SUMS de los archivos y valida con sha256sum --check.
9. Comprime en output/database-migrations.tar.gz.
10. Calcula PACKAGE_SHA256 del paquete y exporta las tres variables.
11. Publica como outputArtifact BINARY database-migration-package.

No aplica DDL, no usa contraseña, wallet ni Python. No requiere registrar cada nuevo SQL en el build. Sí requiere que cada SQL que Liquibase deba ejecutar esté referenciado por el changelog.

### 13.4. Contenido generado del paquete

~~~text
database-migrations.tar.gz
├── db/changelog.xml
├── db/changes/001_create_devops_demo.sql
├── db/changes/002_add_estado.sql
├── scripts/verify.sql
├── release.txt
└── SHA256SUMS
~~~

El árbol anterior corresponde al contenido actual con 002 preparado; los paquetes exitosos originales tenían solo 001. Incluye todos los archivos versionados dentro de db/ y scripts/ si se agregan más. No incluye .git, build_spec.yaml, docs/, infra/ o pipelines/ con esta configuración. Ningún wallet/secreto forma parte del paquete.

release.txt y SHA256SUMS son generados, no se mantienen manualmente. El checksum SHA-256 del tar.gz es distinto del checksum MD5 de un changeset en DATABASECHANGELOG; tienen propósitos distintos.

## 14. Artefacto General de DevOps

DevOpsDatabase → Artifacts → Add artifact:

| Campo | Valor |
|---|---|
| Name | database-migration-package |
| Type | General artifact |
| Artifact source | Artifact Registry repository |
| Artifact registry repository | database-migrations |
| Artifact Location | Set Custom Location |
| Path | database/migrations.tar.gz |
| Version | ${PACKAGE_VERSION} |
| Allow parameterization | ACTIVADO |

Escribir la expresión de versión literalmente, con dólar y llaves. Se sustituye durante el build. No seleccionar Select Existing Location cuando aún no se ha publicado el primer paquete.

El General artifact es una referencia OCI al path/version; no es el archivo tar.gz ni el Command specification.

## 15. Build pipeline

### 15.1. Crear pipeline

DevOpsDatabase → Build pipelines → Create build pipeline:
- Name database-migrations-build.
- Description: empaquetado de cambios Oracle desde Git.

### 15.2. Managed Build

+ → Add stage → Managed Build:

| Campo | Valor |
|---|---|
| Stage name | package-migrations |
| Build runner shape | Predeterminado; valor efectivo no registrado |
| Base image indicada | Oracle Linux 8 |
| Build specification file | build_spec.yaml |
| Timeout | 600 segundos |
| Private network access | Sin configurar |
| Primary source type | OCI Code Repository |
| Repository | Database-Changes |
| Branch | main |
| Build source name | DatabaseChanges |

Guardar la fuente y la etapa. No instalar SQLcl en este runner: el build solo empaqueta.

### 15.3. Deliver Artifacts

+ después de package-migrations → Add stage → Deliver Artifacts:

- Name publish-migration-package.
- Select Artifact database-migration-package.
- Associate Artifacts with Build Result / Build config/result Artifact name: database-migration-package.

La asociación debe coincidir exactamente con outputArtifacts.name del YAML, no con el nombre del tar.gz.

### 15.4. Primera ejecución y error corregido

Start manual run: asignar un nombre y ejecutar. La rama se configura en Managed Build; no exigir un selector de main en el formulario básico. La consola mostrada por el usuario solo tenía nombre/parámetros. Show advanced options permite seleccionar commit/rama cuando esté disponible.

No pipeline parameter found es normal en el build: las tres variables se calculan como exportedVariables, no son valores que deba introducir una persona.

La primera publicación falló por permisos. El grupo tenía use generic-artifacts; la corrección fue manage generic-artifacts. Se publicó exitosamente tras ajustar la política existente.

Resultado esperado:
~~~text
MIGRATION_PACKAGE_READY
Completed SAVE_EXPORTED_VARIABLES
Completed UPLOAD_ARTIFACT database-migration-package successfully
~~~

Verificar Artifact Registry → database-migrations → Artifacts: path database/migrations.tar.gz y versión commit-sufijo. No se requiere copiar esa versión en cada ejecución.

## 16. Transferencia automática al deployment

### 16.1. Parámetros receptores

Deployment pipelines → database-dev-connectivity → Parameters:

| Nombre | Default |
|---|---|
| SOURCE_COMMIT | UNSET |
| PACKAGE_VERSION | UNSET |
| PACKAGE_SHA256 | UNSET |

Guardar respetando mayúsculas. UNSET hace fallar una ejecución final lanzada sin valores en vez de escoger una versión arbitraria. No introducir hashes nuevos manualmente.

### 16.2. Command specification de verificación del paquete

DevOpsDatabase → Artifacts → Add artifact:
- Name verify-migration-package-spec.
- Type Command specification.
- Source Inline.
- Value contenido completo de pipelines/03-verify-package.yaml.
- Allow parameterization DESACTIVADO / argument_substitution_mode NONE.

El error "Invalid Argument Substitution mode for CommandSpec Deploy Artifacts" se resolvió desactivando esa opción, manteniendo las referencias en env.variables.

El General artifact sí lleva parametrización activada; los Command specification no. No generalizar la casilla entre ambos tipos.

### 16.3. Tercera etapa Shell

Después de check-atp-dbtools-login, agregar Shell:
- Name verify-migration-package.
- Artifact verify-migration-package-spec.
- Misma configuración de ejecución/red que las etapas previas.
- Timeout de referencia 600 segundos.

Valida formato de commit/checksum, relación de versión con commit, descarga exacta mediante OCI CLI, SHA-256 y metadata release.txt, y lista el paquete. No ejecuta DDL.

Resultado BUILD_TO_DEPLOYMENT_HANDOFF_OK.

### 16.4. Trigger Deployment en el build

Después de publish-migration-package:
- + → Add stage → Trigger Deployment.
- Name trigger-database-deployment.
- Select Deployment Pipeline: database-dev-connectivity.
- **Send Build Pipelines Parameters activado.**
- Guardar.

Se transfieren los valores exportados por el build al deployment con los mismos nombres. Esta transferencia quedó validada por la descarga y aplicación satisfactoria de los paquetes.

El flujo del build queda package-migrations → publish-migration-package → trigger-database-deployment. No añadir la etapa de trigger antes de publicar el paquete.

## 17. Aplicación de DDL: cuarta etapa Shell

### 17.1. Artefacto

DevOpsDatabase → Artifacts → Add artifact:
- Name apply-database-migrations-spec.
- Type Command specification.
- Source Inline.
- Value contenido íntegro de pipelines/04-apply-migrations.yaml.
- Allow parameterization DESACTIVADO.

**Renombre local:** antes se entregó como pipelines/03-apply-migrations.yaml. Su copia consolidada es ahora 04-apply-migrations.yaml para respetar el orden de las cuatro etapas. No renombrar el artefacto OCI ni crear otro pipeline por este cambio de nombre local.

### 17.2. Etapa

Después de verify-migration-package agregar Shell:
- Name apply-database-migrations.
- Artifact apply-database-migrations-spec.
- Compartment DATABASE-DEVOPS.
- VCN VCN-CARPETA-CIUDADANA, subnet SUBNET-DEVOPS.
- Misma AD, shape/capacidad y NSG de las etapas probadas.
- Timeout de etapa 1200 segundos, YAML global 1200 y comando 900; cada llamada SQLcl usa timeout 360.

### 17.3. Secuencia interna y protección de credenciales

1. set +x impide trazado de comandos; set -euo pipefail falla ante errores/variables no definidas/pipelines fallidos.
2. umask 077 restringe los archivos temporales al usuario del proceso.
3. mktemp crea la carpeta de trabajo; trap limpia al terminar.
4. Descarga el paquete exacto, comprueba checksum completo, metadata y SHA256SUMS internos.
5. Lee user-name, connection-string, user-password.secret-id, key-stores[0] content/type.
6. Exige usuario DEVOPS_DEMO, wallet SSO y puerto 1522 en el descriptor.
7. Recupera CURRENT de password y cwallet.sso, decodifica base64 y comprueba contenido.
8. Rechaza contraseña vacía o con salto de línea/retorno/comillas dobles, porque el archivo CONNECT elegido no las representa de forma segura. No es una regla universal de passwords Oracle; es una limitación explícita del script.
9. Construye tnsnames.ora y sqlnet.ora, y un ZIP temporal mediante jar. TNS_ADMIN apunta a la carpeta temporal.
10. Escribe un SQL de login protegido. La contraseña no aparece en argumentos del proceso ni se imprime.
11. Comprueba usuario/esquema con PL/SQL y emite AUTHENTICATED_SQL_PHASE.
12. run_phase ejecuta SQLcl /nolog @archivo con stdin cerrado, captura salida y código de retorno.
13. Si hay fallo, muestra códigos y hasta 160 líneas posteriores al marcador autenticado; no muestra el preámbulo CONNECT.
14. Ejecuta lb validate antes de update en otra fase conectada.
15. Ejecuta lb update con resumen VERBOSE y scripts/verify.sql desde la raíz del paquete, manteniendo estable la ruta db/changelog.xml.
16. Al tener éxito muestra salida de update posterior a autenticación para ver Run/Previously run y los marcadores, commit y paquete.

Los comandos efectivos son:

~~~sql
lb validate -changelog-file db/changelog.xml
lb update -changelog-file db/changelog.xml -show-summary VERBOSE
@scripts/verify.sql
~~~

No se presupone que WHENEVER SQLERROR capture toda excepción de un plugin. El wrapper también comprueba código de proceso, patrones de error y marcador de finalización. Es la comprobación implementada, no un parser universal de todas las versiones futuras de SQLcl. Los fallos reales ORA-01031 terminaron la etapa en FAILED.

La salida posterior a autenticación puede contener SQL y datos de las verificaciones. No imprimir secretos en los SQL versionados. Mantener el acceso/retención de logs conforme al entorno.

## 18. Pruebas de aceptación y evidencia

### 18.1. Aplicar por primera vez

Arrancar **database-migrations-build**, no el deployment final de forma aislada. Start manual run no requiere hashes, versiones ni password. El trigger de deployment ejecuta las cuatro etapas.

El primer DDL exitoso del 29-10-2026, ~21:24 UTC, registró:

~~~text
CHANGELOG_VALIDATED
MIGRATION_001_VERIFIED
DEPLOYED_COMMIT=a443aa7b3a2c6040af110bf1a799c3f0e423b9f0
DEPLOYED_PACKAGE=a443aa7b3a2c6040af110bf1a799c3f0e423b9f0-amaaaaaacj6z5kiakc4m3esrljuak7yqi4wwegm7vabi5ma37z6eu3h43moa
DATABASE_MIGRATION_SUCCEEDED
All stages complete. 4 were successful and 0 failed
~~~

### 18.2. Consultas SQL de comprobación

Ejecutar en SQL Developer como DEVOPS_DEMO:

~~~sql
SELECT column_name, data_type, nullable
FROM user_tab_columns
WHERE table_name = 'DEVOPS_CHANGE_DEMO'
ORDER BY column_id;

SELECT id, author, filename, dateexecuted,
       orderexecuted, exectype, md5sum, deployment_id
FROM databasechangelog
WHERE id = '001-create-devops-demo'
  AND author = 'database-devops';

SELECT object_name, object_type, status
FROM user_objects
WHERE object_name LIKE 'DATABASECHANGELOG%'
   OR object_name = 'DEVOPS_CHANGE_DEMO'
ORDER BY object_type, object_name;
~~~

Esperado: tres columnas ID/DESCRIPTION/CREATED_AT y una fila EXECUTED para el changeset. FILENAME identifica el changelog que contiene el changeset, no necesariamente el .sql referenciado.

### 18.3. Repetir y demostrar no reaplicación

Antes/después de repetir conservar la consulta anterior. La fila mantiene DATEEXECUTED, ORDEREXECUTED y MD5SUM. EXECTYPE EXECUTED describe la aplicación registrada, no "aplicado en todas las corridas".

La evidencia definitiva del 30-10-2026 a las 13:31:52 UTC fue:

~~~text
UPDATE SUMMARY
Run:                          0
Previously run:               1
Filtered out:                 0
Total change sets:            1
Operation completed successfully.
DEPLOYED_COMMIT=4824bd3a5dc9ab5465dce6e7bf43cdea99477b3f
DEPLOYED_PACKAGE=4824bd3a5dc9ab5465dce6e7bf43cdea99477b3f-aaaaaaaas35k4cyskvcuxusolu4xntnntfe2vqimrughv7tffqz4zxnrlslq
DATABASE_MIGRATION_SUCCEEDED
All stages complete. 4 were successful and 0 failed
~~~

Esto prueba la revisión de pendientes sin reaplicar. No usar únicamente MIGRATION_001_VERIFIED como prueba de aplicación nueva. Aparece varias veces por DBMS_OUTPUT, prompt y wrapper; no son ejecuciones múltiples del changeset.

Consultar fechas de objeto como evidencia complementaria:

~~~sql
SELECT object_name,
       TO_CHAR(created, 'YYYY-MM-DD HH24:MI:SS') AS fecha_creacion,
       TO_CHAR(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_ddl
FROM user_objects
WHERE object_name = 'DEVOPS_CHANGE_DEMO'
  AND object_type = 'TABLE';
~~~

DATEEXECUTED y fechas de diccionario no incluyen necesariamente zona; no comparar sin contexto con UTC de los logs. LAST_DDL_TIME puede cambiar por otras operaciones.

## 19. Protección de main, trigger y prueba documental

Esta sección reproduce el procedimiento dado para estos controles. El log recibido confirma un nuevo commit y no reaplicación, pero no demuestra por sí solo quién/qué disparó la corrida. Para cerrar esa evidencia revisar trigger, branch protection y origen del Build Run en consola.

### 19.1. Branch protection

DevOpsDatabase → Code Repositories → Database-Changes → Settings → Branch protection → Add:
- Branch main.
- Pull request merge only.
- Guardar.
- No elegir Read only, que impediría incorporar cambios.

### 19.2. Aprobaciones

Approval rules: **pendiente**, no configurar mínimo 1 con solo el autor disponible. El usuario confirmó que por ahora solo tiene su cuenta. El merge sin aprobación sirvió al laboratorio; no presentarlo como separación de funciones terminada.

Cuando exista otro usuario: Add approval rule → nombre approval-main-database → target main → seleccionar revisor autorizado → minimum approvals 1 → guardar. Las reglas nuevas aplican a PR creados después. No reconfigurar la identidad o conceder roles genéricos para autoaprobar.

Build status check antes de merge no se implementó como CI separado. El build actual despliega y se dispara tras push a main: no conectarlo a PR created/updated sin separar su capacidad de aplicar DDL.

### 19.3. Trigger del repositorio

DevOpsDatabase → Triggers → Create Trigger:
1. Name database-main-push.
2. Source connection OCI Code Repository.
3. Repository Database-Changes.
4. Add Action → build pipeline database-migrations-build.
5. Event Push.
6. Build run conditions → source repository branch main.
7. Included/excluded files vacíos.
8. Guardar acción y crear trigger.

Una sola acción. No duplicar con PR Merged para el mismo objetivo. Un push a feature no debe iniciar este build; el merge mueve main y debe dispararlo. No se necesita webhook/secret externo para este repo OCI.

### 19.4. Comandos de prueba documental comunicados

Desde la VM Linux:

~~~bash
cd /home/opc/Database-DevOps
git switch main
git pull --ff-only origin main
git status --short --branch

git switch -c feature/test-automatic-trigger
mkdir -p docs
~~~

Crear docs/automatic-deployment.md con el contenido del anexo; después:

~~~bash
git diff --check
git add docs/automatic-deployment.md
git diff --cached
git commit -m "Document automatic database deployment test"
git push -u origin feature/test-automatic-trigger
~~~

No debe iniciar build por estar en feature. Crear PR source feature/test-automatic-trigger, destination main, título Prueba del disparador automático desde main. Revisar y merge con la cuenta disponible, sin declarar aprobación independiente. No pulsar Start manual run: revisar que el Build Run nazca del trigger. Registrar PR/commit, origen de build, deployment y resultados.

El commit posterior observado es 4824bd3a5dc9ab5465dce6e7bf43cdea99477b3f; el contenido exacto de ese árbol no fue exportado. docs/automatic-deployment.md en el workspace reproduce el texto de la prueba instruida.

## 20. Operación diaria y lectura del versionamiento

La configuración de infraestructura/pipelines se hace una vez. En cambios posteriores el cliente:
1. Actualiza main en la VM y crea una rama para el cambio lógico.
2. Escribe SQL, agrega un changeset y su verificación/rollback según corresponda.
3. Revisa el diff, commit y push.
4. Abre PR; el revisor aprueba cuando ese control esté disponible.
5. Hace merge.
6. El trigger/build/deployment actúa automáticamente y se revisa evidencia.

No hay nueva política, grupo dinámico, paquete versionado manualmente ni instalación de Python por cambio. Una rama puede contener varios archivos relacionados.

Git guarda versiones de fuentes; nombre/numero del SQL es una convención humana. Liquibase identifica por archivo de changelog + id + author. Mantener aplicados sin editar para evitar checksum mismatch. El paquete/commit identifica el conjunto entregado; su versión cambia por build aunque Run sea 0.

El build toma cualquier archivo nuevo versionado bajo db/ y scripts/, pero Liquibase ejecuta solo los cambios referenciados por el changelog. Mantener archivos aplicados/rutas estables. No editar DATABASECHANGELOG manualmente.

La verificación actual está deliberadamente centrada en 001. Antes de probar más objetos debe ampliarse con verificaciones del nuevo cambio. Los procedimientos/triggers PL/SQL requieren una plantilla de separadores/splitStatements adecuada; no copiar sin evaluar el patrón DDL de una sola tabla.

## 21. Errores reales y correcciones, sin repetir los pasos fallidos

| Síntoma | Hallazgo | Corrección aplicada |
|---|---|---|
| Trigger shell execution failed / sin logs útiles | Proyecto de otra prueba (MinTic) mezclado con el compartment y políticas de este proyecto. | Volver a DevOpsDatabase / DATABASE-DEVOPS. |
| Imagen del contenedor no descargable | Falla antes de ejecutar el script; salida de subred a Container Registry. | Revisar ruta real de SUBNET-DEVOPS, Service Gateway All ORD Services y NAT. |
| Endpoint privado de Database Tools confuso | No era el mismo recurso que private endpoint de ATP. | Crear/seleccionar DEVOPSDATABASE-Private-Endpoint. |
| ORA-18714 al validar conexión | Descriptor autopoblado con 1521 en un flujo mTLS. | Copiar descriptor mTLS de ATP, host definitivo y puerto 1522; validar. |
| Hostnames distintos | p2q0oapn de prueba previa frente a uepanbou definitivo. | Usar la metadata de atp-devops-demo y wallet de DEVOPSDATABASE1. |
| ZIP del wallet en campo SSO | Formatos distintos entre SQL Developer Cloud Wallet y secret SSO. | Cargar cwallet.sso en Database Tools; el script genera un ZIP temporal para SQLcl. |
| ORA-01005 / JLine Mask Thread | Password suministrado mediante prompt stdin redirigido. | CONNECT en archivo SQL temporal protegido, /nolog @archivo, stdin cerrado. No cambiar un secreto válido para arreglar stdin. |
| Regla dinámica ANY con ALL anidado rechazada | Editor esperaba campos separados. | Match any + Rule1 ALL deployment + Rule2 ALL build. |
| Upload artifact failed / policy | use generic-artifacts no creaba una nueva versión. | manage generic-artifacts en la política existente. |
| Invalid Argument Substitution mode for CommandSpec | Allow parameterization activado en Command specification. | NONE/desactivado; env.variables mantiene referencias. |
| main no aparece en Start manual run | El formulario básico no incluye siempre selector de rama. | Revisar main en Primary build source de Managed Build; no recrear pipeline. |
| Git pide token cada vez | -c credential.helper= desactivaba helper por comando. | Caché local 28800 y quitar -c de operaciones normales. |
| Add self and approve en gris | Solo la cuenta autora disponible; sin reglas iniciales de aprobación. | Merge de laboratorio permitido; aprobación independiente pendiente. |
| ORA-01031 durante update | Inicialización auxiliar parcial, faltaban privilegios efectivos. | Añadir PROCEDURE y luego VIEW/TRIGGER. No confundir con IAM/red. |
| CREATE TABLE manual funciona pero Liquibase no | DDL de usuario permitido; inicialización auxiliar tenía requisitos adicionales. | Completar permisos y evitar atribuir el fallo a la tabla sin sentencia exacta. |
| Tabla creada manualmente durante diagnóstico | Existía fuera del changeset. | Usuario verificó sin registro y eliminó solo DEVOPS_CHANGE_DEMO antes de reintentar. |
| Riesgo ORA-00955 al reintentar | Tabla manual existente y changeset pendiente. | No ejecutar DDL manual. La eliminación mencionada fue exclusivamente del laboratorio vacío, no receta para datos de cliente. |
| Logs solo mostraban ORA-01031 | Wrapper ocultaba demasiado contexto. | Mostrar diagnóstico posterior a AUTHENTICATED_SQL_PHASE. |
| No se distingue nuevo cambio de omitido | Marcadores de verificación no son resumen de ejecución. | Mostrar salida autenticada de update y -show-summary VERBOSE. |
| Scripts Python/installer proponían carga adicional | Propuesta no adoptada ni publicada. | Descartados; changelog autorado por cliente y build Bash genérico. |

No implementar grants ANY/DBA/RESOURCE ni eliminar tablas de control como atajo. No liberar locks sin comprobar si hay otra operación real en curso. Los checksums y CURRENT de secretos permiten detectar problemas sin imprimir credenciales.

## 22. Rollback, parametrización y organización: límites actuales

### 22.1. Rollback explicado, no ejecutado

El changeset 001 contiene DROP TABLE como rollback. Pierde la tabla/datos. Git revert o desplegar un paquete antiguo no revierte por sí mismo la base.

Los comandos de SQLcl explicados, para un procedimiento aprobado y usando paquete exacto, fueron:

~~~sql
lb rollback-count-sql -count 1 -changelog-file db/changelog.xml
lb rollback-count -count 1 -changelog-file db/changelog.xml
~~~

El primero genera SQL; el segundo revierte. count 1 es un changeset, no una corrida Run:0. No ejecutar como parte de este documento. No existe pipeline de rollback configurado. Tras rollback el registro se retira de DATABASECHANGELOG; los logs/evidencias conservan historia adicional. Un update posterior podría reaplicar; el verify.sql actual espera la tabla y no sirve como verificación de rollback.

### 22.2. Objetos y parámetros

Se explicó que se pueden versionar DDL, paquetes/procedimientos, cambios DML en tablas de configuración y archivos externos. Solo se probó CREATE TABLE.

Para DML se debe definir la fila exacta, precondiciones/valor previo y verificación; no se versionan automáticamente todos los datos. Archivos externos necesitan una etapa de aplicación específica; el empaquetado actual no incluye config/.

runOnChange es una alternativa deliberada para objetos CREATE OR REPLACE, no una configuración activada en este proyecto.

### 22.3. Varios changelogs

Se puede conservar db/changelog.xml como entrada e incluir archivos clasificados. No se crearon esos archivos en el flujo actual. Mantener el changeset 001 donde está; moverlo cambia su identidad si no se preserva la ruta lógica. No agregar "changelog de ejemplo" al workspace como si se estuviera usando.

### 22.4. Dashboard y auditoría

OCI Logging contiene salida del pipeline. Monitoring tiene métricas DevOps de build/deployment. Un dashboard puede combinar métricas y búsquedas de logs, pero no se creó. La lista de changesets requiere correlacionar/publicar evidencia de Liquibase; no existe automáticamente como métrica nativa.

No se habilitó ni se verificó auditoría SQL de todas las modificaciones manuales. No presentar Git/Liquibase como detección universal de cambios fuera del flujo. Retención de logs, archivos de evidencia y correlación PR/commit/paquete/changeset deben completarse según el cliente.

## 23. Inventario limpio: uso de cada archivo

| Archivo | Uso / dónde se consume |
|---|---|
| README.md | Entrada breve al workspace y enlace a este documento. |
| CONFIGURACION_COMPLETA_OCI_DATABASE_DEVOPS.md | Reconstrucción completa, contenidos íntegros y explicaciones. |
| .gitattributes | Reglas de finales de línea del clon Git. |
| .gitignore | Exclusión de secretos, wallets y salidas de build. |
| build_spec.yaml | Raíz del repo fuente; Managed Build. |
| db/changelog.xml | Entrada de Liquibase en el paquete. |
| db/changes/001_create_devops_demo.sql | DDL real versionado del changeset 001. |
| db/changes/002_add_estado.sql | DDL más reciente de la segunda prueba, pendiente de éxito después de corregir XML. |
| scripts/verify.sql | Comprobación posterior real del paquete. |
| pipelines/01-network-probe.yaml | Copia para artefacto Inline database-network-probe. |
| pipelines/02-dbtools-login.yaml | Copia para artefacto Inline database-dbtools-login. |
| pipelines/03-verify-package.yaml | Copia recuperada para artefacto Inline verify-migration-package-spec. |
| pipelines/04-apply-migrations.yaml | Copia final para artefacto Inline apply-database-migrations-spec. |
| infra/dynamic-group-rules.txt | Dos reglas usadas en el grupo existente. No se ejecuta como shell. |
| infra/devops-policy.txt | Política consolidada de los enunciados utilizados. No es Terraform. |
| infra/database-user.sql | Consolida CREATE USER/cuota/grants ejecutados en SQL Developer; para alta inicial, no pipeline. |
| docs/automatic-deployment.md | Contenido comunicado para la prueba documental del trigger; no aplica SQL. |
| .git/ | Metadata técnica del workspace preexistente, preservada. No es un archivo para OCI. |

infra/ y pipelines/ son copias de referencia locales organizadas en esta limpieza; no se afirma que ya estén publicadas en el repositorio de la VM. Para publicarlas debe realizarse el ciclo explícito Git/PR desde la VM, si se desea. El código de pipeline ya funciona en sus artefactos Inline y no cambia por esta limpieza.

### 23.1. Retirado del workspace

- improvements/ completo: apply-improvements.sh, make_delivery.py, changes.py, pruebas y build/verificador Python descartados.
- config/target.example.json: ejemplo no consumido por ninguna etapa.
- scripts/deploy.sql y scripts/validate.sql: wrappers locales propuestos pero no usados por el flujo exitoso.
- infra/deploy-shell-policy.template.txt e infra/dbtools-login-policy.txt: reemplazados por reglas/política consolidadas completas.
- pipelines/build-spec-no-python.yaml: duplicado renombrado a build_spec.yaml en raíz.
- pipelines/03-apply-migrations.yaml: renombrado a 04-apply-migrations.yaml.
- README antiguo: contenía estados previos ya obsoletos.

La limpieza solo afecta este workspace Windows. No borra repositorios OCI, ramas de la VM, artefactos, secretos, recursos ni tablas.

Antes de la limpieza se creó una copia fuera del workspace, en el TEMP del usuario, con nombre Database-DevOps-before-cleanup-20261030-102017.zip. Es respaldo temporal, no una política de conservación permanente. No introducirlo en Git.

### 23.2. Diferencias reconciliadas con el historial

La copia local de scripts/verify.sql tenía una variante anterior; se reemplazó por el contenido exacto publicado en la instrucción inicial de la VM, con SERVEROUTPUT y DBMS_OUTPUT de MIGRATION_001_VERIFIED. .gitignore y db/changelog.xml también se alinearon con los bloques de creación comunicados. El YAML de verificación del paquete se recuperó del mensaje que se copió a consola. El YAML de red consolidado usa el patrón original comunicado, con el hostname definitivo.

No se exportaron de OCI los Inline finales byte por byte ni el árbol Linux actual. Esta reconstrucción usa la última versión enviada y el éxito confirmado. Para acreditar igualdad exacta, comparar los Inline en consola y ejecutar en la VM git show HEAD:ruta; el registro no permite afirmar una comparación que no se hizo.

## 24. Referencias oficiales y límites de la reconstrucción

Los enlaces son referencias de producto. La evidencia de ejecución de esta tenancy son los logs/capturas del usuario descritos arriba. Los requisitos de producción, aprobación independiente y observabilidad ampliada no se declaran terminados.

- [DevOps IAM](https://docs.oracle.com/en-us/iaas/Content/devops/using/devops_iampolicies.htm)
- [Shell stage y red de ejecución](https://docs.oracle.com/en-us/iaas/Content/devops/using/shell_stage.htm)
- [Command specification y env](https://docs.oracle.com/en-us/iaas/Content/devops/using/command_spec.htm)
- [Build specification y variables](https://docs.oracle.com/en-us/iaas/Content/devops/using/build_specs.htm)
- [Managed Build](https://docs.oracle.com/en-us/iaas/Content/devops/using/add_buildstage.htm)
- [Deliver Artifacts](https://docs.oracle.com/en-us/iaas/Content/devops/using/add_deliverartifact.htm)
- [Trigger Deployment](https://docs.oracle.com/en-us/iaas/Content/devops/using/triggerdeploy_stage.htm)
- [Ejecución manual build](https://docs.oracle.com/en-us/iaas/Content/devops/using/run_build.htm)
- [Trigger de repositorio](https://docs.oracle.com/en-us/iaas/Content/devops/using/trigger_build.htm)
- [Repository settings / approvals / protection](https://docs.oracle.com/en-us/iaas/Content/devops/using/reposettings.htm)
- [Autenticación HTTPS Git](https://docs.oracle.com/en-us/iaas/Content/devops/using/https_auth.htm)
- [Crear Artifact Registry repository](https://docs.oracle.com/en-us/iaas/Content/artifacts/create-repo.htm)
- [Database Tools: crear conexión](https://docs.oracle.com/en-us/iaas/database-tools/doc/using-oracle-cloud-infrastructure-console.html)
- [Database Tools: private endpoint](https://docs.oracle.com/en-us/iaas/database-tools/doc/using-console2.html)
- [ATP: descargar wallet y descriptores](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/connect-download-wallet.html)
- [Bastion: port forwarding session](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/create-session-port-forwarding.htm)
- [Bastion: conectarse al túnel](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/connect-port-forwarding.htm)
- [Requisitos Liquibase SQLcl](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/25.2/sqcug/requirements-using-liquibase.html)
- [SQLcl: comandos Liquibase](https://docs.oracle.com/en/database/oracle/sql-developer-command-line/26.1/sqcug/liquibase.html)
- [SQLcl: objetos auxiliares documentados](https://www.oracle.com/tools/sqlcl/sqlcl-relnotes-24.1.html)
- [Métricas DevOps](https://docs.oracle.com/en-us/iaas/Content/devops/using/devops_metrics.htm)
- [Widgets de dashboard](https://docs.oracle.com/en-us/iaas/Content/Dashboards/Tasks/widgetmanagement.htm)

La documentación accesible de SQLcl consultada fue 26.1 y requisitos 25.2; la guía 26.2 no resultó accesible por el buscador durante la sesión. El runtime observado y probado fue SQLcl 26.2.1. No afirmar que se verificó una guía 26.2 inexistente/inaccesible.

### Datos de consola que deben completarse desde los recursos existentes

| Dato no suministrado | Dónde obtenerlo | ¿Bloquea el flujo actual? |
|---|---|---|
| AD/shape/OCPU/memoria exactos de Shell | Editar/ver configuración de cada Shell stage | No; el flujo ya funciona. Necesario para réplica idéntica de capacidad. |
| Imagen/build runner efectivo | Managed Build stage y logs | No; conservar el usado. |
| OCID de build/deployment pipelines y stages | General information de cada recurso | No; selectores usan nombres. |
| Log Group/log OCID/retención | Proyecto → Logging y Logging → Logs | No; necesario para evidencia de retención. |
| Topic/suscripción de notificaciones | General information del proyecto y Notifications | No; no se verificó entrega de avisos. |
| Vault key OCID | Secrets → Encryption key | No; necesario al reconstruir secretos. |
| IP privada final ATP y Reverse Connection IPs | ATP / Database Tools private endpoint | No; descriptor DNS ya funciona. |
| Nombres/OCID route tables, gateways, DHCP, VCN/subnets | Networking → recurso | No; no inventar identificadores. |
| Bastion/session OCID y comando final | Bastion → Sessions | No para pipeline; solo administración desde laptop. |
| Estado final del trigger/protection/origen de Build Run | DevOps → Triggers / repo Settings / build details | Necesario para certificar automatismo y protección. |

Estos vacíos son ausencia de datos en el registro, no pasos omitidos intencionalmente. Se incluye cómo obtenerlos. Reproducir la función es posible con los valores/selecciones descritos; afirmar una réplica bit a bit de la tenancy sin esos datos no sería correcto.

## 25. Contenido íntegro de archivos y bloques de creación

Los bloques siguientes son copias completas de los archivos conservados. Para archivos que se usan en la consola, copiar solo el contenido YAML/texto indicado, no cat/EOF. Para fuentes del repositorio, el bloque Bash crea el archivo en Linux. Ejecutar primero mkdir -p db/changes scripts pipelines infra docs dentro del clon cuando se quiera materializar todas las copias de configuración.

Los archivos infra y pipelines de este anexo permiten documentar la configuración; no se añaden al paquete de DDL por el build actual. No es obligatorio publicarlos todos para repetir el despliegue existente.


### 25.1. .gitattributes

Se publica en Git. Mantiene LF en SQL/XML/YAML/shell/Markdown. No configura ejecución ni reemplaza las comprobaciones de SQL.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
cat > .gitattributes <<'EOF'
* text=auto
*.sh text eol=lf
*.sql text eol=lf
*.xml text eol=lf
*.yaml text eol=lf
*.md text eol=lf
EOF
~~~

### 25.2. .gitignore

Se publica en Git. Evita agregar tokens/configuración OCI/wallets/output. Ignorar no elimina un secreto que ya haya sido versionado; aquí no se versionaron secretos.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
cat > .gitignore <<'EOF'
.env
.env.*
*.pem
*.key
*.p12
*.sso
*.jks
*.zip
*.log
.oci/
wallet*/
Wallet*/
tnsnames.ora
sqlnet.ora
ojdbc.properties
output/
EOF
~~~

### 25.3. db/changelog.xml

Se publica y empaqueta. Contiene los changesets 001 y 002 con sus respectivos SQL y rollback. 001 tiene ejecución confirmada; 002 contiene la corrección XML preparada, sin éxito posterior confirmado. No mover ni modificar la identidad de 001. No ejecutar rollback durante reconstrucción.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
mkdir -p db
cat > db/changelog.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog https://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.0.xsd">

    <changeSet id="001-create-devops-demo" author="database-devops">
        <sqlFile
            path="changes/001_create_devops_demo.sql"
            relativeToChangelogFile="true"
            splitStatements="true"
            endDelimiter=";"/>
        <rollback>
            <sql>DROP TABLE DEVOPS_CHANGE_DEMO</sql>
        </rollback>
    </changeSet>

    <changeSet id="002-add-estado" author="database-devops">
        <sqlFile
            path="changes/002_add_estado.sql"
            relativeToChangelogFile="true"
            splitStatements="true"
            endDelimiter=";"/>

        <rollback>
            <sql>ALTER TABLE DEVOPS_CHANGE_DEMO DROP COLUMN ESTADO</sql>
        </rollback>
    </changeSet>
</databaseChangeLog>
EOF
~~~

### 25.4. db/changes/001_create_devops_demo.sql

SQL publicado y aplicado por Liquibase. NUMBER PRIMARY KEY, DESCRIPTION obligatoria y CREATED_AT con valor por defecto. No contiene creación de usuario ni grants.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
mkdir -p db/changes
cat > db/changes/001_create_devops_demo.sql <<'EOF'
CREATE TABLE DEVOPS_CHANGE_DEMO (
    ID NUMBER PRIMARY KEY,
    DESCRIPTION VARCHAR2(200) NOT NULL,
    CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);
EOF
~~~

### 25.5. scripts/verify.sql

Contenido recuperado del bloque enviado a la VM y consistente con DBMS_OUTPUT observado. Hace fallar SQLcl si no coincide identidad, columnas o registro EXECUTED. Este verificador es específico de 001; no es un control general de futuras migraciones.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
mkdir -p scripts
cat > scripts/verify.sql <<'EOF'
WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT FAILURE
SET ECHO OFF
SET VERIFY OFF
SET SERVEROUTPUT ON

DECLARE
    column_count PLS_INTEGER;
    history_count PLS_INTEGER;
BEGIN
    IF USER <> 'DEVOPS_DEMO'
       OR SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') <> 'DEVOPS_DEMO' THEN
        RAISE_APPLICATION_ERROR(-20001, 'Expected DEVOPS_DEMO session and schema');
    END IF;

    SELECT COUNT(*)
      INTO column_count
      FROM USER_TAB_COLUMNS
     WHERE TABLE_NAME = 'DEVOPS_CHANGE_DEMO'
       AND COLUMN_NAME IN ('ID', 'DESCRIPTION', 'CREATED_AT');

    IF column_count <> 3 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Demo table verification failed');
    END IF;

    SELECT COUNT(*)
      INTO history_count
      FROM DATABASECHANGELOG
     WHERE ID = '001-create-devops-demo'
       AND AUTHOR = 'database-devops'
       AND EXECTYPE = 'EXECUTED';

    IF history_count <> 1 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Migration history verification failed');
    END IF;

    DBMS_OUTPUT.PUT_LINE('MIGRATION_001_VERIFIED');
END;
/
EOF
~~~

### 25.6. build_spec.yaml

Se coloca en la raíz del repo fuente. Managed Build lo consume del commit seleccionado; sus valores runtime vienen de OCI y no deben sustituirse en el archivo. outputArtifacts enlaza con Deliver Artifacts.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
cat > build_spec.yaml <<'EOF'
version: 0.1
component: build
timeoutInSeconds: 600
shell: bash
failImmediatelyOnError: true
env:
  exportedVariables:
    - SOURCE_COMMIT
    - PACKAGE_VERSION
    - PACKAGE_SHA256
steps:
  - type: Command
    name: Package versioned database changes
    timeoutInSeconds: 300
    command: |
      set -euo pipefail
      cd "$OCI_PRIMARY_SOURCE_DIR"
      export SOURCE_COMMIT="$OCI_PRIMARY_SOURCE_COMMIT_HASH"
      [[ "$SOURCE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]]
      test "$(git rev-parse HEAD)" = "$SOURCE_COMMIT"
      export PACKAGE_VERSION="${SOURCE_COMMIT}-${OCI_BUILD_RUN_ID##*.}"
      PACKAGE_DIR=$(mktemp -d)
      trap 'rm -rf -- "$PACKAGE_DIR"' EXIT
      mkdir -p output
      git archive --format=tar "$SOURCE_COMMIT" db scripts > "$PACKAGE_DIR/source.tar"
      mkdir "$PACKAGE_DIR/content"
      tar -xf "$PACKAGE_DIR/source.tar" -C "$PACKAGE_DIR/content"
      cd "$PACKAGE_DIR/content"
      test -s db/changelog.xml
      test -s scripts/verify.sql
      if find db scripts -type l -print -quit | grep -q .; then
        echo "ERROR: symbolic links are not allowed in the package"
        exit 1
      fi
      printf 'source_commit=%s\nbuild_run=%s\npackage_version=%s\n' \
        "$SOURCE_COMMIT" "$OCI_BUILD_RUN_ID" "$PACKAGE_VERSION" > release.txt
      find db scripts -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
      sha256sum release.txt >> SHA256SUMS
      sha256sum --check SHA256SUMS
      tar -czf "$OCI_PRIMARY_SOURCE_DIR/output/database-migrations.tar.gz" .
      cd "$OCI_PRIMARY_SOURCE_DIR"
      PACKAGE_SHA256=$(sha256sum output/database-migrations.tar.gz | cut -d ' ' -f 1)
      export PACKAGE_SHA256
      tar -tzf output/database-migrations.tar.gz
      printf 'SOURCE_COMMIT=%s\nPACKAGE_VERSION=%s\nPACKAGE_SHA256=%s\n' \
        "$SOURCE_COMMIT" "$PACKAGE_VERSION" "$PACKAGE_SHA256"
      echo MIGRATION_PACKAGE_READY
outputArtifacts:
  - name: database-migration-package
    type: BINARY
    location: output/database-migrations.tar.gz
EOF
~~~

### 25.7. pipelines/01-network-probe.yaml

Copiar el YAML completo al Inline database-network-probe, Allow parameterization OFF. Host consolidado definitivo. El SQLcl mostrado debe existir en el runtime; esta etapa solo mide DNS/TCP.

Uso en OCI: seleccionar el artefacto indicado, Edit → Inline, sustituir todo el contenido y guardar. No pegar el wrapper cat del bloque Bash siguiente en el campo Inline.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~yaml
version: 0.1
component: command
timeoutInSeconds: 300
shell: bash
failImmediatelyOnError: true

env:
  variables:
    DB_HOST: "uepanbou.adb.us-chicago-1.oraclecloud.com"
    DB_PORT: "1522"

steps:
  - type: Command
    name: "Check SQLcl and ATP connectivity"
    timeoutInSeconds: 120
    command: |
      set -euo pipefail

      echo "STEP 1: Check SQLcl"
      command -v sql
      sql -version

      echo "STEP 2: Resolve ATP private hostname"
      getent ahostsv4 "$DB_HOST"

      echo "STEP 3: Check TCP port 1522"
      timeout 15 bash -euc \
        'exec 3<>/dev/tcp/"$1"/"$2"; exec 3>&-; exec 3<&-' \
        probe "$DB_HOST" "$DB_PORT"

      echo "NETWORK_PROBE_OK"
~~~

### 25.8. pipelines/02-dbtools-login.yaml

Copiar al Inline database-dbtools-login, OFF. Login probe v2 exitoso. Descarga metadata/secrets, crea wallet temporal y ejecuta CONNECT no interactivo. No aplica cambios.

Uso en OCI: seleccionar el artefacto indicado, Edit → Inline, sustituir todo el contenido y guardar. No pegar el wrapper cat del bloque Bash siguiente en el campo Inline.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~yaml
# Read-only DEV login probe. Inline artifact; Allow parameterization OFF.
# Uses OCI CLI resource principal to retrieve the existing connection and SSO secret.
# No user OCI API keys/config, no bucket, and no DDL.
version: 0.1
component: command
timeoutInSeconds: 600
shell: bash
failImmediatelyOnError: true
env:
  variables:
    CONNECTION_OCID: "ocid1.databasetoolsconnection.oc1.us-chicago-1.amaaaaaacj6z5kiayoiodu263eacr6dshwagahee5jvjq7hn2ohayunv2hhq"
steps:
  - type: Command
    name: "Connect as DEVOPS_DEMO using Database Tools metadata"
    timeoutInSeconds: 480
    command: |
      set +x
      set -euo pipefail
      umask 077
      for tool in oci sql jar base64 timeout; do command -v "$tool" >/dev/null; done
      probe_dir=$(mktemp -d /tmp/dbtools-login.XXXXXXXX)
      trap 'unset db_password; rm -rf -- "$probe_dir"' EXIT
      export OCI_CLI_AUTH=resource_principal
      export OCI_CLI_REGION=us-chicago-1

      echo "STEP 1: Read Database Tools connection"
      conn_field() {
        oci dbtools connection get --connection-id "$CONNECTION_OCID" \
          --auth resource_principal --region us-chicago-1 --query "$1" --raw-output
      }
      db_user=$(conn_field 'data."user-name"')
      descriptor=$(conn_field 'data."connection-string"')
      password_secret=$(conn_field 'data."user-password"."secret-id"')
      wallet_secret=$(conn_field 'data."key-stores"[0]."key-store-content"."secret-id"')
      wallet_type=$(conn_field 'data."key-stores"[0]."key-store-type"')
      [[ "$db_user" == DEVOPS_DEMO ]]
      [[ "$wallet_type" == SSO ]]
      [[ "$password_secret" == ocid1.vaultsecret.* && "$wallet_secret" == ocid1.vaultsecret.* ]]
      if ! printf '%s' "$descriptor" | grep -Eiq '\(port[[:space:]]*=[[:space:]]*1522\)'; then
        echo "Expected the validated mTLS descriptor on port 1522."
        exit 1
      fi

      echo "STEP 2: Retrieve password and SSO wallet without printing content"
      secret_content() {
        oci secrets secret-bundle get --secret-id "$1" --stage CURRENT \
          --auth resource_principal --region us-chicago-1 \
          --query 'data."secret-bundle-content".content' --raw-output
      }
      db_password=$(secret_content "$password_secret" | base64 --decode)
      if [[ -z "$db_password" || "$db_password" == *$'\n'* || "$db_password" == *$'\r'* || "$db_password" == *'"'* ]]; then
        echo "Password content cannot be represented safely in this login script."
        exit 1
      fi
      secret_content "$wallet_secret" | base64 --decode > "$probe_dir/cwallet.sso"
      [[ -s "$probe_dir/cwallet.sso" ]]
      # Reject a ZIP saved as the SSO secret; do not inspect or print credential contents.
      if [[ "$(head -c 2 "$probe_dir/cwallet.sso")" == PK ]]; then
        echo "The wallet secret contains a ZIP; this probe requires cwallet.sso content."
        exit 1
      fi
      printf 'devops_target = %s\n' "$descriptor" > "$probe_dir/tnsnames.ora"
      printf 'WALLET_LOCATION=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY="%s")))\nSSL_SERVER_DN_MATCH=YES\n' "$probe_dir" > "$probe_dir/sqlnet.ora"
      jar cf "$probe_dir/wallet.zip" -C "$probe_dir" cwallet.sso -C "$probe_dir" tnsnames.ora -C "$probe_dir" sqlnet.ora
      export TNS_ADMIN="$probe_dir"

      echo "STEP 3: Non-interactive authentication (login probe v2)"
      # Use a protected SQL file: never invoke JLine's interactive password reader.
      # The secret is not an OS command argument and is not printed to deployment logs.
      {
        printf '%s\n' 'set echo off' 'set verify off' 'set define off'
        printf '%s\n' 'whenever oserror exit failure' 'whenever sqlerror exit failure'
        printf 'connect DEVOPS_DEMO/"%s"@devops_target\n' "$db_password"
        printf '%s\n' 'set heading off' 'set feedback off' 'set pagesize 0'
        printf '%s\n' "SELECT CASE WHEN USER = 'DEVOPS_DEMO' AND SYS_CONTEXT('USERENV','CURRENT_SCHEMA') = 'DEVOPS_DEMO' THEN 'DBTOOLS_LOGIN_OK:DEVOPS_DEMO' ELSE 'DBTOOLS_LOGIN_WRONG_USER' END FROM DUAL;"
        printf '%s\n' 'exit success'
      } > "$probe_dir/login.sql"
      unset db_password
      if ! timeout 180 sql -S -L -cloudconfig "$probe_dir/wallet.zip" /nolog @"$probe_dir/login.sql" </dev/null > "$probe_dir/sqlcl-output.txt" 2>&1; then
        echo "SQLcl login probe failed; error codes (raw output withheld to protect credentials):"
        grep -Eo '(ORA|SP2|SQLCL)-[0-9]+' "$probe_dir/sqlcl-output.txt" | sort -u || true
        exit 1
      fi
      if ! grep -Eq '^[[:space:]]*DBTOOLS_LOGIN_OK:DEVOPS_DEMO[[:space:]]*$' "$probe_dir/sqlcl-output.txt"; then
        echo "Expected identity marker missing; probe failed."
        grep -Eo '(ORA|SP2|SQLCL)-[0-9]+' "$probe_dir/sqlcl-output.txt" | sort -u || true
        exit 1
      fi
      echo "DBTOOLS_LOGIN_OK:DEVOPS_DEMO"
      echo "DBTOOLS_LOGIN_PROBE_SUCCEEDED"
~~~

### 25.9. pipelines/03-verify-package.yaml

Copiar al Inline verify-migration-package-spec, OFF. Recuperado íntegramente de la instrucción que se ejecutó en OCI. env.variables recibe parámetros; no activar sustitución general de CommandSpec.

Uso en OCI: seleccionar el artefacto indicado, Edit → Inline, sustituir todo el contenido y guardar. No pegar el wrapper cat del bloque Bash siguiente en el campo Inline.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~yaml
# Command specification Inline: Allow parameterization OFF (NONE).
version: 0.1
component: command
timeoutInSeconds: 600
shell: bash
failImmediatelyOnError: true

env:
  variables:
    RELEASE_COMMIT: "${SOURCE_COMMIT}"
    RELEASE_VERSION: "${PACKAGE_VERSION}"
    RELEASE_SHA256: "${PACKAGE_SHA256}"

steps:
  - type: Command
    name: Verify package received from build
    timeoutInSeconds: 300
    command: |
      set -euo pipefail
      umask 077

      echo "STEP 1: Validate automatically received parameters"

      [[ "$RELEASE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]]
      [[ "$RELEASE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]
      [[ "$RELEASE_VERSION" == "$RELEASE_COMMIT"-* ]]

      printf 'SOURCE_COMMIT=%s\nPACKAGE_VERSION=%s\nPACKAGE_SHA256=%s\n' \
        "$RELEASE_COMMIT" "$RELEASE_VERSION" "$RELEASE_SHA256"

      work_dir=$(mktemp -d)
      trap 'rm -rf -- "$work_dir"' EXIT

      echo "STEP 2: Download the exact package produced by the build"

      oci artifacts generic artifact download-by-path \
        --auth resource_principal \
        --region us-chicago-1 \
        --repository-id ocid1.artifactrepository.oc1.us-chicago-1.0.amaaaaaacj6z5kiagpfcblufsym7iv4schnzbe7ja5ks47wrflm6ipvb5vca \
        --artifact-path database/migrations.tar.gz \
        --artifact-version "$RELEASE_VERSION" \
        --file "$work_dir/package.tar.gz"

      echo "STEP 3: Verify package checksum"

      printf '%s  %s\n' "$RELEASE_SHA256" "$work_dir/package.tar.gz" \
        | sha256sum --check -

      echo "STEP 4: Verify release metadata"

      tar -xOf "$work_dir/package.tar.gz" ./release.txt \
        > "$work_dir/release.txt"

      grep -Fx "source_commit=$RELEASE_COMMIT" "$work_dir/release.txt"
      grep -Fx "package_version=$RELEASE_VERSION" "$work_dir/release.txt"

      echo "STEP 5: List package contents"

      tar -tzf "$work_dir/package.tar.gz"

      echo BUILD_TO_DEPLOYMENT_HANDOFF_OK
~~~

### 25.10. pipelines/04-apply-migrations.yaml

Copiar al Inline apply-database-migrations-spec, OFF. Versión final con permisos ya preparados fuera del pipeline, diagnóstico posterior al login y resumen VERBOSE que permitió demostrar Run:0. Renombrado local desde 03-apply-migrations.yaml; el artefacto OCI conserva su nombre.

Uso en OCI: seleccionar el artefacto indicado, Edit → Inline, sustituir todo el contenido y guardar. No pegar el wrapper cat del bloque Bash siguiente en el campo Inline.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~yaml
# Applies the demo changelog to ATP. Command specification: Allow parameterization OFF.
version: 0.1
component: command
timeoutInSeconds: 1200
shell: bash
failImmediatelyOnError: true
env:
  variables:
    RELEASE_COMMIT: "${SOURCE_COMMIT}"
    RELEASE_VERSION: "${PACKAGE_VERSION}"
    RELEASE_SHA256: "${PACKAGE_SHA256}"
    CONNECTION_OCID: "ocid1.databasetoolsconnection.oc1.us-chicago-1.amaaaaaacj6z5kiayoiodu263eacr6dshwagahee5jvjq7hn2ohayunv2hhq"
steps:
  - type: Command
    name: Apply verified migration package to ATP
    timeoutInSeconds: 900
    command: |
      set +x
      set -euo pipefail
      umask 077
      for tool in oci sql jar base64 timeout; do command -v "$tool" >/dev/null; done
      probe_dir=$(mktemp -d /tmp/dbtools-login.XXXXXXXX)
      trap 'unset db_password; rm -rf -- "$probe_dir"' EXIT
      export OCI_CLI_AUTH=resource_principal
      export OCI_CLI_REGION=us-chicago-1
      
      echo "STEP 0: Download and verify the release package"
      [[ "$RELEASE_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]]
      [[ "$RELEASE_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]
      [[ "$RELEASE_VERSION" == "$RELEASE_COMMIT"-* ]]
      oci artifacts generic artifact download-by-path \
        --auth resource_principal --region us-chicago-1 \
        --repository-id ocid1.artifactrepository.oc1.us-chicago-1.0.amaaaaaacj6z5kiagpfcblufsym7iv4schnzbe7ja5ks47wrflm6ipvb5vca \
        --artifact-path database/migrations.tar.gz \
        --artifact-version "$RELEASE_VERSION" --file "$probe_dir/package.tar.gz"
      printf '%s  %s\n' "$RELEASE_SHA256" "$probe_dir/package.tar.gz" | sha256sum --check -
      mkdir "$probe_dir/package"
      tar -xzf "$probe_dir/package.tar.gz" -C "$probe_dir/package"
      cd "$probe_dir/package"
      grep -Fx "source_commit=$RELEASE_COMMIT" release.txt
      grep -Fx "package_version=$RELEASE_VERSION" release.txt
      sha256sum --check SHA256SUMS
      test -s db/changelog.xml
      test -s scripts/verify.sql
      echo "STEP 1: Read Database Tools connection"
      conn_field() {
        oci dbtools connection get --connection-id "$CONNECTION_OCID" \
          --auth resource_principal --region us-chicago-1 --query "$1" --raw-output
      }
      db_user=$(conn_field 'data."user-name"')
      descriptor=$(conn_field 'data."connection-string"')
      password_secret=$(conn_field 'data."user-password"."secret-id"')
      wallet_secret=$(conn_field 'data."key-stores"[0]."key-store-content"."secret-id"')
      wallet_type=$(conn_field 'data."key-stores"[0]."key-store-type"')
      [[ "$db_user" == DEVOPS_DEMO ]]
      [[ "$wallet_type" == SSO ]]
      [[ "$password_secret" == ocid1.vaultsecret.* && "$wallet_secret" == ocid1.vaultsecret.* ]]
      if ! printf '%s' "$descriptor" | grep -Eiq '\(port[[:space:]]*=[[:space:]]*1522\)'; then
        echo "Expected the validated mTLS descriptor on port 1522."
        exit 1
      fi
      
      echo "STEP 2: Retrieve password and SSO wallet without printing content"
      secret_content() {
        oci secrets secret-bundle get --secret-id "$1" --stage CURRENT \
          --auth resource_principal --region us-chicago-1 \
          --query 'data."secret-bundle-content".content' --raw-output
      }
      db_password=$(secret_content "$password_secret" | base64 --decode)
      if [[ -z "$db_password" || "$db_password" == *$'\n'* || "$db_password" == *$'\r'* || "$db_password" == *'"'* ]]; then
        echo "Password content cannot be represented safely in this login script."
        exit 1
      fi
      secret_content "$wallet_secret" | base64 --decode > "$probe_dir/cwallet.sso"
      [[ -s "$probe_dir/cwallet.sso" ]]
      # Reject a ZIP saved as the SSO secret; do not inspect or print credential contents.
      if [[ "$(head -c 2 "$probe_dir/cwallet.sso")" == PK ]]; then
        echo "The wallet secret contains a ZIP; this probe requires cwallet.sso content."
        exit 1
      fi
      printf 'devops_target = %s\n' "$descriptor" > "$probe_dir/tnsnames.ora"
      printf 'WALLET_LOCATION=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY="%s")))\nSSL_SERVER_DN_MATCH=YES\n' "$probe_dir" > "$probe_dir/sqlnet.ora"
      jar cf "$probe_dir/wallet.zip" -C "$probe_dir" cwallet.sso -C "$probe_dir" tnsnames.ora -C "$probe_dir" sqlnet.ora
      export TNS_ADMIN="$probe_dir"
      
      echo "STEP 3: Prepare protected login script"
      {
        printf '%s\n' 'set echo off' 'set verify off' 'set define off'
        printf '%s\n' 'whenever oserror exit failure' 'whenever sqlerror exit failure'
        printf 'connect DEVOPS_DEMO/"%s"@devops_target\n' "$db_password"
        printf '%s\n' "BEGIN IF USER <> 'DEVOPS_DEMO' OR SYS_CONTEXT('USERENV','CURRENT_SCHEMA') <> 'DEVOPS_DEMO' THEN RAISE_APPLICATION_ERROR(-20001,'Unexpected target schema'); END IF; END;" '/'
        printf '%s\n' 'prompt AUTHENTICATED_SQL_PHASE'
      } > "$probe_dir/login-prefix.sql"
      unset db_password
      
      run_phase() {
        local phase="$1"
        local marker="$2"
        local commands="$3"
        cat "$probe_dir/login-prefix.sql" > "$probe_dir/run.sql"
        printf '%s\n' "$commands" "prompt $marker" 'exit success' >> "$probe_dir/run.sql"
        local result=0
        timeout 360 sql -S -L -cloudconfig "$probe_dir/wallet.zip" \
          /nolog @"$probe_dir/run.sql" </dev/null > "$probe_dir/sqlcl-output.txt" 2>&1 || result=$?
        if [[ "$result" != 0 ]] ||
           grep -Eiq '(ORA|SP2|SQLCL)-[0-9]+|Exception|Validation Failed|Unexpected error|(^|[[:space:]])(ERROR|SEVERE)([[:space:]:]|$)' "$probe_dir/sqlcl-output.txt" ||
           ! grep -Eq "^[[:space:]]*$marker[[:space:]]*$" "$probe_dir/sqlcl-output.txt"; then
          echo "SQLCL_PHASE_FAILED:$phase exit_code=$result"
          echo "Error codes:"
          grep -Eo '(ORA|SP2|SQLCL)-[0-9]+' "$probe_dir/sqlcl-output.txt" | sort -u || true
          echo "SQLcl diagnostics after successful authentication (up to 160 lines):"
          awk '/^[[:space:]]*AUTHENTICATED_SQL_PHASE[[:space:]]*$/ {authenticated=1; next} authenticated && count++ < 160 {print}' "$probe_dir/sqlcl-output.txt"
          exit 1
        fi
        if [[ "$phase" == update ]]; then
          echo "SQLCL_UPDATE_OUTPUT_BEGIN"
          awk '/^[[:space:]]*AUTHENTICATED_SQL_PHASE[[:space:]]*$/ {authenticated=1; next} authenticated {print}' "$probe_dir/sqlcl-output.txt"
          echo "SQLCL_UPDATE_OUTPUT_END"
        fi
        echo "$marker"
      }
      
      echo "STEP 4: Validate changelog before applying changes"
      run_phase validate CHANGELOG_VALIDATED \
        'lb validate -changelog-file db/changelog.xml'
      
      echo "STEP 5: Apply pending changes and run package verification"
      run_phase update MIGRATION_001_VERIFIED \
        $'lb update -changelog-file db/changelog.xml -show-summary VERBOSE\n@scripts/verify.sql'
      
      printf 'DEPLOYED_COMMIT=%s\nDEPLOYED_PACKAGE=%s\n' "$RELEASE_COMMIT" "$RELEASE_VERSION"
      echo DATABASE_MIGRATION_SUCCEEDED
~~~

### 25.11. infra/dynamic-group-rules.txt

Copia consolidada para el editor de reglas. No pegar los comentarios como reglas; Rule1 y Rule2 se ingresan por separado con Match any. No es un script ni un recurso adicional.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~text
# Dominio Default / grupo existente DG-DEVOPS-SVC.
# En el editor: Match any rules defined below.
# Introducir cada ALL en un campo Rule separado; no envolver con ANY anidado.

# Rule 1
ALL {resource.type = 'devopsdeploypipeline', resource.compartment.id = 'ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa'}

# Rule 2
ALL {resource.type = 'devopsbuildpipeline', resource.compartment.id = 'ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa'}
~~~

### 25.12. infra/devops-policy.txt

Copia consolidada de la política existente. Una sentencia por línea, sin comentarios, en editor de política OCI. Incluye manage generic-artifacts y filtros de conexión/secretos. No reemplazar otras políticas ajenas.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~text
# Política consolidada del laboratorio para Default/DG-DEVOPS-SVC.
# Crear/editar en root o ancestro común a DATABASE-DEVOPS y red.
# Una sentencia por línea en el editor manual. No copiar comentarios al editor.
# manage generic-artifacts es la corrección que permitió publicar versiones nuevas.
Allow dynamic-group Default/DG-DEVOPS-SVC to manage devops-family in compartment id ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa
Allow dynamic-group Default/DG-DEVOPS-SVC to manage compute-container-instances in compartment id ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa
Allow dynamic-group Default/DG-DEVOPS-SVC to manage compute-containers in compartment id ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa
Allow dynamic-group Default/DG-DEVOPS-SVC to use vnics in compartment id ocid1.compartment.oc1..aaaaaaaa2sjgd3dlxfmlmxkowtir2vykrws75bjrg6kinussk7mo4phax7ba
Allow dynamic-group Default/DG-DEVOPS-SVC to use subnets in compartment id ocid1.compartment.oc1..aaaaaaaa2sjgd3dlxfmlmxkowtir2vykrws75bjrg6kinussk7mo4phax7ba
Allow dynamic-group Default/DG-DEVOPS-SVC to use dhcp-options in compartment id ocid1.compartment.oc1..aaaaaaaa2sjgd3dlxfmlmxkowtir2vykrws75bjrg6kinussk7mo4phax7ba
Allow dynamic-group Default/DG-DEVOPS-SVC to use network-security-groups in compartment id ocid1.compartment.oc1..aaaaaaaa2sjgd3dlxfmlmxkowtir2vykrws75bjrg6kinussk7mo4phax7ba
Allow dynamic-group Default/DG-DEVOPS-SVC to read database-tools-connections in compartment DATABASE-DEVOPS where target.resource.id = 'ocid1.databasetoolsconnection.oc1.us-chicago-1.amaaaaaacj6z5kiayoiodu263eacr6dshwagahee5jvjq7hn2ohayunv2hhq'
Allow dynamic-group Default/DG-DEVOPS-SVC to read secret-bundles in compartment DATABASE-DEVOPS where any {target.secret.id = 'ocid1.vaultsecret.oc1.us-chicago-1.amaaaaaacj6z5kiadwexzpdzyukjfbv67l6ou3xwtk63kqt6y6cco2kryzoa', target.secret.id = 'ocid1.vaultsecret.oc1.us-chicago-1.amaaaaaacj6z5kialvko46bdcpbkpxmjmf27zobxgo5o5d3xqyg4ezxxkxpq'}
Allow dynamic-group Default/DG-DEVOPS-SVC to manage generic-artifacts in compartment id ocid1.compartment.oc1..aaaaaaaaobjorjhdznidcrbfst5gwyzl4x4cjopcxkkwnst4bxm7a3kribpa
~~~

### 25.13. infra/database-user.sql

Consolidación de SQL de alta/grants efectivamente utilizados. Ejecutar en SQL Developer como ADMIN solo para alta inicial; reemplazar password localmente. No copiar este script a la etapa de migración ni al paquete de cambios.

Contenido completo para el recurso indicado; no ejecutarlo como Bash:

~~~sql
-- Ejecutar como ADMIN en DEVOPSDATABASE1, desde SQL Developer.
-- Creación inicial solamente. No volver a crear el usuario existente.
-- Sustituir el placeholder localmente; no versionar la contraseña real.
CREATE USER DEVOPS_DEMO IDENTIFIED BY "REEMPLAZAR_POR_PASSWORD_LOCAL";

-- Unión de los permisos concedidos durante la configuración exitosa.
GRANT CREATE SESSION, CREATE TABLE, CREATE PROCEDURE,
      CREATE VIEW, CREATE TRIGGER TO DEVOPS_DEMO;
ALTER USER DEVOPS_DEMO QUOTA 20M ON DATA;

SELECT USERNAME, ACCOUNT_STATUS FROM DBA_USERS WHERE USERNAME = 'DEVOPS_DEMO';
SELECT PRIVILEGE FROM DBA_SYS_PRIVS WHERE GRANTEE = 'DEVOPS_DEMO' ORDER BY PRIVILEGE;
SELECT TABLESPACE_NAME, MAX_BYTES FROM DBA_TS_QUOTAS WHERE USERNAME = 'DEVOPS_DEMO';
~~~

### 25.14. docs/automatic-deployment.md

Texto comunicado para el PR de prueba documental. Su cambio no añade un changeset. El build actual no empaqueta docs/; el trigger sin filtros de archivos puede arrancar por su merge.

Bloque completo de creación en la VM Linux, desde /home/opc/Database-DevOps. Las líneas entre EOF son el contenido íntegro:

~~~bash
mkdir -p docs
cat > docs/automatic-deployment.md <<'EOF'
# Prueba de despliegue automático

Este cambio documental verifica que un merge a main inicia
el build y el deployment automáticamente.

No incorpora nuevos cambios SQL ni modifica el changelog.
EOF
~~~


### 25.15. db/changes/002_add_estado.sql

Archivo actual preparado para la segunda prueba. Se aplica por 002-add-estado; no ejecutarlo manualmente. Éxito posterior a la corrección XML todavía no confirmado.

~~~bash
mkdir -p db/changes
cat > db/changes/002_add_estado.sql <<'EOF'
ALTER TABLE DEVOPS_CHANGE_DEMO
ADD ESTADO VARCHAR2(20) DEFAULT 'PENDIENTE' NOT NULL;
EOF
~~~

## 26. Explicación de comandos y construcciones usados en los archivos

Las explicaciones siguientes cubren los comandos Linux de los bloques operativos y de los YAML. Las variables y rutas concretas se conservan en el anexo, no se sustituyen por valores genéricos al copiar a OCI.

### 26.1. Shell, archivos y ejecución

| Comando / construcción | Qué hace y por qué se usa |
|---|---|
| cat /etc/os-release | Muestra distribución y versión; confirmó Oracle Linux 9.8 en la VM. |
| uname -m | Muestra arquitectura; confirmó x86_64. |
| pwd | Muestra directorio actual para no operar sobre otro clon. |
| cd ruta | Cambia de directorio. En SQLcl, cd es un comando distinto del cliente; el flujo utiliza cd de Bash a la raíz del paquete. |
| mkdir -p | Crea una carpeta y padres ausentes; no falla porque ya exista. |
| cat > archivo | Escribe/reemplaza el archivo; revisar que sea la ruta autorizada antes de ejecutar. |
| <<'EOF' | Heredoc literal: no expande variables ni ejecuta sustituciones de su contenido. La línea EOF final no lleva espacios. |
| command -v herramienta | Comprueba si un ejecutable está disponible en PATH. No lo instala. |
| sql -version | Consulta SQLcl del runtime; no conecta a la base. |
| set +x | Desactiva impresión de comandos expandidos, especialmente cuando se manejan credenciales. |
| set -euo pipefail | -e sale ante fallos no controlados; -u rechaza variables no definidas; pipefail propaga fallos de elementos de una tubería. No reemplaza comprobaciones explícitas en condicionales/plugins. |
| umask 077 | Nuevos archivos normalmente quedan 600 y directorios 700; restringe material de wallet/login. |
| export NOMBRE=valor | Hace disponible una variable a procesos hijos. env.exportedVariables de OCI además la publica para etapas posteriores. |
| asignación con $(comando) | Captura stdout, no imprime por sí misma el resultado. No usarla para mostrar secretos. |
| comillas dobles alrededor de variables | Mantienen espacios/caracteres como un solo argumento e impiden expansión de comodines accidentales. |
| [[ condición ]] | Condicional Bash, usado para formato SHA, usuario, tipo SSO y restricciones de password. |
| =~ expresión regular | Compara formato de commit y SHA-256; no verifica contenido criptográfico por sí solo. |
| == patrón | Permite exigir que versión empiece por el commit o que un identificador tenga un prefijo OCID esperado. |
| test -s ruta | Comprueba que el archivo existe y tiene tamaño mayor que cero. |
| if ... then ... fi | Permite fallar con mensaje explícito y detener etapas antes del DDL. |
| for ... do ... done | Comprueba en una sola iteración cada ejecutable requerido. |
| función() { ... } | Reutiliza consultas a metadata, secretos o ejecución SQLcl sin duplicar lógica. |
| local variable | Limita la variable a la función Bash, por ejemplo phase/marker/result de run_phase. |
| mktemp -d | Crea un directorio temporal único; no se fija una ruta compartida por corridas. |
| trap '...' EXIT | Ejecuta limpieza al salir de la Shell por éxito o error normal. No garantiza limpieza ante destrucción forzada de la instancia. |
| unset db_password | Retira el password de la variable Shell cuando ya se escribió al archivo protegido. No elimina el archivo, que limpia el trap. |
| rm -rf -- directorio_temporal | Borra únicamente la carpeta creada por mktemp en los scripts de OCI. -- termina opciones. No ejecutar sobre rutas calculadas ajenas. |
| printf | Escribe texto con formato controlado. %s evita tratar contenido como formato; se usa para metadata y archivos SQL/net. |
| \n en printf | Crea saltos de línea reales al generar archivos. |
| $'texto' en Bash | Sintaxis que interpreta escapes como salto de línea para concatenar comandos SQL. |
| head -c 2 archivo | Lee solo dos bytes para detectar un ZIP por su firma PK; no vuelca el wallet. |
| sort -z | Ordena nombres separados por NUL para soportar espacios en rutas. |
| sort -u | Elimina duplicados de códigos de error al mostrarlos. |
| cut -d ' ' -f 1 | Extrae el hash de la salida sha256sum del paquete. |
| grep -Fx | Busca una línea completa literal, por ejemplo source_commit=valor y package_version=valor. |
| grep -Eq / -Eiq | Expresión regular extendida, silenciosa y opcionalmente insensible a mayúsculas; detecta marcadores/errores. |
| grep -Eo | Imprime solo las coincidencias, usado para ORA/SP2/SQLCL codes. |
| awk | Muestra salida posterior al marcador autenticado. En fallo limita 160 líneas; en éxito de update muestra el resumen completo autenticado. |
| exit 1 | Señala fallo al runtime OCI y marca etapa fallida. |
| comando || variable=$? | Captura un fallo controlado y su exit code sin que set -e cierre antes del diagnóstico. |
| || true | Permite que una búsqueda sin coincidencias no sustituya el error original con otro error. No se usa para ignorar un update fallido. |
| > archivo 2>&1 | Captura stdout y stderr de SQLcl en un archivo protegido. |
| </dev/null | Cierra entrada interactiva: evita prompts de password que fallaban con JLine. |
| timeout N comando | Limita tiempo de ejecución. El exit code puede indicar timeout; la fase se considera fallida. |
| getent ahostsv4 hostname | Consulta resolución IPv4 según el resolver configurado en la subred. |
| bash -euc | Ejecuta un comando corto de Bash con -e y -u; -c recibe el texto siguiente. |
| /dev/tcp/host/port | Extensión Bash que abre conexión TCP para la prueba. No crea un archivo normal del sistema. |
| exec 3<> /dev/tcp/... | Abre descriptor 3 para lectura/escritura TCP; exec 3>&- y 3<&- lo cierran. |

La eliminación de carpetas temporales anterior ocurre dentro de Linux administrado. La limpieza de este workspace Windows se hizo mediante rutas verificadas y cmdlets nativos; esos comandos de mantenimiento local no forman parte del cliente/pipeline.

### 26.2. Git

| Comando | Explicación |
|---|---|
| git clone URL Database-DevOps | Crea un clon y remote origin. Se hace una vez por clon. |
| git -c credential.helper= ... | Override vacío para una operación: impide usar helpers. Se usó inicialmente, después se retiró de pull/push. |
| git config --local | Solo afecta al .git/config de ese clon. |
| user.name / user.email | Identidad de autor de commits, no usuario/password de autenticación. |
| core.autocrlf false | Evita conversión automática general; atributos por extensión siguen aplicándose. |
| --replace-all credential.helper '' | Restablece la lista heredada de helpers para este repo. |
| --add credential.helper 'cache --timeout=28800' | Agrega caché temporal de credenciales en memoria. |
| git remote -v | Verifica URLs fetch/push. No añadir tokens a origin. |
| git status --short --branch | Rama, relación upstream y archivos modificados/no versionados. |
| git log -3 --oneline | Tres commits más recientes en formato compacto. |
| git ls-tree -r --name-only HEAD | Lista nombres versionados del commit HEAD recursivamente. |
| git switch main | Cambia a main sin descartar cambios automáticamente. |
| git switch -c feature/nombre | Crea una rama nueva y cambia a ella. No duplicar una rama existente con -C. |
| git pull --ff-only origin main | Descarga e integra solo si main puede avanzar sin merge local. |
| git fetch origin | Descarga referencias sin cambiar el árbol de trabajo. |
| git add archivos | Selecciona qué entra al commit; evitar git add . sin revisar secretos/outputs. |
| git diff -- archivo | Cambios de trabajo respecto a staging para ese archivo. |
| git diff --check | Revisa whitespace de cambios de trabajo, no valida Oracle. |
| git diff --cached | Muestra exactamente lo que se va a confirmar. |
| git diff --cached --check | Revisa whitespace del staging. |
| git diff --cached --stat | Resumen de archivos y volumen del commit. |
| git commit -m mensaje | Crea commit local con los archivos seleccionados. |
| git push -u origin rama | Publica rama y configura upstream. |
| git push | Envía rama a upstream existente. |
| git rev-parse HEAD | Devuelve hash del commit checkout; el build lo compara con el informado por OCI. |
| git archive --format=tar COMMIT db scripts | Empaqueta esos directorios del commit, no cualquier archivo presente sin versionar. |
| git show HEAD:ruta | Consulta contenido exacto de un archivo versionado sin modificarlo. |
| git credential-cache exit | Finaliza daemon de caché del usuario y olvida credenciales en memoria. |

### 26.3. Paquetes y checksums

| Comando | Explicación |
|---|---|
| tar -xf source.tar -C carpeta | Extrae el archive Git para preparar el paquete. |
| tar -czf destino.tar.gz . | Crea archivo tar comprimido con gzip desde el directorio actual. |
| tar -tzf paquete.tar.gz | Lista miembros sin extraerlos. |
| tar -xzf paquete.tar.gz -C carpeta | Extrae un paquete verificado en carpeta temporal. |
| tar -xOf paquete.tar.gz ./release.txt | Extrae ese miembro a stdout, redirigido a metadata temporal. |
| find db scripts -type l -print -quit | Detecta un primer symlink y hace que el build rechace ese contenido. |
| find db scripts -type f -print0 | Lista archivos normales separados por NUL. |
| xargs -0 sha256sum | Calcula hashes de esos nombres sin romper espacios. |
| sha256sum archivo | Hash SHA-256 del contenido exacto. |
| sha256sum --check SHA256SUMS | Valida todos los hashes del manifiesto. |
| printf hash/ruta seguido de sha256sum --check - | Compara el paquete descargado con PACKAGE_SHA256 recibido desde el build. |
| release.txt | Vincula commit, build run y versión dentro del paquete. |
| SHA256SUMS | Manifiesto interno de todos los archivos versionados db/scripts y release.txt. |

El paquete solo se extrae para aplicación después de comprobar SHA-256 externo. El build rechaza symlinks. Son controles de este flujo entre repositorio/artefactos autorizados, no instrucciones para extraer tar arbitrarios de remitentes desconocidos.

### 26.4. OCI CLI y wallet

| Comando / campo | Explicación |
|---|---|
| oci dbtools connection get --connection-id ... | Recupera la conexión Database Tools existente. |
| --query | Filtra campos mediante JMESPath para obtener un valor específico; claves con guion requieren comillas dentro de la expresión. |
| --raw-output | Devuelve el valor de texto sin envoltura JSON. No usarlo para imprimir un secret en consola. |
| --auth resource_principal | Autentica OCI CLI con la identidad del pipeline habilitada en IAM. |
| --region us-chicago-1 | Fija la región de los recursos de esta prueba. |
| data."user-name" | Usuario Oracle esperado. |
| data."connection-string" | Descriptor de conexión validado, no una conexión al servicio Database Tools. |
| data."user-password"."secret-id" | Referencia al secreto de contraseña. |
| data."key-stores"[0]."key-store-content"."secret-id" | Referencia al secreto de contenido wallet. Se presupone un único wallet SSO relevante. |
| data."key-stores"[0]."key-store-type" | Debe ser SSO en este flujo. |
| oci secrets secret-bundle get --secret-id ... --stage CURRENT | Obtiene la versión CURRENT del secreto. |
| base64 --decode | Convierte content base64 de Secret Bundle al password/bytes SSO reales. |
| oci artifacts generic artifact download-by-path | Descarga por repository-id + artifact-path + artifact-version. --file fija el archivo temporal de salida. |
| jar cf wallet.zip ... | Usa la herramienta Java del runtime para crear ZIP con cwallet.sso, tnsnames.ora y sqlnet.ora. No instala Java en la VM. |
| tnsnames.ora | Asocia devops_target con el descriptor ATP. |
| sqlnet.ora | Define ubicación del wallet y validación DN. |
| TNS_ADMIN | Directorio temporal de configuración Oracle Net para esa ejecución. |
| sql -S -L -cloudconfig wallet.zip /nolog @run.sql | SQLcl silencioso, intento de login limitado, configuración wallet y ejecución del archivo sin login interactivo inicial. |
| OCI_CLI_AUTH y OCI_CLI_REGION | Variables de OCI CLI del runtime; los comandos también pasan opciones explícitas. |

### 26.5. SQL, SQLcl y Liquibase

| Instrucción | Explicación |
|---|---|
| CREATE USER | Alta inicial de DEVOPS_DEMO; no forma parte de changeset de aplicación. |
| GRANT CREATE ... | Habilita tipos de objetos en el esquema; IAM no reemplaza estos permisos. |
| ALTER USER ... QUOTA | Limita espacio asignable en DATA. |
| SELECT USER / SYS_CONTEXT | Verifica la identidad y esquema reales. |
| SET ECHO OFF / VERIFY OFF | Evita eco del script y de sustituciones SQLcl. |
| SET DEFINE OFF | Desactiva sustitución & en SQLcl durante login y ejecución; no afecta variables Bash/OCI. |
| SET SERVEROUTPUT ON | Permite visualizar DBMS_OUTPUT de verify.sql. |
| WHENEVER OSERROR EXIT FAILURE | Termina por errores de sistema que reconoce SQLcl. |
| WHENEVER SQLERROR EXIT FAILURE | Termina por SQL error; se complementa con el wrapper de proceso y salida. |
| CONNECT DEVOPS_DEMO/...@devops_target | Autenticación Oracle en archivo temporal protegido. |
| BEGIN ... END; / | Bloque PL/SQL y línea / para ejecutar el bloque en el cliente. |
| RAISE_APPLICATION_ERROR | Falla explícitamente la verificación con ORA-20001/2/3 según condición. |
| @scripts/verify.sql | Ejecuta script relativo al directorio del paquete. |
| lb validate -changelog-file | Comprueba changelog, referencias y condiciones/checksums que detecta Liquibase. No garantiza que el usuario tenga todos los permisos de cada DDL. |
| lb update -changelog-file | Aplica changesets pendientes y mantiene tablas de control. |
| -show-summary VERBOSE | Pide resumen detallado de lo ejecutado/ya aplicado/filtrado. |
| prompt MARCADOR | Imprime una línea del cliente; no prueba por sí sola ejecución de DDL. |
| exit success | Termina el cliente con estado de éxito cuando se alcanzó el final. |
| DATABASECHANGELOG | Registro del estado de changesets aplicados; no ledger inmutable de cada intento/rollback. |
| DATABASECHANGELOGLOCK | Control de exclusión de operaciones Liquibase. No manipular sin diagnóstico. |
| DATABASECHANGELOG_ACTIONS / trigger / vista | Objetos auxiliares de la integración Oracle para acciones/detalles; requieren permisos adicionales. |

## 27. Mantenimiento de copias, referencias y verificación de equivalencia

### 27.1. Mapa exacto de archivo a recurso

| Archivo local | Recurso / campo destino | Parametrización |
|---|---|---|
| build_spec.yaml | Git main, raíz → Managed Build build spec path | Variables del runtime/exportedVariables |
| pipelines/01-network-probe.yaml | database-network-probe → Inline Value | NONE |
| pipelines/02-dbtools-login.yaml | database-dbtools-login → Inline Value | NONE |
| pipelines/03-verify-package.yaml | verify-migration-package-spec → Inline Value | NONE |
| pipelines/04-apply-migrations.yaml | apply-database-migrations-spec → Inline Value | NONE |
| infra/dynamic-group-rules.txt | Default/DG-DEVOPS-SVC → Rule 1 / Rule 2 | Match any |
| infra/devops-policy.txt | Política IAM existente → manual statements | No aplica |
| infra/database-user.sql | Worksheet SQL Developer ADMIN → ATP | Password sustituido localmente |
| db/changelog.xml + db/changes/* + scripts/verify.sql | Git → build archive → paquete → SQLcl | Mismo commit verificado |

El tar.gz se identifica mediante el General artifact database-migration-package, path database/migrations.tar.gz, versión PACKAGE_VERSION, parametrización SI. No confundir esa referencia con los cinco artefactos de instrucciones/paquete en el menú DevOps.

### 27.2. Comparación del clon Linux con las fuentes conservadas

Sin editar nada, en la VM:

~~~bash
cd /home/opc/Database-DevOps
git status --short --branch
git remote -v
git log -5 --oneline
git ls-tree -r --name-only HEAD

git show HEAD:build_spec.yaml
git show HEAD:db/changelog.xml
git show HEAD:db/changes/001_create_devops_demo.sql
git show HEAD:scripts/verify.sql
git show HEAD:.gitattributes
git show HEAD:.gitignore
~~~

Comparar esos contenidos con el anexo. No asumir que el workspace Windows está sincronizado con main; aquí no se hizo fetch/pull al repositorio de OCI y el .git local no tiene commits.

En consola abrir cada artefacto Inline → Edit y comparar YAML completo. Copiar cambios locales a la consola solo si se desea modificar su ejecución; no hace falta recrear el artefacto. Para la versión final de apply el resumen VERBOSE ya quedó confirmado por los logs.

### 27.3. Comprobaciones locales realizadas al consolidar

- Reconstrucción de archivos de migración desde los bloques del historial enviados a la VM.
- Conservación de un único build_spec.yaml final en raíz.
- Comprobación de XML y referencias sqlFile.
- Comprobación de sintaxis Bash de los comandos incrustados en los YAML.
- Prueba aislada del build con un repo temporal: más de un SQL versionado entra en el paquete; uno sin versionar no entra; hashes se verifican.
- Prueba local de control de salida SQLcl simulada: éxito, ORA y error de Liquibase, marcador faltante; exclusión del preámbulo de conexión.
- Comparación automática de los bloques de contenido del documento con sus archivos, para evitar truncamientos.
- Revisión de inventario y referencias, sin archivos Python/instaladores descartados dentro del workspace.

Estas pruebas locales no ejecutan otra vez OCI ni ATP y no sustituyen los resultados reales registrados en §18. No se descargó un wallet ni un secreto en esta consolidación.

### 27.4. README conservado

El README es solo un índice. Su contenido completo es el siguiente:

~~~markdown
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
~~~

## 28. Segunda prueba: columna ESTADO y corrección de XML

Actualización del 3 de noviembre de 2026. Esta sección sustituye las instrucciones anteriores de añadir PL/SQL por cada cambio.

### 28.1. Estado y cambios locales

- El changeset 001 y su repetición sin reaplicación sí tienen logs exitosos.
- Se preparó 002-add-estado para agregar ESTADO a DEVOPS_CHANGE_DEMO.
- El 2 de noviembre el usuario aportó un fallo del parser XML: faltaba cerrar un changeSet.
- Se entregó el changelog completo con 001 y 002 como hermanos, ambos cerrados.
- No se aportó éxito posterior. La corrección está preparada y validada localmente, no confirmada como aplicada en ATP.
- No se cambió scripts/verify.sql para 002. Su verificación original de 001 sigue ejecutándose como comprobación de la demostración; no prueba por sí sola la columna ESTADO.
- El marcador MIGRATION_001_VERIFIED del wrapper sigue presente porque no se modificó el artefacto. No interpretarlo como una prueba de 002; revisar el resumen Liquibase y DATABASECHANGELOG.
- No se preparó ni se publicó un segundo pipeline.

Archivo nuevo, contenido completo:

~~~bash
mkdir -p db/changes
cat > db/changes/002_add_estado.sql <<'EOF'
ALTER TABLE DEVOPS_CHANGE_DEMO
ADD ESTADO VARCHAR2(20) DEFAULT 'PENDIENTE' NOT NULL;
EOF
~~~

El changelog completo y corregido está en el anexo 25.3 y en db/changelog.xml. Su segundo changeset referencia ese SQL y declara como rollback DROP COLUMN ESTADO, que eliminaría los valores de esa columna. No se ejecuta rollback en esta prueba.

### 28.2. VS Code conectado a la VM

1. En la ventana remota, File → Open Folder → /home/opc/Database-DevOps.
2. Abrir Terminal → New Terminal.
3. Ejecutar:

~~~bash
cd /home/opc/Database-DevOps
git rev-parse --show-toplevel
git status --short --branch
git branch --show-current
~~~

La raíz devuelta debe ser el clon abierto. El Explorer muestra archivos, no un selector de rama. La rama se ve en la barra inferior o con git branch --show-current. Crear/editar desde Explorer modifica el mismo árbol de trabajo; no se registra en la rama hasta commit. Archivos modificados/no versionados pueden acompañar un switch y no son exclusivos de una rama.

Ctrl+Shift+G abre Source Control; ahí se revisan Changes/Staged Changes. No se necesita otra versión de VS Code.

### 28.3. Inicio nuevo de la prueba (si 002 todavía no está en main)

Esta ruta es histórica para preparar el cambio desde cero; no repetirla sobre el main que ya contiene 002. Si el estado tiene cambios sin commit, conservarlos y revisarlos antes de cambiar de rama. Con main limpio:

~~~bash
git switch main
git pull --ff-only origin main
git switch -c feature/add-estado-column
git branch --show-current
~~~

Crear el SQL 002 y añadir su changeSet después del cierre de 001 y antes de databaseChangeLog final. Puede usarse el archivo completo del anexo 25.3 para evitar un cierre faltante. No modificar id/author/ruta/SQL del changeset aplicado 001. Guardar con File → Save All.

No añadir una verificación PL/SQL de 002 a scripts/verify.sql. Si se pegó el bloque propuesto y luego descartado, retirar solo ese bloque de 002, no la comprobación original de 001; revisar el diff para comprobar que el archivo vuelve al contenido anterior.

Comprobar estructura antes del commit:

~~~bash
xmllint --nonet --noout db/changelog.xml
echo $?
git status --short --branch
~~~

Si la primera comprobación falla o el código no es 0, no continuar.

Staging obligatorio:

~~~bash
git add db/changelog.xml db/changes/002_add_estado.sql
git status --short --branch
git diff --cached --check
git diff --cached --stat
git diff --cached
~~~

Esperado:

~~~text
## feature/add-estado-column
M  db/changelog.xml
A  db/changes/002_add_estado.sql
~~~

El error observado "no changes added to commit" significó que faltaba git add. No existe autocommit activado por una versión nueva de Git. Un M en segunda posición indica cambio no preparado; un A en primera posición, archivo preparado para agregar.

Continuar solamente tras revisar los dos archivos:

~~~bash
git commit -m "Add ESTADO column through changeset 002"
git push -u origin feature/add-estado-column
~~~

Si commit falla, no continuar con push como si el cambio estuviera registrado. No usar commit -a como sustituto de git add: no añade por sí solo un archivo nuevo sin seguimiento.

Crear PR en OCI:
- Source feature/add-estado-column.
- Destination main.
- Título Agrega columna ESTADO a DEVOPS_CHANGE_DEMO.
- Revisar Differences: solo dos archivos para este cambio.
- Merge con la cuenta disponible; aprobación independiente pendiente.
- No iniciar manualmente el build; comprobar la ejecución del trigger.

### 28.4. Corrección cuando 002 ya se publicó y el XML falló

El log del 2 de noviembre, 18:09 UTC, mostró:

~~~text
The element type "changeSet" must be terminated by the matching end-tag "</changeSet>".
All stages complete. 3 were successful and 1 failed
~~~

Es un error de XML publicado. No requiere cambiar IAM, grants, wallet, build ni artefactos. No demuestra aplicación de 002. Consultar el estado si se necesita certificar lo que hay actualmente en ATP.

Con árbol limpio, crear corrección sobre el main publicado:

~~~bash
cd /home/opc/Database-DevOps
git status --short --branch
git switch main
git pull --ff-only origin main
git switch -c fix/changelog-002-xml
~~~

En VS Code reemplazar db/changelog.xml por el contenido completo correcto del anexo 25.3. Guardar. No volver a crear la rama original ni recrear tablas.

~~~bash
ls -l db/changes/001_create_devops_demo.sql db/changes/002_add_estado.sql
cat db/changes/002_add_estado.sql
xmllint --nonet --noout db/changelog.xml
echo $?
~~~

Solo tras validación exitosa:

~~~bash
git add db/changelog.xml
git diff --cached --check
git diff --cached
git status --short --branch
git commit -m "Fix XML structure for changeset 002"
git push -u origin fix/changelog-002-xml
~~~

Crear PR fix/changelog-002-xml → main, título Corrige estructura XML del changelog 002, revisar y merge. Debe iniciarse build/deployment automáticamente si el trigger sigue configurado. Conservar evidencias del origen de ejecución.

La comprobación xmllint es local y manual en esta fase. **No se añadió validación XML temprana al build administrado**: su runtime/herramienta tendría que comprobarse antes de introducir una dependencia. No afirmar que el fallo XML ahora se detecta automáticamente en el build.

### 28.5. Resultado esperado y consultas

Si 001 está aplicado y 002 pendiente, una aplicación correcta debería mostrar:

~~~text
UPDATE SUMMARY
Run:                          1
Previously run:               1
Filtered out:                 0
Total change sets:            2
DATABASE_MIGRATION_SUCCEEDED
~~~

Ese es un resultado esperado, no un log recibido.

En SQL Developer como DEVOPS_DEMO, antes de la prueba o después de una falla:

~~~sql
SELECT column_name
FROM user_tab_columns
WHERE table_name = 'DEVOPS_CHANGE_DEMO'
  AND column_name = 'ESTADO';

SELECT id, author, dateexecuted, exectype
FROM databasechangelog
WHERE id = '002-add-estado'
  AND author = 'database-devops';
~~~

Si antes de aplicar aparecen columna o registro, revisar el estado antes de continuar; no eliminar automáticamente para "hacer pasar" el pipeline.

Después del éxito:

~~~sql
SELECT column_name, data_type, char_length, nullable, data_default
FROM user_tab_columns
WHERE table_name = 'DEVOPS_CHANGE_DEMO'
  AND column_name = 'ESTADO';

SELECT id, author, filename, dateexecuted, orderexecuted, exectype
FROM databasechangelog
WHERE id IN ('001-create-devops-demo', '002-add-estado')
ORDER BY dateexecuted, orderexecuted;
~~~

Esperado: ESTADO VARCHAR2 de longitud 20, NOT NULL y default PENDIENTE; dos registros EXECUTED. Estas consultas de demostración no se añaden como código PL/SQL obligatorio del cliente.

Tras confirmar éxito, actualizar el clon:

~~~bash
git switch main
git pull --ff-only origin main
git status --short --branch
~~~

### 28.6. Esfuerzo por cambio y decisiones conservadas

Una rama por solicitud/cambio lógico, no por archivo ni por cada edición. La rama puede contener varios SQL/commits relacionados. El ejemplo 002 usa solo SQL y XML. No requiere políticas, pipelines, conexiones nuevas ni hashes introducidos manualmente. Las pruebas funcionales adicionales se deciden según riesgo, no se impone un bloque PL/SQL por cada DDL.

La sustitución de verify.sql por un reporte genérico se explicó como mejora para la entrega al cliente, pero **no se implementó**; se conserva la versión realmente utilizada. Tampoco se activaron runOnChange, múltiples changelogs, rollback automático ni dashboard.

## 29. Alcance de la actualización local del 3 de noviembre de 2026

- Añadido db/changes/002_add_estado.sql.
- Actualizado db/changelog.xml con la última corrección completa suministrada.
- Actualizados README y los contenidos embebidos de esta guía.
- Corregidas las rutas operativas del clon según la captura posterior de VS Code.
- Añadida preparación desde cero de paquetes, separada de los pasos históricamente ejecutados y de Java opcional.
- Conservados sin cambios build_spec.yaml, scripts/verify.sql y los cuatro Command specification.
- No se añadió Python ni un instalador; no se generaron ejemplos sin uso dentro del workspace.
- XML bien formado, dos changesets hermanos, IDs únicos y referencias SQL locales comprobados.
- La sintaxis Bash de los YAML se verifica localmente; no se ejecuta la base.
- Sin fetch/pull de la VM o tenancy: las fuentes son la conversación y las copias locales. No se afirma equivalencia byte por byte con los Inline actuales ni el main remoto.
- No se ejecutaron commit, push, merge, deployment ni DDL desde este workspace.
- No se recibió evidencia de éxito posterior al fallo XML de la prueba 002.

El respaldo previo a esta actualización se dejó fuera del workspace, en TEMP, como Database-DevOps-before-update-20261103-080721.zip. No es un artefacto del pipeline ni debe publicarse.
