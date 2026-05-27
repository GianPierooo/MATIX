// Matix — Nueva nota (editor en blanco)

const NN = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const ic = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  bold: <span style={{fontWeight:800, fontSize:16}}>B</span>,
  italic: <span style={{fontStyle:'italic', fontWeight:600, fontSize:16, fontFamily:'serif'}}>I</span>,
  h: <span style={{fontWeight:700, fontSize:14}}>H1</span>,
  list: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6h11M9 12h11M9 18h11"/><circle cx="5" cy="6" r="1.2"/><circle cx="5" cy="12" r="1.2"/><circle cx="5" cy="18" r="1.2"/></svg>,
  check: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="4" y="4" width="6" height="6" rx="1.5"/><path d="M5 7l1.5 1.5L9 5.5"/><path d="M13 7h8M13 17h8"/><rect x="4" y="14" width="6" height="6" rx="1.5"/></svg>,
  code: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M8 8 4 12l4 4M16 8l4 4-4 4M14 5l-4 14"/></svg>,
  img: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="4.5" width="17" height="15" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="M4 17l5-5 4 4 3-2 4 4"/></svg>,
  mic: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>,
  spark: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.2 6.6 6.8 1.2-5.2 4.7 1.5 6.8L12 18.5 6.7 21.8l1.5-6.8L3 10.3l6.8-1.2z"/></svg>,
  chev: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M6 9l6 6 6-6"/></svg>,
};

function TopBar() {
  return (
    <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'14px 14px 8px'}}>
      <a href="Apuntes.html" style={{width:40, height:40, borderRadius:12, background:NN.card, color:NN.text, display:'flex', alignItems:'center', justifyContent:'center', textDecoration:'none'}}>{ic.close}</a>
      <div style={{display:'inline-flex', alignItems:'center', gap:6, padding:'7px 12px 7px 10px', borderRadius:99, background:NN.card, border:'1px solid rgba(255,255,255,0.04)'}}>
        <span style={{width:8, height:8, borderRadius:'50%', background:NN.accent}}/>
        <span style={{fontSize:12.5, fontWeight:600, color:NN.text}}>Cálculo III</span>
        <span style={{color:NN.muted}}>{ic.chev}</span>
      </div>
      <div style={{display:'flex', gap:8}}>
        <div style={{padding:'9px 14px', borderRadius:12, background:NN.accent, color:'#fff', fontSize:13, fontWeight:700, boxShadow:'0 6px 16px rgba(45,127,249,0.35)'}}>Guardar</div>
      </div>
    </div>
  );
}

function FormatBar({active}) {
  const tools = [
    {k:'b', el:ic.bold}, {k:'i', el:ic.italic}, {k:'h', el:ic.h},
    {k:'l', el:ic.list, active:true}, {k:'c', el:ic.check}, {k:'k', el:ic.code}, {k:'img', el:ic.img},
  ];
  return (
    <div style={{padding:'10px 12px', background:NN.bg, borderTop:`1px solid ${NN.hairline}`, display:'flex', alignItems:'center', gap:6, overflowX:'auto'}}>
      {tools.map(t => (
        <div key={t.k} style={{
          width:38, height:38, borderRadius:10, flexShrink:0,
          background: t.active ? hexA(NN.accent,0.14) : NN.card,
          color: t.active ? NN.accent : NN.muted,
          border: t.active ? `1px solid ${hexA(NN.accent,0.32)}` : '1px solid transparent',
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>{t.el}</div>
      ))}
      <div style={{flex:1}}/>
      <div style={{display:'inline-flex', alignItems:'center', gap:6, padding:'9px 12px', borderRadius:10, background:hexA(NN.accent,0.14), border:`1px solid ${hexA(NN.accent,0.32)}`, color:NN.accent, fontSize:12.5, fontWeight:700, whiteSpace:'nowrap'}}>
        {ic.spark}<span>Mejorar</span>
      </div>
      <div style={{width:38, height:38, borderRadius:10, background:NN.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', boxShadow:'0 4px 12px rgba(45,127,249,0.30)', flexShrink:0}}>{ic.mic}</div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:NN.bg, color:NN.text, height:'100%', display:'flex', flexDirection:'column', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <TopBar/>

      <div style={{flex:1, overflowY:'auto', padding:'10px 0'}}>
        {/* Title placeholder w/ caret */}
        <div style={{padding:'8px 20px'}}>
          <div style={{fontSize:24, fontWeight:700, color:NN.text, letterSpacing:-0.5, lineHeight:1.2}}>
            <span>Clase 13 — Derivadas direccionales</span>
            <span style={{display:'inline-block', width:2, height:26, background:NN.accent, marginLeft:3, verticalAlign:'-5px', animation:'blink 1.1s steps(1) infinite'}}/>
          </div>
          <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>
          <div style={{marginTop:4, fontSize:13, color:NN.muted}}>23 mayo · 10:42</div>
        </div>

        {/* Body w/ a small bulleted list user already started */}
        <div style={{padding:'12px 20px 4px', fontSize:15, color:NN.text, lineHeight:1.6}}>
          La derivada direccional mide la razón de cambio de f en un punto y una dirección específica.
        </div>

        <ul style={{margin:'4px 0', paddingLeft:32, color:NN.text}}>
          <li style={{padding:'3px 20px 3px 8px', fontSize:14.5, lineHeight:1.55}}>Vector unitario en la dirección que importa.</li>
          <li style={{padding:'3px 20px 3px 8px', fontSize:14.5, lineHeight:1.55}}>D_u f = ∇f · u</li>
          <li style={{padding:'3px 20px 3px 8px', fontSize:14.5, color:NN.muted, lineHeight:1.55}}>
            <span style={{color:NN.muted}}>Empieza a escribir…</span>
          </li>
        </ul>

        {/* Inline suggestion (Matix continuation) */}
        <div style={{margin:'10px 16px', padding:'12px 14px', background:NN.card, borderRadius:14, border:`1px dashed ${hexA(NN.accent,0.45)}`, position:'relative'}}>
          <div style={{display:'inline-flex', alignItems:'center', gap:5, padding:'2px 8px 2px 7px', borderRadius:99, background:hexA(NN.accent,0.16), color:NN.accent, fontSize:10, fontWeight:700, letterSpacing:1.2, marginBottom:8}}>
            {ic.spark}<span>SUGERENCIA</span>
          </div>
          <div style={{fontSize:13, color:NN.muted, lineHeight:1.55, fontStyle:'italic'}}>
            «La dirección de máximo crecimiento de f en un punto es la del gradiente, y el valor máximo de la derivada direccional es |∇f|.»
          </div>
          <div style={{display:'flex', gap:6, marginTop:10}}>
            <div style={{padding:'6px 12px', borderRadius:8, background:NN.accent, color:'#fff', fontSize:12, fontWeight:700}}>Aceptar</div>
            <div style={{padding:'6px 12px', borderRadius:8, background:'rgba(255,255,255,0.04)', color:NN.muted, fontSize:12, fontWeight:600}}>Descartar</div>
          </div>
        </div>

        {/* Quick blocks */}
        <div style={{padding:'10px 18px 4px'}}>
          <div style={{fontSize:11, fontWeight:600, color:NN.muted, letterSpacing:0.6, textTransform:'uppercase', marginBottom:8}}>Insertar</div>
          <div style={{display:'flex', gap:8, overflowX:'auto'}}>
            {[
              {l:'Lista de tareas', c:NN.green},
              {l:'Bloque de código', c:NN.purple},
              {l:'Imagen', c:NN.amber},
              {l:'Fecha', c:NN.accent},
              {l:'Tabla', c:NN.muted},
            ].map((b,i) => (
              <div key={i} style={{flexShrink:0, display:'flex', alignItems:'center', gap:7, padding:'8px 12px', borderRadius:99, background:NN.card, border:'1px solid rgba(255,255,255,0.04)'}}>
                <span style={{width:6, height:6, borderRadius:'50%', background:b.c}}/>
                <span style={{fontSize:12.5, color:NN.text, fontWeight:500}}>{b.l}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      <FormatBar/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
