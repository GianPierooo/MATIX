// Matix — Modal de confirmación (eliminar tarea)

const MD = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1F2542',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  trash: <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M5 7h14"/><path d="M10 11v6M14 11v6"/><path d="M6 7l1 12.5a1.5 1.5 0 0 0 1.5 1.5h7a1.5 1.5 0 0 0 1.5-1.5L18 7"/><path d="M9 7V4.5h6V7"/></svg>,
  check: <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>,
};

function BgScreen() {
  // Faded "Detalle de tarea" behind
  return (
    <div style={{position:'absolute', inset:0, background:MD.bg, opacity:0.6, pointerEvents:'none'}}>
      <div style={{padding:'14px 14px 8px', display:'flex', justifyContent:'space-between'}}>
        <div style={{width:40, height:40, borderRadius:12, background:MD.card}}/>
        <div style={{display:'flex', gap:8}}>
          <div style={{width:40, height:40, borderRadius:12, background:MD.card}}/>
          <div style={{width:40, height:40, borderRadius:12, background:MD.card}}/>
        </div>
      </div>
      <div style={{padding:'8px 20px 16px'}}>
        <div style={{height:24, width:'60%', background:MD.card, borderRadius:8}}/>
        <div style={{marginTop:12, height:32, width:'90%', background:MD.card, borderRadius:8}}/>
        <div style={{marginTop:6, height:32, width:'70%', background:MD.card, borderRadius:8}}/>
      </div>
      <div style={{padding:'0 16px'}}>
        <div style={{height:240, background:MD.card, borderRadius:18}}/>
        <div style={{marginTop:14, height:120, background:MD.card, borderRadius:18}}/>
      </div>
    </div>
  );
}

function Scrim() {
  return <div style={{position:'absolute', inset:0, background:'rgba(0,0,0,0.65)', backdropFilter:'blur(3px)'}}/>;
}

function Dialog() {
  return (
    <div style={{
      position:'absolute', left:'50%', top:'50%', transform:'translate(-50%,-50%)',
      width:'calc(100% - 40px)', maxWidth:340,
      background:MD.cardHi, borderRadius:22,
      padding:24,
      border:`1px solid ${hexA(MD.red,0.25)}`,
      boxShadow:`0 30px 80px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.04)`,
      textAlign:'center',
    }}>
      {/* Glow */}
      <div style={{position:'absolute', top:-20, left:'50%', transform:'translateX(-50%)', width:200, height:120, background:`radial-gradient(circle, ${hexA(MD.red,0.18)} 0%, transparent 70%)`, pointerEvents:'none', borderRadius:'50%'}}/>

      <div style={{position:'relative'}}>
        <div style={{
          width:62, height:62, borderRadius:'50%',
          background: hexA(MD.red, 0.16),
          border: `1.5px solid ${hexA(MD.red, 0.50)}`,
          color: MD.red,
          display:'flex', alignItems:'center', justifyContent:'center',
          margin:'0 auto 14px',
          boxShadow: `0 0 0 8px ${hexA(MD.red, 0.06)}`,
        }}>{ic.trash}</div>

        <div style={{fontSize:18, fontWeight:700, color:MD.text, letterSpacing:-0.3, lineHeight:1.25}}>
          ¿Eliminar esta tarea?
        </div>
        <div style={{marginTop:8, fontSize:13.5, color:MD.muted, lineHeight:1.5, fontWeight:500, padding:'0 4px'}}>
          Vas a eliminar <b style={{color:MD.text, fontWeight:600}}>“Resolver problemario del capítulo 7”</b> y sus 5 subtareas. Esta acción no se puede deshacer.
        </div>

        {/* Optional opt-in */}
        <div style={{marginTop:14, display:'flex', alignItems:'center', gap:8, padding:'8px 10px', borderRadius:10, background:'rgba(255,255,255,0.03)', justifyContent:'flex-start'}}>
          <div style={{width:18, height:18, borderRadius:5, background:MD.accent, display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
            {ic.check}
          </div>
          <span style={{fontSize:12, color:MD.muted, fontWeight:500, textAlign:'left'}}>
            También cancelar el bloque en mi calendario
          </span>
        </div>

        <div style={{display:'flex', gap:10, marginTop:18}}>
          <a href="Detalle%20Tarea.html" style={{flex:1, padding:'13px 0', borderRadius:13, background:'rgba(255,255,255,0.05)', color:MD.text, display:'flex', alignItems:'center', justifyContent:'center', fontSize:14, fontWeight:600, textDecoration:'none'}}>
            Cancelar
          </a>
          <a href="Tareas.html" style={{flex:1, padding:'13px 0', borderRadius:13, background:MD.red, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', fontSize:14, fontWeight:700, boxShadow:`0 10px 24px ${hexA(MD.red,0.40)}`, textDecoration:'none'}}>
            Eliminar
          </a>
        </div>
      </div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:MD.bg, color:MD.text, height:'100%', position:'relative', overflow:'hidden', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <BgScreen/>
      <Scrim/>
      <Dialog/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
