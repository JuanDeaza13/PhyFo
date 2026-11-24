'use strict';
// PHY-FO · servidor de la aplicación web (Node.js + Express + mssql + dotenv).
// Toda la lógica de negocio vive en la base de datos (restricciones, triggers y
// procedimientos); este servidor solo recibe las peticiones, usa consultas
// parametrizadas y se conecta con la cuenta de cada rol (mínimo privilegio).
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const sql = require('mssql');

const PUERTO = parseInt(process.env.PORT || '3000', 10);
const CARPETA_FOTOS = path.join(__dirname, 'public', 'uploads');
fs.mkdirSync(CARPETA_FOTOS, { recursive: true });
const ADMINS = (process.env.ADMIN_CORREOS || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

/* ---------------- conexiones: una por rol de la base de datos ---------------- */
function configuracion(usuario, clave) {
  const cfg = {
    server: process.env.DB_SERVER || 'localhost',
    database: process.env.DB_NAME || 'phyfo',
    user: usuario,
    password: clave,
    options: { encrypt: true, trustServerCertificate: true },
    pool: { max: 5, min: 0, idleTimeoutMillis: 30000 }
  };
  if (process.env.DB_INSTANCE) cfg.options.instanceName = process.env.DB_INSTANCE;
  else cfg.port = parseInt(process.env.DB_PORT || '1433', 10);
  return cfg;
}
const pools = {};
async function conectar() {
  const cuentas = {
    publico: ['DB_PUBLICO_USER', 'DB_PUBLICO_PASS'],
    app: ['DB_APP_USER', 'DB_APP_PASS'],
    admin: ['DB_ADMIN_USER', 'DB_ADMIN_PASS']
  };
  for (const [rol, [u, p]] of Object.entries(cuentas)) {
    if (!process.env[u] || !process.env[p]) throw new Error('Falta ' + u + ' o ' + p + ' en el archivo .env');
    pools[rol] = await new sql.ConnectionPool(configuracion(process.env[u], process.env[p])).connect();
  }
}
// Ejecuta una consulta parametrizada. params: { nombre: [tipoSql, valor] }
async function consulta(rol, texto, params) {
  const r = pools[rol].request();
  for (const [nombre, [tipo, valor]] of Object.entries(params || {})) r.input(nombre, tipo, valor);
  return (await r.query(texto)).recordset;
}

/* ---------------- sesiones (en memoria, cookie HttpOnly) ---------------- */
const sesiones = new Map();
function leerCookie(req, nombre) {
  const c = (req.headers.cookie || '').split(';').map((s) => s.trim());
  const par = c.find((x) => x.startsWith(nombre + '='));
  return par ? par.slice(nombre.length + 1) : null;
}
function abrirSesion(res, datos) {
  const token = crypto.randomBytes(24).toString('hex');
  sesiones.set(token, datos);
  res.setHeader('Set-Cookie', 'phyfo_sid=' + token + '; HttpOnly; SameSite=Lax; Path=/; Max-Age=28800');
}
function cerrarSesion(req, res) {
  const t = leerCookie(req, 'phyfo_sid');
  if (t) sesiones.delete(t);
  res.setHeader('Set-Cookie', 'phyfo_sid=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0');
}
const esAdmin = (u) => ADMINS.includes(String(u.correo).toLowerCase());

/* ---------------- ayudas ---------------- */
function errorUsuario(mensaje, estado) {
  const e = new Error(mensaje);
  e.usuario = true;
  e.estado = estado || 400;
  return e;
}
// Traduce los errores de SQL Server (restricciones, triggers y procedimientos).
function fallo(res, e) {
  if (e.usuario) return res.status(e.estado).json({ error: e.message });
  const n = e.number;
  if (n >= 50000) return res.status(400).json({ error: e.message });   // reglas de triggers y procedimientos
  if (n === 2627 || n === 2601) return res.status(409).json({ error: 'Ya existe un registro con esos datos.' });
  if (n === 547) return res.status(400).json({ error: 'Los datos no cumplen las reglas de la base de datos.' });
  if (n === 229 || n === 230 || n === 262) return res.status(403).json({ error: 'No tienes permiso para esa operación.' });
  console.error(e);
  return res.status(500).json({ error: 'Error del servidor.' });
}
const h = (fn) => (req, res) => fn(req, res).catch((e) => fallo(res, e));
const entero = (v) => { const n = parseInt(v, 10); return Number.isInteger(n) ? n : null; };

function conSesion(req, res, next) {
  const t = leerCookie(req, 'phyfo_sid');
  const u = t ? sesiones.get(t) : null;
  if (!u) return res.status(401).json({ error: 'Inicia sesión para continuar.' });
  req.usuario = u;
  next();
}
function soloAdmin(req, res, next) {
  conSesion(req, res, () => {
    if (!esAdmin(req.usuario)) return res.status(403).json({ error: 'Acceso restringido al administrador.' });
    next();
  });
}

// Intentos fallidos de inicio de sesión (bloqueo corto contra fuerza bruta)
const fallidos = new Map();
function bloqueado(correo) { const f = fallidos.get(correo); return f && f.n >= 5 && Date.now() < f.hasta; }
function registrarFallo(correo) {
  const f = fallidos.get(correo) || { n: 0, hasta: 0 };
  f.n += 1; f.hasta = Date.now() + 60000; fallidos.set(correo, f);
}

/* ---------------- fotografías ---------------- */
const EXT = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };
function firmaValida(tipo, b) {
  if (tipo === 'image/jpeg') return b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff;
  if (tipo === 'image/png') return b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47;
  return b.toString('ascii', 0, 4) === 'RIFF' && b.toString('ascii', 8, 12) === 'WEBP';
}
function guardarFotos(lista) {
  const rutas = [], archivos = [];
  if (lista !== undefined && !Array.isArray(lista)) throw errorUsuario('Fotografías no válidas.');
  if ((lista || []).length > 10) throw errorUsuario('Una publicación admite como máximo 10 fotografías.');
  try {
    for (const f of lista || []) {
      const m = /^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/.exec(typeof f === 'string' ? f : '');
      if (!m) throw errorUsuario('Formato de imagen no válido (jpg, png o webp).');
      const buf = Buffer.from(m[2], 'base64');
      if (buf.length > 3 * 1024 * 1024) throw errorUsuario('Cada fotografía debe pesar menos de 3 MB.');
      if (!firmaValida(m[1], buf)) throw errorUsuario('El archivo no es una imagen válida.');
      const nombre = crypto.randomBytes(12).toString('hex') + EXT[m[1]];
      const ruta = path.join(CARPETA_FOTOS, nombre);
      fs.writeFileSync(ruta, buf);
      archivos.push(ruta); rutas.push('/uploads/' + nombre);
    }
  } catch (e) { archivos.forEach((a) => fs.unlink(a, () => {})); throw e; }
  return { rutas, archivos };
}

/* ---------------- aplicación ---------------- */
const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '40mb' }));
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  // Mitiga CSRF: las peticiones que modifican datos deben ser JSON (no formularios de otros sitios)
  if (req.method === 'POST' && !req.is('application/json')) return res.status(415).json({ error: 'Formato no admitido.' });
  next();
});
app.use(express.static(path.join(__dirname, 'public')));

/* ---- sesión y cuentas (RF-01) ---- */
app.get('/api/yo', (req, res) => {
  const t = leerCookie(req, 'phyfo_sid');
  const u = t ? sesiones.get(t) : null;
  res.json({ usuario: u ? { id: u.uid, nombre: u.nombre, correo: u.correo, admin: esAdmin(u) } : null });
});

app.post('/api/registro', h(async (req, res) => {
  const { nombre, correo, contrasena } = req.body || {};
  if (!nombre || !String(nombre).trim() || !correo || !contrasena) throw errorUsuario('Escribe tu nombre, un correo y una contraseña.');
  try {
    const r = await pools.app.request()
      .input('p_nombre', sql.NVarChar(100), String(nombre).trim())
      .input('p_correo', sql.NVarChar(100), String(correo).trim())
      .input('p_contrasena', sql.NVarChar(100), String(contrasena))
      .output('p_id', sql.Int)
      .execute('sp_registrar_usuario');
    const datos = { uid: r.output.p_id, nombre: String(nombre).trim(), correo: String(correo).trim() };
    abrirSesion(res, datos);
    res.json({ usuario: { id: datos.uid, nombre: datos.nombre, correo: datos.correo, admin: esAdmin(datos) } });
  } catch (e) {
    if (e.number === 2627 || e.number === 2601) throw errorUsuario('Ese correo ya está registrado.', 409);
    if (e.number === 547) throw errorUsuario('El correo no tiene un formato válido.');
    throw e;
  }
}));

app.post('/api/login', h(async (req, res) => {
  const correo = String((req.body || {}).correo || '').trim();
  const contrasena = String((req.body || {}).contrasena || '');
  if (bloqueado(correo.toLowerCase())) throw errorUsuario('Demasiados intentos. Espera un minuto.', 429);
  const r = await pools.app.request()
    .input('p_correo', sql.NVarChar(100), correo)
    .input('p_contrasena', sql.NVarChar(100), contrasena)
    .execute('sp_validar_login');
  const fila = r.recordset[0];
  if (!fila) { registrarFallo(correo.toLowerCase()); throw errorUsuario('Correo o contraseña incorrectos.', 401); }
  fallidos.delete(correo.toLowerCase());
  const datos = { uid: fila.ID_usuario, nombre: fila.nombre, correo };
  abrirSesion(res, datos);
  res.json({ usuario: { id: datos.uid, nombre: datos.nombre, correo, admin: esAdmin(datos) } });
}));

app.post('/api/logout', (req, res) => { cerrarSesion(req, res); res.json({ ok: true }); });

/* ---- datos de apoyo para formularios ---- */
app.get('/api/meta', h(async (req, res) => {
  const [plataformas, transportadoras, ciudades, ediciones] = await Promise.all([
    consulta('app', 'SELECT Nombre AS nombre FROM Plataforma ORDER BY ID_plataforma'),
    consulta('app', 'SELECT ID_transportadora AS id, Nombre AS nombre FROM Transportadora ORDER BY Nombre'),
    consulta('app', 'SELECT c.ID_ciudad AS id, c.Nombre AS ciudad, d.Nombre AS departamento FROM Ciudad c JOIN Departamento d ON d.ID_departamento = c.ID_departamento ORDER BY c.Nombre'),
    consulta('app', `SELECT e.ID_edicion AS id, v.Titulo AS titulo, pl.Nombre AS plataforma, te.Nombre AS tipo
                     FROM Edicion e
                     JOIN Videojuego  v  ON v.ID_videojuego    = e.ID_videojuego
                     JOIN Plataforma  pl ON pl.ID_plataforma   = e.ID_plataforma
                     JOIN TipoEdicion te ON te.ID_tipo_edicion = e.ID_tipo_edicion
                     ORDER BY v.Titulo, pl.Nombre, te.Nombre`)
  ]);
  res.json({ plataformas: plataformas.map((x) => x.nombre), transportadoras, ciudades, ediciones });
}));

/* ---- catálogo público (RF-06): usa la cuenta de consulta pública, solo la vista ---- */
app.get('/api/catalogo', h(async (req, res) => {
  const { q, plataforma, estado, max, orden } = req.query;
  const donde = [], params = {};
  if (q) { donde.push('Titulo LIKE @q'); params.q = [sql.NVarChar(100), '%' + String(q).slice(0, 100) + '%']; }
  if (plataforma) { donde.push('Plataforma = @pl'); params.pl = [sql.NVarChar(45), String(plataforma)]; }
  if (estado) { donde.push('Estado_fisico = @es'); params.es = [sql.NVarChar(45), String(estado)]; }
  if (max !== undefined && max !== '' && !isNaN(Number(max))) { donde.push('Precio <= @mx'); params.mx = [sql.Decimal(10, 2), Number(max)]; }
  const orderBy = orden === 'pd' ? 'Precio DESC' : orden === 't' ? 'Titulo, Precio' : 'Precio ASC';   // lista blanca
  const filas = await consulta('publico',
    `SELECT ID_publicacion, Titulo, Tipo_edicion, Plataforma, Estado_fisico, Estado_caja, Precio, Vendedor, Cantidad_fotos, Foto_principal
       FROM vw_catalogo_publicaciones ${donde.length ? 'WHERE ' + donde.join(' AND ') : ''} ORDER BY ${orderBy}`, params);
  res.json(filas);
}));

/* ---- detalle de una publicación (RF-06) y reseñas del vendedor (RF-09) ---- */
app.get('/api/publicacion/:id', h(async (req, res) => {
  const id = entero(req.params.id);
  if (id === null) throw errorUsuario('Publicación no válida.');
  const pub = await consulta('app', `
    SELECT p.ID_publicacion AS id, p.Precio AS precio, v.Titulo AS titulo, v.Anio_lanzamiento AS anio,
           d.Nombre AS desarrollador, g.Nombre AS genero, c.Codigo AS clasificacion, pl.Nombre AS plataforma,
           te.Nombre AS edicion, i.Estado_fisico AS fisico, i.Estado_caja AS caja, i.Observaciones AS obs,
           u.ID_usuario AS idVendedor, u.nombre AS vendedor,
           CASE WHEN EXISTS (SELECT 1 FROM Transaccion t WHERE t.ID_publicacion = p.ID_publicacion) THEN 1 ELSE 0 END AS vendida
      FROM Publicacion p
      JOIN Inventario    i  ON i.ID_inventario    = p.ID_inventario
      JOIN Edicion       e  ON e.ID_edicion       = i.ID_edicion
      JOIN Videojuego    v  ON v.ID_videojuego    = e.ID_videojuego
      JOIN Desarrollador d  ON d.ID_desarrollador = v.ID_desarrollador
      JOIN Genero        g  ON g.ID_genero        = v.ID_genero
      JOIN Clasificacion c  ON c.ID_clasificacion = v.ID_clasificacion
      JOIN Plataforma    pl ON pl.ID_plataforma   = e.ID_plataforma
      JOIN TipoEdicion   te ON te.ID_tipo_edicion = e.ID_tipo_edicion
      JOIN Usuario       u  ON u.ID_usuario       = i.ID_usuario
     WHERE p.ID_publicacion = @id`, { id: [sql.Int, id] });
  if (!pub.length) throw errorUsuario('Publicación no encontrada.', 404);
  const v = pub[0];
  const [fotos, ciudad, resenas] = await Promise.all([
    consulta('app', 'SELECT Ruta_fotografia AS ruta FROM FotografiaPublicacion WHERE ID_publicacion = @id ORDER BY Orden', { id: [sql.Int, id] }),
    consulta('app', `SELECT TOP (1) c.Nombre AS ciudad FROM Direccion d JOIN Ciudad c ON c.ID_ciudad = d.ID_ciudad
                      WHERE d.ID_usuario = @v ORDER BY d.ID_direccion`, { v: [sql.Int, v.idVendedor] }),
    consulta('app', `SELECT vj.Titulo AS juego, r.Calificacion AS calificacion, r.Comentario AS comentario, uc.nombre AS comprador
                       FROM Resena r
                       JOIN Publicacion p2 ON p2.ID_publicacion = r.ID_publicacion
                       JOIN Inventario  i2 ON i2.ID_inventario  = p2.ID_inventario
                       JOIN Edicion     e2 ON e2.ID_edicion     = i2.ID_edicion
                       JOIN Videojuego  vj ON vj.ID_videojuego  = e2.ID_videojuego
                       JOIN Usuario     uc ON uc.ID_usuario     = r.ID_usuario
                      WHERE i2.ID_usuario = @v ORDER BY r.ID_resena DESC`, { v: [sql.Int, v.idVendedor] })
  ]);
  const promedio = resenas.length ? resenas.reduce((a, r) => a + r.calificacion, 0) / resenas.length : null;
  res.json({ pub: v, fotos: fotos.map((f) => f.ruta), ciudad: ciudad.length ? ciudad[0].ciudad : '', promedio, resenas });
}));

/* ---- mi cuenta: ejemplares, direcciones, compras y ventas (RF-02, RF-04, RF-07..RF-09) ---- */
app.get('/api/mis/ejemplares', conSesion, h(async (req, res) => {
  res.json(await consulta('app', `
    SELECT i.ID_inventario AS id, v.Titulo AS titulo, pl.Nombre AS plataforma, te.Nombre AS edicion,
           i.Estado_fisico AS fisico, i.Estado_caja AS caja, i.Observaciones AS obs, s.Estado AS estado,
           p.ID_publicacion AS idPublicacion
      FROM Inventario i
      JOIN vw_estado_inventario s ON s.ID_inventario = i.ID_inventario
      JOIN Edicion     e  ON e.ID_edicion     = i.ID_edicion
      JOIN Videojuego  v  ON v.ID_videojuego  = e.ID_videojuego
      JOIN Plataforma  pl ON pl.ID_plataforma = e.ID_plataforma
      JOIN TipoEdicion te ON te.ID_tipo_edicion = e.ID_tipo_edicion
      LEFT JOIN Publicacion p ON p.ID_inventario = i.ID_inventario
     WHERE i.ID_usuario = @u ORDER BY i.ID_inventario`, { u: [sql.Int, req.usuario.uid] }));
}));

app.get('/api/mis/direcciones', conSesion, h(async (req, res) => {
  res.json(await consulta('app', `
    SELECT d.ID_direccion AS id, c.Nombre AS ciudad, dp.Nombre AS departamento, d.Direccion_detalle AS detalle
      FROM Direccion d JOIN Ciudad c ON c.ID_ciudad = d.ID_ciudad JOIN Departamento dp ON dp.ID_departamento = c.ID_departamento
     WHERE d.ID_usuario = @u ORDER BY d.ID_direccion`, { u: [sql.Int, req.usuario.uid] }));
}));

app.post('/api/mis/direcciones', conSesion, h(async (req, res) => {
  const idCiudad = entero((req.body || {}).idCiudad);
  const detalle = String((req.body || {}).detalle || '').trim();
  if (idCiudad === null) throw errorUsuario('Elige una ciudad.');
  if (!detalle) throw errorUsuario('El detalle de la dirección no puede estar vacío.');
  await pools.app.request().input('u', sql.Int, req.usuario.uid).input('c', sql.Int, idCiudad)
    .input('d', sql.NVarChar(150), detalle.slice(0, 150))
    .query('INSERT INTO Direccion (ID_usuario, ID_ciudad, Direccion_detalle) VALUES (@u, @c, @d)');
  res.json({ ok: true });
}));

const BASE_VENTAS = `
  FROM Transaccion t
  JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
  JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
  JOIN Edicion     e ON e.ID_edicion     = i.ID_edicion
  JOIN Videojuego  v ON v.ID_videojuego  = e.ID_videojuego
  JOIN Usuario     us ON us.ID_usuario   = i.ID_usuario
  JOIN Usuario     uc ON uc.ID_usuario   = t.ID_comprador
  LEFT JOIN Envio en ON en.ID_transaccion = t.ID_transaccion
  LEFT JOIN Transportadora tr ON tr.ID_transportadora = en.ID_transportadora
  LEFT JOIN Resena r ON r.ID_publicacion = p.ID_publicacion AND r.ID_usuario = t.ID_comprador`;
const COLUMNAS_VENTAS = `
  p.ID_publicacion AS idPublicacion, v.Titulo AS titulo, us.nombre AS vendedor, uc.nombre AS comprador,
  p.Precio AS publicado, t.precio_final AS precioFinal, t.Fecha_transaccion AS fecha, t.Forma_entrega AS forma,
  t.Fecha_entrega_persona AS fechaEntrega, tr.Nombre AS transportadora, en.Numero_guia AS guia,
  en.Estado_envio AS estadoEnvio, r.Calificacion AS calificacion, r.Comentario AS comentario`;

app.get('/api/mis/compras', conSesion, h(async (req, res) => {
  res.json(await consulta('app', `SELECT ${COLUMNAS_VENTAS} ${BASE_VENTAS} WHERE t.ID_comprador = @u ORDER BY t.Fecha_transaccion DESC`, { u: [sql.Int, req.usuario.uid] }));
}));
app.get('/api/mis/ventas', conSesion, h(async (req, res) => {
  res.json(await consulta('app', `SELECT ${COLUMNAS_VENTAS} ${BASE_VENTAS} WHERE i.ID_usuario = @u ORDER BY t.Fecha_transaccion DESC`, { u: [sql.Int, req.usuario.uid] }));
}));

/* ---- vender: publicar con fotografías (RF-03, RF-04, RF-05) ---- */
app.post('/api/publicar', conSesion, h(async (req, res) => {
  const b = req.body || {};
  const precio = Number(b.precio);
  if (!(precio > 0)) throw errorUsuario('El precio debe ser mayor que cero.');
  let archivos = [];
  try {
    const guardadas = guardarFotos(b.fotos);
    archivos = guardadas.archivos;
    let idInv = entero(b.idInventario);
    if (b.modo === 'nuevo') {
      if (guardadas.rutas.length === 0) throw errorUsuario('Una publicación debe tener al menos una fotografía.');
      const idEdicion = entero(b.idEdicion);
      if (idEdicion === null) throw errorUsuario('Elige el videojuego y su edición.');
      const r = await pools.app.request()
        .input('ed', sql.Int, idEdicion).input('u', sql.Int, req.usuario.uid)
        .input('f', sql.NVarChar(45), String(b.fisico || '')).input('c', sql.NVarChar(45), String(b.caja || ''))
        .input('o', sql.NVarChar(300), b.obs ? String(b.obs).slice(0, 300) : null)
        .query('INSERT INTO Inventario (ID_edicion, ID_usuario, Estado_fisico, Estado_caja, Observaciones) OUTPUT inserted.ID_inventario AS id VALUES (@ed, @u, @f, @c, @o)');
      idInv = r.recordset[0].id;
    } else {
      // El procedimiento no sabe quién es el usuario: la propiedad del ejemplar se comprueba aquí
      const dueno = await consulta('app', 'SELECT ID_usuario FROM Inventario WHERE ID_inventario = @i', { i: [sql.Int, idInv] });
      if (!dueno.length || dueno[0].ID_usuario !== req.usuario.uid) throw errorUsuario('El ejemplar no existe o no es tuyo.', 403);
    }
    const r = await pools.app.request()
      .input('p_inventario', sql.Int, idInv).input('p_precio', sql.Decimal(10, 2), precio)
      .input('p_fotos', sql.NVarChar(sql.MAX), guardadas.rutas.join('|'))
      .execute('sp_publicar_ejemplar');
    res.json({ idPublicacion: r.recordset[0].ID_publicacion });
  } catch (e) {
    archivos.forEach((a) => fs.unlink(a, () => {}));
    throw e;
  }
}));

/* ---- comprar (RF-07, RF-08): el procedimiento registra la venta completa ---- */
app.post('/api/comprar', conSesion, h(async (req, res) => {
  const b = req.body || {};
  const forma = b.forma === 'Transportadora' ? 'Transportadora' : 'En persona';
  const envio = forma === 'Transportadora';
  await pools.app.request()
    .input('p_publicacion', sql.Int, entero(b.idPublicacion))
    .input('p_comprador', sql.Int, req.usuario.uid)
    .input('p_precio', sql.Decimal(10, 2), Number(b.precioFinal))
    .input('p_direccion', sql.Int, envio ? entero(b.idDireccion) : null)
    .input('p_transportadora', sql.Int, envio ? entero(b.idTransportadora) : null)
    .input('p_guia', sql.NVarChar(30), envio && b.guia ? String(b.guia).trim().slice(0, 30) : null)
    .input('p_forma_entrega', sql.NVarChar(20), forma)
    .execute('sp_registrar_venta');
  res.json({ ok: true });
}));

/* ---- reseñas (RF-09): el trigger exige que quien reseña sea el comprador ---- */
app.post('/api/resenas', conSesion, h(async (req, res) => {
  const b = req.body || {};
  await pools.app.request()
    .input('p', sql.Int, entero(b.idPublicacion)).input('u', sql.Int, req.usuario.uid)
    .input('c', sql.Int, entero(b.calificacion))
    .input('m', sql.NVarChar(100), b.comentario ? String(b.comentario).trim().slice(0, 100) : null)
    .query('INSERT INTO Resena (ID_publicacion, ID_usuario, Calificacion, Comentario) VALUES (@p, @u, @c, @m)');
  res.json({ ok: true });
}));

/* ---- administrador (RF-10): usa la cuenta del rol administrador ---- */
app.get('/api/admin/resumen', soloAdmin, h(async (req, res) => {
  const [kpis, generos, vendedores, usuarios] = await Promise.all([
    consulta('admin', `SELECT COUNT(*) AS ventas, ISNULL(SUM(precio_final), 0) AS total, ISNULL(AVG(precio_final), 0) AS promedio,
                              ISNULL(MIN(precio_final), 0) AS minimo, ISNULL(MAX(precio_final), 0) AS maximo FROM Transaccion`),
    consulta('admin', `SELECT g.Nombre AS genero, COUNT(*) AS ventas, SUM(t.precio_final) AS ingresos
                         FROM Transaccion t
                         JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
                         JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
                         JOIN Edicion     e ON e.ID_edicion     = i.ID_edicion
                         JOIN Videojuego  v ON v.ID_videojuego  = e.ID_videojuego
                         JOIN Genero      g ON g.ID_genero      = v.ID_genero
                        GROUP BY g.Nombre ORDER BY ingresos DESC`),
    consulta('admin', `SELECT TOP (5) u.nombre AS vendedor, COUNT(*) AS ventas, SUM(t.precio_final) AS ingresos
                         FROM Transaccion t
                         JOIN Publicacion p ON p.ID_publicacion = t.ID_publicacion
                         JOIN Inventario  i ON i.ID_inventario  = p.ID_inventario
                         JOIN Usuario     u ON u.ID_usuario     = i.ID_usuario
                        GROUP BY u.nombre ORDER BY ingresos DESC`),
    consulta('admin', `SELECT u.ID_usuario AS id, u.nombre, u.correo,
                              (SELECT TOP (1) c.Nombre FROM Direccion d JOIN Ciudad c ON c.ID_ciudad = d.ID_ciudad
                                WHERE d.ID_usuario = u.ID_usuario ORDER BY d.ID_direccion) AS ciudad,
                              (SELECT COUNT(*) FROM Inventario i WHERE i.ID_usuario = u.ID_usuario) AS ejemplares
                         FROM Usuario u ORDER BY u.ID_usuario`)
  ]);
  res.json({ kpis: kpis[0], generos, vendedores, usuarios });
}));

app.use('/api', (req, res) => res.status(404).json({ error: 'Ruta no encontrada.' }));
app.use((err, req, res, next) => {   // JSON mal formado o cuerpo demasiado grande
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Las fotografías pesan demasiado.' });
  if (err.type === 'entity.parse.failed') return res.status(400).json({ error: 'Petición no válida.' });
  console.error(err);
  res.status(500).json({ error: 'Error del servidor.' });
});

conectar()
  .then(() => app.listen(PUERTO, () => console.log('PHY-FO disponible en http://localhost:' + PUERTO)))
  .catch((e) => { console.error('No se pudo conectar a SQL Server: ' + e.message); process.exit(1); });
