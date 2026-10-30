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
