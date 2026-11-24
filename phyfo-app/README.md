# PHY-FO · aplicación web básica (fase 7)

Aplicación local para la compraventa de videojuegos físicos. Interfaz en HTML, CSS y JavaScript
sin bibliotecas externas; servidor Node.js con Express; acceso a SQL Server con `mssql`; configuración con `dotenv`.

## Requisitos
- Node.js 18 o superior
- Base de datos `phyfo` creada con `PHY-FO_SQLServer_3FN_v4.sql`
- Cuentas y roles creados con la **parte 1** de `PHY-FO_Seguridad_Monitoreo.sql`
- SQL Server con **autenticación mixta** y **TCP/IP habilitado** (ver pasos en el chat)

## Ejecución
1. `npm install`
2. Copie `.env.example` como `.env` y revise los valores.
3. `npm start`
4. Abra http://localhost:3000

## Cuentas de prueba de la aplicación
Cualquier usuario del script de datos. Por ejemplo: `monica.reyes@example.com` / `Phyfo#1001` (administrador, según `ADMIN_CORREOS`).

## Estructura
- `server.js`: API y conexión a la base de datos (una conexión por rol: público, aplicación y administrador).
- `public/`: interfaz (`index.html`, `styles.css`, `app.js`) y carpeta `uploads/` donde se guardan las fotografías.
