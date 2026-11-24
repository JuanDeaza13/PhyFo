-- ============================================================
-- PHY-FO | Fases 5 y 6: seguridad (roles, usuarios y pruebas) y monitoreo
-- Gestor: Microsoft SQL Server 2025 Express - SQL Server Management Studio
-- Requisito: haber ejecutado antes el script de implementación (base phyfo
-- creada y con datos de prueba). Ejecutar con una cuenta sysadmin.
--
--   Parte 1. Inicios de sesión, usuarios, roles y permisos
--   Parte 2. Pruebas de integridad (reglas violadas, P01 a P26)
--   Parte 3. Pruebas de contraseñas y de acceso por rol
--   Parte 4. Monitoreo (indicadores de la instancia)
--
-- Nota: los rechazos consumen valores IDENTITY, por lo que pueden quedar
-- saltos en los ID; es normal. Para volver al estado inicial, ejecute de
-- nuevo el script de implementación.
-- ============================================================

-- ------------------------------------------------------------
-- PARTE 1. CUENTAS, ROLES Y PERMISOS (mínimo privilegio)
-- ------------------------------------------------------------
-- Las contraseñas de estas cuentas son de EJEMPLO: cámbielas por claves propias
-- antes de ejecutar (deben cumplir la política de contraseñas de SQL Server).
-- Son de prueba para el entorno local;
-- en producción se guardarían fuera del script.

USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'phyfo_admin')
    CREATE LOGIN phyfo_admin   WITH PASSWORD = N'CAMBIAR_Admin#2026', CHECK_POLICY = ON, DEFAULT_DATABASE = phyfo;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'phyfo_app')
    CREATE LOGIN phyfo_app     WITH PASSWORD = N'CAMBIAR_App#2026x', CHECK_POLICY = ON, DEFAULT_DATABASE = phyfo;
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'phyfo_publico')
    CREATE LOGIN phyfo_publico WITH PASSWORD = N'CAMBIAR_Publico#2026x', CHECK_POLICY = ON, DEFAULT_DATABASE = phyfo;
GO

USE phyfo;
GO
CREATE USER u_admin   FOR LOGIN phyfo_admin;
CREATE USER u_app     FOR LOGIN phyfo_app;
CREATE USER u_publico FOR LOGIN phyfo_publico;

CREATE ROLE rol_administrador;
CREATE ROLE rol_aplicacion;
CREATE ROLE rol_consulta_publica;

ALTER ROLE rol_administrador     ADD MEMBER u_admin;
ALTER ROLE rol_aplicacion        ADD MEMBER u_app;
ALTER ROLE rol_consulta_publica  ADD MEMBER u_publico;
GO

-- Administrador: consulta y mantiene los datos; no modifica la estructura ni
-- lee la sal y el hash de las contraseñas.
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::dbo TO rol_administrador;
DENY  SELECT ON dbo.Usuario (sal, contrasena) TO rol_administrador;
DENY  CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION TO rol_administrador;
DENY  ALTER ON SCHEMA::dbo TO rol_administrador;

-- Aplicación: lee datos, ejecuta los procedimientos y solo escribe directamente
-- en las tablas que no tienen un procedimiento propio. Usuario, Publicacion,
-- Transaccion y Envio se modifican únicamente mediante los procedimientos
-- (que acceden a las tablas por encadenamiento de propiedad).
GRANT SELECT ON SCHEMA::dbo TO rol_aplicacion;
DENY  SELECT ON dbo.Usuario (sal, contrasena) TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_registrar_usuario  TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_validar_login      TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_publicar_ejemplar  TO rol_aplicacion;
GRANT EXECUTE ON dbo.sp_registrar_venta    TO rol_aplicacion;
GRANT INSERT, UPDATE ON dbo.Inventario            TO rol_aplicacion;
GRANT INSERT, UPDATE ON dbo.Direccion             TO rol_aplicacion;
GRANT INSERT, UPDATE ON dbo.Resena                TO rol_aplicacion;
GRANT INSERT, UPDATE ON dbo.FotografiaPublicacion TO rol_aplicacion;
DENY  INSERT, UPDATE, DELETE ON dbo.Usuario       TO rol_aplicacion;
DENY  INSERT, UPDATE, DELETE ON dbo.Publicacion   TO rol_aplicacion;
DENY  INSERT, UPDATE, DELETE ON dbo.Transaccion   TO rol_aplicacion;
DENY  INSERT, UPDATE, DELETE ON dbo.Envio         TO rol_aplicacion;
DENY  CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION TO rol_aplicacion;
DENY  ALTER ON SCHEMA::dbo TO rol_aplicacion;

-- Consulta pública: solo la vista del catálogo.
GRANT SELECT ON dbo.vw_catalogo_publicaciones TO rol_consulta_publica;
GO

-- ------------------------------------------------------------
-- PARTE 2. PRUEBAS DE INTEGRIDAD (reglas violadas)
-- Cada prueba se ejecuta en una transacción que se revierte, registra el
-- error devuelto por el motor y lo compara con el esperado.
-- 547 = CHECK o FOREIGN KEY, 2627 = UNIQUE, 50xxx = triggers y procedimientos.
-- ------------------------------------------------------------
DECLARE @r TABLE (Prueba NVARCHAR(5), Regla NVARCHAR(90), Esperado INT, Obtenido INT NULL, Mensaje NVARCHAR(300) NULL);
DECLARE @p INT;

-- P01 correo repetido
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Usuario (nombre, correo, sal, contrasena)
    VALUES (N'Prueba', N'monica.reyes@example.com', REPLICATE('a', 32), REPLICATE('b', 64));
    INSERT INTO @r VALUES (N'P01', N'Correo repetido', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P01', N'Correo repetido', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P02 correo con formato inválido
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Usuario (nombre, correo, sal, contrasena)
    VALUES (N'Prueba', N'correo-sin-arroba', REPLICATE('a', 32), REPLICATE('b', 64));
    INSERT INTO @r VALUES (N'P02', N'Correo con formato inválido', 547, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P02', N'Correo con formato inválido', 547, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P03 videojuego repetido (mismo título y año)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Videojuego (Titulo, ID_desarrollador, ID_genero, ID_clasificacion, Anio_lanzamiento)
    SELECT TOP (1) Titulo, ID_desarrollador, ID_genero, ID_clasificacion, Anio_lanzamiento FROM dbo.Videojuego;
    INSERT INTO @r VALUES (N'P03', N'Videojuego repetido (título y año)', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P03', N'Videojuego repetido (título y año)', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P04 edición repetida (mismo videojuego, plataforma y tipo)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Edicion (ID_videojuego, ID_plataforma, ID_tipo_edicion)
    SELECT TOP (1) ID_videojuego, ID_plataforma, ID_tipo_edicion FROM dbo.Edicion;
    INSERT INTO @r VALUES (N'P04', N'Edición repetida', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P04', N'Edición repetida', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P05 precio final mayor al publicado
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Transaccion (ID_publicacion, ID_comprador, precio_final)
    SELECT p.ID_publicacion, 1, p.Precio + 1 FROM dbo.Publicacion p WHERE p.ID_publicacion = 3;
    INSERT INTO @r VALUES (N'P05', N'Precio final mayor al publicado', 50010, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P05', N'Precio final mayor al publicado', 50010, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P06 comprar la propia publicación
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Transaccion (ID_publicacion, ID_comprador, precio_final)
    SELECT p.ID_publicacion, i.ID_usuario, p.Precio
    FROM dbo.Publicacion p JOIN dbo.Inventario i ON i.ID_inventario = p.ID_inventario
    WHERE p.ID_publicacion = 3;
    INSERT INTO @r VALUES (N'P06', N'Comprar la propia publicación', 50011, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P06', N'Comprar la propia publicación', 50011, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P07 vender dos veces la misma publicación
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Transaccion (ID_publicacion, ID_comprador, precio_final) VALUES (1, 1, 1000);
    INSERT INTO @r VALUES (N'P07', N'Vender dos veces una publicación', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P07', N'Vender dos veces una publicación', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P08 ejemplar con estado de disco inválido
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Inventario (ID_edicion, ID_usuario, Estado_fisico) VALUES (1, 1, N'Roto');
    INSERT INTO @r VALUES (N'P08', N'Ejemplar con estado inválido', 547, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P08', N'Ejemplar con estado inválido', 547, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P09 publicar dos veces el mismo ejemplar
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_publicar_ejemplar 1, 100000, N'/uploads/prueba/a.jpg';
    INSERT INTO @r VALUES (N'P09', N'Publicar dos veces el mismo ejemplar', 50054, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P09', N'Publicar dos veces el mismo ejemplar', 50054, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P10 publicación con precio cero
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Publicacion (ID_inventario, Precio) VALUES (53, 0);
    INSERT INTO @r VALUES (N'P10', N'Publicación con precio cero', 547, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P10', N'Publicación con precio cero', 547, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P11 publicar sin fotografías
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_publicar_ejemplar 53, 100000, N'';
    INSERT INTO @r VALUES (N'P11', N'Publicar sin fotografías', 50051, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P11', N'Publicar sin fotografías', 50051, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P12 vender una publicación sin fotografías
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Publicacion (ID_inventario, Precio) VALUES (53, 100000);
    SET @p = SCOPE_IDENTITY();
    INSERT INTO dbo.Transaccion (ID_publicacion, ID_comprador, precio_final) VALUES (@p, 1, 90000);
    INSERT INTO @r VALUES (N'P12', N'Vender una publicación sin fotografías', 50013, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P12', N'Vender una publicación sin fotografías', 50013, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P13 borrar la última fotografía de una publicación
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM dbo.FotografiaPublicacion WHERE ID_publicacion = 3;
    INSERT INTO @r VALUES (N'P13', N'Borrar la última fotografía', 50050, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P13', N'Borrar la última fotografía', 50050, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P14 registrar un envío para una venta en persona
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Envio (ID_transaccion, ID_direccion, ID_transportadora, Numero_guia)
    SELECT TOP (1) t.ID_transaccion, d.ID_direccion, 1, N'PRUEBA0001'
    FROM dbo.Transaccion t JOIN dbo.Direccion d ON d.ID_usuario = t.ID_comprador
    WHERE t.Forma_entrega = N'En persona';
    INSERT INTO @r VALUES (N'P14', N'Envío para una venta en persona', 50021, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P14', N'Envío para una venta en persona', 50021, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P15 envío con una dirección que no es del comprador
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_registrar_venta 3, 1, 1000, 2, 1, N'PRUEBA0002';
    INSERT INTO @r VALUES (N'P15', N'Envío con dirección de otro usuario', 50020, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P15', N'Envío con dirección de otro usuario', 50020, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P16 reseña de un usuario que no compró la publicación
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Resena (ID_publicacion, ID_usuario, Calificacion, Comentario) VALUES (1, 2, 5, N'Prueba');
    INSERT INTO @r VALUES (N'P16', N'Reseña de quien no compró', 50040, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P16', N'Reseña de quien no compró', 50040, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P17 calificación fuera de rango (6)
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Resena (ID_publicacion, ID_usuario, Calificacion, Comentario) VALUES (22, 5, 6, N'Prueba');
    INSERT INTO @r VALUES (N'P17', N'Calificación fuera de 1 a 5', 547, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P17', N'Calificación fuera de 1 a 5', 547, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P18 contraseña de menos de 8 caracteres
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_registrar_usuario N'Prueba', N'prueba@example.com', N'corta';
    INSERT INTO @r VALUES (N'P18', N'Contraseña de menos de 8 caracteres', 50060, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P18', N'Contraseña de menos de 8 caracteres', 50060, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P19 guía de envío repetida
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Envio (ID_transaccion, ID_direccion, ID_transportadora, Numero_guia)
    SELECT TOP (1) t.ID_transaccion, d.ID_direccion, 1, N'PF202600001'
    FROM dbo.Transaccion t JOIN dbo.Direccion d ON d.ID_usuario = t.ID_comprador
    WHERE t.Forma_entrega = N'En persona';
    INSERT INTO @r VALUES (N'P19', N'Guía de envío repetida', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P19', N'Guía de envío repetida', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P20 reseñar dos veces la misma publicación
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Resena (ID_publicacion, ID_usuario, Calificacion, Comentario) VALUES (1, 19, 4, N'Prueba');
    INSERT INTO @r VALUES (N'P20', N'Reseñar dos veces una publicación', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P20', N'Reseñar dos veces una publicación', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P21 Publicar con 11 fotografías
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_publicar_ejemplar 53, 100000, N'/f/1.jpg|/f/2.jpg|/f/3.jpg|/f/4.jpg|/f/5.jpg|/f/6.jpg|/f/7.jpg|/f/8.jpg|/f/9.jpg|/f/10.jpg|/f/11.jpg';
    INSERT INTO @r VALUES (N'P21', N'Publicar con 11 fotografías', 50052, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P21', N'Publicar con 11 fotografías', 50052, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P22 Venta de una publicación inexistente
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_registrar_venta 999999, 1, 1000, NULL, NULL, NULL, N'En persona';
    INSERT INTO @r VALUES (N'P22', N'Venta de una publicación inexistente', 50030, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P22', N'Venta de una publicación inexistente', 50030, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P23 Transportadora sin dirección, empresa ni guía
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_registrar_venta 3, 1, 1000, NULL, NULL, NULL, N'Transportadora';
    INSERT INTO @r VALUES (N'P23', N'Transportadora sin dirección, empresa ni guía', 50031, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P23', N'Transportadora sin dirección, empresa ni guía', 50031, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P24 Venta en persona con datos de envío
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_registrar_venta 3, 1, 1000, 1, 1, N'PRUEBA0003', N'En persona';
    INSERT INTO @r VALUES (N'P24', N'Venta en persona con datos de envío', 50032, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P24', N'Venta en persona con datos de envío', 50032, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

-- P25 compra fallida (guía repetida): el error aparece al registrar el envío,
--     después de insertar la transacción; la compra debe revertirse por completo.
BEGIN TRY
    BEGIN TRANSACTION;
    EXEC dbo.sp_registrar_venta 3, 1, 1000, 1, 1, N'PF202600001';
    INSERT INTO @r VALUES (N'P25', N'Compra fallida (guía repetida)', 2627, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P25', N'Compra fallida (guía repetida)', 2627, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;
-- P25 (comprobación) no debe quedar ninguna transacción de la publicación 3
INSERT INTO @r
SELECT N'P25', N'Reversión completa (transacciones de la publicación 3)', 0, COUNT(*), N'Filas encontradas'
FROM dbo.Transaccion WHERE ID_publicacion = 3;

-- P26 Dirección con el detalle vacío
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Direccion (ID_usuario, ID_ciudad, Direccion_detalle) VALUES (1, 1, N'   ');
    INSERT INTO @r VALUES (N'P26', N'Dirección con el detalle vacío', 547, NULL, N'NO RECHAZADO');
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @r VALUES (N'P26', N'Dirección con el detalle vacío', 547, ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

SELECT Prueba, Regla, Esperado, Obtenido,
       CASE WHEN Esperado = Obtenido THEN N'OK' ELSE N'FALLA' END AS Resultado,
       LEFT(Mensaje, 70) AS Mensaje
FROM @r
ORDER BY Prueba;
GO

-- ------------------------------------------------------------
-- PARTE 3. CONTRASEÑAS Y ACCESO POR ROL
-- ------------------------------------------------------------
-- 3.1 La contraseña no se guarda en texto plano: sal de 32 y hash de 64
--     caracteres hexadecimales.
SELECT TOP (3) ID_usuario, correo, LEFT(sal, 8) + N'...' AS sal,
       LEFT(contrasena, 16) + N'...' AS hash, LEN(contrasena) AS longitud_hash
FROM dbo.Usuario
ORDER BY ID_usuario;

-- 3.2 Dos usuarios con la MISMA contraseña tienen sal y hash distintos
--     (la prueba se revierte y no deja datos).
BEGIN TRANSACTION;
EXEC dbo.sp_registrar_usuario N'Prueba A', N'prueba.a@example.com', N'Clave#segura1';
EXEC dbo.sp_registrar_usuario N'Prueba B', N'prueba.b@example.com', N'Clave#segura1';
SELECT nombre, LEFT(sal, 8) + N'...' AS sal, LEFT(contrasena, 16) + N'...' AS hash
FROM dbo.Usuario
WHERE correo IN (N'prueba.a@example.com', N'prueba.b@example.com');
ROLLBACK TRANSACTION;

-- 3.3 Inicio de sesión: una fila con la contraseña correcta y ninguna con una incorrecta.
EXEC dbo.sp_validar_login N'monica.reyes@example.com', N'Phyfo#1001';
EXEC dbo.sp_validar_login N'monica.reyes@example.com', N'incorrecta';
GO

-- 3.4 Pruebas de acceso por rol (EXECUTE AS USER)
DECLARE @a TABLE (Prueba NVARCHAR(5), Rol NVARCHAR(25), Accion NVARCHAR(80), Esperado NVARCHAR(10), Obtenido NVARCHAR(10), Error INT NULL);
DECLARE @n INT;
DECLARE @v TABLE (ID_usuario INT, nombre NVARCHAR(100));

-- A01 consulta pública lee el catálogo
EXECUTE AS USER = N'u_publico';
BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.vw_catalogo_publicaciones;
    INSERT INTO @a VALUES (N'A01', N'consulta pública', N'Leer vw_catalogo_publicaciones', N'Permitido', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A01', N'consulta pública', N'Leer vw_catalogo_publicaciones', N'Permitido', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A02 consulta pública intenta leer una tabla
EXECUTE AS USER = N'u_publico';
BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.Usuario;
    INSERT INTO @a VALUES (N'A02', N'consulta pública', N'Leer la tabla Usuario', N'Denegado', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A02', N'consulta pública', N'Leer la tabla Usuario', N'Denegado', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A03 aplicación inicia sesión con el procedimiento
EXECUTE AS USER = N'u_app';
BEGIN TRY
    INSERT INTO @v EXEC dbo.sp_validar_login N'monica.reyes@example.com', N'Phyfo#1001';
    INSERT INTO @a VALUES (N'A03', N'aplicación', N'Ejecutar sp_validar_login', N'Permitido', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A03', N'aplicación', N'Ejecutar sp_validar_login', N'Permitido', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A04 aplicación intenta leer el hash de las contraseñas
EXECUTE AS USER = N'u_app';
BEGIN TRY
    SELECT @n = COUNT(contrasena) FROM dbo.Usuario;
    INSERT INTO @a VALUES (N'A04', N'aplicación', N'Leer Usuario.contrasena', N'Denegado', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A04', N'aplicación', N'Leer Usuario.contrasena', N'Denegado', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A05 aplicación intenta insertar una publicación sin el procedimiento
EXECUTE AS USER = N'u_app';
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.Publicacion (ID_inventario, Precio) VALUES (53, 1000);
    ROLLBACK TRANSACTION;
    INSERT INTO @a VALUES (N'A05', N'aplicación', N'Insertar directamente en Publicacion', N'Denegado', N'Permitido', NULL);
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @a VALUES (N'A05', N'aplicación', N'Insertar directamente en Publicacion', N'Denegado', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A06 aplicación intenta crear una tabla
EXECUTE AS USER = N'u_app';
BEGIN TRY
    CREATE TABLE dbo.t_prueba (x INT);
    INSERT INTO @a VALUES (N'A06', N'aplicación', N'Crear una tabla', N'Denegado', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A06', N'aplicación', N'Crear una tabla', N'Denegado', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;
IF OBJECT_ID(N'dbo.t_prueba') IS NOT NULL DROP TABLE dbo.t_prueba;

-- A07 aplicación lee el catálogo de videojuegos
EXECUTE AS USER = N'u_app';
BEGIN TRY
    SELECT @n = COUNT(*) FROM dbo.Videojuego;
    INSERT INTO @a VALUES (N'A07', N'aplicación', N'Leer la tabla Videojuego', N'Permitido', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A07', N'aplicación', N'Leer la tabla Videojuego', N'Permitido', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A08 administrador modifica datos
EXECUTE AS USER = N'u_admin';
BEGIN TRY
    UPDATE dbo.Genero SET Nombre = Nombre WHERE ID_genero = 1;
    INSERT INTO @a VALUES (N'A08', N'administrador', N'Modificar datos de Genero', N'Permitido', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A08', N'administrador', N'Modificar datos de Genero', N'Permitido', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A09 administrador intenta leer la sal de las contraseñas
EXECUTE AS USER = N'u_admin';
BEGIN TRY
    SELECT @n = COUNT(sal) FROM dbo.Usuario;
    INSERT INTO @a VALUES (N'A09', N'administrador', N'Leer Usuario.sal', N'Denegado', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A09', N'administrador', N'Leer Usuario.sal', N'Denegado', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;

-- A10 administrador intenta crear una tabla
EXECUTE AS USER = N'u_admin';
BEGIN TRY
    CREATE TABLE dbo.t_prueba (x INT);
    INSERT INTO @a VALUES (N'A10', N'administrador', N'Crear una tabla', N'Denegado', N'Permitido', NULL);
END TRY
BEGIN CATCH
    INSERT INTO @a VALUES (N'A10', N'administrador', N'Crear una tabla', N'Denegado', N'Denegado', ERROR_NUMBER());
END CATCH;
REVERT;
IF OBJECT_ID(N'dbo.t_prueba') IS NOT NULL DROP TABLE dbo.t_prueba;

SELECT Prueba, Rol, Accion, Esperado, Obtenido,
       CASE WHEN Esperado = Obtenido THEN N'OK' ELSE N'FALLA' END AS Resultado, Error
FROM @a
ORDER BY Prueba;
GO

-- ------------------------------------------------------------
-- PARTE 4. MONITOREO (indicadores de la instancia)
-- Query Store solo registra lo que se ejecuta DESPUÉS de activarlo. Orden:
--   1) ejecutar el ALTER DATABASE ... QUERY_STORE = ON;
--   2) ejecutar las consultas Q1 a Q13 del script de implementación;
--   3) ejecutar los indicadores M1 a M6.
-- ------------------------------------------------------------
USE master;
GO
ALTER DATABASE phyfo SET QUERY_STORE = ON;
GO
USE phyfo;
GO

-- M1 Versión y edición de la instancia
SELECT CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50)) AS version,
       CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100))       AS edicion;

-- M2 Conexiones activas por cuenta
SELECT login_name, COUNT(*) AS conexiones
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name
ORDER BY conexiones DESC;

-- M3 Consultas más lentas de la base (Query Store)
SELECT TOP (20) LEFT(qt.query_sql_text, 80) AS consulta,
       rs.count_executions AS ejecuciones,
       CAST(rs.avg_duration AS INT) AS duracion_promedio_us,
       CAST(rs.avg_logical_io_reads AS INT) AS lecturas_promedio
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q           ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p            ON p.query_id      = q.query_id
JOIN sys.query_store_runtime_stats rs  ON rs.plan_id      = p.plan_id
WHERE qt.query_sql_text NOT LIKE N'%sys.%'
  AND qt.query_sql_text NOT LIKE N'%query_store%'
ORDER BY rs.avg_duration DESC;

-- M4 Uso de los índices
SELECT OBJECT_NAME(s.object_id) AS tabla, i.name AS indice,
       s.user_seeks AS busquedas, s.user_scans AS recorridos, s.user_updates AS actualizaciones
FROM sys.dm_db_index_usage_stats s
JOIN sys.indexes i ON i.object_id = s.object_id AND i.index_id = s.index_id
WHERE s.database_id = DB_ID()
  AND OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY s.user_seeks + s.user_scans DESC;

-- M5 Errores de usuario acumulados desde el inicio de la instancia
SELECT counter_name, instance_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE N'%SQL Errors%' AND instance_name = N'User Errors';

-- M6 Tamaño y crecimiento de los archivos, y filas por tabla
SELECT name AS archivo, type_desc AS tipo, size * 8 / 1024 AS tamano_mb,
       CASE is_percent_growth
            WHEN 1 THEN CAST(growth AS NVARCHAR(10)) + N' %'
            ELSE CAST(growth * 8 / 1024 AS NVARCHAR(10)) + N' MB' END AS crecimiento
FROM sys.database_files;

SELECT t.name AS tabla, SUM(ps.row_count) AS filas
FROM sys.dm_db_partition_stats ps
JOIN sys.tables t ON t.object_id = ps.object_id
WHERE ps.index_id IN (0, 1)
GROUP BY t.name
ORDER BY filas DESC;
GO