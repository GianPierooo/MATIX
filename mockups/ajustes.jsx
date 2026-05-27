// Matix — Perfil y ajustes

const AJ = {
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
  chev: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6l6 6-6 6"/></svg>,
  user: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></svg>,
  bell: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2H4.5z"/><path d="M10.5 21h3"/></svg>,
  theme: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 0 0 18"/><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor" opacity="0.5"/></svg>,
  spark: <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  shield: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l8 3v6c0 4.5-3.5 8.5-8 9-4.5-.5-8-4.5-8-9V6z"/></svg>,
  globe: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/></svg>,
  sync: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12a8 8 0 0 1 14-5.3L20 9"/><path d="M20 5v4h-4"/><path d="M20 12a8 8 0 0 1-14 5.3L4 15"/><path d="M4 19v-4h4"/></svg>,
  help: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 0 1 5 0c0 1.5-2.5 2-2.5 3.5"/><circle cx="12" cy="17" r="0.8" fill="currentColor"/></svg>,
  star: <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3l2.5 6 6.5.7-5 4.5L17.5 21 12 17.5 6.5 21l1.5-6.8-5-4.5 6.5-.7z"/></svg>,
  logout: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M9 4H5a1 1 0 0 0-1 1v14a1 1 0 0 0 1 1h4"/><path d="M16 8l4 4-4 4M20 12H10"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 10px', position:'relative'}}>
      <a href="Inicio.html" style={{width:40, height:40, borderRadius:12, background:AJ.card, color:AJ.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ic.back}</a>
      <div style={{position:'absolute', left:0, right:0, textAlign:'center', pointerEvents:'none'}}>
        <span style={{fontSize:16, fontWeight:600, color:AJ.text, letterSpacing:-0.1}}>Perfil y ajustes</span>
      </div>
      <div style={{width:40, height:40}}/>
    </div>
  );
}

function Profile() {
  return (
    <div style={{margin:'12px 16px 0', padding:'18px 16px', background:AJ.card, borderRadius:18, border:'1px solid rgba(255,255,255,0.03)', display:'flex', alignItems:'center', gap:14, position:'relative', overflow:'hidden'}}>
      <div style={{position:'absolute', top:-40, right:-30, width:180, height:180, background:`radial-gradient(circle, ${hexA(AJ.accent,0.14)} 0%, transparent 70%)`, pointerEvents:'none'}}/>
      <div style={{position:'relative', width:60, height:60, borderRadius:'50%', background:`linear-gradient(135deg, ${AJ.accent}, ${AJ.purple})`, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', fontSize:22, fontWeight:700, letterSpacing:-0.3, boxShadow:`0 6px 20px ${hexA(AJ.accent,0.35)}`, flexShrink:0}}>LV</div>
      <div style={{position:'relative', flex:1, minWidth:0}}>
        <div style={{fontSize:18, fontWeight:700, color:AJ.text, letterSpacing:-0.3, lineHeight:1.15}}>Lucas Velarde</div>
        <div style={{fontSize:12.5, color:AJ.muted, marginTop:3, fontWeight:500}}>lucas.velarde@uni.pe</div>
        <div style={{marginTop:8, display:'inline-flex', alignItems:'center', gap:5, padding:'3px 9px 3px 8px', borderRadius:99, background:hexA(AJ.amber,0.14), border:`1px solid ${hexA(AJ.amber,0.32)}`, color:AJ.amber, fontSize:10.5, fontWeight:700, letterSpacing:0.5}}>
          {ic.star}<span>MATIX PRO</span>
        </div>
      </div>
      <span style={{position:'relative', color:AJ.muted}}>{ic.chev}</span>
    </div>
  );
}

function Stat({label, value, color}) {
  return (
    <div style={{flex:1, display:'flex', flexDirection:'column', alignItems:'center', padding:'10px 0'}}>
      <span style={{fontSize:22, fontWeight:700, color:color||AJ.text, letterSpacing:-0.5}}>{value}</span>
      <span style={{fontSize:10.5, color:AJ.muted, fontWeight:600, marginTop:3, letterSpacing:0.4, textTransform:'uppercase'}}>{label}</span>
    </div>
  );
}

function Stats() {
  return (
    <div style={{margin:'12px 16px 0', background:AJ.card, borderRadius:18, padding:'8px 4px', display:'flex', border:'1px solid rgba(255,255,255,0.03)'}}>
      <Stat label="Tareas hechas" value="248" color={AJ.green}/>
      <div style={{width:1, alignSelf:'center', height:36, background:AJ.hairline}}/>
      <Stat label="Promedio" value="16.4" color={AJ.accent}/>
      <div style={{width:1, alignSelf:'center', height:36, background:AJ.hairline}}/>
      <Stat label="Racha" value="14d" color={AJ.amber}/>
    </div>
  );
}

function Section({children}) {
  return <div style={{padding:'18px 22px 8px', fontSize:11, fontWeight:600, color:AJ.muted, letterSpacing:0.8, textTransform:'uppercase'}}>{children}</div>;
}

function Row({icon, color, label, value, toggle, danger, last}) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:14, padding:'13px 16px', borderBottom: last?'none':`1px solid ${AJ.hairline}`}}>
      <div style={{width:34, height:34, borderRadius:10, background:hexA(color||AJ.muted,0.14), color:color||AJ.muted, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>{icon}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{fontSize:14, fontWeight:600, color:danger?AJ.red:AJ.text, letterSpacing:-0.1}}>{label}</div>
        {value && <div style={{fontSize:11.5, color:AJ.muted, marginTop:2, fontWeight:500}}>{value}</div>}
      </div>
      {toggle !== undefined ? (
        <div style={{width:42, height:24, borderRadius:99, background:toggle?AJ.accent:'rgba(255,255,255,0.08)', position:'relative', flexShrink:0}}>
          <div style={{position:'absolute', top:2, left:toggle?20:2, width:20, height:20, borderRadius:'50%', background:'#fff', boxShadow:'0 2px 6px rgba(0,0,0,0.3)'}}/>
        </div>
      ) : <span style={{color:AJ.muted}}>{ic.chev}</span>}
    </div>
  );
}

function Card({children}) {
  return <div style={{margin:'0 16px', background:AJ.card, borderRadius:16, overflow:'hidden', border:'1px solid rgba(255,255,255,0.03)'}}>{children}</div>;
}

function Screen() {
  return (
    <div style={{background:AJ.bg, color:AJ.text, height:'100%', display:'flex', flexDirection:'column', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:30}}>
        <Profile/>
        <Stats/>

        <Section>Cuenta</Section>
        <Card>
          <Row icon={ic.user} color={AJ.accent} label="Datos personales" value="Nombre, correo, foto"/>
          <Row icon={ic.shield} color={AJ.green} label="Privacidad y seguridad" value="Contraseña, 2FA, sesiones" last/>
        </Card>

        <Section>Matix · Asistente</Section>
        <Card>
          <Row icon={ic.spark} color={AJ.accent} label="Personalidad" value="Equilibrada"/>
          <Row icon={ic.bell} color={AJ.amber} label="Sugerencias automáticas" value="Plan del día y bloques de estudio" toggle={true}/>
          <Row icon={ic.sync} color={AJ.purple} label="Sincronizar con calendario" value="Google Calendar conectado" toggle={true} last/>
        </Card>

        <Section>Apariencia</Section>
        <Card>
          <Row icon={ic.theme} color={AJ.purple} label="Tema" value="Oscuro"/>
          <Row icon={ic.globe} color={AJ.accent} label="Idioma" value="Español (PE)" last/>
        </Card>

        <Section>Notificaciones</Section>
        <Card>
          <Row icon={ic.bell} color={AJ.amber} label="Push" value="Tareas y eventos" toggle={true}/>
          <Row icon={ic.bell} color={AJ.green} label="Recordatorios" value="15 min antes por defecto" toggle={true}/>
          <Row icon={ic.bell} color={AJ.muted} label="Resumen semanal" toggle={false} last/>
        </Card>

        <Section>Soporte</Section>
        <Card>
          <Row icon={ic.help} color={AJ.accent} label="Centro de ayuda"/>
          <Row icon={ic.star} color={AJ.amber} label="Calificar Matix" last/>
        </Card>

        <div style={{padding:'18px 16px 0'}}>
          <div style={{padding:'13px 16px', background:hexA(AJ.red,0.10), border:`1px solid ${hexA(AJ.red,0.25)}`, borderRadius:14, display:'flex', alignItems:'center', gap:12, color:AJ.red}}>
            <div style={{width:34, height:34, borderRadius:10, background:hexA(AJ.red,0.14), display:'flex', alignItems:'center', justifyContent:'center'}}>{ic.logout}</div>
            <span style={{flex:1, fontSize:14, fontWeight:700}}>Cerrar sesión</span>
          </div>
        </div>

        <div style={{textAlign:'center', padding:'18px 0', fontSize:11, color:AJ.muted, fontWeight:500, letterSpacing:0.2}}>
          Matix v2.4.1 · made with care
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
