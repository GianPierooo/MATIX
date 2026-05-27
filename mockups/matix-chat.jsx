// Matix — Chat con el asistente

const MX = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1B2138',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const mx = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  spark: <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  sparkBig: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.5l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  send: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12 20 4l-3 16-4-7z"/></svg>,
  mic: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  attach: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 5v14M5 12h14"/></svg>,
  check: <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>,
  copy: <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M4 16V6a2 2 0 0 1 2-2h10"/></svg>,
  thumb: <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M7 10h-3v10h3z"/><path d="M7 10l4-6c1.5 0 2.5 1 2.5 2.5V10h5a2 2 0 0 1 2 2.3l-1 6A2 2 0 0 1 17.5 20H7"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 10px', borderBottom:`1px solid ${MX.hairline}`}}>
      <a href="Inicio.html" style={{width:40, height:40, borderRadius:12, background:MX.card, color:MX.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{mx.close}</a>
      <div style={{display:'flex', alignItems:'center', gap:10}}>
        <div style={{width:32, height:32, borderRadius:'50%', background:hexA(MX.accent,0.16), border:`1.5px solid ${MX.accent}`, color:MX.accent, display:'flex', alignItems:'center', justifyContent:'center', boxShadow:`0 0 0 3px ${hexA(MX.accent,0.10)}`}}>
          {mx.sparkBig}
        </div>
        <div style={{display:'flex', flexDirection:'column'}}>
          <span style={{fontSize:14.5, fontWeight:700, color:MX.text, letterSpacing:-0.2}}>Matix</span>
          <span style={{fontSize:11, color:MX.green, fontWeight:600, display:'inline-flex', alignItems:'center', gap:5}}>
            <span style={{width:6, height:6, borderRadius:'50%', background:MX.green, boxShadow:`0 0 8px ${MX.green}`}}/>
            Activo
          </span>
        </div>
      </div>
      <div style={{width:40, height:40, borderRadius:12, background:MX.card, color:MX.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{mx.more}</div>
    </div>
  );
}

function DayDivider({label}) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:8, padding:'10px 22px 4px'}}>
      <div style={{flex:1, height:1, background:MX.hairline}}/>
      <span style={{fontSize:10.5, fontWeight:600, color:MX.muted, letterSpacing:0.8, textTransform:'uppercase'}}>{label}</span>
      <div style={{flex:1, height:1, background:MX.hairline}}/>
    </div>
  );
}

function UserMsg({children, time}) {
  return (
    <div style={{padding:'6px 16px', display:'flex', justifyContent:'flex-end'}}>
      <div style={{maxWidth:'78%', display:'flex', flexDirection:'column', alignItems:'flex-end'}}>
        <div style={{padding:'10px 14px', background:MX.accent, color:'#fff', borderRadius:'16px 16px 4px 16px', fontSize:14, lineHeight:1.45, fontWeight:500, boxShadow:'0 4px 14px rgba(45,127,249,0.25)'}}>
          {children}
        </div>
        <div style={{fontSize:10.5, color:MX.muted, marginTop:4, fontWeight:500}}>{time}</div>
      </div>
    </div>
  );
}

function MatixMsg({children, time, actions, planCard}) {
  return (
    <div style={{padding:'6px 16px', display:'flex', gap:10, alignItems:'flex-start'}}>
      <div style={{width:28, height:28, borderRadius:'50%', background:hexA(MX.accent,0.16), border:`1.2px solid ${MX.accent}`, color:MX.accent, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, marginTop:2}}>
        {mx.spark}
      </div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{padding:'11px 14px', background:MX.card, color:MX.text, borderRadius:'4px 16px 16px 16px', fontSize:14, lineHeight:1.55, fontWeight:400, border:'1px solid rgba(255,255,255,0.03)'}}>
          {children}
          {planCard}
        </div>
        <div style={{display:'flex', alignItems:'center', gap:10, marginTop:6, padding:'0 4px'}}>
          <span style={{fontSize:10.5, color:MX.muted, fontWeight:500}}>{time}</span>
          {actions !== false && (
            <>
              <span style={{flex:1}}/>
              <div style={{display:'flex', gap:4, color:MX.muted}}>
                <div style={{width:24, height:24, borderRadius:7, display:'flex', alignItems:'center', justifyContent:'center'}}>{mx.copy}</div>
                <div style={{width:24, height:24, borderRadius:7, display:'flex', alignItems:'center', justifyContent:'center'}}>{mx.thumb}</div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function PlanCard() {
  const items = [
    {t:'11:00 — 12:30', l:'Repasar derivadas parciales', c:MX.amber},
    {t:'14:00 — 15:30', l:'Clase de Cálculo III', c:MX.accent},
    {t:'18:00 — 20:00', l:'Laboratorio de Física', c:MX.red, urgent:true},
    {t:'21:00 — 22:00', l:'Revisar correo del tutor', c:MX.green},
  ];
  return (
    <div style={{marginTop:10, background:'rgba(255,255,255,0.025)', border:`1px solid ${MX.hairline}`, borderRadius:12, padding:'10px 12px'}}>
      <div style={{display:'flex', alignItems:'center', gap:6, fontSize:10.5, fontWeight:700, color:MX.accent, letterSpacing:0.6, textTransform:'uppercase', marginBottom:6}}>
        {mx.spark}<span>Plan sugerido · sábado</span>
      </div>
      {items.map((it,i) => (
        <div key={i} style={{display:'flex', alignItems:'center', gap:10, padding:'6px 0', borderBottom:i<items.length-1?`1px dashed ${MX.hairline}`:'none'}}>
          <span style={{width:5, height:5, borderRadius:'50%', background:it.c, flexShrink:0, boxShadow:`0 0 6px ${hexA(it.c,0.5)}`}}/>
          <span style={{fontSize:11, fontWeight:600, color:MX.muted, width:84, flexShrink:0, letterSpacing:0.2}}>{it.t}</span>
          <span style={{fontSize:12.5, fontWeight:500, color:MX.text, flex:1, minWidth:0}}>{it.l}</span>
          {it.urgent && <span style={{padding:'1px 6px', borderRadius:5, background:hexA(MX.red,0.14), border:`1px solid ${hexA(MX.red,0.35)}`, color:MX.red, fontSize:9, fontWeight:700, letterSpacing:0.3}}>URGENTE</span>}
        </div>
      ))}
      <div style={{display:'flex', gap:6, marginTop:10}}>
        <div style={{flex:1, padding:'9px 0', borderRadius:9, background:MX.accent, color:'#fff', fontSize:12, fontWeight:700, textAlign:'center', boxShadow:'0 4px 12px rgba(45,127,249,0.30)'}}>
          Agregar al calendario
        </div>
        <div style={{padding:'9px 14px', borderRadius:9, background:'rgba(255,255,255,0.04)', color:MX.text, fontSize:12, fontWeight:600, textAlign:'center'}}>
          Ajustar
        </div>
      </div>
    </div>
  );
}

function Suggestions() {
  const sug = [
    'Crear tarea para mañana',
    '¿Cómo voy en Cálculo?',
    'Resumir mis apuntes',
  ];
  return (
    <div style={{display:'flex', gap:7, padding:'8px 16px 6px', overflowX:'auto'}}>
      {sug.map((s,i) => (
        <div key={i} style={{flexShrink:0, padding:'8px 12px', borderRadius:99, background:MX.card, color:MX.text, fontSize:12.5, fontWeight:500, border:'1px solid rgba(255,255,255,0.04)'}}>
          {s}
        </div>
      ))}
    </div>
  );
}

function Composer() {
  return (
    <div style={{padding:'8px 12px 14px', borderTop:`1px solid ${MX.hairline}`, background:MX.bg, display:'flex', alignItems:'center', gap:8}}>
      <div style={{width:40, height:40, borderRadius:12, background:MX.card, color:MX.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{mx.attach}</div>
      <div style={{flex:1, minHeight:44, padding:'12px 16px', background:MX.card, borderRadius:14, color:MX.muted, fontSize:14, fontWeight:500, display:'flex', alignItems:'center', border:'1px solid rgba(255,255,255,0.04)'}}>
        Pregunta a Matix…
      </div>
      <a href="Matix%20Escuchando.html" style={{width:44, height:44, borderRadius:14, background:MX.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0, boxShadow:'0 6px 16px rgba(45,127,249,0.35)', textDecoration:'none'}}>{mx.mic}</a>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:MX.bg, color:MX.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingTop:6, paddingBottom:6}}>
        <DayDivider label="Hoy · 09:42"/>
        <MatixMsg time="09:42" actions={false}>
          Buenos días, Lucas. Tienes <b>3 tareas para hoy</b> y la entrega de Física vence esta noche. ¿Quieres que arme un plan?
        </MatixMsg>

        <UserMsg time="09:43">Sí, organízame el día.</UserMsg>

        <MatixMsg time="09:43" planCard={<PlanCard/>}>
          Listo. Distribuí tus tareas alrededor de la clase de Cálculo y dejé margen para el laboratorio de Física, que es lo más urgente.
        </MatixMsg>

        <UserMsg time="09:44">¿Cuánto me falta para preparar el examen de Cálculo del viernes?</UserMsg>

        <MatixMsg time="09:44">
          Te quedan <b>5 días</b>. Cubriste 4 de los 7 temas (integrales múltiples, Taylor, derivadas parciales, gradiente). Faltan <b>direccionales, optimización y un repaso general</b>. Si dedicas 1 h diaria deberías llegar bien.
        </MatixMsg>
      </div>

      <Suggestions/>
      <Composer/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
