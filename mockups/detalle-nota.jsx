// Matix — Detalle / Editor de nota

const DN = {
  bg:'#0B0F1A', card:'#161B2E', cardHi:'#1B2138',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ni = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  pin: <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M14 2l8 8-4 2-2 6-4-4-6 6v-4l6-6-4-4 6-2z"/></svg>,
  share: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="18" cy="5" r="2.5"/><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="19" r="2.5"/><path d="M8.2 10.8 15.8 6.5M8.2 13.2 15.8 17.5"/></svg>,
  bold: <span style={{fontWeight:800, fontSize:15, color:'currentColor'}}>B</span>,
  italic: <span style={{fontStyle:'italic', fontWeight:600, fontSize:15, color:'currentColor', fontFamily:'serif'}}>I</span>,
  list: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6h11M9 12h11M9 18h11"/><circle cx="5" cy="6" r="1.2"/><circle cx="5" cy="12" r="1.2"/><circle cx="5" cy="18" r="1.2"/></svg>,
  check: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="4" y="4" width="6" height="6" rx="1.5"/><path d="M5 7l1.5 1.5L9 5.5"/><path d="M13 7h8M13 17h8"/><rect x="4" y="14" width="6" height="6" rx="1.5"/></svg>,
  code: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M8 8 4 12l4 4M16 8l4 4-4 4M14 5l-4 14"/></svg>,
  mic: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  spark: <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 8px'}}>
      <a href="Apuntes.html" style={{width:40, height:40, borderRadius:12, background:DN.card, color:DN.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ni.back}</a>
      <div style={{display:'flex', alignItems:'center', gap:8}}>
        <span style={{fontSize:11.5, fontWeight:600, color:DN.muted, letterSpacing:0.3}}>Guardado · 23 may</span>
        <div style={{width:40, height:40, borderRadius:12, background:DN.card, color:DN.amber, display:'flex', alignItems:'center', justifyContent:'center'}}>{ni.pin}</div>
        <div style={{width:40, height:40, borderRadius:12, background:DN.card, color:DN.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{ni.share}</div>
        <div style={{width:40, height:40, borderRadius:12, background:DN.card, color:DN.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{ni.more}</div>
      </div>
    </div>
  );
}

function H({children}) {
  return <div style={{fontSize:22, fontWeight:700, color:DN.text, letterSpacing:-0.6, lineHeight:1.2, padding:'8px 20px 4px'}}>{children}</div>;
}
function H2({children}) {
  return <div style={{fontSize:16, fontWeight:700, color:DN.text, letterSpacing:-0.2, padding:'18px 20px 6px'}}>{children}</div>;
}
function P({children}) {
  return <p style={{margin:0, padding:'4px 20px', fontSize:14.5, color:DN.text, lineHeight:1.6, fontWeight:400, letterSpacing:0}}>{children}</p>;
}
function Bullet({children}) {
  return (
    <li style={{margin:0, padding:'4px 20px 4px 8px', fontSize:14.5, color:DN.text, lineHeight:1.55, fontWeight:400}}>{children}</li>
  );
}
function Math({lines}) {
  return (
    <div style={{margin:'10px 20px', padding:'14px 16px', background:'rgba(255,255,255,0.025)', border:`1px solid ${DN.hairline}`, borderRadius:14, fontFamily:"'JetBrains Mono', ui-monospace, monospace", fontSize:13, color:DN.text, lineHeight:1.7, whiteSpace:'pre', overflow:'auto'}}>
      {lines.map((l,i) => <div key={i}>{l}</div>)}
    </div>
  );
}

function FormatBar() {
  const tools = [ni.bold, ni.italic, ni.list, ni.check, ni.code];
  return (
    <div style={{padding:'10px 12px', background:DN.bg, borderTop:`1px solid ${DN.hairline}`, display:'flex', alignItems:'center', gap:6}}>
      {tools.map((t,i) => (
        <div key={i} style={{width:38, height:38, borderRadius:10, background:DN.card, color:DN.muted, display:'flex', alignItems:'center', justifyContent:'center'}}>{t}</div>
      ))}
      <div style={{flex:1}}/>
      <div style={{display:'inline-flex', alignItems:'center', gap:6, padding:'9px 12px', borderRadius:10, background:hexA(DN.accent,0.14), border:`1px solid ${hexA(DN.accent,0.32)}`, color:DN.accent, fontSize:12.5, fontWeight:700}}>
        {ni.spark}<span>Resumir</span>
      </div>
      <div style={{width:38, height:38, borderRadius:10, background:DN.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 4px 12px rgba(45,127,249,0.30)'}}>{ni.mic}</div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:DN.bg, color:DN.text, height:'100%', display:'flex', flexDirection:'column', position:'relative', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto'}}>
        {/* Notebook chip */}
        <div style={{padding:'4px 20px 0'}}>
          <span style={{display:'inline-flex', alignItems:'center', gap:6, padding:'4px 10px', borderRadius:99, background:hexA(DN.accent,0.14), border:`1px solid ${hexA(DN.accent,0.35)}`, color:DN.accent, fontSize:11, fontWeight:700, letterSpacing:0.4, textTransform:'uppercase'}}>
            <span style={{width:6, height:6, borderRadius:'50%', background:DN.accent}}/>
            Cálculo III · Cuaderno
          </span>
        </div>

        <H>Integrales múltiples — resumen</H>
        <div style={{padding:'2px 20px 10px', display:'flex', alignItems:'center', gap:8, fontSize:12, color:DN.muted, fontWeight:500}}>
          <span>Hoy · 09:42</span>
          <span style={{width:3, height:3, borderRadius:'50%', background:DN.muted, opacity:0.5}}/>
          <span>4 min de lectura</span>
          <span style={{width:3, height:3, borderRadius:'50%', background:DN.muted, opacity:0.5}}/>
          <span>312 palabras</span>
        </div>

        {/* Matix AI summary */}
        <div style={{margin:'8px 16px 6px', padding:'12px 14px', background:DN.card, borderRadius:14, border:`1px solid ${hexA(DN.accent,0.30)}`, position:'relative', overflow:'hidden'}}>
          <div style={{position:'absolute', top:-30, right:-20, width:120, height:120, background:`radial-gradient(circle, ${hexA(DN.accent,0.14)} 0%, transparent 70%)`}}/>
          <div style={{position:'relative'}}>
            <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'3px 9px 3px 8px', borderRadius:99, background:hexA(DN.accent,0.16), color:DN.accent, fontSize:10, fontWeight:700, letterSpacing:1.2}}>
              {ni.spark}<span>RESUMEN MATIX</span>
            </div>
            <div style={{marginTop:8, fontSize:13, color:DN.text, lineHeight:1.55, fontWeight:500}}>
              La nota cubre cambio de orden de integración, el rol del Jacobiano y dos ejemplos resueltos en coordenadas polares.
            </div>
          </div>
        </div>

        <P>Una integral múltiple extiende la idea de integral a funciones de varias variables. Para una región <i>R</i> en el plano, escribimos la integral doble como un límite de sumas de Riemann.</P>

        <H2>Cambio de orden de integración</H2>
        <P>Si la región es de tipo I y tipo II a la vez, se puede reordenar los diferenciales. Esto a veces simplifica radicalmente el cálculo cuando los límites de una variable son funciones complejas.</P>

        <ul style={{margin:'4px 0', paddingLeft:32, color:DN.text}}>
          <Bullet>Identificar el tipo de región.</Bullet>
          <Bullet>Dibujar el dominio para visualizar los límites.</Bullet>
          <Bullet>Reescribir con los nuevos límites.</Bullet>
        </ul>

        <H2>Jacobiano</H2>
        <P>Cuando se aplica un cambio de variables, el elemento de área se ajusta por el valor absoluto del determinante de la matriz de derivadas parciales.</P>

        <Math lines={[
          "∫∫ f(x,y) dA",
          "  = ∫∫ f(g(u,v), h(u,v)) · |J| du dv",
          "",
          "J = ∂(x,y)/∂(u,v)",
        ]}/>

        <H2>Tareas para casa</H2>
        <div style={{padding:'4px 18px 4px'}}>
          {[
            {t:'Resolver ejercicios 4.1 a 4.4', d:true},
            {t:'Repasar ejemplo 4.5 (cambio a polares)', d:true},
            {t:'Hacer ejercicio 4.8 — Jacobiano', d:false},
          ].map((it,i) => (
            <div key={i} style={{display:'flex', alignItems:'center', gap:10, padding:'7px 0', fontSize:14, color:it.d?DN.muted:DN.text}}>
              <div style={{width:18, height:18, borderRadius:5, background:it.d?DN.green:'transparent', border:it.d?'none':'1.6px solid rgba(255,255,255,0.22)', display:'flex', alignItems:'center', justifyContent:'center', flexShrink:0}}>
                {it.d && <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0B0F1A" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>}
              </div>
              <span style={{textDecoration:it.d?'line-through':'none', fontWeight:500}}>{it.t}</span>
            </div>
          ))}
        </div>

        <div style={{height:24}}/>
      </div>

      <FormatBar/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
