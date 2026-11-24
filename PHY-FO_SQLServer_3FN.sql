-- ============================================================
-- PHY-FO | Plataforma web para compraventa de videojuegos físicos
-- Fase 2: Diseño e implementación de la base de datos
-- Gestor: Microsoft SQL Server (T-SQL) - SQL Server Management Studio
-- Modelo normalizado hasta Tercera Forma Normal (3FN)
-- ============================================================

USE master;
GO
IF DB_ID(N'phyfo') IS NOT NULL
BEGIN
    ALTER DATABASE phyfo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE phyfo;
END;
GO

-- ------------------------------------------------------------
-- 8.1 CREACIÓN DE LA BASE DE DATOS
-- ------------------------------------------------------------
CREATE DATABASE phyfo COLLATE Latin1_General_100_CI_AI;
GO
USE phyfo;
GO

-- ------------------------------------------------------------
-- 8.2 CREACIÓN DE TABLAS (PK, FK, NOT NULL, UNIQUE, CHECK, DEFAULT)
-- ------------------------------------------------------------

-- Catálogos independientes
CREATE TABLE Plataforma (
    ID_plataforma INT IDENTITY(1,1) NOT NULL,
    Nombre        NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_plataforma PRIMARY KEY (ID_plataforma),
    CONSTRAINT uq_plataforma_nombre UNIQUE (Nombre)
);

CREATE TABLE Desarrollador (
    ID_desarrollador INT IDENTITY(1,1) NOT NULL,
    Nombre           NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_desarrollador PRIMARY KEY (ID_desarrollador),
    CONSTRAINT uq_desarrollador_nombre UNIQUE (Nombre)
);

CREATE TABLE Genero (
    ID_genero INT IDENTITY(1,1) NOT NULL,
    Nombre    NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_genero PRIMARY KEY (ID_genero),
    CONSTRAINT uq_genero_nombre UNIQUE (Nombre)
);

CREATE TABLE Clasificacion (
    ID_clasificacion INT IDENTITY(1,1) NOT NULL,
    Codigo           NVARCHAR(10) NOT NULL,
    Descripcion      NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_clasificacion PRIMARY KEY (ID_clasificacion),
    CONSTRAINT uq_clasificacion_codigo UNIQUE (Codigo)
);

-- Tipo de edición: distingue versiones del mismo título en la misma plataforma
CREATE TABLE TipoEdicion (
    ID_tipo_edicion INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_tipo_edicion PRIMARY KEY (ID_tipo_edicion),
    CONSTRAINT uq_tipo_edicion_nombre UNIQUE (Nombre)
);

CREATE TABLE Departamento (
    ID_departamento INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_departamento PRIMARY KEY (ID_departamento),
    CONSTRAINT uq_departamento_nombre UNIQUE (Nombre)
);

CREATE TABLE Ciudad (
    ID_ciudad       INT IDENTITY(1,1) NOT NULL,
    Nombre          NVARCHAR(45) NOT NULL,
    ID_departamento INT NOT NULL,
    CONSTRAINT pk_ciudad PRIMARY KEY (ID_ciudad),
    CONSTRAINT fk_ciudad_departamento
        FOREIGN KEY (ID_departamento) REFERENCES Departamento (ID_departamento),
    CONSTRAINT uq_ciudad_nombre_depto UNIQUE (Nombre, ID_departamento)
);

CREATE TABLE Transportadora (
    ID_transportadora INT IDENTITY(1,1) NOT NULL,
    Nombre            NVARCHAR(45) NOT NULL,
    CONSTRAINT pk_transportadora PRIMARY KEY (ID_transportadora),
    CONSTRAINT uq_transportadora_nombre UNIQUE (Nombre)
);

CREATE TABLE Usuario (
    ID_usuario INT IDENTITY(1,1) NOT NULL,
    nombre     NVARCHAR(100) NOT NULL,
    correo     NVARCHAR(100) NOT NULL,
    sal        CHAR(32)      NOT NULL,      -- sal aleatoria única por usuario (16 bytes en hexadecimal)
    contrasena CHAR(64)      NOT NULL,      -- hash SHA-256 con sal e iteraciones (fn_hash_contrasena), nunca texto plano
    CONSTRAINT pk_usuario PRIMARY KEY (ID_usuario),
    CONSTRAINT uq_usuario_correo UNIQUE (correo),
    CONSTRAINT chk_usuario_correo
        CHECK (correo LIKE N'_%@_%._%' AND correo NOT LIKE N'% %'),
    CONSTRAINT chk_usuario_credenciales
        CHECK (LEN(sal) = 32 AND LEN(contrasena) = 64)
);

-- Videojuegos: el TÍTULO (datos que no dependen de la plataforma).
-- El título solo no es único (p. ej. Resident Evil 4 de 2005 y de 2023).
CREATE TABLE Videojuego (
    ID_videojuego    INT IDENTITY(1,1) NOT NULL,
    Titulo           NVARCHAR(60) NOT NULL,
    ID_desarrollador INT NOT NULL,
    ID_genero        INT NOT NULL,
    ID_clasificacion INT NOT NULL,
    Anio_lanzamiento SMALLINT NOT NULL,
    CONSTRAINT pk_videojuego PRIMARY KEY (ID_videojuego),
    CONSTRAINT uq_videojuego_titulo_anio UNIQUE (Titulo, Anio_lanzamiento),
    CONSTRAINT chk_videojuego_anio CHECK (Anio_lanzamiento BETWEEN 1970 AND 2100),
    CONSTRAINT fk_videojuego_desarrollador
        FOREIGN KEY (ID_desarrollador) REFERENCES Desarrollador (ID_desarrollador),
    CONSTRAINT fk_videojuego_genero
        FOREIGN KEY (ID_genero) REFERENCES Genero (ID_genero),
    CONSTRAINT fk_videojuego_clasificacion
        FOREIGN KEY (ID_clasificacion) REFERENCES Clasificacion (ID_clasificacion)
);

-- Edición: un videojuego en una plataforma y con un tipo de edición concretos
-- (lo que realmente se vende). Elden Ring PS5 Estándar y Elden Ring PS5
-- Coleccionista son ediciones distintas.
CREATE TABLE Edicion (
    ID_edicion      INT IDENTITY(1,1) NOT NULL,
    ID_videojuego   INT NOT NULL,
    ID_plataforma   INT NOT NULL,
    ID_tipo_edicion INT NOT NULL,
    CONSTRAINT pk_edicion PRIMARY KEY (ID_edicion),
    CONSTRAINT fk_edicion_videojuego
        FOREIGN KEY (ID_videojuego) REFERENCES Videojuego (ID_videojuego),
    CONSTRAINT fk_edicion_plataforma
        FOREIGN KEY (ID_plataforma) REFERENCES Plataforma (ID_plataforma),
    CONSTRAINT fk_edicion_tipo
        FOREIGN KEY (ID_tipo_edicion) REFERENCES TipoEdicion (ID_tipo_edicion),
    CONSTRAINT uq_edicion_juego_plataforma_tipo
        UNIQUE (ID_videojuego, ID_plataforma, ID_tipo_edicion)
);

CREATE TABLE Direccion (
    ID_direccion INT IDENTITY(1,1) NOT NULL,
    ID_usuario   INT NOT NULL,
    ID_ciudad    INT NOT NULL,
    Direccion_detalle NVARCHAR(150) NOT NULL,   -- calle, número y complemento
    CONSTRAINT pk_direccion PRIMARY KEY (ID_direccion),
    CONSTRAINT fk_direccion_usuario
        FOREIGN KEY (ID_usuario) REFERENCES Usuario (ID_usuario) ON DELETE CASCADE,
    CONSTRAINT fk_direccion_ciudad
        FOREIGN KEY (ID_ciudad) REFERENCES Ciudad (ID_ciudad),
    CONSTRAINT chk_direccion_detalle
        CHECK (LEN(LTRIM(RTRIM(Direccion_detalle))) > 0)
);

-- Inventario: cada ejemplar físico que posee un usuario. Cada fila es UNA unidad
-- distinta, aunque dos filas sean el mismo juego y la misma edición: se
-- diferencian por su estado, el de la caja y las observaciones.
-- No guarda datos de la venta (están en Transaccion) ni su estado de
-- disponibilidad (se deriva en vw_estado_inventario).
CREATE TABLE Inventario (
    ID_inventario INT IDENTITY(1,1) NOT NULL,
    ID_edicion    INT NOT NULL,
    ID_usuario    INT NOT NULL,
    Estado_fisico NVARCHAR(45) NOT NULL DEFAULT N'Buen estado',   -- del disco o cartucho
    Estado_caja   NVARCHAR(45) NOT NULL DEFAULT N'Buen estado',   -- de la caja o estuche
    Observaciones NVARCHAR(300) NULL,                             -- daños, faltantes o extras de ESTA unidad
    CONSTRAINT pk_inventario PRIMARY KEY (ID_inventario),
    CONSTRAINT fk_inventario_edicion
        FOREIGN KEY (ID_edicion) REFERENCES Edicion (ID_edicion),
    CONSTRAINT fk_inventario_usuario
        FOREIGN KEY (ID_usuario) REFERENCES Usuario (ID_usuario),
    CONSTRAINT chk_inventario_estado_fisico
        CHECK (Estado_fisico IN (N'Nuevo', N'Como nuevo', N'Buen estado', N'Aceptable')),
    CONSTRAINT chk_inventario_estado_caja
        CHECK (Estado_caja IN (N'Nuevo', N'Como nuevo', N'Buen estado', N'Aceptable', N'Dañada', N'Sin caja'))
);

-- Publicación: oferta de un ejemplar. Vendedor, edición y estado físico
-- se obtienen desde Inventario.
CREATE TABLE Publicacion (
    ID_publicacion INT IDENTITY(1,1) NOT NULL,
    ID_inventario  INT NOT NULL,
    Precio         DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_publicacion PRIMARY KEY (ID_publicacion),
    CONSTRAINT fk_publicacion_inventario
        FOREIGN KEY (ID_inventario) REFERENCES Inventario (ID_inventario),
    CONSTRAINT uq_publicacion_inventario UNIQUE (ID_inventario),
    CONSTRAINT chk_publicacion_precio CHECK (Precio > 0)
);

-- Fotografías reales de cada publicación (RF-08): relación 1:N con Publicacion.
-- Solo se guarda la ruta/URL; el archivo vive fuera de la base de datos.
-- Toda publicación debe conservar al menos una (sp_publicar_ejemplar,
-- trg_fotografia_adu y trg_transaccion_ai).
CREATE TABLE FotografiaPublicacion (
    ID_fotografia   INT IDENTITY(1,1) NOT NULL,
    ID_publicacion  INT NOT NULL,
    Ruta_fotografia NVARCHAR(500) NOT NULL,
    Orden           TINYINT NOT NULL,          -- 1 = foto principal
    CONSTRAINT pk_fotografia_publicacion PRIMARY KEY (ID_fotografia),
    CONSTRAINT fk_fotografia_publicacion
        FOREIGN KEY (ID_publicacion) REFERENCES Publicacion (ID_publicacion)
        ON DELETE CASCADE,
    CONSTRAINT uq_fotografia_publicacion_orden UNIQUE (ID_publicacion, Orden),
    CONSTRAINT uq_fotografia_ruta UNIQUE (Ruta_fotografia),   -- una foto no se reutiliza en otra publicación
    CONSTRAINT chk_fotografia_orden CHECK (Orden BETWEEN 1 AND 10),
    CONSTRAINT chk_fotografia_ruta
        CHECK (Ruta_fotografia LIKE N'%.jpg'  OR Ruta_fotografia LIKE N'%.jpeg'
            OR Ruta_fotografia LIKE N'%.png'  OR Ruta_fotografia LIKE N'%.webp')
);

CREATE TABLE Transaccion (
    ID_transaccion    INT IDENTITY(1,1) NOT NULL,
    ID_publicacion    INT NOT NULL,
    ID_comprador      INT NOT NULL,
    precio_final      DECIMAL(10,2) NOT NULL,
    Fecha_transaccion DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    Forma_entrega     NVARCHAR(20) NOT NULL DEFAULT N'Transportadora',
    Fecha_entrega_persona DATETIME2(0) NULL,   -- confirmación de entrega en persona
    CONSTRAINT pk_transaccion PRIMARY KEY (ID_transaccion),
    CONSTRAINT fk_transaccion_publicacion
        FOREIGN KEY (ID_publicacion) REFERENCES Publicacion (ID_publicacion),
    CONSTRAINT fk_transaccion_comprador
        FOREIGN KEY (ID_comprador) REFERENCES Usuario (ID_usuario),
    CONSTRAINT uq_transaccion_publicacion UNIQUE (ID_publicacion),
    CONSTRAINT chk_transaccion_precio CHECK (precio_final > 0),
    CONSTRAINT chk_transaccion_forma_entrega
        CHECK (Forma_entrega IN (N'En persona', N'Transportadora')),
    CONSTRAINT chk_transaccion_fecha_entrega
        CHECK (Fecha_entrega_persona IS NULL
               OR (Forma_entrega = N'En persona' AND Fecha_entrega_persona >= Fecha_transaccion))
);

-- Envío: solo existe cuando la venta se entrega por Transportadora (RF-12)
CREATE TABLE Envio (
    ID_envio          INT IDENTITY(1,1) NOT NULL,
    ID_transaccion    INT NOT NULL,
    ID_direccion      INT NOT NULL,
    ID_transportadora INT NOT NULL,
    Numero_guia       NVARCHAR(30) NOT NULL,
    Estado_envio      NVARCHAR(45) NOT NULL DEFAULT N'Pendiente',
    CONSTRAINT pk_envio PRIMARY KEY (ID_envio),
    CONSTRAINT fk_envio_transaccion
        FOREIGN KEY (ID_transaccion) REFERENCES Transaccion (ID_transaccion),
    CONSTRAINT fk_envio_direccion
        FOREIGN KEY (ID_direccion) REFERENCES Direccion (ID_direccion),
    CONSTRAINT fk_envio_transportadora
        FOREIGN KEY (ID_transportadora) REFERENCES Transportadora (ID_transportadora),
    CONSTRAINT uq_envio_transaccion UNIQUE (ID_transaccion),
    CONSTRAINT uq_envio_guia UNIQUE (Numero_guia),
    CONSTRAINT chk_envio_estado
        CHECK (Estado_envio IN (N'Pendiente', N'En tránsito', N'Entregado', N'Cancelado'))
);

CREATE TABLE Resena (
    ID_resena      INT IDENTITY(1,1) NOT NULL,
    ID_publicacion INT NOT NULL,
    ID_usuario     INT NOT NULL,
    Calificacion   INT NOT NULL,
    Comentario     NVARCHAR(100) NULL,
    CONSTRAINT pk_resena PRIMARY KEY (ID_resena),
    CONSTRAINT fk_resena_publicacion
        FOREIGN KEY (ID_publicacion) REFERENCES Publicacion (ID_publicacion) ON DELETE CASCADE,
    CONSTRAINT fk_resena_usuario
        FOREIGN KEY (ID_usuario) REFERENCES Usuario (ID_usuario) ON DELETE CASCADE,
    CONSTRAINT uq_resena_publicacion_usuario UNIQUE (ID_publicacion, ID_usuario),
    CONSTRAINT chk_resena_calificacion CHECK (Calificacion BETWEEN 1 AND 5)
);
GO

-- ------------------------------------------------------------
-- Índices sobre llaves foráneas (SQL Server no los crea solo)
-- ------------------------------------------------------------
CREATE INDEX ix_ciudad_departamento     ON Ciudad      (ID_departamento);
CREATE INDEX ix_videojuego_desarrollador ON Videojuego (ID_desarrollador);
CREATE INDEX ix_videojuego_genero       ON Videojuego  (ID_genero);
CREATE INDEX ix_videojuego_clasificacion ON Videojuego (ID_clasificacion);
CREATE INDEX ix_edicion_plataforma      ON Edicion     (ID_plataforma);
CREATE INDEX ix_edicion_tipo            ON Edicion     (ID_tipo_edicion);
CREATE INDEX ix_direccion_usuario       ON Direccion   (ID_usuario);
CREATE INDEX ix_direccion_ciudad        ON Direccion   (ID_ciudad);
CREATE INDEX ix_inventario_edicion      ON Inventario  (ID_edicion);
CREATE INDEX ix_inventario_usuario      ON Inventario  (ID_usuario);
-- (Publicacion.ID_inventario y FotografiaPublicacion.ID_publicacion ya quedan
--  indexadas por sus restricciones UNIQUE)
CREATE INDEX ix_transaccion_comprador   ON Transaccion (ID_comprador);
CREATE INDEX ix_envio_direccion         ON Envio       (ID_direccion);
CREATE INDEX ix_envio_transportadora    ON Envio       (ID_transportadora);
CREATE INDEX ix_resena_usuario          ON Resena      (ID_usuario);
GO

-- ------------------------------------------------------------
-- Reglas de negocio entre tablas (triggers), procedimiento y vista
-- ------------------------------------------------------------

-- Sin triggers de estado sobre Publicacion: un ejemplar no puede publicarse dos
-- veces (UNIQUE (ID_inventario)) y una publicación vendida no se puede borrar
-- (FK desde Transaccion), así que ya no hay estado almacenado que mantener.

-- Al vender: precio final <= precio publicado, comprador distinto del vendedor
-- y publicación con al menos una fotografía.
-- Que una publicación no se venda dos veces lo garantiza UNIQUE (ID_publicacion)
-- en Transaccion.
CREATE TRIGGER trg_transaccion_ai
ON Transaccion
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted t
               JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
               WHERE t.precio_final > p.Precio)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50010, N'El precio final no puede superar el precio publicado.', 1;
    END;

    IF EXISTS (SELECT 1
               FROM inserted t
               JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
               JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
               WHERE t.ID_comprador = i.ID_usuario)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50011, N'El comprador no puede ser el mismo vendedor.', 1;
    END;

    IF EXISTS (SELECT 1
               FROM inserted t
               WHERE NOT EXISTS (SELECT 1 FROM FotografiaPublicacion f
                                 WHERE f.ID_publicacion = t.ID_publicacion))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50013, N'No se puede vender una publicación sin fotografías.', 1;
    END;
END;
GO

-- La dirección de envío debe pertenecer al comprador y la venta debe ser
-- por transportadora (una venta en persona no tiene envío)
CREATE TRIGGER trg_envio_ai
ON Envio
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted e
               JOIN Transaccion t ON t.ID_transaccion = e.ID_transaccion
               JOIN Direccion   d ON d.ID_direccion   = e.ID_direccion
               WHERE d.ID_usuario <> t.ID_comprador)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50020, N'La dirección de envío debe pertenecer al comprador.', 1;
    END;

    IF EXISTS (SELECT 1
               FROM inserted e
               JOIN Transaccion t ON t.ID_transaccion = e.ID_transaccion
               WHERE t.Forma_entrega <> N'Transportadora')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50021, N'La venta es en persona: no admite registro de envío.', 1;
    END;
END;
GO

-- Solo el comprador de la publicación puede reseñarla
CREATE TRIGGER trg_resena_ai
ON Resena
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM inserted r
               LEFT JOIN Transaccion t ON t.ID_publicacion = r.ID_publicacion
                                      AND t.ID_comprador   = r.ID_usuario
               WHERE t.ID_transaccion IS NULL)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50040, N'Solo el comprador de la publicación puede reseñarla.', 1;
    END;
END;
GO

-- Registro atómico de una venta: transacción + envío. Si la entrega es en
-- persona no se crea envío.
CREATE PROCEDURE sp_registrar_venta
    @p_publicacion     INT,
    @p_comprador       INT,
    @p_precio          DECIMAL(10,2),
    @p_direccion       INT           = NULL,
    @p_transportadora  INT           = NULL,
    @p_guia            NVARCHAR(30)  = NULL,
    @p_forma_entrega   NVARCHAR(20)  = N'Transportadora'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @v_pub   INT;
    DECLARE @v_trans INT;

    BEGIN TRY
        -- Coherencia entre la forma de entrega y los datos de envío
        IF @p_forma_entrega = N'Transportadora'
           AND (@p_direccion IS NULL OR @p_transportadora IS NULL OR @p_guia IS NULL)
            THROW 50031, N'La entrega por transportadora exige dirección, transportadora y guía.', 1;

        IF @p_forma_entrega = N'En persona'
           AND (@p_direccion IS NOT NULL OR @p_transportadora IS NOT NULL OR @p_guia IS NOT NULL)
            THROW 50032, N'La entrega en persona no admite datos de envío.', 1;

        BEGIN TRANSACTION;

        -- Bloquea la publicación mientras se registra la venta
        SELECT @v_pub = ID_publicacion
          FROM Publicacion WITH (UPDLOCK, HOLDLOCK)
         WHERE ID_publicacion = @p_publicacion;

        IF @v_pub IS NULL
            THROW 50030, N'La publicación indicada no existe.', 1;

        INSERT INTO Transaccion (ID_publicacion, ID_comprador, precio_final, Forma_entrega)
        VALUES (@p_publicacion, @p_comprador, @p_precio, @p_forma_entrega);

        SET @v_trans = SCOPE_IDENTITY();

        IF @p_forma_entrega = N'Transportadora'
            INSERT INTO Envio (ID_transaccion, ID_direccion, ID_transportadora, Numero_guia)
            VALUES (@v_trans, @p_direccion, @p_transportadora, @p_guia);

        COMMIT TRANSACTION;
        SELECT @v_trans AS ID_transaccion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- ------------------------------------------------------------
-- Contraseñas: sal única por usuario + SHA-256 iterado
-- ------------------------------------------------------------
-- Nota: T-SQL no ofrece bcrypt/Argon2. En producción lo ideal es calcular el
-- hash en la aplicación con uno de ellos y guardar el resultado; aquí se usa
-- HASHBYTES con sal y 10.000 rondas (estiramiento de clave) para encarecer la
-- fuerza bruta y evitar que dos usuarios con la misma clave tengan el mismo hash.
CREATE FUNCTION fn_hash_contrasena (@p_sal CHAR(32), @p_contrasena NVARCHAR(100))
RETURNS CHAR(64)
AS
BEGIN
    DECLARE @v_sal  VARBINARY(16)  = CONVERT(VARBINARY(16), @p_sal, 2);
    DECLARE @v_clave VARBINARY(200) = CONVERT(VARBINARY(200), @p_contrasena);
    DECLARE @v_hash VARBINARY(32)  = HASHBYTES('SHA2_256', @v_sal + @v_clave);
    DECLARE @i INT = 1;

    WHILE @i < 10000
    BEGIN
        SET @v_hash = HASHBYTES('SHA2_256', @v_hash + @v_sal + @v_clave);
        SET @i += 1;
    END;

    RETURN LOWER(CONVERT(CHAR(64), @v_hash, 2));
END;
GO

-- Registro de usuario: genera la sal y guarda solo el hash.
-- Uso: EXEC sp_registrar_usuario N'Nombre', N'correo@dominio.com', N'Clave#segura1';
CREATE PROCEDURE sp_registrar_usuario
    @p_nombre      NVARCHAR(100),
    @p_correo      NVARCHAR(100),
    @p_contrasena  NVARCHAR(100),
    @p_id          INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF @p_contrasena IS NULL OR LEN(@p_contrasena) < 8
        THROW 50060, N'La contraseña debe tener al menos 8 caracteres.', 1;

    DECLARE @v_sal CHAR(32) = LOWER(CONVERT(CHAR(32), CRYPT_GEN_RANDOM(16), 2));

    INSERT INTO Usuario (nombre, correo, sal, contrasena)
    VALUES (@p_nombre, @p_correo, @v_sal, dbo.fn_hash_contrasena(@v_sal, @p_contrasena));

    SET @p_id = SCOPE_IDENTITY();
END;
GO

-- Inicio de sesión: devuelve una fila si las credenciales son correctas y
-- ninguna si no lo son (sin revelar si falló el correo o la contraseña).
-- Uso: EXEC sp_validar_login N'correo@dominio.com', N'Clave#segura1';
CREATE PROCEDURE sp_validar_login
    @p_correo      NVARCHAR(100),
    @p_contrasena  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.ID_usuario, u.nombre
      FROM Usuario u
     WHERE u.correo = @p_correo
       AND u.contrasena = dbo.fn_hash_contrasena(u.sal, @p_contrasena);
END;
GO

-- ------------------------------------------------------------
-- Publicaciones con fotografía obligatoria
-- ------------------------------------------------------------
-- Publica un ejemplar con sus fotos en una sola transacción (mínimo 1, máximo 10).
-- @p_fotos: rutas separadas por '|'; la primera es la foto principal.
-- Uso: EXEC sp_publicar_ejemplar 53, 150000, N'/uploads/p/a.jpg|/uploads/p/b.jpg';
-- (STRING_SPLIT con ordinal requiere nivel de compatibilidad 160 o superior)
CREATE PROCEDURE sp_publicar_ejemplar
    @p_inventario  INT,
    @p_precio      DECIMAL(10,2),
    @p_fotos       NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @v_pub INT;
    DECLARE @v_n   INT;
    DECLARE @rutas TABLE (Orden INT NOT NULL, Ruta NVARCHAR(500) NOT NULL);

    BEGIN TRY
        INSERT INTO @rutas (Orden, Ruta)
        SELECT ROW_NUMBER() OVER (ORDER BY ordinal), LTRIM(RTRIM(value))
          FROM STRING_SPLIT(@p_fotos, N'|', 1)
         WHERE LTRIM(RTRIM(value)) <> N'';

        SELECT @v_n = COUNT(*) FROM @rutas;

        IF @v_n = 0
            THROW 50051, N'Una publicación debe tener al menos una fotografía.', 1;
        IF @v_n > 10
            THROW 50052, N'Una publicación admite como máximo 10 fotografías.', 1;
        IF NOT EXISTS (SELECT 1 FROM Inventario WHERE ID_inventario = @p_inventario)
            THROW 50053, N'El ejemplar indicado no existe.', 1;
        IF EXISTS (SELECT 1 FROM Publicacion WHERE ID_inventario = @p_inventario)
            THROW 50054, N'El ejemplar ya tiene una publicación.', 1;

        BEGIN TRANSACTION;

        INSERT INTO Publicacion (ID_inventario, Precio)
        VALUES (@p_inventario, @p_precio);

        SET @v_pub = SCOPE_IDENTITY();

        INSERT INTO FotografiaPublicacion (ID_publicacion, Ruta_fotografia, Orden)
        SELECT @v_pub, Ruta, CAST(Orden AS TINYINT)
          FROM @rutas;

        COMMIT TRANSACTION;
        SELECT @v_pub AS ID_publicacion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- No se puede borrar (ni mover a otra publicación) la última fotografía de una
-- publicación que sigue existiendo. Si se borra la publicación completa, sus
-- fotos se eliminan en cascada y esta regla no se activa.
CREATE TRIGGER trg_fotografia_adu
ON FotografiaPublicacion
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
               FROM deleted d
               WHERE EXISTS (SELECT 1 FROM Publicacion p
                             WHERE p.ID_publicacion = d.ID_publicacion)
                 AND NOT EXISTS (SELECT 1 FROM FotografiaPublicacion f
                                 WHERE f.ID_publicacion = d.ID_publicacion))
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50050, N'Una publicación debe conservar al menos una fotografía.', 1;
    END;
END;
GO

-- Estado de cada ejemplar, calculado (no almacenado):
--   Disponible = sin publicación | Publicado = con publicación sin venta | Vendido = con transacción
CREATE VIEW vw_estado_inventario AS
SELECT i.ID_inventario, i.ID_usuario, i.ID_edicion, i.Estado_fisico, i.Estado_caja,
       CASE WHEN t.ID_transaccion IS NOT NULL THEN N'Vendido'
            WHEN p.ID_publicacion IS NOT NULL THEN N'Publicado'
            ELSE N'Disponible'
       END AS Estado
FROM Inventario i
LEFT JOIN Publicacion p ON p.ID_inventario  = i.ID_inventario
LEFT JOIN Transaccion t ON t.ID_publicacion = p.ID_publicacion;
GO

-- Vista del catálogo público (publicaciones con fotografía y aún sin venta, con tipo de edición,
-- estado del disco y de la caja, observaciones y fotografías)
CREATE VIEW vw_catalogo_publicaciones AS
SELECT p.ID_publicacion, v.Titulo, te.Nombre AS Tipo_edicion, pl.Nombre AS Plataforma,
       g.Nombre AS Genero, c.Codigo AS Clasificacion, i.Estado_fisico, i.Estado_caja,
       i.Observaciones, p.Precio, u.nombre AS Vendedor,
       (SELECT COUNT(*) FROM FotografiaPublicacion f
         WHERE f.ID_publicacion = p.ID_publicacion) AS Cantidad_fotos,
       (SELECT TOP (1) f.Ruta_fotografia FROM FotografiaPublicacion f
         WHERE f.ID_publicacion = p.ID_publicacion
         ORDER BY f.Orden) AS Foto_principal
FROM Publicacion  p
JOIN Inventario   i  ON i.ID_inventario  = p.ID_inventario
JOIN Edicion      e  ON e.ID_edicion     = i.ID_edicion
JOIN Videojuego   v  ON v.ID_videojuego  = e.ID_videojuego
JOIN TipoEdicion  te ON te.ID_tipo_edicion = e.ID_tipo_edicion
JOIN Plataforma   pl ON pl.ID_plataforma = e.ID_plataforma
JOIN Genero       g  ON g.ID_genero      = v.ID_genero
JOIN Clasificacion c ON c.ID_clasificacion = v.ID_clasificacion
JOIN Usuario      u  ON u.ID_usuario     = i.ID_usuario
WHERE EXISTS     (SELECT 1 FROM FotografiaPublicacion f
                  WHERE f.ID_publicacion = p.ID_publicacion)
  AND NOT EXISTS (SELECT 1 FROM Transaccion t
                  WHERE t.ID_publicacion = p.ID_publicacion);
GO

-- ------------------------------------------------------------
-- 8.3 DATOS DE PRUEBA (380 registros; 54 ejemplares en Inventario)
-- ------------------------------------------------------------
INSERT INTO Plataforma (Nombre) VALUES
    (N'PlayStation 5'),
    (N'PlayStation 4'),
    (N'Xbox Series X'),
    (N'Xbox One'),
    (N'Nintendo Switch');

INSERT INTO Desarrollador (Nombre) VALUES
    (N'FromSoftware'),
    (N'Nintendo'),
    (N'CD Projekt Red'),
    (N'Rockstar Games'),
    (N'Naughty Dog'),
    (N'Santa Monica Studio'),
    (N'Capcom'),
    (N'Square Enix'),
    (N'Bethesda Game Studios'),
    (N'Insomniac Games'),
    (N'Ubisoft'),
    (N'Electronic Arts');

INSERT INTO Genero (Nombre) VALUES
    (N'Acción'),
    (N'RPG'),
    (N'Aventura'),
    (N'Deportes'),
    (N'Carreras'),
    (N'Shooter'),
    (N'Plataformas'),
    (N'Terror');

INSERT INTO Clasificacion (Codigo, Descripcion) VALUES
    (N'E',    N'Todos'),
    (N'E10+', N'Todos mayores de 10 años'),
    (N'T',    N'Adolescentes'),
    (N'M',    N'Maduro (17+)');

INSERT INTO TipoEdicion (Nombre) VALUES
    (N'Estándar'),
    (N'Deluxe'),
    (N'Coleccionista'),
    (N'Aniversario'),
    (N'Definitiva');

INSERT INTO Departamento (Nombre) VALUES
    (N'Atlántico'),
    (N'Risaralda'),
    (N'Magdalena'),
    (N'Valle del Cauca'),
    (N'Bolívar'),
    (N'Norte de Santander'),
    (N'Antioquia'),
    (N'Santander'),
    (N'Caldas'),
    (N'Bogotá D.C.');

INSERT INTO Ciudad (Nombre, ID_departamento) VALUES
    (N'Barranquilla', 1),
    (N'Pereira',      2),
    (N'Santa Marta',  3),
    (N'Cali',         4),
    (N'Cartagena',    5),
    (N'Cúcuta',       6),
    (N'Medellín',     7),
    (N'Bucaramanga',  8),
    (N'Manizales',    9),
    (N'Bogotá',      10);

INSERT INTO Transportadora (Nombre) VALUES
    (N'TCC'),
    (N'Interrapidísimo'),
    (N'Coordinadora'),
    (N'Servientrega'),
    (N'Envía');

-- Usuarios de prueba: se registran con el procedimiento (sal única y hash por usuario)
EXEC sp_registrar_usuario N'Mónica Reyes', N'monica.reyes@example.com', N'Phyfo#1001';
EXEC sp_registrar_usuario N'Juan Pérez', N'juan.perez@example.com', N'Phyfo#1002';
EXEC sp_registrar_usuario N'Laura Gómez', N'laura.gomez@example.com', N'Phyfo#1003';
EXEC sp_registrar_usuario N'Carlos Ramírez', N'carlos.ramirez@example.com', N'Phyfo#1004';
EXEC sp_registrar_usuario N'Valentina Rojas', N'valentina.rojas@example.com', N'Phyfo#1005';
EXEC sp_registrar_usuario N'Santiago Torres', N'santiago.torres@example.com', N'Phyfo#1006';
EXEC sp_registrar_usuario N'Camila Herrera', N'camila.herrera@example.com', N'Phyfo#1007';
EXEC sp_registrar_usuario N'Andrés Molina', N'andres.molina@example.com', N'Phyfo#1008';
EXEC sp_registrar_usuario N'Daniela Castro', N'daniela.castro@example.com', N'Phyfo#1009';
EXEC sp_registrar_usuario N'Felipe Ortiz', N'felipe.ortiz@example.com', N'Phyfo#1010';
EXEC sp_registrar_usuario N'Mariana Vargas', N'mariana.vargas@example.com', N'Phyfo#1011';
EXEC sp_registrar_usuario N'Sebastián Cárdenas', N'sebastian.cardenas@example.com', N'Phyfo#1012';
EXEC sp_registrar_usuario N'Natalia Quintero', N'natalia.quintero@example.com', N'Phyfo#1013';
EXEC sp_registrar_usuario N'Julián Ospina', N'julian.ospina@example.com', N'Phyfo#1014';
EXEC sp_registrar_usuario N'Paula Mendoza', N'paula.mendoza@example.com', N'Phyfo#1015';
EXEC sp_registrar_usuario N'David Salazar', N'david.salazar@example.com', N'Phyfo#1016';
EXEC sp_registrar_usuario N'Sofía Arango', N'sofia.arango@example.com', N'Phyfo#1017';
EXEC sp_registrar_usuario N'Mateo Gutiérrez', N'mateo.gutierrez@example.com', N'Phyfo#1018';
EXEC sp_registrar_usuario N'Isabella Rincón', N'isabella.rincon@example.com', N'Phyfo#1019';
EXEC sp_registrar_usuario N'Nicolás Peña', N'nicolas.pena@example.com', N'Phyfo#1020';

-- Videojuegos (26 títulos). Clasificación: 1=E, 2=E10+, 3=T, 4=M
INSERT INTO Videojuego (Titulo, ID_desarrollador, ID_genero, ID_clasificacion, Anio_lanzamiento) VALUES
    (N'Elden Ring', 1, 2, 4, 2022),
    (N'The Legend of Zelda: Tears of the Kingdom', 2, 3, 2, 2023),
    (N'Super Mario Odyssey', 2, 7, 2, 2017),
    (N'Cyberpunk 2077', 3, 2, 4, 2020),
    (N'Red Dead Redemption 2', 4, 1, 4, 2018),
    (N'Grand Theft Auto V', 4, 1, 4, 2013),
    (N'The Last of Us Part II', 5, 3, 4, 2020),
    (N'God of War Ragnarök', 6, 1, 4, 2022),
    (N'God of War', 6, 1, 4, 2018),
    (N'Resident Evil 4', 7, 8, 4, 2023),
    (N'Resident Evil Village', 7, 8, 4, 2021),
    (N'Street Fighter 6', 7, 1, 3, 2023),
    (N'Final Fantasy XVI', 8, 2, 4, 2023),
    (N'Starfield', 9, 2, 4, 2023),
    (N'The Elder Scrolls V: Skyrim', 9, 2, 4, 2011),
    (N'Marvel''s Spider-Man 2', 10, 1, 3, 2023),
    (N'Marvel''s Spider-Man: Miles Morales', 10, 1, 3, 2020),
    (N'Assassin''s Creed Valhalla', 11, 1, 4, 2020),
    (N'Assassin''s Creed Mirage', 11, 1, 4, 2023),
    (N'Far Cry 6', 11, 6, 4, 2021),
    (N'EA Sports FC 25', 12, 4, 1, 2024),
    (N'Need for Speed Unbound', 12, 5, 3, 2022),
    (N'Mario Kart 8 Deluxe', 2, 5, 1, 2017),
    (N'Animal Crossing: New Horizons', 2, 3, 1, 2020),
    (N'Metroid Dread', 2, 1, 3, 2021),
    (N'Ratchet & Clank: Rift Apart', 10, 7, 2, 2021);

-- Ediciones (título + plataforma + tipo). Tipo: 1=Estándar, 2=Deluxe, 3=Coleccionista,
-- 4=Aniversario, 5=Definitiva. Los 30 IDs originales son Estándar; 31 a 34 son nuevas.
INSERT INTO Edicion (ID_videojuego, ID_plataforma, ID_tipo_edicion) VALUES
    (1, 1, 1),   -- 1  Elden Ring, PS5
    (1, 3, 1),   -- 2  Elden Ring, Xbox Series X
    (2, 5, 1),   -- 3  Zelda TOTK, Switch
    (3, 5, 1),   -- 4  Super Mario Odyssey, Switch
    (4, 1, 1),   -- 5  Cyberpunk 2077, PS5
    (4, 3, 1),   -- 6  Cyberpunk 2077, Xbox Series X
    (5, 2, 1),   -- 7  RDR2, PS4
    (6, 2, 1),   -- 8  GTA V, PS4
    (6, 4, 1),   -- 9  GTA V, Xbox One
    (7, 2, 1),   -- 10 The Last of Us Part II, PS4
    (8, 1, 1),   -- 11 God of War Ragnarök, PS5
    (9, 2, 1),   -- 12 God of War, PS4
    (10, 1, 1),  -- 13 Resident Evil 4, PS5
    (11, 3, 1),  -- 14 Resident Evil Village, Xbox Series X
    (12, 1, 1),  -- 15 Street Fighter 6, PS5
    (13, 1, 1),  -- 16 Final Fantasy XVI, PS5
    (14, 3, 1),  -- 17 Starfield, Xbox Series X
    (15, 5, 1),  -- 18 Skyrim, Switch
    (16, 1, 1),  -- 19 Spider-Man 2, PS5
    (17, 2, 1),  -- 20 Miles Morales, PS4
    (18, 4, 1),  -- 21 AC Valhalla, Xbox One
    (19, 1, 1),  -- 22 AC Mirage, PS5
    (20, 3, 1),  -- 23 Far Cry 6, Xbox Series X
    (21, 1, 1),  -- 24 EA Sports FC 25, PS5
    (21, 5, 1),  -- 25 EA Sports FC 25, Switch
    (22, 3, 1),  -- 26 Need for Speed Unbound, Xbox Series X
    (23, 5, 1),  -- 27 Mario Kart 8 Deluxe, Switch
    (24, 5, 1),  -- 28 Animal Crossing, Switch
    (25, 5, 1),  -- 29 Metroid Dread, Switch
    (26, 1, 1),  -- 30 Ratchet & Clank, PS5
    (1, 1, 3),   -- 31 Elden Ring, PS5, Coleccionista
    (4, 1, 5),   -- 32 Cyberpunk 2077, PS5, Definitiva
    (15, 5, 4),  -- 33 Skyrim, Switch, Aniversario
    (8, 1, 3);   -- 34 God of War Ragnarök, PS5, Coleccionista

-- Direcciones (usuarios 1-20 con una dirección; 6 direcciones adicionales)
INSERT INTO Direccion (ID_usuario, ID_ciudad, Direccion_detalle) VALUES
    (1,  1,  N'Calle 72 # 43-15, Apto 301'),
    (2,  2,  N'Carrera 7 # 21-40'),
    (3,  3,  N'Calle 22 # 5-18'),
    (4,  4,  N'Avenida 6N # 25-30, Casa 2'),
    (5,  5,  N'Carrera 3 # 31-12'),
    (6,  6,  N'Calle 10 # 4-55, Torre B Apto 502'),
    (7,  7,  N'Carrera 43A # 1-50'),
    (8,  8,  N'Calle 36 # 27-10'),
    (9,  9,  N'Carrera 23 # 62-19'),
    (10, 10, N'Calle 100 # 15-20, Oficina 704'),
    (11, 1,  N'Carrera 54 # 68-80'),
    (12, 2,  N'Calle 19 # 8-33'),
    (13, 3,  N'Carrera 5 # 14-27'),
    (14, 4,  N'Calle 5 # 38-14, Apto 101'),
    (15, 5,  N'Calle 30 # 17-45'),
    (16, 6,  N'Avenida 0 # 12-60'),
    (17, 7,  N'Carrera 70 # 44-22, Apto 204'),
    (18, 8,  N'Calle 45 # 31-09'),
    (19, 9,  N'Carrera 21 # 24-70'),
    (20, 10, N'Carrera 15 # 85-40, Apto 603'),
    (2,  10, N'Calle 53 # 21-18'),        -- Juan: Bogotá
    (3,  4,  N'Carrera 100 # 11-52'),     -- Laura: Cali
    (5,  7,  N'Calle 10 # 36-14'),        -- Valentina: Medellín
    (8,  2,  N'Carrera 8 # 20-31'),       -- Andrés: Pereira
    (12, 5,  N'Calle 33 # 8-27'),         -- Sebastián: Cartagena
    (15, 10, N'Transversal 23 # 95-12');  -- Paula: Bogotá

-- Inventario: (edición, propietario, estado físico). Estado inicial = Disponible.
INSERT INTO Inventario (ID_edicion, ID_usuario, Estado_fisico, Estado_caja, Observaciones) VALUES
    (11, 5,  N'Buen estado', N'Buen estado', NULL),
    (13, 2,  N'Aceptable', N'Aceptable', NULL),
    (3,  18, N'Aceptable', N'Dañada', N'Caja con rayones y marcas de humedad'),
    (4,  12, N'Nuevo', N'Nuevo', NULL),
    (19, 2,  N'Buen estado', N'Buen estado', NULL),
    (30, 17, N'Nuevo', N'Nuevo', NULL),
    (7,  2,  N'Buen estado', N'Buen estado', NULL),
    (3,  14, N'Buen estado', N'Buen estado', NULL),
    (14, 3,  N'Buen estado', N'Buen estado', NULL),
    (8,  3,  N'Nuevo', N'Nuevo', NULL),
    (18, 14, N'Buen estado', N'Buen estado', NULL),
    (2,  19, N'Aceptable', N'Dañada', N'Esquina inferior de la caja aplastada y funda rota'),
    (4,  8,  N'Buen estado', N'Buen estado', NULL),
    (21, 19, N'Como nuevo', N'Como nuevo', NULL),
    (2,  19, N'Como nuevo', N'Como nuevo', NULL),
    (19, 13, N'Buen estado', N'Buen estado', NULL),
    (2,  8,  N'Buen estado', N'Buen estado', N'Incluye manual'),
    (2,  18, N'Como nuevo', N'Sin caja', N'Se vende solo el disco, sin caja'),
    (28, 5,  N'Buen estado', N'Buen estado', NULL),
    (10, 14, N'Buen estado', N'Buen estado', NULL),
    (5,  18, N'Buen estado', N'Buen estado', NULL),
    (4,  19, N'Buen estado', N'Buen estado', NULL),
    (10, 18, N'Buen estado', N'Buen estado', NULL),
    (27, 6,  N'Como nuevo', N'Como nuevo', NULL),
    (4,  19, N'Nuevo', N'Nuevo', NULL),
    (19, 7,  N'Como nuevo', N'Como nuevo', NULL),
    (12, 4,  N'Como nuevo', N'Como nuevo', NULL),
    (18, 3,  N'Buen estado', N'Buen estado', NULL),
    (19, 2,  N'Como nuevo', N'Como nuevo', NULL),
    (20, 7,  N'Buen estado', N'Buen estado', NULL),
    (16, 18, N'Como nuevo', N'Como nuevo', NULL),
    (14, 11, N'Aceptable', N'Aceptable', NULL),
    (15, 19, N'Aceptable', N'Aceptable', NULL),
    (30, 15, N'Buen estado', N'Buen estado', NULL),
    (12, 10, N'Aceptable', N'Aceptable', NULL),
    (8,  6,  N'Nuevo', N'Nuevo', NULL),
    (23, 8,  N'Aceptable', N'Aceptable', NULL),
    (3,  19, N'Buen estado', N'Buen estado', NULL),
    (10, 17, N'Buen estado', N'Buen estado', NULL),
    (16, 11, N'Buen estado', N'Buen estado', NULL),
    (24, 15, N'Buen estado', N'Buen estado', NULL),   -- 41 a 50: ejemplares sin publicar
    (10, 20, N'Buen estado', N'Buen estado', NULL),
    (3,  4,  N'Buen estado', N'Buen estado', NULL),
    (17, 14, N'Buen estado', N'Buen estado', NULL),
    (6,  11, N'Buen estado', N'Buen estado', NULL),
    (5,  16, N'Buen estado', N'Buen estado', NULL),
    (14, 2,  N'Buen estado', N'Buen estado', NULL),
    (22, 3,  N'Buen estado', N'Buen estado', NULL),
    (25, 18, N'Buen estado', N'Buen estado', NULL),
    (19, 11, N'Buen estado', N'Buen estado', NULL),
    -- 51 a 54: ejemplares de ediciones especiales (51 y 52 se publican, 53 y 54 no)
    (31, 5,  N'Nuevo', N'Nuevo', NULL),         -- 51 Elden Ring PS5 Coleccionista
    (32, 9,  N'Como nuevo', N'Como nuevo', NULL),    -- 52 Cyberpunk 2077 PS5 Definitiva
    (33, 14, N'Buen estado', N'Buen estado', NULL),   -- 53 Skyrim Switch Aniversario
    (34, 3,  N'Nuevo', N'Nuevo', NULL);         -- 54 God of War Ragnarök PS5 Coleccionista

-- Publicaciones de los ejemplares 1 a 40 y 51 a 52
INSERT INTO Publicacion (ID_inventario, Precio) VALUES
    (1,  170000.00), (2,  215000.00), (3,  205000.00), (4,  100000.00),
    (5,  210000.00), (6,   90000.00), (7,  240000.00), (8,  150000.00),
    (9,  170000.00), (10, 245000.00), (11, 110000.00), (12,  95000.00),
    (13,  75000.00), (14, 150000.00), (15, 135000.00), (16, 185000.00),
    (17,  85000.00), (18, 200000.00), (19, 235000.00), (20, 100000.00),
    (21, 235000.00), (22, 190000.00), (23, 180000.00), (24, 105000.00),
    (25, 135000.00), (26, 130000.00), (27,  60000.00), (28, 245000.00),
    (29, 140000.00), (30,  60000.00), (31, 190000.00), (32, 175000.00),
    (33, 240000.00), (34, 100000.00), (35, 255000.00), (36, 245000.00),
    (37, 185000.00), (38, 185000.00), (39,  90000.00), (40, 260000.00),
    (51, 650000.00), (52, 180000.00);

-- Fotografías de prueba: de 1 a 3 por publicación (Orden 1 = principal)
INSERT INTO FotografiaPublicacion (ID_publicacion, Ruta_fotografia, Orden)
SELECT p.ID_publicacion,
       N'/uploads/publicaciones/' + CAST(p.ID_publicacion AS NVARCHAR(10))
         + N'/foto' + CAST(o.n AS NVARCHAR(2)) + N'.jpg',
       o.n
FROM Publicacion p
JOIN (VALUES (1), (2), (3)) AS o(n)
  ON o.n <= 1 + (p.ID_publicacion % 3);

-- Ventas
-- Forma de entrega: las ventas 2, 7, 10, 13 y 15 son en persona (sin envío)
INSERT INTO Transaccion (ID_publicacion, ID_comprador, precio_final, Fecha_transaccion, Forma_entrega, Fecha_entrega_persona) VALUES
    (1,  19, 170000.00, '2026-08-05 10:00:00', N'Transportadora', NULL),
    (2,  13, 215000.00, '2026-08-09 10:00:00', N'En persona', '2026-08-10 16:00:00'),
    (4,   3, 100000.00, '2026-08-13 10:00:00', N'Transportadora', NULL),
    (5,  14, 210000.00, '2026-08-17 10:00:00', N'Transportadora', NULL),
    (8,   9, 145000.00, '2026-08-21 10:00:00', N'Transportadora', NULL),
    (11, 12, 100000.00, '2026-08-25 10:00:00', N'Transportadora', NULL),
    (13,  4,  75000.00, '2026-08-29 10:00:00', N'En persona', '2026-08-30 16:00:00'),
    (14, 16, 140000.00, '2026-09-02 10:00:00', N'Transportadora', NULL),
    (19, 17, 225000.00, '2026-09-06 10:00:00', N'Transportadora', NULL),
    (20, 10, 100000.00, '2026-09-10 10:00:00', N'En persona', '2026-09-11 16:00:00'),
    (22,  5, 190000.00, '2026-09-14 10:00:00', N'Transportadora', NULL),
    (26, 12, 125000.00, '2026-09-18 10:00:00', N'Transportadora', NULL),
    (29, 17, 140000.00, '2026-09-22 10:00:00', N'En persona', '2026-09-23 16:00:00'),
    (37, 18, 185000.00, '2026-09-26 10:00:00', N'Transportadora', NULL),
    (39,  7,  85000.00, '2026-09-30 10:00:00', N'En persona', '2026-10-01 16:00:00');

-- Transportadora: 1=TCC, 2=Interrapidísimo, 3=Coordinadora, 4=Servientrega, 5=Envía
-- Solo las ventas por transportadora tienen envío (transacciones 1, 3, 4, 5, 6, 8, 9, 11, 12 y 14)
INSERT INTO Envio (ID_transaccion, ID_direccion, ID_transportadora, Numero_guia, Estado_envio) VALUES
    (1,  19, 1, N'PF202600001', N'Entregado'),
    (3,  22, 2, N'PF202600003', N'Pendiente'),
    (4,  14, 1, N'PF202600004', N'Entregado'),
    (5,   9, 3, N'PF202600005', N'En tránsito'),
    (6,  12, 4, N'PF202600006', N'Pendiente'),
    (8,  16, 2, N'PF202600008', N'En tránsito'),
    (9,  17, 5, N'PF202600009', N'Entregado'),
    (11,  5, 2, N'PF202600011', N'En tránsito'),
    (12, 12, 2, N'PF202600012', N'Entregado'),
    (14, 18, 2, N'PF202600014', N'En tránsito');

INSERT INTO Resena (ID_publicacion, ID_usuario, Calificacion, Comentario) VALUES
    (1,  19, 5, N'Llegó en perfecto estado, tal como se describía.'),
    (2,  13, 5, N'Excelente vendedor, muy recomendado.'),
    (4,   3, 4, N'El empaque venía algo golpeado, pero el disco perfecto.'),
    (5,  14, 5, N'Envío rápido y el juego funciona sin problemas.'),
    (8,   9, 4, N'Buen precio, volvería a comprar.'),
    (11, 12, 3, N'La caja tenía detalles menores de uso.'),
    (13,  4, 5, N'Todo bien, comunicación clara con el vendedor.'),
    (14, 16, 4, N'Cumplió con lo prometido en la publicación.'),
    (19, 17, 5, N'Muy buena atención, entrega en dos días.'),
    (20, 10, 5, N'El juego llegó sellado, impecable.');
GO

-- ------------------------------------------------------------
-- 8.4 CONSULTAS SQL DE DEMOSTRACIÓN
-- ------------------------------------------------------------

-- @Q1 | SELECT | Catálogo de videojuegos (primeros 8 títulos)
SELECT TOP (8) ID_videojuego, Titulo, ID_clasificacion
FROM Videojuego
ORDER BY ID_videojuego;

-- @Q2 | WHERE | Publicaciones nuevas con precio menor a $250.000
SELECT p.ID_publicacion, v.Titulo, p.Precio, i.Estado_fisico
FROM Publicacion p
JOIN Inventario  i ON i.ID_inventario = p.ID_inventario
JOIN Edicion     e ON e.ID_edicion    = i.ID_edicion
JOIN Videojuego  v ON v.ID_videojuego = e.ID_videojuego
WHERE i.Estado_fisico = N'Nuevo' AND p.Precio < 250000;

-- @Q3 | ORDER BY | Las 5 publicaciones más costosas
SELECT TOP (5) p.ID_publicacion, v.Titulo, p.Precio
FROM Publicacion p
JOIN Inventario  i ON i.ID_inventario = p.ID_inventario
JOIN Edicion     e ON e.ID_edicion    = i.ID_edicion
JOIN Videojuego  v ON v.ID_videojuego = e.ID_videojuego
ORDER BY p.Precio DESC;

-- @Q4 | Funciones de agregación | Resumen de ventas
SELECT COUNT(*)          AS ventas,
       SUM(precio_final) AS total_vendido,
       AVG(precio_final) AS promedio,
       MIN(precio_final) AS minimo,
       MAX(precio_final) AS maximo
FROM Transaccion;

-- @Q5 | GROUP BY + HAVING | Ediciones por plataforma (con 5 o más títulos)
SELECT pl.Nombre AS Plataforma, COUNT(DISTINCT e.ID_videojuego) AS titulos
FROM Edicion e
JOIN Plataforma pl ON pl.ID_plataforma = e.ID_plataforma
GROUP BY pl.Nombre
HAVING COUNT(DISTINCT e.ID_videojuego) >= 5
ORDER BY titulos DESC;

-- @Q6 | INNER JOIN | Publicaciones con título, plataforma y vendedor
SELECT TOP (6) p.ID_publicacion, LEFT(v.Titulo, 28) AS Titulo, te.Nombre AS Edicion,
       pl.Nombre AS Plataforma, u.nombre AS Vendedor, p.Precio
FROM Publicacion p
JOIN Inventario  i  ON i.ID_inventario  = p.ID_inventario
JOIN Edicion     e  ON e.ID_edicion     = i.ID_edicion
JOIN Videojuego  v  ON v.ID_videojuego  = e.ID_videojuego
JOIN TipoEdicion te ON te.ID_tipo_edicion = e.ID_tipo_edicion
JOIN Plataforma  pl ON pl.ID_plataforma = e.ID_plataforma
JOIN Usuario     u  ON u.ID_usuario     = i.ID_usuario
ORDER BY p.ID_publicacion;

-- @Q7 | LEFT JOIN | Usuarios y cantidad de ejemplares en su inventario
SELECT TOP (6) u.nombre, COUNT(i.ID_inventario) AS ejemplares
FROM Usuario u
LEFT JOIN Inventario i ON i.ID_usuario = u.ID_usuario
GROUP BY u.ID_usuario, u.nombre
ORDER BY ejemplares ASC, u.nombre;

-- @Q8 | Varias tablas (9) + LEFT JOIN | Detalle de ventas: juego, comprador, vendedor y envío
--      (las ventas en persona no tienen envío: sus campos de envío salen en NULL)
SELECT TOP (6) t.ID_transaccion, LEFT(v.Titulo, 22) AS Titulo,
       LEFT(c.nombre, CHARINDEX(' ', c.nombre + ' ') - 1) AS Comprador,
       LEFT(s.nombre, CHARINDEX(' ', s.nombre + ' ') - 1) AS Vendedor,
       t.precio_final, t.Forma_entrega, ci.Nombre AS Ciudad, tr.Nombre AS Transportadora, en.Estado_envio
FROM Transaccion t
JOIN Publicacion    p  ON p.ID_publicacion    = t.ID_publicacion
JOIN Inventario     i  ON i.ID_inventario     = p.ID_inventario
JOIN Edicion        e  ON e.ID_edicion        = i.ID_edicion
JOIN Videojuego     v  ON v.ID_videojuego     = e.ID_videojuego
JOIN Usuario        c  ON c.ID_usuario        = t.ID_comprador
JOIN Usuario        s  ON s.ID_usuario        = i.ID_usuario
LEFT JOIN Envio          en ON en.ID_transaccion   = t.ID_transaccion
LEFT JOIN Direccion      d  ON d.ID_direccion      = en.ID_direccion
LEFT JOIN Ciudad         ci ON ci.ID_ciudad        = d.ID_ciudad
LEFT JOIN Transportadora tr ON tr.ID_transportadora = en.ID_transportadora
ORDER BY t.ID_transaccion;

-- @Q9 | JOIN + GROUP BY | Ingresos por género
SELECT g.Nombre AS Genero, COUNT(*) AS ventas, SUM(t.precio_final) AS ingresos
FROM Transaccion t
JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
JOIN Edicion     e ON e.ID_edicion     = i.ID_edicion
JOIN Videojuego  v ON v.ID_videojuego  = e.ID_videojuego
JOIN Genero      g ON g.ID_genero      = v.ID_genero
GROUP BY g.Nombre
ORDER BY ingresos DESC;

-- @Q10 | Subconsulta | Reseñas con calificación superior al promedio general
SELECT TOP (5) r.ID_resena, LEFT(v.Titulo, 24) AS Titulo, r.Calificacion,
       LEFT(r.Comentario, 38) AS Comentario
FROM Resena r
JOIN Publicacion p ON p.ID_publicacion = r.ID_publicacion
JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
JOIN Edicion     e ON e.ID_edicion     = i.ID_edicion
JOIN Videojuego  v ON v.ID_videojuego  = e.ID_videojuego
WHERE r.Calificacion > (SELECT AVG(CAST(Calificacion AS DECIMAL(5,2))) FROM Resena)
ORDER BY r.Calificacion DESC, r.ID_resena;

-- @Q11 | Función de ventana | Ranking de vendedores por ingresos
SELECT TOP (5) RANK() OVER (ORDER BY SUM(t.precio_final) DESC) AS posicion,
       s.nombre AS Vendedor, COUNT(*) AS ventas, SUM(t.precio_final) AS ingresos
FROM Transaccion t
JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
JOIN Usuario     s ON s.ID_usuario     = i.ID_usuario
GROUP BY s.ID_usuario, s.nombre
ORDER BY posicion;

-- @Q12 | Vista | Catálogo público ordenado por precio (5 más baratos)
SELECT TOP (5) ID_publicacion, LEFT(Titulo, 30) AS Titulo, Tipo_edicion, Plataforma,
       Estado_fisico, Estado_caja, Cantidad_fotos, Precio
FROM vw_catalogo_publicaciones
ORDER BY Precio;

-- @Q13 | Vista | Ejemplares por estado calculado (Disponible, Publicado, Vendido)
SELECT Estado, COUNT(*) AS ejemplares
FROM vw_estado_inventario
GROUP BY Estado
ORDER BY ejemplares DESC;
GO

-- ===============================================================================================================================================================================

-- ------------------------------------------------------------
-- 10. AFINAMIENTO: ESTRATEGIA IMPLEMENTADA (ÍNDICES)
-- ------------------------------------------------------------
-- Índices de apoyo sobre las columnas más filtradas del esquema real
-- (los de llaves foráneas ya se crearon arriba).
USE phyfo;
GO
CREATE INDEX idx_publicacion_precio ON Publicacion (Precio);
CREATE INDEX idx_inventario_estado_fisico ON Inventario (Estado_fisico);
CREATE INDEX idx_envio_estado       ON Envio       (Estado_envio);
UPDATE STATISTICS Publicacion;
UPDATE STATISTICS Inventario;
UPDATE STATISTICS Envio;
GO

-- Prueba de carga: base aparte con 300.000 publicaciones sintéticas,
-- para medir el efecto real del índice (con 40 filas no se aprecia).
USE master;
GO
IF DB_ID(N'phyfo_afinamiento') IS NOT NULL
BEGIN
    ALTER DATABASE phyfo_afinamiento SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE phyfo_afinamiento;
END;
GO
CREATE DATABASE phyfo_afinamiento;
GO
USE phyfo_afinamiento;
GO

-- Tabla plana A PROPÓSITO: solo sirve para medir el efecto del índice con
-- volumen. No forma parte del modelo normalizado de phyfo (allí el vendedor,
-- la edición y el estado físico viven en Inventario).
CREATE TABLE Publicacion_carga (
    ID_publicacion      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ID_usuario_vendedor INT NOT NULL,
    ID_videojuego       INT NOT NULL,
    Precio              DECIMAL(10,2) NOT NULL,
    Estado_fisico       NVARCHAR(45) NOT NULL
);
GO

INSERT INTO Publicacion_carga (ID_usuario_vendedor, ID_videojuego, Precio, Estado_fisico)
SELECT 1 + (n.i % 20),
       1 + (n.i % 30),
       50000 + ((n.i * 7919) % 250000),
       CHOOSE(1 + (n.i % 4), N'Nuevo', N'Como nuevo', N'Buen estado', N'Aceptable')
FROM (SELECT TOP (300000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
      FROM sys.all_objects a CROSS JOIN sys.all_objects b) AS n;
GO

-- Para ver el plan: Ctrl+M (Incluir plan de ejecución real) antes de ejecutar.
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- ANTES: sin índice (recorrido completo de la tabla: Clustered Index Scan)
SELECT ID_publicacion, Precio
FROM Publicacion_carga
WHERE Estado_fisico = N'Nuevo' AND Precio BETWEEN 100000 AND 120000
ORDER BY Precio;
GO

-- Estrategia: índice compuesto (columna de igualdad primero, luego rango/orden)
CREATE INDEX idx_carga_estado_precio ON Publicacion_carga (Estado_fisico, Precio);
GO

-- DESPUÉS: con índice (Index Seek por rango, cubierto por el índice y sin Sort)
SELECT ID_publicacion, Precio
FROM Publicacion_carga
WHERE Estado_fisico = N'Nuevo' AND Precio BETWEEN 100000 AND 120000
ORDER BY Precio;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
USE phyfo;
GO
