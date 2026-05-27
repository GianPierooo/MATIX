// Matix — Notificaciones

const NT = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  settings: <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1A2 2 0 1 1 7 4.5l.1.1a1.7 1.7 0 0 0 1.8.3 1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8 1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>,
  task: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l2 2 4-4"/></svg>,
  cal: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  uni: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/></svg>,
  alert: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 2.8 17a2 2 0 0 0 1.7 3h15a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg>,
  spark: <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  check: <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 10px'}}>
      <div style={{display:'flex', alignItems:'center', gap:10}}>
        <a href="Inicio.html" style={{width:40, height:40, borderRadius:12, background:NT.card, color:NT.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ic.back}</a>
        <div style={{display:'flex', flexDirection:'column'}}>
          <span style={{fontSize:18, fontWeight:700, color:NT.text, letterSpacing:-0.3, lineHeight:1.1}}>Notificaciones</span>
          <span style={{fontSize:11.5, color:NT.muted, marginTop:2, fontWeight:500}}>3 nuevas · 12 total</span>
        </div>
      </div>
      <div style={{width:40, height:40, borderRadius:12, background:NT.card, color:NT.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{ic.settings}</div>
    </div>
  );
}

function Chips() {
  const tabs = [{l:'Todas', a:true, n:12}, {l:'No leídas', n:3}, {l:'Cursos'}, {l:'Matix'}];
  return (
    <div style={{display:'flex', gap:8, padding:'4px 16px 12px', overflowX:'auto'}}>
      {tabs.map((t,i) => (
        <div key={i} style={{flexShrink:0, display:'flex', alignItems:'center', gap:6, padding:'8px 13px', borderRadius:99, background:t.a?NT.accent:NT.card, color:t.a?'#fff':NT.muted, fontSize:12.5, fontWeight:t.a?600:500, boxShadow:t.a?'0 4px 14px rgba(45,127,249,0.30)':'none'}}>
          {t.l}
          {t.n && <span style={{padding:'1px 6px', borderRadius:99, background:t.a?'rgba(255,255,255,0.22)':'rgba(255,255,255,0.05)', fontSize:10, fontWeight:700}}>{t.n}</span>}
        </div>
      ))}
    </div>
  );
}

function Section({label, action}) {
  return (
    <div style={{display:'flex', alignItems:'baseline', justifyContent:'space-between', padding:'10px 22px 6px'}}>
      <span style={{fontSize:11, fontWeight:600, color:NT.muted, letterSpacing:0.8, textTransform:'uppercase'}}>{label}</span>
      {action && <span style={{fontSize:12, color:NT.accent, fontWeight:600}}>{action}</span>}
    </div>
  );
}

function Notif({icon, kindColor, title, body, time, unread, urgent, actions}) {
  return (
    <div style={{margin:'4px 16px', padding:'12px 14px', background:unread?NT.card:'rgba(255,255,255,0.025)', borderRadius:14, border: urgent?`1px solid ${hexA(NT.red,0.30)}` : '1px solid rgba(255,255,255,0.03)', display:'flex', gap:12, position:'relative'}}>
      {unread && <span style={{position:'absolute', top:14, left:-2, width:5, height:24, borderRadius:99, background:NT.accent, boxShadow:`0 0 8px ${hexA(NT.accent,0.7)}`}}/>}

      <div style={{width:36, height:36, borderRadius:10, background:hexA(kindColor,0.14), border:`1px solid ${hexA(kindColor,0.30)}`, color:kindColor, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{icon}</div>

      <div style={{flex:1, minWidth:0}}>
        <div style={{display:'flex', alignItems:'baseline', justifyContent:'space-between', gap:8}}>
          <div style={{fontSize:14, fontWeight:unread?700:600, color:NT.text, letterSpacing:-0.1, lineHeight:1.25, flex:1}}>{title}</div>
          <span style={{fontSize:10.5, color:NT.muted, fontWeight:500, whiteSpace:'nowrap', flexShrink:0}}>{time}</span>
        </div>
        <div style={{fontSize:12.5, color:NT.muted, marginTop:4, lineHeight:1.45, fontWeight:500}}>{body}</div>
        {actions && (
          <div style={{display:'flex', gap:6, marginTop:10}}>
            {actions.map((a,i) => (
              <div key={i} style={{padding:'6px 11px', borderRadius:8, background:a.primary?NT.accent:'rgba(255,255,255,0.04)', color:a.primary?'#fff':NT.text, fontSize:11.5, fontWeight:700, display:'inline-flex', alignItems:'center', gap:5, boxShadow:a.primary?'0 4px 12px rgba(45,127,249,0.25)':'none'}}>
                {a.icon}{a.l}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:NT.bg, color:NT.text, height:'100%', display:'flex', flexDirection:'column', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>
      <Chips/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:24}}>
        <Section label="Nuevas · 3" action="Marcar como leídas"/>
        <Notif
          icon={ic.alert} kindColor={NT.red} urgent unread
          title="Entrega de Física vence en 1 hora"
          body="Laboratorio 4 — Circuitos RC. Aún no marcas como completada."
          time="ahora"
          actions={[{l:'Marcar hecha', primary:true, icon:ic.check}, {l:'Recordar 30 min'}]}
        />
        <Notif
          icon={ic.spark} kindColor={NT.accent} unread
          title="Matix te armó el plan del sábado"
          body="4 bloques de trabajo, sin chocar con la clase de Cálculo. Toca para revisarlo."
          time="hace 12 min"
          actions={[{l:'Ver plan', primary:true}, {l:'Descartar'}]}
        />
        <Notif
          icon={ic.uni} kindColor={NT.purple} unread
          title="Nueva entrega en Filosofía de la Ciencia"
          body="Prof. Aguirre publicó un ensayo corto. Fecha límite: 4 de junio."
          time="hace 1 h"
        />

        <Section label="Hoy"/>
        <Notif
          icon={ic.cal} kindColor={NT.accent}
          title="Cálculo III — Clase en 4 horas"
          body="Aula 4B · 14:00 — 15:30"
          time="09:00"
        />
        <Notif
          icon={ic.task} kindColor={NT.amber}
          title="Recordatorio: repasar derivadas parciales"
          body="Bloque sugerido por Matix: 11:00 — 12:30"
          time="08:30"
        />

        <Section label="Ayer"/>
        <Notif
          icon={ic.uni} kindColor={NT.green}
          title="Calificación publicada — Estadística II"
          body="Quiz 3: 17 / 20. Tu promedio sube a 17.2."
          time="ayer · 18:42"
        />
        <Notif
          icon={ic.spark} kindColor={NT.accent}
          title="Resumen semanal listo"
          body="Avanzaste un 14% más que la semana pasada. Tu mejor materia: Estadística II."
          time="ayer · 21:00"
        />
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
