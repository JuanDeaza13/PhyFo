'use strict';
// PHY-FO · interfaz web (HTML, CSS y JavaScript sin bibliotecas externas).
// Todos los datos vienen de la API del servidor, que consulta la base de datos phyfo.
(function () {
  var META = null, ME = null, tab = 'ejemplares', flash = '';
  var ESTADOS = ['Nuevo', 'Como nuevo', 'Buen estado', 'Aceptable'];
  var CAJAS = ['Nuevo', 'Como nuevo', 'Buen estado', 'Aceptable', 'Dañada', 'Sin caja'];
  var COLOR = { 'PlayStation 5': '#1B4FD1', 'PlayStation 4': '#26358F', 'Xbox Series X': '#1F7A33', 'Xbox One': '#4B6B2A', 'Nintendo Switch': '#C8202F' };

  /* ---------- ayudas ---------- */
  function $(s, r) { return (r || document).querySelector(s); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function money(n) { return '$ ' + new Intl.NumberFormat('es-CO').format(n); }
  function fdate(s) { return s ? String(s).slice(0, 10) : ''; }
  function opts(list, sel) { return list.map(function (x) { return '<option' + (x === sel ? ' selected' : '') + '>' + esc(x) + '</option>'; }).join(''); }
  function stars(n) { return '<span class="stars" aria-label="' + n + ' de 5">' + '★★★★★'.slice(0, n) + '☆☆☆☆☆'.slice(0, 5 - n) + '</span>'; }
  function tagEstado(s) { return '<span class="tag ' + (s === 'Disponible' ? 'ok' : s === 'Publicado' ? 'pub' : 'sold') + '">' + esc(s) + '</span>'; }
  function ratingTxt(avg, n) { return n ? '★ ' + avg.toFixed(1).replace('.', ',') + ' (' + n + ')' : 'Sin reseñas'; }
  function head(t, rf) { return '<div class="title"><h1>' + esc(t) + '</h1>' + (rf ? '<span class="rf">' + rf + '</span>' : '') + '</div>'; }
  function say(el, clase, msg) { el.innerHTML = '<div class="note ' + clase + '">' + msg + '</div>'; }
  function cover(titulo, plataforma, ruta, grande) {
    var img = ruta ? '<img src="' + esc(ruta) + '" alt="" onload="this.parentNode.classList.add(\'ok\')" onerror="this.remove()">' : '';
    return '<div class="cover" style="--c:' + (COLOR[plataforma] || '#12275C') + (grande ? ';min-height:200px' : '') + '">' + img +
      '<small>' + esc(plataforma) + '</small><b>' + esc(titulo) + '</b></div>';
  }
  function needLogin(que) {
    return head(que, 'RF-01') + '<div class="box stack"><p>Inicia sesión para continuar.</p><p><a class="btn" href="#ingresar">Iniciar sesión</a></p></div>';
  }
  async function api(url, datos) {
    var o = {};
    if (datos !== undefined) { o.method = 'POST'; o.headers = { 'Content-Type': 'application/json' }; o.body = JSON.stringify(datos); }
    var r = await fetch(url, o);
    var j = await r.json().catch(function () { return {}; });
    if (!r.ok) { var e = new Error(j.error || 'Ocurrió un error.'); e.status = r.status; throw e; }
    return j;
  }
  function leerArchivo(f) {
    return new Promise(function (ok, no) { var r = new FileReader(); r.onload = function () { ok(r.result); }; r.onerror = no; r.readAsDataURL(f); });
  }
  function entregaTxt(t) {
    if (t.forma === 'En persona') return 'En persona · ' + (t.fechaEntrega ? 'entregada ' + fdate(t.fechaEntrega) : 'sin confirmar');
    return t.guia ? esc(t.transportadora) + " · <span class='mono'>" + esc(t.guia) + "</span> · <span class='tag'>" + esc(t.estadoEnvio) + '</span>' : 'Transportadora';
  }

  /* ---------- Catálogo (RF-06) ---------- */
  function viewCatalogo() {
    var h = head('Catálogo de publicaciones', 'RF-06') +
      '<div class="box"><div class="row">' +
      '<div class="field"><label for="fq">Título</label><input id="fq" type="search" placeholder="Ej. Elden Ring"></div>' +
      '<div class="field"><label for="fp">Plataforma</label><select id="fp"><option value="">Todas</option>' + opts(META.plataformas) + '</select></div>' +
      '<div class="field"><label for="fe">Estado físico</label><select id="fe"><option value="">Todos</option>' + opts(ESTADOS) + '</select></div>' +
      '<div class="field"><label for="fm">Precio máximo (COP)</label><input id="fm" type="number" min="0" step="5000" placeholder="Sin límite"></div>' +
      '<div class="field"><label for="fo">Ordenar por</label><select id="fo"><option value="pa">Precio: menor a mayor</option><option value="pd">Precio: mayor a menor</option><option value="t">Título</option></select></div>' +
      '</div></div><p class="small muted" id="cnt" style="margin-top:12px"></p><div class="grid" id="grid"></div>';
    return { html: h, after: function () {
      var espera = null;
      async function draw() {
        var qs = new URLSearchParams({ q: $('#fq').value.trim(), plataforma: $('#fp').value, estado: $('#fe').value, max: $('#fm').value, orden: $('#fo').value });
        try {
          var list = await api('/api/catalogo?' + qs.toString());
          $('#cnt').textContent = list.length + (list.length === 1 ? ' publicación activa' : ' publicaciones activas');
          $('#grid').innerHTML = list.length ? list.map(function (p) {
            return '<a class="card" href="#juego-' + p.ID_publicacion + '">' + cover(p.Titulo, p.Plataforma, p.Foto_principal) +
              '<div class="body"><div class="price">' + money(p.Precio) + '</div>' +
              '<div class="meta"><span class="tag">Disco: ' + esc(p.Estado_fisico) + '</span><span class="tag">Caja: ' + esc(p.Estado_caja) + '</span><span class="tag">' + esc(p.Tipo_edicion) + '</span></div>' +
              '<div class="who">' + esc(p.Vendedor) + ' · ' + p.Cantidad_fotos + (p.Cantidad_fotos === 1 ? ' foto' : ' fotos') + '</div></div></a>';
          }).join('') : '<div class="empty">Ninguna publicación coincide con los filtros.</div>';
        } catch (e) { $('#grid').innerHTML = '<div class="empty">' + esc(e.message) + '</div>'; }
      }
      ['fq', 'fp', 'fe', 'fm', 'fo'].forEach(function (id) {
        $('#' + id).addEventListener('input', function () { clearTimeout(espera); espera = setTimeout(draw, 250); });
      });
      draw();
    } };
  }

  /* ---------- Detalle y compra (RF-06, RF-07, RF-08, RF-09) ---------- */
  async function viewJuego(id) {
    var d;
    try { d = await api('/api/publicacion/' + id); }
    catch (e) { return { html: head('Publicación no encontrada') + '<p><a href="#catalogo">Volver al catálogo</a></p>' }; }
    var p = d.pub, vendida = !!p.vendida;
    var fotos = d.fotos.map(function (r, k) {
      return '<div><img src="' + esc(r) + '" alt="Foto ' + (k + 1) + '" onerror="this.parentNode.textContent=\'Foto ' + (k + 1) + ' (archivo no disponible)\'"></div>';
    }).join('');
    var h = '<p class="small"><a href="#catalogo">← Volver al catálogo</a></p>' + head(p.titulo, 'RF-06') +
      '<div class="two"><div>' + cover(p.titulo, p.plataforma, d.fotos[0], true) + '<div class="photos">' + fotos + '</div></div>' +
      '<dl class="kv" style="margin:0">' +
      '<dt>Precio</dt><dd><b class="mono">' + money(p.precio) + '</b> ' + (vendida ? '<span class="tag sold">Vendida</span>' : '') + '</dd>' +
      '<dt>Plataforma</dt><dd>' + esc(p.plataforma) + '</dd><dt>Edición</dt><dd>' + esc(p.edicion) + '</dd>' +
      '<dt>Desarrollador</dt><dd>' + esc(p.desarrollador) + '</dd><dt>Género</dt><dd>' + esc(p.genero) + '</dd>' +
      '<dt>Clasificación</dt><dd>' + esc(p.clasificacion) + '</dd><dt>Año</dt><dd>' + p.anio + '</dd>' +
      '<dt>Estado del disco</dt><dd>' + esc(p.fisico) + '</dd><dt>Estado de la caja</dt><dd>' + esc(p.caja) + '</dd>' +
      '<dt>Observaciones</dt><dd>' + (p.obs ? esc(p.obs) : '<span class="muted">Ninguna</span>') + '</dd>' +
      '<dt>Vendedor</dt><dd>' + esc(p.vendedor) + (d.ciudad ? ' · ' + esc(d.ciudad) : '') + ' · ' + esc(ratingTxt(d.promedio, d.resenas.length)) + '</dd></dl></div>';

    if (!vendida) {
      h += "<h2>Comprar <span class='rf'>RF-07 · RF-08</span></h2>" +
        '<form class="box stack" id="buy" style="max-width:640px">' +
        '<div class="field"><label for="pf">Precio final pactado (COP)</label><input id="pf" type="number" min="1" step="1" value="' + p.precio + '"></div>' +
        '<div class="field"><span class="lbl">Forma de entrega</span><div class="radios">' +
        '<label><input type="radio" name="fe" value="p" checked> En persona</label><label><input type="radio" name="fe" value="t"> Transportadora</label></div></div>' +
        '<div class="stack" id="trp" hidden>' +
        '<div class="field"><label for="dd">Dirección de envío</label><select id="dd"><option value="">Inicia sesión para ver tus direcciones</option></select></div>' +
        '<div class="row"><div class="field"><label for="dt">Transportadora</label><select id="dt">' +
        META.transportadoras.map(function (t) { return '<option value="' + t.id + '">' + esc(t.nombre) + '</option>'; }).join('') + '</select></div>' +
        '<div class="field"><label for="dg">Número de guía</label><input id="dg" type="text" maxlength="30" placeholder="PF2026…"></div></div></div>' +
        '<p class="small muted" id="enp">En persona: la fecha de confirmación se registra cuando se entrega.</p>' +
        '<div id="res"></div><div><button class="btn" type="submit">Confirmar compra</button></div></form>';
    }
    h += "<h2>Reseñas del vendedor <span class='rf'>RF-09</span></h2>" + (d.resenas.length ?
      '<div class="tw"><table><thead><tr><th>Juego</th><th>Calificación</th><th>Comentario</th><th>Comprador</th></tr></thead><tbody>' +
      d.resenas.map(function (r) { return '<tr><td>' + esc(r.juego) + '</td><td>' + stars(r.calificacion) + '</td><td>' + esc(r.comentario || '') + '</td><td>' + esc(r.comprador) + '</td></tr>'; }).join('') +
      '</tbody></table></div>' : '<p class="muted">Este vendedor aún no tiene reseñas.</p>');

    return { html: h, after: async function () {
      var f = $('#buy'); if (!f) return;
      function sync() { var t = f.elements.fe.value === 't'; $('#trp').hidden = !t; $('#enp').hidden = t; }
      f.addEventListener('change', sync); sync();
      if (ME) {
        try {
          var dirs = await api('/api/mis/direcciones');
          $('#dd').innerHTML = dirs.length ? dirs.map(function (x) { return '<option value="' + x.id + '">' + esc(x.ciudad) + ' · ' + esc(x.detalle) + '</option>'; }).join('') : '<option value="">No tienes direcciones guardadas</option>';
        } catch (e) { /* se muestra al enviar */ }
      }
      f.addEventListener('submit', async function (e) {
        e.preventDefault();
        var r = $('#res'), t = f.elements.fe.value === 't';
        if (!ME) return say(r, 'err', 'Debes iniciar sesión para comprar. <a href="#ingresar">Iniciar sesión</a>');
        try {
          await api('/api/comprar', { idPublicacion: id, precioFinal: parseFloat($('#pf').value), forma: t ? 'Transportadora' : 'En persona',
            idDireccion: $('#dd').value, idTransportadora: $('#dt').value, guia: $('#dg').value });
          flash = 'Compra registrada.'; tab = 'compras'; location.hash = 'cuenta';
        } catch (er) { say(r, 'err', esc(er.message)); }
      });
    } };
  }

  /* ---------- Ingresar y registrarse (RF-01) ---------- */
  function viewIngresar() {
    var h = head('Ingresar', 'RF-01') + '<div class="two">' +
      '<form class="box stack" id="login"><h2 style="margin:0">Iniciar sesión</h2>' +
      '<div class="field"><label for="lc">Correo</label><input id="lc" type="email" autocomplete="username"></div>' +
      '<div class="field"><label for="lp">Contraseña</label><input id="lp" type="password" autocomplete="current-password"></div>' +
      '<div id="lr"></div><div><button class="btn" type="submit">Ingresar</button></div></form>' +
      '<form class="box stack" id="reg"><h2 style="margin:0">Crear cuenta</h2>' +
      '<div class="field"><label for="rn">Nombre</label><input id="rn" type="text" maxlength="100" placeholder="Nombre completo"></div>' +
      '<div class="field"><label for="rc">Correo</label><input id="rc" type="email" maxlength="100" placeholder="correo@dominio.com"></div>' +
      '<div class="field"><label for="rp">Contraseña (mínimo 8 caracteres)</label><input id="rp" type="password" autocomplete="new-password"></div>' +
      '<div id="rr"></div><div><button class="btn alt" type="submit">Registrarme</button></div></form></div>';
    return { html: h, after: function () {
      $('#login').addEventListener('submit', async function (e) {
        e.preventDefault();
        try { var j = await api('/api/login', { correo: $('#lc').value, contrasena: $('#lp').value }); ME = j.usuario; tab = 'ejemplares'; location.hash = 'cuenta'; paintSession(); route(); }
        catch (er) { say($('#lr'), 'err', esc(er.message)); }
      });
      $('#reg').addEventListener('submit', async function (e) {
        e.preventDefault();
        try {
          var j = await api('/api/registro', { nombre: $('#rn').value, correo: $('#rc').value, contrasena: $('#rp').value });
          ME = j.usuario; flash = 'Cuenta creada. ¡Bienvenido a PHY-FO!'; tab = 'ejemplares'; location.hash = 'cuenta'; paintSession(); route();
        } catch (er) { say($('#rr'), 'err', esc(er.message)); }
      });
    } };
  }

  /* ---------- Mi cuenta (RF-02, RF-04, RF-07, RF-08, RF-09) ---------- */
  async function viewCuenta() {
    if (!ME) return { html: needLogin('Mi cuenta') };
    var tabs = [['ejemplares', 'Mis ejemplares'], ['direcciones', 'Mis direcciones'], ['compras', 'Mis compras'], ['ventas', 'Mis ventas']];
    var h = head('Mi cuenta', '') + (flash ? '<div class="note good" style="margin-bottom:14px">' + esc(flash) + '</div>' : '') +
      '<p class="muted" style="margin-bottom:14px">' + esc(ME.nombre) + ' · ' + esc(ME.correo) + '</p>' +
      '<div class="tabs" role="tablist">' + tabs.map(function (t) { return '<button role="tab" data-t="' + t[0] + '" aria-selected="' + (tab === t[0]) + '">' + t[1] + '</button>'; }).join('') + "</div><div id='tb'></div>";
    flash = '';
    return { html: h, after: async function () {
      Array.prototype.forEach.call(document.querySelectorAll('.tabs button'), function (b) {
        b.addEventListener('click', function () { tab = b.getAttribute('data-t'); route(); });
      });
      var t = $('#tb');
      try {
        if (tab === 'ejemplares') {
          var mine = await api('/api/mis/ejemplares');
          t.innerHTML = '<p style="margin-bottom:10px"><span class="rf">RF-04</span> <a class="btn sm" href="#publicar">Agregar ejemplar o publicar</a></p>' +
            (mine.length ? '<div class="tw"><table><thead><tr><th>Videojuego</th><th>Plataforma</th><th>Edición</th><th>Disco</th><th>Caja</th><th>Observaciones</th><th>Disponibilidad</th><th></th></tr></thead><tbody>' +
            mine.map(function (i) {
              var act = i.estado === 'Disponible' ? '<a class="btn sm" href="#publicar">Publicar</a>' : i.estado === 'Publicado' ? '<a class="btn sm alt" href="#juego-' + i.idPublicacion + '">Ver</a>' : '';
              return '<tr><td>' + esc(i.titulo) + '</td><td>' + esc(i.plataforma) + '</td><td>' + esc(i.edicion) + '</td><td>' + esc(i.fisico) + '</td><td>' + esc(i.caja) + '</td><td>' + esc(i.obs || '') + '</td><td>' + tagEstado(i.estado) + '</td><td>' + act + '</td></tr>';
            }).join('') + '</tbody></table></div>' : '<div class="empty">Aún no tienes ejemplares.</div>');
        } else if (tab === 'direcciones') {
          var ds = await api('/api/mis/direcciones');
          t.innerHTML = '<p style="margin-bottom:10px"><span class="rf">RF-02</span></p>' +
            (ds.length ? '<div class="tw"><table><thead><tr><th>Ciudad</th><th>Departamento</th><th>Detalle</th></tr></thead><tbody>' +
            ds.map(function (d) { return '<tr><td>' + esc(d.ciudad) + '</td><td>' + esc(d.departamento) + '</td><td>' + esc(d.detalle) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<div class="empty">Aún no tienes direcciones.</div>') +
            '<h2>Agregar dirección</h2><form class="box" id="fd"><div class="row"><div class="field"><label for="dc">Ciudad</label><select id="dc">' +
            META.ciudades.map(function (c) { return '<option value="' + c.id + '">' + esc(c.ciudad) + ' — ' + esc(c.departamento) + '</option>'; }).join('') +
            '</select></div><div class="field"><label for="dx">Calle, número y complemento</label><input id="dx" type="text" maxlength="150" placeholder="Calle 10 # 4-55, Apto 502"></div>' +
            '<div><button class="btn" type="submit">Guardar dirección</button></div></div><div id="dm" style="margin-top:10px"></div></form>';
          $('#fd').addEventListener('submit', async function (e) {
            e.preventDefault();
            try { await api('/api/mis/direcciones', { idCiudad: $('#dc').value, detalle: $('#dx').value }); route(); }
            catch (er) { say($('#dm'), 'err', esc(er.message)); }
          });
        } else if (tab === 'compras') {
          var cs = await api('/api/mis/compras');
          t.innerHTML = '<p style="margin-bottom:10px"><span class="rf">RF-07 · RF-08 · RF-09</span></p><div id="rm"></div>' + (cs.length ? '<div class="tw"><table><thead><tr><th>Videojuego</th><th>Vendedor</th><th class="n">Precio final</th><th>Fecha</th><th>Entrega</th><th>Reseña</th></tr></thead><tbody>' +
            cs.map(function (x) {
              var cell = x.calificacion ? stars(x.calificacion) + "<br><span class='small'>" + esc(x.comentario || '') + '</span>' :
                '<div class="stack" style="min-width:200px"><select class="rc" data-p="' + x.idPublicacion + '"><option>5</option><option>4</option><option>3</option><option>2</option><option>1</option></select>' +
                '<input type="text" maxlength="100" class="rm" data-p="' + x.idPublicacion + '" placeholder="Comentario (máx. 100)"><button class="btn sm rb" data-p="' + x.idPublicacion + '" type="button">Enviar reseña</button></div>';
              return '<tr><td>' + esc(x.titulo) + '</td><td>' + esc(x.vendedor) + '</td><td class="n mono">' + money(x.precioFinal) + '</td><td>' + fdate(x.fecha) + '</td><td>' + entregaTxt(x) + '</td><td>' + cell + '</td></tr>';
            }).join('') + '</tbody></table></div>' : '<div class="empty">Aún no has comprado.</div>');
          Array.prototype.forEach.call(t.querySelectorAll('.rb'), function (b) {
            b.addEventListener('click', async function () {
              var pid = parseInt(b.getAttribute('data-p'), 10);
              try {
                await api('/api/resenas', { idPublicacion: pid, calificacion: t.querySelector('.rc[data-p="' + pid + '"]').value, comentario: t.querySelector('.rm[data-p="' + pid + '"]').value });
                route();
              } catch (er) { say($('#rm'), 'err', esc(er.message)); }
            });
          });
        } else {
          var vs = await api('/api/mis/ventas');
          t.innerHTML = '<p style="margin-bottom:10px"><span class="rf">RF-07 · RF-08</span></p>' + (vs.length ? '<div class="tw"><table><thead><tr><th>Videojuego</th><th>Comprador</th><th class="n">Publicado</th><th class="n">Precio final</th><th>Fecha</th><th>Entrega</th></tr></thead><tbody>' +
            vs.map(function (x) { return '<tr><td>' + esc(x.titulo) + '</td><td>' + esc(x.comprador) + '</td><td class="n mono">' + money(x.publicado) + '</td><td class="n mono">' + money(x.precioFinal) + '</td><td>' + fdate(x.fecha) + '</td><td>' + entregaTxt(x) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<div class="empty">Aún no has vendido.</div>');
        }
      } catch (e) { t.innerHTML = '<div class="note err">' + esc(e.message) + '</div>'; }
    } };
  }

  /* ---------- Vender un juego (RF-03, RF-04, RF-05) ---------- */
  async function viewPublicar() {
    if (!ME) return { html: needLogin('Vender un juego') };
    var mios = await api('/api/mis/ejemplares');
    var libres = mios.filter(function (i) { return i.estado === 'Disponible'; });
    var h = head('Vender un juego', 'RF-05') + '<form class="stack" id="fv" style="max-width:760px">' +
      '<div class="box stack"><h2 style="margin:0">1. Ejemplar</h2>' +
      '<div class="radios"><label><input type="radio" name="md" value="e" ' + (libres.length ? 'checked' : '') + '> Uno de mi inventario</label><label><input type="radio" name="md" value="n" ' + (libres.length ? '' : 'checked') + '> Agregar un ejemplar nuevo <span class="rf">RF-03 · RF-04</span></label></div>' +
      '<div class="field" id="m-e"><label for="se">Ejemplar disponible</label><select id="se">' + (libres.length ? libres.map(function (i) { return '<option value="' + i.id + '">' + esc(i.titulo) + ' · ' + esc(i.plataforma) + ' · ' + esc(i.edicion) + ' · disco ' + esc(i.fisico.toLowerCase()) + '</option>'; }).join('') : '<option value="">No tienes ejemplares disponibles</option>') + '</select></div>' +
      '<div class="stack" id="m-n" hidden><div class="field"><label for="ne">Videojuego, plataforma y edición</label><select id="ne">' +
      META.ediciones.map(function (x) { return '<option value="' + x.id + '">' + esc(x.titulo) + ' · ' + esc(x.plataforma) + ' · ' + esc(x.tipo) + '</option>'; }).join('') + '</select></div>' +
      '<div class="row"><div class="field"><label for="nf">Estado del disco o cartucho</label><select id="nf">' + opts(ESTADOS, 'Buen estado') + '</select></div>' +
      '<div class="field"><label for="nc">Estado de la caja</label><select id="nc">' + opts(CAJAS, 'Buen estado') + '</select></div></div>' +
      '<div class="field"><label for="no">Observaciones (daños, faltantes o extras)</label><textarea id="no" maxlength="300"></textarea></div></div></div>' +
      '<div class="box stack"><h2 style="margin:0">2. Precio</h2><div class="field" style="max-width:260px"><label for="pr">Precio (COP)</label><input id="pr" type="number" min="1" step="1" value="150000"></div></div>' +
      '<div class="box stack"><h2 style="margin:0">3. Fotografías (de 1 a 10)</h2><input id="ph" type="file" accept=".jpg,.jpeg,.png,.webp" multiple><p class="small muted">La primera foto es la principal. Formatos: jpg, png o webp, de hasta 3 MB cada una.</p></div>' +
      '<div id="vr"></div><div><button class="btn" type="submit">Publicar juego</button></div></form>';
    return { html: h, after: function () {
      var f = $('#fv');
      function sync() { var nuevo = f.elements.md.value === 'n'; $('#m-e').hidden = nuevo; $('#m-n').hidden = !nuevo; }
      f.addEventListener('change', sync); sync();
      f.addEventListener('submit', async function (e) {
        e.preventDefault();
        var r = $('#vr'), files = Array.prototype.slice.call($('#ph').files);
        if (files.length > 10) return say(r, 'err', 'Una publicación admite como máximo 10 fotografías.');
        try {
          var fotos = await Promise.all(files.map(leerArchivo));
          var nuevo = f.elements.md.value === 'n';
          var j = await api('/api/publicar', { modo: nuevo ? 'nuevo' : 'existente', idInventario: $('#se').value, idEdicion: $('#ne').value,
            fisico: $('#nf').value, caja: $('#nc').value, obs: $('#no').value, precio: parseFloat($('#pr').value), fotos: fotos });
          say(r, 'good', 'Publicación creada con ' + files.length + (files.length === 1 ? ' foto' : ' fotos') + '. <a href="#juego-' + j.idPublicacion + '">Ver publicación</a>');
          f.reset();
        } catch (er) { say(r, 'err', esc(er.message)); }
      });
    } };
  }

  /* ---------- Administrador (RF-10) ---------- */
  async function viewAdmin() {
    if (!ME) return { html: needLogin('Administrador') };
    var d;
    try { d = await api('/api/admin/resumen'); }
    catch (e) { return { html: head('Administrador', 'RF-10') + '<div class="note err">' + esc(e.message) + '</div>' }; }
    var k = d.kpis, max = d.generos.length ? d.generos[0].ingresos : 1;
    var h = head('Administrador', 'RF-10') + "<h2 style='margin-top:0'>Resumen de ventas</h2>" +
      '<div class="kpis"><div><b>' + k.ventas + '</b><span>Ventas</span></div><div><b>' + money(k.total) + '</b><span>Total vendido</span></div><div><b>' + money(Math.round(k.promedio)) + '</b><span>Promedio</span></div><div><b>' + money(k.minimo) + '</b><span>Mínimo</span></div><div><b>' + money(k.maximo) + '</b><span>Máximo</span></div></div>' +
      '<div class="two" style="margin-top:8px"><div><h2>Ingresos por género</h2><div class="tw"><table><thead><tr><th>Género</th><th class="n">Ventas</th><th class="n">Ingresos</th><th style="width:30%"></th></tr></thead><tbody>' +
      d.generos.map(function (g) { return '<tr><td>' + esc(g.genero) + '</td><td class="n">' + g.ventas + '</td><td class="n mono">' + money(g.ingresos) + '</td><td><span class="bar-in" style="width:' + Math.round(g.ingresos / max * 100) + '%"></span></td></tr>'; }).join('') + '</tbody></table></div></div>' +
      "<div><h2>Ranking de vendedores</h2><div class='tw'><table><thead><tr><th>#</th><th>Vendedor</th><th class='n'>Ventas</th><th class='n'>Ingresos</th></tr></thead><tbody>" +
      d.vendedores.map(function (v, i) { return '<tr><td>' + (i + 1) + '</td><td>' + esc(v.vendedor) + '</td><td class="n">' + v.ventas + '</td><td class="n mono">' + money(v.ingresos) + '</td></tr>'; }).join('') + '</tbody></table></div></div></div>' +
      "<h2>Usuarios registrados</h2><div class='tw'><table><thead><tr><th>#</th><th>Nombre</th><th>Correo</th><th>Ciudad</th><th class='n'>Ejemplares</th></tr></thead><tbody>" +
      d.usuarios.map(function (u) { return '<tr><td>' + u.id + '</td><td>' + esc(u.nombre) + '</td><td>' + esc(u.correo) + '</td><td>' + esc(u.ciudad || '') + '</td><td class="n">' + u.ejemplares + '</td></tr>'; }).join('') + '</tbody></table></div>';
    return { html: h };
  }

  /* ---------- sesión, navegación y arranque ---------- */
  function paintSession() {
    var s = $('#ses');
    s.innerHTML = ME ? '<span>' + esc(ME.nombre) + '</span><button type="button" id="out">Salir</button>' : '<a class="in" href="#ingresar">Ingresar</a>';
    $('#nav-admin').hidden = !(ME && ME.admin);
    if (ME) $('#out').addEventListener('click', async function () { await api('/api/logout', {}); ME = null; paintSession(); location.hash = 'catalogo'; route(); });
  }
  async function route() {
    var hs = location.hash.replace('#', '') || 'catalogo', m = /^juego-(\d+)$/.exec(hs), r, nav = hs;
    try {
      if (m) { r = await viewJuego(parseInt(m[1], 10)); nav = 'catalogo'; }
      else if (hs === 'ingresar') r = viewIngresar();
      else if (hs === 'cuenta') r = await viewCuenta();
      else if (hs === 'publicar') r = await viewPublicar();
      else if (hs === 'admin') r = await viewAdmin();
      else { r = viewCatalogo(); nav = 'catalogo'; }
    } catch (e) { r = { html: head('No se pudo cargar') + '<div class="note err">' + esc(e.message) + '</div>' }; }
    $('#app').innerHTML = r.html;
    if (r.after) r.after();
    Array.prototype.forEach.call(document.querySelectorAll('#nav a'), function (a) { a.classList.toggle('on', a.getAttribute('data-r') === nav); });
    window.scrollTo(0, 0);
  }
  window.addEventListener('hashchange', route);
  (async function () {
    try {
      var y = await api('/api/yo'); ME = y.usuario;
      META = await api('/api/meta');
    } catch (e) { $('#app').innerHTML = '<div class="note err">No se pudo conectar con el servidor: ' + esc(e.message) + '</div>'; return; }
    paintSession();
    route();
  })();
})();
