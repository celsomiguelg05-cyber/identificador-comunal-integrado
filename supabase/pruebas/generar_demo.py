# Genera supabase/seed_demo.sql (datos ficticios). Uso: python3 supabase/pruebas/generar_demo.py
import random, datetime as dt, pathlib
random.seed(2026)
F=["Juana","María","Manuela","Francisca","Catarina","Petrona","Rosa","Andrea","Micaela","Magdalena","Tomasa","Sebastiana","Lucía","Ana","Dominga"]
M=["Juan","Pedro","Diego","Francisco","Manuel","Andrés","Tomás","Miguel","Gaspar","Santiago","José","Lucas","Sebastián","Antonio","Felipe"]
A=["Tzul","Batz","Tzunún","Ixcoy","Chuc","Puac","Yax","Tax","Xiloj","Sapón","García","Pérez","Vásquez","Coyoy","Gutiérrez","Ajpacajá","Ixchop","Tacam","Chaclán","Tumax","Ordóñez","Menchú","Baquiax","Itzep"]
SEC=["Sector Centro","Sector Norte","Sector Sur","Sector Oriente","Sector Poniente","Sector Alto"]
OF_F=["Tejedora","Comerciante","Ama de casa","Agricultora","Costurera","Maestra","Panadera"]
OF_M=["Agricultor","Carpintero","Albañil","Comerciante","Tejedor","Maestro","Piloto","Herrero","Sastre"]
q=lambda s: "null" if s is None else "'"+str(s).replace("'","''")+"'"
out=["-- =====================================================================",
"-- DATOS FICTICIOS PARA DEMOSTRACIÓN. Ninguna persona es real.",
"-- Correr después de la migración, como dueño de la base (editor SQL de Supabase).",
"-- Para borrarlos: ver supabase/borrar_demo.sql",
"-- =====================================================================","begin;"]
ppl=[]
for i in range(1,81):
    fem = random.random()<0.5
    n=random.choice(F if fem else M)
    if random.random()<0.3: n+=" "+random.choice(F if fem else M)
    ap=random.choice(A)+" "+random.choice(A)
    nac=dt.date(random.randint(1950,2005),random.randint(1,12),random.randint(1,28))
    pid=f"PXT-{i:04d}"
    ver=2 if random.random()<0.08 else 1
    estado="baja" if i in (37,64) else "activo"
    hogar=f"H-{(i+1)//2:03d}"
    tel=f"{random.choice([3,4,5])}{random.randint(100,999)}-{random.randint(1000,9999)}" if random.random()<0.7 else None
    creado=dt.datetime(2026,5,random.randint(4,29),random.randint(15,22),random.randint(0,59))
    ppl.append((pid,ver,estado,creado))
    out.append(f"insert into public.moradores (id,comunidad_id,nombres,apellidos,nacimiento,sexo,sector,hogar,oficio,telefono,foto_path,ver,estado,obligado,creado) values "
      f"({q(pid)},'PXT',{q(n)},{q(ap)},'{nac}',{q('F' if fem else 'M')},{q(random.choice(SEC))},{q(hogar)},{q(random.choice(OF_F if fem else OF_M))},{q(tel)},null,{ver},{q(estado)},{'false' if nac.year>2008 else 'true'},'{creado}+00');")
    if ver==2:
        out.append(f"insert into public.carnes (comunidad_id,morador_id,ver,estado,emitido,anulado_en,motivo) values ('PXT',{q(pid)},1,'anulado','{creado}+00','2026-08-10 16:00+00','reposición (extravío)');")
    if estado=="activo":
        out.append(f"insert into public.carnes (comunidad_id,morador_id,ver,estado,emitido) values ('PXT',{q(pid)},{ver},'vigente','{creado if ver==1 else '2026-08-10 16:00'}+00');")
    else:
        out.append(f"insert into public.carnes (comunidad_id,morador_id,ver,estado,emitido,anulado_en,motivo) values ('PXT',{q(pid)},{ver},'anulado','{creado}+00','2026-09-01 15:00+00','baja');")
# eventos: (id, tipo, nombre, fecha, lugar, multa_falta, multa_sin_salida, abierta)
EV=[("demo-asm-2026-06","asamblea","Asamblea general de junio","2026-06-07","Salón comunal",25,10),
    ("demo-faena-2026-06","faena","Faena: limpieza del nacimiento de agua","2026-06-20","Nacimiento Pa Ja'",50,25),
    ("demo-asm-2026-07","asamblea","Asamblea general de julio","2026-07-05","Salón comunal",25,10),
    ("demo-asm-2026-08","asamblea","Asamblea general de agosto","2026-08-02","Salón comunal",25,10),
    ("demo-faena-2026-08","faena","Faena: reparación del camino al bosque comunal","2026-08-22","Camino al bosque",50,25),
    ("demo-asm-2026-09","asamblea","Asamblea general de septiembre","2026-09-06","Salón comunal",25,10),
    ("demo-reu-2026-09","reunion","Reunión del comité de agua","2026-09-19","Escuela",None,None),
    ("demo-asm-2026-10","asamblea","Asamblea general de octubre","2026-10-04","Salón comunal",25,10)]
mk=0; inc=0
lazy=set(random.sample(range(80),8))   # faltan seguido
for (eid,tipo,nom,fecha,lugar,mf,ms) in EV:
    d=dt.date.fromisoformat(fecha)
    start=dt.datetime(d.year,d.month,d.day,14,0)  # 8:00 Guatemala
    end=start+dt.timedelta(hours=3,minutes=30)
    out.append(f"insert into public.asambleas (id,comunidad_id,tipo,nombre,fecha,lugar,inicio,tolerancia,abierta,abierta_en,cerrada_en,multa_falta,multa_sin_salida,dispositivo_id) values "
      f"({q(eid)},'PXT',{q(tipo)},{q(nom)},'{fecha}',{q(lugar)},'08:00',15,false,'{start}+00','{end+dt.timedelta(minutes=20)}+00',{mf if mf else 'null'},{ms if ms else 'null'},'demo-cel-1');")
    if tipo=="reunion":
        asist=random.sample([p for p in ppl if p[2]=="activo"],12)
    else:
        asist=[]
        for idx,p in enumerate(ppl):
            if p[2]!="activo" and fecha>"2026-08-31": continue
            pr=0.55 if idx in lazy else 0.9
            if random.random()<pr: asist.append(p)
    for p in asist:
        cel=random.choice(["demo-cel-1","demo-cel-2"])
        via=random.choices(["carne","digital","manual"],[80,17,3])[0]
        motivo="Carné olvidado; lo reconoció la directiva" if via=="manual" else ""
        e=start+dt.timedelta(minutes=(random.randint(-25,14) if random.random()<0.86 else random.randint(16,50)),seconds=random.randint(0,59))
        mk+=1
        out.append(f"insert into public.marcajes (id,comunidad_id,asamblea_id,morador_id,tipo,hora,via,motivo,dispositivo_id) values ('demo-m-{mk}','PXT',{q(eid)},{q(p[0])},'entrada','{e}+00',{q(via)},{q(motivo)},{q(cel)});")
        if random.random()<0.93:
            s=end+dt.timedelta(minutes=random.randint(-10,15),seconds=random.randint(0,59))
            mk+=1
            out.append(f"insert into public.marcajes (id,comunidad_id,asamblea_id,morador_id,tipo,hora,via,motivo,dispositivo_id) values ('demo-m-{mk}','PXT',{q(eid)},{q(p[0])},'salida','{s}+00',{q(via)},'',{q(cel)});")
    # incidentes
    for t,det in random.sample([("anulado","Presentó el carné nº 1, que fue repuesto. Se le pidió el nuevo."),
                                ("vencido","QR del celular vencido: parece captura de pantalla."),
                                ("suplantacion","La foto en pantalla no coincidía con quien presentó el carné. Se retuvo el carné."),
                                ("firma","QR con firma inválida (carné fotocopiado o alterado)."),
                                ("sin_entrada","Quiso marcar salida sin haber marcado entrada.")], random.randint(1,3)):
        inc+=1
        p=random.choice(ppl)
        h=start+dt.timedelta(minutes=random.randint(0,200))
        out.append(f"insert into public.incidentes (id,comunidad_id,asamblea_id,persona,morador_id,tipo,detalle,hora,revisado,nota,dispositivo_id) values ('demo-i-{inc}','PXT',{q(eid)},{q(p[0])},{q(p[0])},{q(t)},{q(det)},'{h}+00',{'true' if fecha<'2026-10-01' else 'false'},{q('Revisado en sesión de directiva' if fecha<'2026-10-01' else None)},'demo-cel-1');")
# multas a partir de la asistencia: inasistencia/faena, tardanza (después de 8:15) y sin salida
out.append("""select sum(app_private.calcular_multas(id)) as multas_generadas from public.asambleas where id like 'demo-%';
update public.multas mu set creada = a.cerrada_en + interval '1 day'
  from public.asambleas a where a.id = mu.asamblea_id and a.id like 'demo-%';""")
out.append("""-- Multas por rechazar convenios comunales
insert into public.multas (id, comunidad_id, morador_id, motivo, monto, descripcion, creada) values
 ('demo-conv-1','PXT','PXT-0014','convenio',100,'Rechazó el convenio de cuidado del bosque comunal','2026-07-06 15:00+00'),
 ('demo-conv-2','PXT','PXT-0029','convenio',100,'Rechazó el convenio de uso del agua','2026-09-07 15:00+00'),
 ('demo-conv-3','PXT','PXT-0047','convenio',100,'Rechazó el convenio de uso del agua','2026-09-07 15:00+00');""")
out.append("""-- Pagos: ~70 % de las multas anteriores a octubre, con recibo
with p as (select id, row_number() over (order by creada, id) n from public.multas
            where asamblea_id like 'demo-%' and creada < '2026-10-01' and abs(hashtext(id::text)) % 10 < 7)
update public.multas mu set estado='pagada', pagada_en = mu.creada + interval '9 days', recibo = 'R-' || lpad(p.n::text, 4, '0')
  from p where p.id = mu.id;
update public.multas set estado='condonada', nota='Condonada por enfermedad (acuerdo de asamblea)'
 where id = (select id from public.multas where asamblea_id like 'demo-%' and estado='pendiente' order by creada, id limit 1);""")
TR=[("PXT-0003","constancia_residencia","Para trámite de DPI","entregado"),("PXT-0011","solvencia","Para optar a lote en el cementerio","entregado"),
    ("PXT-0020","carta_aval","Aval para crédito en cooperativa","aprobado"),("PXT-0025","constancia_residencia","Para inscripción escolar","entregado"),
    ("PXT-0031","reposicion_carne","Carné extraviado","entregado"),("PXT-0042","solvencia","Para servicio de agua","rechazado"),
    ("PXT-0050","constancia_residencia","Para trámite en RENAP","solicitado"),("PXT-0058","carta_aval","Aval para beca","solicitado"),
    ("PXT-0066","otro","Permiso para corte de leña en bosque comunal","aprobado"),("PXT-0072","solvencia","Para cargo en comité","solicitado")]
for i,(pid,t,d,e) in enumerate(TR):
    c=dt.datetime(2026,6+i//2,3+i*2,16,0)
    res = f"'{c+dt.timedelta(days=3)}+00'" if e!="solicitado" else "null"
    nota = "'Tiene multas pendientes'" if e=="rechazado" else "null"
    out.append(f"insert into public.tramites (comunidad_id,folio,morador_id,tipo,descripcion,estado,monto,creado,resuelto_en,nota) values ('PXT',0,{q(pid)},{q(t)},{q(d)},{q(e)},{10 if t!='reposicion_carne' else 15},'{c}+00',{res},{nota});")
out.append("commit;")
open(pathlib.Path(__file__).resolve().parent.parent / "seed_demo.sql","w").write("\n".join(out)+"\n")
print(len(out), mk, inc)
