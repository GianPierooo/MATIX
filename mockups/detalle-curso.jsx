// Matix — Detalle de curso (Cálculo III)

const DC = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1B2138',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const COURSE = DC.accent;
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  mic: <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  clock: <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>,
  home: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/></svg>,
  tasks: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M7.5 9.5l2 2 4-4"/><path d="M7.5 15.5h9"/></svg>,
  cal: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  uni: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/></svg>,
  notes: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/></svg>,
  loc: <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 21s7-7.5 7-12a7 7 0 1 0-14 0c0 4.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.4"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 8px'}}>
      <a href="Universidad.html" style={{width:40, height:40, borderRadius:12, background:DC.card, color:DC.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ic.back}</a>
      <div style={{width:40, height:40, borderRadius:12, background:DC.card, color:DC.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{ic.more}</div>
    </div>
  );
}

function Hero() {
  return (
    <div style={{padding:'6px 20px 16px', position:'relative'}}>
      <div style={{display:'flex', alignItems:'center', gap:14}}>
        <div style={{width:60, height:60, borderRadius:'50%', background:hexA(COURSE,0.16), border:`1.5px solid ${hexA(COURSE,0.55)}`, color:COURSE, display:'flex', alignItems:'center', justifyContent:'center', fontSize:26, fontWeight:700, letterSpacing:-0.5, flexShrink:0, boxShadow:`0 0 24px ${hexA(COURSE,0.22)}`}}>
          C
        </div>
        <div style={{flex:1, minWidth:0}}>
          <div style={{fontSize:11, fontWeight:600, color:COURSE, letterSpacing:0.6, textTransform:'uppercase'}}>Curso · 4 créditos</div>
          <div style={{fontSize:24, fontWeight:700, color:DC.text, letterSpacing:-0.6, marginTop:3, lineHeight:1.1}}>Cálculo III</div>
        </div>
      </div>

      <div style={{marginTop:14, padding:'12px 14px', background:DC.card, borderRadius:14, display:'flex', alignItems:'center', gap:12, flexWrap:'wrap'}}>
        <Meta label="Profesor" value="Mendoza"/>
        <Divider/>
        <Meta label="Horario" value="Lun · Mié · 14:00"/>
        <Divider/>
        <Meta label="Aula" value="4B"/>
      </div>
    </div>
  );
}

function Meta({label, value}) {
  return (
    <div>
      <div style={{fontSize:10, fontWeight:600, color:DC.muted, letterSpacing:0.6, textTransform:'uppercase'}}>{label}</div>
      <div style={{fontSize:13, fontWeight:600, color:DC.text, marginTop:2, letterSpacing:-0.1}}>{value}</div>
    </div>
  );
}
function Divider() { return <div style={{width:1, height:24, background:DC.hairline}}/>; }

function GradeCard() {
  return (
    <div style={{margin:'0 16px', padding:'16px', background:DC.card, borderRadius:18, border:'1px solid rgba(255,255,255,0.03)', display:'flex', alignItems:'center', gap:16}}>
      <div style={{flex:'0 0 auto', position:'relative', width:84, height:84}}>
        <svg width="84" height="84" viewBox="0 0 84 84">
          <circle cx="42" cy="42" r="36" fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="6"/>
          <circle cx="42" cy="42" r="36" fill="none" stroke={COURSE} strokeWidth="6" strokeLinecap="round" strokeDasharray={`${0.79*226} 226`} transform="rotate(-90 42 42)"/>
        </svg>
        <div style={{position:'absolute', inset:0, display:'flex', flexDirection:'column', alignItems:'center', justifyContent:'center'}}>
          <span style={{fontSize:22, fontWeight:700, color:DC.text, letterSpacing:-0.8, lineHeight:1}}>15.8</span>
          <span style={{fontSize:10, color:DC.muted, fontWeight:600, marginTop:2}}>/20</span>
        </div>
      </div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{fontSize:11, fontWeight:600, color:DC.muted, letterSpacing:0.6, textTransform:'uppercase'}}>Nota actual</div>
        <div style={{display:'flex', alignItems:'baseline', gap:6, marginTop:4}}>
          <span style={{fontSize:13, fontWeight:600, color:DC.text}}>Mínimo necesario</span>
          <span style={{fontSize:13, fontWeight:700, color:DC.amber, letterSpacing:-0.2}}>14.2</span>
        </div>
        <div style={{display:'flex', alignItems:'center', gap:8, marginTop:8, fontSize:11, color:DC.muted, fontWeight:500}}>
          <span style={{padding:'2px 7px', borderRadius:6, background:hexA(DC.green,0.14), color:DC.green, fontWeight:700}}>3 evaluadas</span>
          <span style={{padding:'2px 7px', borderRadius:6, background:'rgba(255,255,255,0.04)', color:DC.muted, fontWeight:600}}>4 restantes</span>
        </div>
      </div>
    </div>
  );
}

function Tabs({active}) {
  const tabs = ['Entregas', 'Exámenes', 'Notas', 'Apuntes'];
  return (
    <div style={{display:'flex', gap:8, padding:'18px 20px 12px', overflowX:'auto'}}>
      {tabs.map(t => (
        <div key={t} style={{flexShrink:0, padding:'8px 14px', borderRadius:99, background:t===active?COURSE:DC.card, color:t===active?'#fff':DC.muted, fontSize:13, fontWeight:t===active?600:500, boxShadow:t===active?`0 4px 14px ${hexA(COURSE,0.35)}`:'none'}}>
          {t}
        </div>
      ))}
    </div>
  );
}

function DeliveryCard({title, due, dueColor, status, statusColor}) {
  const isDone = status === 'Entregada';
  return (
    <div style={{margin:'6px 16px', padding:'14px 14px', background:DC.card, border:'1px solid rgba(255,255,255,0.03)', borderRadius:14}}>
      <div style={{display:'flex', alignItems:'flex-start', justifyContent:'space-between', gap:8}}>
        <div style={{flex:1, minWidth:0}}>
          <div style={{fontSize:14.5, fontWeight:600, color:isDone?DC.muted:DC.text, textDecoration:isDone?'line-through':'none', letterSpacing:-0.15, lineHeight:1.25}}>{title}</div>
          <div style={{display:'inline-flex', alignItems:'center', gap:5, marginTop:8, padding:'3px 9px', borderRadius:8, background:hexA(dueColor,0.14), border:`1px solid ${hexA(dueColor,0.32)}`, color:dueColor, fontSize:11.5, fontWeight:700}}>
            {ic.clock}<span>{due}</span>
          </div>
        </div>
        <span style={{padding:'3px 9px', borderRadius:99, background:hexA(statusColor,0.14), border:`1px solid ${hexA(statusColor,0.32)}`, color:statusColor, fontSize:11, fontWeight:700, whiteSpace:'nowrap', flexShrink:0, marginTop:2}}>{status}</span>
      </div>
    </div>
  );
}

function FAB() {
  return (
    <div style={{position:'absolute', right:18, bottom:96, width:60, height:60, borderRadius:'50%', background:DC.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)'}}>{ic.mic}</div>
  );
}

function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ic.home},
    {key:'tasks', label:'Tareas', icon:ic.tasks},
    {key:'cal', label:'Calendario', icon:ic.cal},
    {key:'uni', label:'Universidad', icon:ic.uni, active:true},
    {key:'notes', label:'Apuntes', icon:ic.notes},
  ];
  return (
    <div style={{background:DC.bg, borderTop:`1px solid ${DC.hairline}`, padding:'10px 8px 8px', display:'flex', justifyContent:'space-around'}}>
      {items.map(it => (
        <div key={it.key} style={{display:'flex', flexDirection:'column', alignItems:'center', gap:4, flex:1, padding:'4px 0', color:it.active?DC.accent:DC.muted}}>
          {it.active ? <div style={{padding:'4px 14px', borderRadius:999, background:'rgba(45,127,249,0.16)', display:'flex', alignItems:'center', justifyContent:'center'}}>{it.icon}</div> : it.icon}
          <span style={{fontSize:10.5, fontWeight:it.active?600:500, letterSpacing:0.1}}>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:DC.bg, color:DC.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>
      <div style={{flex:1, overflowY:'auto', paddingBottom:160}}>
        <Hero/>
        <GradeCard/>
        <Tabs active="Entregas"/>

        {/* Group: this week */}
        <div style={{display:'flex', alignItems:'center', gap:10, padding:'4px 22px 4px'}}>
          <span style={{fontSize:11, fontWeight:600, color:DC.muted, letterSpacing:0.8, textTransform:'uppercase'}}>Esta semana</span>
          <div style={{flex:1, height:1, background:DC.hairline}}/>
        </div>

        <DeliveryCard
          title="Problemario capítulo 7 — derivadas parciales"
          due="Hoy · 23:59" dueColor={DC.red}
          status="Pendiente" statusColor={DC.amber}
        />
        <DeliveryCard
          title="Trabajo grupal — Aplicaciones del gradiente"
          due="Mar 26 · 18:00" dueColor={DC.amber}
          status="Pendiente" statusColor={DC.amber}
        />

        <div style={{display:'flex', alignItems:'center', gap:10, padding:'14px 22px 4px'}}>
          <span style={{fontSize:11, fontWeight:600, color:DC.muted, letterSpacing:0.8, textTransform:'uppercase'}}>Próximamente</span>
          <div style={{flex:1, height:1, background:DC.hairline}}/>
        </div>

        <DeliveryCard
          title="Proyecto final — Modelado vectorial"
          due="Jun 10 · 23:59" dueColor={DC.accent}
          status="Pendiente" statusColor={DC.muted}
        />

        <div style={{display:'flex', alignItems:'center', gap:10, padding:'14px 22px 4px'}}>
          <span style={{fontSize:11, fontWeight:600, color:DC.muted, letterSpacing:0.8, textTransform:'uppercase'}}>Entregadas · 2</span>
          <div style={{flex:1, height:1, background:DC.hairline}}/>
        </div>

        <DeliveryCard
          title="Problemario capítulo 6 — integrales múltiples"
          due="May 16 · 23:59" dueColor={DC.muted}
          status="Entregada" statusColor={DC.green}
        />
        <DeliveryCard
          title="Quiz 2 — series de Taylor"
          due="May 9 · 14:00" dueColor={DC.muted}
          status="Entregada" statusColor={DC.green}
        />
      </div>

      <MatixFAB/>
      <MatixBottomNav active="uni"/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
