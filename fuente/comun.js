/* Código compartido por la app de control y la app del miembro: infracciones, reglas de multas y datos de demostración */
const INFRACCIONES_BASE = [
  { codigo: "inasistencia", nombre: "No asistir a la asamblea", monto: 50 },
  { codigo: "tardanza", nombre: "Llegar tarde", monto: 10 },
  { codigo: "sin_salida", nombre: "Retirarse sin marcar salida", monto: 25 },
  { codigo: "faena", nombre: "No cumplir la faena", monto: 75 },
  { codigo: "convenio", nombre: "Rechazar un convenio comunal", monto: 100 },
  { codigo: "otro", nombre: "Otra falta", monto: 0 }];
const ESTADO_MULTA = { pendiente: "Pendiente", pagada: "Pagada", condonada: "Condonada", anulada: "Anulada" };
const quetzales = n => "Q " + Number(n || 0).toLocaleString("es-GT", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/* Hora de inicio del evento en milisegundos */
function inicioEvento(a){
  const [h, m] = String(a.inicio || "08:00").split(":").map(Number);
  const d = new Date(a.fecha + "T00:00:00"); d.setHours(h || 0, m || 0, 0, 0); return d.getTime();
}
/* Situación de una persona en un evento: entrada, salida, tarde y estado */
function situacion(a, marks){
  const e = marks.find(m => m.tipo === "entrada"), s = marks.find(m => m.tipo === "salida");
  const limite = inicioEvento(a) + (Number(a.tolerancia) || 0) * 60000;
  const tarde = !!(e && e.hora > limite);
  let estado = "ausente";
  if (e && s) estado = "completa"; else if (e) estado = a.abierta ? "dentro" : "sin_salida";
  return { e, s, tarde, estado, minTarde: tarde ? Math.round((e.hora - limite) / 60000) : 0 };
}
/* Multas que corresponden a un evento cerrado (sin repetir las que ya existen) */
function multasDeEvento(a, personas, marksDe, catalogo, existentes){
  const monto = c => (catalogo.find(i => i.codigo === c) || {}).monto || 0;
  const ya = new Set(existentes.filter(m => m.asamblea === a.id && m.estado !== "anulada").map(m => m.persona + "|" + m.motivo));
  const out = [];
  for (const p of personas) {
    const st = situacion(a, marksDe(p.id)), add = (motivo, descripcion) => {
      if (!ya.has(p.id + "|" + motivo) && monto(motivo) > 0) out.push({ persona: p.id, asamblea: a.id, motivo, descripcion, monto: monto(motivo) });
    };
    if (st.estado === "ausente") add(a.tipo === "faena" ? "faena" : "inasistencia", `${a.nombre}: no se presentó`);
    if (st.tarde) add("tardanza", `${a.nombre}: llegó ${st.minTarde} min tarde`);
    if (st.estado === "sin_salida") add("sin_salida", `${a.nombre}: se retiró sin marcar salida`);
  }
  return out;
}

/* ===== Datos de demostración (personas ficticias, iguales en las dos apps) ===== */
const DEMO_MASTER = "1IosNc6DlBtOOkSNMHJwtcf715Yv4hsYGVpJxY-9upo";
const DEMO_PERSONAS = [
  ["María Elena","Tzul Batz","Sector Centro","Tejedora","1968-03-14"],["Juan Diego","Chuc Tax","Sector Norte","Carpintero","1975-07-02"],
  ["Rosa Amalia","Ixcoy Puac","Sector Centro","Comerciante","1982-11-21"],["Pedro Pablo","Sapón Tzoc","Sector Sur","Agricultor","1959-01-30"],
  ["Catarina","Pu Cuxil","Sector Oriente","Tejedora","1990-05-09"],["Francisco","Batz Ixcoy","Sector Norte","Albañil","1971-09-17"],
  ["Juana Isabel","Tax Chuc","Sector Sur","Maestra","1986-12-03"],["Diego Alberto","Tzoc Sapón","Sector Oriente","Mecánico","1994-04-25"],
  ["Magdalena","Puac Tzul","Sector Centro","Comadrona","1955-08-12"],["Manuel","Cuxil Pu","Sector Norte","Agricultor","1979-02-28"],
  ["Ana Lucía","Chuc Sapón","Sector Sur","Enfermera","1992-10-06"],["Tomás","Ixcoy Batz","Sector Oriente","Panadero","1965-06-19"]];
/* Por evento y por persona: [minutos de entrada respecto al inicio, minutos de salida] o null si faltó */
const DEMO_EVENTOS = [
  { key: "e1", tipo: "asamblea", nombre: "Asamblea general", dias: -21, inicio: "08:00", tolerancia: 15,
    a: [[2,170],[5,170],[-3,165],[25,170],[8,170],null,[1,168],[12,170],[0,171],[4,null],[6,170],[3,170]] },
  { key: "e2", tipo: "faena", nombre: "Faena: limpieza del camino al bosque", dias: -14, inicio: "07:00", tolerancia: 15,
    a: [[0,240],[3,240],null,[1,238],[30,240],[2,240],[5,240],null,[0,240],[1,240],[4,null],[2,240]] },
  { key: "e3", tipo: "asamblea", nombre: "Asamblea sobre el agua potable", dias: -7, inicio: "08:00", tolerancia: 15,
    a: [[1,150],[22,150],[4,150],[2,150],[5,150],[40,150],null,[3,null],[2,150],[0,150],[6,150],null] },
  { key: "e4", tipo: "asamblea", nombre: "Asamblea de práctica", dias: 0, inicio: "08:00", tolerancia: 15, abierta: true,
    a: [[3,150],[5,null],[6,null],[9,null],[12,null],null,[14,null],null,[21,158],null,null,null] }];
const DEMO_RECIBOS = ["e1", "e2"]; /* multas de estos eventos ya están cobradas */
function fechaRelativa(dias){ const d = new Date(); d.setDate(d.getDate() + dias); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); }
function demoConstruir(prefijo){
  const pid = i => `${prefijo}-${String(i + 1).padStart(4, "0")}`;
  const people = DEMO_PERSONAS.map(([nombres, apellidos, sector, oficio, nacimiento], i) =>
    ({ id: pid(i), nombres, apellidos, sector, oficio, nacimiento, telefono: "", ver: i === 5 ? 2 : 1, estado: "activo",
       anulados: i === 5 ? [{ ver: 1, fecha: Date.now() - 86400000 * 30 }] : [], ejemplo: true }));
  const assemblies = [], marks = [], incidents = [], multas = [];
  for (const ev of DEMO_EVENTOS) {
    const a = { id: "demo-" + ev.key, tipo: ev.tipo, nombre: ev.nombre, fecha: fechaRelativa(ev.dias), inicio: ev.inicio, tolerancia: ev.tolerancia,
                abierta: !!ev.abierta, ejemplo: true };
    const t0 = inicioEvento(a); a.abierta_en = t0 - 10 * 60000; a.cerrada_en = ev.abierta ? null : t0 + 260 * 60000;
    assemblies.push(a);
    ev.a.forEach((x, i) => {
      if (!x) return;
      marks.push({ id: `demo-${ev.key}-${i}-e`, asamblea: a.id, persona: pid(i), tipo: "entrada", hora: t0 + x[0] * 60000, via: "carne", motivo: "", ejemplo: true });
      if (x[1] != null) marks.push({ id: `demo-${ev.key}-${i}-s`, asamblea: a.id, persona: pid(i), tipo: "salida", hora: t0 + x[1] * 60000, via: "carne", motivo: "", ejemplo: true });
    });
  }
  let recibo = 0;
  for (const a of assemblies.filter(a => !a.abierta)) {
    const nuevas = multasDeEvento(a, people, id => marks.filter(m => m.asamblea === a.id && m.persona === id), INFRACCIONES_BASE, multas);
    nuevas.forEach((m, k) => {
      const x = Object.assign({ id: `demo-multa-${a.id}-${k}`, estado: "pendiente", creada: a.cerrada_en + 3600000, pagada_en: null, recibo: "", nota: "", ejemplo: true }, m);
      if (DEMO_RECIBOS.includes(a.id.replace("demo-", ""))) {
        if (k === 1) { x.estado = "condonada"; x.nota = "Condonada por la directiva: estaba enfermo y presentó constancia"; }
        else { x.estado = "pagada"; x.pagada_en = x.creada + 86400000 * 3; x.recibo = "R-" + String(++recibo).padStart(4, "0"); }
      }
      multas.push(x);
    });
  }
  const e3 = assemblies.find(a => a.id === "demo-e3");
  multas.push({ id: "demo-multa-convenio", persona: pid(5), asamblea: e3.id, motivo: "convenio", descripcion: "Se negó a firmar el convenio comunal del agua potable",
    monto: 100, estado: "pendiente", creada: e3.cerrada_en + 7200000, pagada_en: null, recibo: "", nota: "", ejemplo: true });
  const e4 = assemblies.find(a => a.id === "demo-e4"), t4 = inicioEvento(e4);
  incidents.push({ id: "demo-inc-1", asamblea: e4.id, persona: pid(1), tipo: "doble", detalle: "Intentó marcar entrada por segunda vez", hora: t4 + 17 * 60000, ejemplo: true });
  incidents.push({ id: "demo-inc-2", asamblea: e4.id, persona: pid(5), tipo: "anulado", detalle: "Presentó el carné número 1; el vigente es el 2", hora: t4 + 19 * 60000, ejemplo: true });
  return { people, assemblies, marks, incidents, multas, recibo };
}

/* ===== Sonidos: tonos suaves de marimba hechos en el momento con Web Audio (no ocupan archivos y suenan sin internet) ===== */
const Sonido = (() => {
  const CLAVE = "carne-comunal-sonido";
  /* Notas de la escala de Sol, como las teclas de una marimba */
  const N = { G3:196, B3:246.94, D4:293.66, E4:329.63, G4:392, A4:440, B4:493.88, C5:523.25, D5:587.33, E5:659.25, G5:783.99, A5:880, B5:987.77, D6:1174.66, E6:1318.51, G6:1567.98 };
  /* Cada sonido: lista de [nota, tiempo en segundos, fuerza]; "r" al final = redoble (la nota se repite rápido, como en la marimba) */
  const FRASES = {
    lectura:    [["E6", 0, .55]],
    valido:     [["D5", 0, .6], ["G5", .09, .7]],
    registrado: [["G4", 0, .55], ["B4", .07, .6], ["D5", .14, .65], ["G5", .21, .8, "r"]],
    aviso:      [["B4", 0, .65], ["B4", .16, .55]],
    error:      [["D4", 0, .8], ["B3", .14, .8], ["G3", .28, .75]],
    cobro:      [["D5", 0, .55], ["G5", .06, .6], ["B5", .12, .65], ["D6", .18, .7], ["G6", .3, .45, "r"]],
    abrir:      [["G4", 0, .5], ["A4", .08, .55], ["B4", .16, .6], ["D5", .24, .65], ["E5", .32, .7], ["G5", .42, .8, "r"]],
    cerrar:     [["G5", 0, .6], ["E5", .1, .6], ["D5", .2, .6], ["B4", .3, .6], ["G4", .42, .75]],
    guardado:   [["B4", 0, .55], ["E5", .08, .6]],
    quitar:     [["E5", 0, .55], ["B4", .1, .55]],
    toque:      [["D6", 0, .55]],
    bienvenida: [["D5", 0, .5], ["G5", .1, .6], ["B5", .2, .65], ["D6", .3, .7], ["B5", .46, .45], ["G5", .58, .7, "r"]],
  };
  let ctx = null, salida = null;
  let activo = true; try { activo = localStorage.getItem(CLAVE) !== "0"; } catch {}
  function iniciar(){
    if (ctx) { if (ctx.state === "suspended") ctx.resume().catch(() => {}); return ctx; }
    const AC = window.AudioContext || window.webkitAudioContext; if (!AC) return null;
    ctx = new AC();
    /* Volumen general, un compresor suave y un poco de eco de salón de madera */
    salida = ctx.createGain(); salida.gain.value = 1;
    const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -18; comp.ratio.value = 3;
    const sala = ctx.createConvolver(), largo = Math.floor(ctx.sampleRate * 1.1), ir = ctx.createBuffer(2, largo, ctx.sampleRate);
    for (let c = 0; c < 2; c++) { const d = ir.getChannelData(c); for (let i = 0; i < largo; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / largo, 3.2); }
    sala.buffer = ir; const mezcla = ctx.createGain(); mezcla.gain.value = .16;
    salida.connect(comp); salida.connect(sala); sala.connect(mezcla); mezcla.connect(comp); comp.connect(ctx.destination);
    return ctx;
  }
  /* Una tecla de marimba: tono base que se apaga en medio segundo, el armónico de madera (x4) que se apaga rápido y un golpecito de baqueta */
  function tecla(f, t, fuerza){
    const v = .32 * fuerza, dur = Math.min(1.1, 220 / f + .35);
    const parcial = (mult, gan, caida) => {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = "sine"; o.frequency.value = f * mult;
      g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(v * gan, t + .004); g.gain.exponentialRampToValueAtTime(.0001, t + caida);
      o.connect(g); g.connect(salida); o.start(t); o.stop(t + caida + .02);
    };
    parcial(1, 1, dur); parcial(4, .22, dur * .22); parcial(9.9, .05, .05);
  }
  function tocar(nombre){
    if (!activo) return;
    const frase = FRASES[nombre]; if (!frase || !iniciar()) return;
    const t0 = ctx.currentTime + .02;
    for (const [n, dt, fuerza, redoble] of frase) {
      if (redoble) for (let k = 0; k < 5; k++) tecla(N[n], t0 + dt + k * .055, fuerza * (1 - k * .17));
      else tecla(N[n], t0 + dt, fuerza);
    }
  }
  /* Los navegadores solo dejan sonar después de que la persona toca la pantalla: se prepara con el primer toque */
  ["pointerdown", "keydown", "touchstart"].forEach(ev => document.addEventListener(ev, () => { if (activo) iniciar(); }, { capture: true, passive: true }));
  return {
    tocar,
    get activo(){ return activo; },
    poner(si){ activo = !!si; try { localStorage.setItem(CLAVE, activo ? "1" : "0"); } catch {} if (activo) { iniciar(); tocar("guardado"); } },
    alternar(){ this.poner(!activo); return activo; },
  };
})();
/* Ícono de bocina para el botón de sonido */
function iconoSonido(on){
  return `<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 9h4l5-4v14l-5-4H4z"/>${on ? `<path d="M16.5 8.5a5 5 0 0 1 0 7M19 6a8.5 8.5 0 0 1 0 12"/>` : `<path d="M17 9l5 6M22 9l-5 6"/>`}</svg>`;
}
