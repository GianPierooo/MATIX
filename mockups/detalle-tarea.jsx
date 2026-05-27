// Matix — Detalle de tarea

const DT = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1B2138',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const dt = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  star: <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3l2.5 6 6.5.7-5 4.5L17.5 21 12 17.5 6.5 21l1.5-6.8-5-4.5 6.5-.7z"/></svg>,
  starO: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round"><path d="M12 3l2.5 6 6.5.7-5 4.5L17.5 21 12 17.5 6.5 21l1.5-6.8-5-4.5 6.5-.7z"/></svg>,
  check: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>,
  cal: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  flag: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M5 21V4"/><path d="M5 4h12l-2 4 2 4H5"/></svg>,
  folder: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3.5 7a1.5 1.5 0 0 1 1.5-1.5h4l2 2h8A1.5 1.5 0 0 1 20.5 9v9a1.5 1.5 0 0 1-1.5 1.5H5A1.5 1.5 0 0 1 3.5 18V7z"/></svg>,
  rep: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12a8 8 0 0 1 14-5.3L20 9"/><path d="M20 5v4h-4"/><path d="M20 12a8 8 0 0 1-14 5.3L4 15"/><path d="M4 19v-4h4"/></svg>,
  bell: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2H4.5z"/><path d="M10.5 21h3"/></svg>,
  link: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 1 0-5.7-5.7L11.5 7"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7L12.5 17"/></svg>,
  spark: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  flame: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2c.5 4 4 5.5 4 9.5 0 2.2-1.8 4-4 4s-4-1.8-4-4c0-2.2 1.5-3 1.5-5.5 0 1.5 1.5 2 2.5 2-1-1-1-3.5 0-6z"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 8px'}}>
      <a href="Tareas.html" style={{width:40, height:40, borderRadius:12, background:DT.card, color:DT.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{dt.back}</a>
      <div style={{display:'flex', gap:8}}>
        <div style={{width:40, height:40, borderRadius:12, background:DT.card, color:DT.amber, display:'flex', alignItems:'center', justifyContent:'center'}}>{dt.star}</div>
        <a href="Modal%20Borrar.html" style={{width:40, height:40, borderRadius:12, background:DT.card, color:DT.muted, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{dt.more}</a>
      </div>
    </div>
  );
}

function Hero() {
  return (
    <div style={{padding:'8px 20px 16px'}}>
      <div style={{display:'flex', alignItems:'center', gap:8, marginBottom:10}}>
        <span style={{display:'inline-flex', alignItems:'center', gap:5, padding:'4px 10px', borderRadius:99, background:hexA(DT.red,0.14), border:`1px solid ${hexA(DT.red,0.35)}`, color:DT.red, fontSize:11, fontWeight:700, letterSpacing:0.4, textTransform:'uppercase'}}>
          {dt.flame}<span>Alta prioridad</span>
        </span>
        <span style={{display:'inline-flex', alignItems:'center', gap:5, padding:'4px 9px', borderRadius:99, background:hexA(DT.accent,0.14), border:`1px solid ${hexA(DT.accent,0.35)}`, color:DT.accent, fontSize:11, fontWeight:700, letterSpacing:0.4, textTransform:'uppercase'}}>
          Cálculo III
        </span>
      </div>
      <div style={{fontSize:24, fontWeight:700, color:DT.text, letterSpacing:-0.6, lineHeight:1.22}}>
        Resolver problemario del capítulo 7 — derivadas parciales
      </div>
      <div style={{display:'flex', alignItems:'center', gap:8, marginTop:14, padding:'10px 12px', borderRadius:12, background:hexA(DT.red,0.10), border:`1px solid ${hexA(DT.red,0.30)}`, color:DT.red, fontSize:13, fontWeight:600}}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>
        <span>Vence hoy a las 23:59</span>
        <span style={{marginLeft:'auto', fontSize:12, opacity:0.8, fontWeight:500}}>en 9 h 12 min</span>
      </div>
    </div>
  );
}

function MetaRow({icon, label, value, valueColor}) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:14, padding:'14px 18px', borderBottom:`1px solid ${DT.hairline}`}}>
      <div style={{width:32, height:32, borderRadius:9, background:'rgba(255,255,255,0.04)', color:DT.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{icon}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{fontSize:11, fontWeight:600, color:DT.muted, letterSpacing:0.6, textTransform:'uppercase'}}>{label}</div>
        <div style={{fontSize:14, fontWeight:600, color:valueColor||DT.text, marginTop:3, letterSpacing:-0.1}}>{value}</div>
      </div>
    </div>
  );
}

function Subtask({title, done}) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:12, padding:'10px 14px', borderRadius:12, background:'rgba(255,255,255,0.025)', marginBottom:6}}>
      <div style={{width:18, height:18, borderRadius:'50%', background:done?DT.green:'transparent', border:done?'none':'1.6px solid rgba(255,255,255,0.22)', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
        {done && <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>}
      </div>
      <span style={{flex:1, fontSize:13.5, fontWeight:500, color:done?DT.muted:DT.text, textDecoration:done?'line-through':'none'}}>{title}</span>
    </div>
  );
}

function SectionLabel({children, right}) {
  return (
    <div style={{display:'flex', alignItems:'baseline', justifyContent:'space-between', padding:'18px 22px 8px'}}>
      <span style={{fontSize:11, fontWeight:600, color:DT.muted, letterSpacing:0.8, textTransform:'uppercase'}}>{children}</span>
      {right && <span style={{fontSize:12, color:DT.accent, fontWeight:600}}>{right}</span>}
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:DT.bg, color:DT.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:120}}>
        <Hero/>

        {/* Progress mini */}
        <div style={{margin:'0 16px', background:DT.card, borderRadius:18, padding:'14px 16px', border:'1px solid rgba(255,255,255,0.03)'}}>
          <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', marginBottom:10}}>
            <span style={{fontSize:13, fontWeight:600, color:DT.text}}>Progreso</span>
            <span style={{fontSize:12, fontWeight:600, color:DT.muted}}>2/5 subtareas</span>
          </div>
          <div style={{height:6, borderRadius:99, background:'rgba(255,255,255,0.06)', overflow:'hidden'}}>
            <div style={{height:'100%', width:'40%', background:`linear-gradient(90deg, ${DT.accent}, ${DT.green})`, borderRadius:99}}/>
          </div>
        </div>

        {/* Meta card */}
        <div style={{margin:'12px 16px 0', background:DT.card, borderRadius:18, overflow:'hidden'}}>
          <MetaRow icon={dt.cal} label="Fecha y hora" value="Sábado 23 de mayo · 23:59" valueColor={DT.red}/>
          <MetaRow icon={dt.flag} label="Prioridad" value={<span style={{display:'inline-flex', alignItems:'center', gap:6}}><span style={{width:7, height:7, borderRadius:'50%', background:DT.red}}/>Alta</span>}/>
          <MetaRow icon={dt.folder} label="Curso" value={<span style={{display:'inline-flex', alignItems:'center', gap:6}}><span style={{width:7, height:7, borderRadius:'50%', background:DT.accent}}/>Cálculo III</span>}/>
          <MetaRow
            icon={(
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 22V4"/><path d="M5 4h12l-2.5 4.5L17 13H5"/>
              </svg>
            )}
            label="Proyecto"
            value={<span style={{display:'inline-flex', alignItems:'center', gap:6}}><span style={{width:7, height:7, borderRadius:'50%', background:DT.accent}}/>Matix · #1</span>}
          />
          <MetaRow icon={dt.rep} label="Repetición" value="No se repite"/>
          <MetaRow icon={dt.bell} label="Recordatorio" value="15 min y 2 h antes"/>
        </div>

        <SectionLabel>Subtareas · 2 de 5</SectionLabel>
        <div style={{padding:'0 16px'}}>
          <Subtask title="Repasar regla de la cadena" done/>
          <Subtask title="Hacer ejercicios 7.1 a 7.4" done/>
          <Subtask title="Ejercicio 7.5 — máximos y mínimos"/>
          <Subtask title="Ejercicio 7.6 — gradiente y direccional"/>
          <Subtask title="Revisar notas de la clase del jueves"/>
        </div>

        <SectionLabel>Nota</SectionLabel>
        <div style={{margin:'0 16px', padding:'14px 14px', background:DT.card, borderRadius:14, fontSize:13.5, color:DT.muted, lineHeight:1.55}}>
          Llevar resumen impreso de la fórmula del gradiente. El profesor mencionó que el 7.6 podría caer en el examen del viernes.
        </div>

        <SectionLabel right="Añadir">Adjuntos</SectionLabel>
        <div style={{padding:'0 16px', display:'flex', flexDirection:'column', gap:8}}>
          {[{n:'Problemario_cap7.pdf', s:'2.4 MB · PDF'}, {n:'Apuntes clase 12 — Taylor', s:'Apunte · Matix'}].map((a,i) => (
            <div key={i} style={{display:'flex', alignItems:'center', gap:12, padding:'12px 12px', background:DT.card, borderRadius:12}}>
              <div style={{width:32, height:32, borderRadius:9, background:hexA(DT.accent,0.14), color:DT.accent, display:'flex', alignItems:'center', justifyContent:'center'}}>{dt.link}</div>
              <div style={{flex:1, minWidth:0}}>
                <div style={{fontSize:13, fontWeight:600, color:DT.text, whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'}}>{a.n}</div>
                <div style={{fontSize:11, color:DT.muted, marginTop:2, fontWeight:500}}>{a.s}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Matix suggestion */}
        <div style={{margin:'18px 16px 0', padding:'14px 14px', background:DT.card, borderRadius:16, border:`1px solid ${hexA(DT.accent,0.35)}`, position:'relative', overflow:'hidden'}}>
          <div style={{position:'absolute', top:-30, right:-20, width:120, height:120, background:`radial-gradient(circle, ${hexA(DT.accent,0.16)} 0%, transparent 70%)`}}/>
          <div style={{position:'relative'}}>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'3px 9px 3px 8px', borderRadius:99, background:hexA(DT.accent,0.16), color:DT.accent, fontSize:10.5, fontWeight:700, letterSpacing:1.2}}>
              {dt.spark}<span>SUGERENCIA</span>
            </div>
            <div style={{marginTop:9, fontSize:13.5, color:DT.text, lineHeight:1.5, fontWeight:500}}>
              Te quedan 9 h y 3 subtareas. Bloqueo <span style={{color:DT.accent, fontWeight:700}}>14:00–16:00</span> en tu calendario para terminar a tiempo.
            </div>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, marginTop:10, padding:'7px 12px', borderRadius:10, background:DT.accent, color:'#fff', fontSize:12.5, fontWeight:600, boxShadow:'0 4px 12px rgba(45,127,249,0.30)'}}>
              Programar bloque
            </div>
          </div>
        </div>
      </div>

      {/* Footer actions */}
      <div style={{padding:'12px 16px 18px', background:`linear-gradient(180deg, rgba(11,15,26,0) 0%, ${DT.bg} 30%)`, display:'flex', gap:10}}>
        <div style={{padding:'14px 0', flex:1, borderRadius:14, background:'rgba(255,255,255,0.04)', color:DT.text, display:'flex', alignItems:'center', justifyContent:'center', fontSize:14, fontWeight:600}}>
          Editar
        </div>
        <div style={{padding:'14px 0', flex:1.4, borderRadius:14, background:DT.green, color:'#0B0F1A', display:'flex', alignItems:'center', justifyContent:'center', gap:8, fontSize:14, fontWeight:700, boxShadow:'0 10px 24px rgba(33,208,122,0.30)'}}>
          {dt.check}<span>Marcar hecha</span>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
