// Matix — Filtros (bottom sheet sobre Tareas)

const FL = {
  bg:'#0B0F1A', card:'#161B2E',
  accent:'#2D7FF9', green:'#21D07A', red:'#FF4D5E', amber:'#E0A33A', purple:'#9B7BFF',
  text:'#E8ECF4', muted:'#8A93A8', hairline:'rgba(255,255,255,0.06)',
};
const hexA = (hex,a) => {
  const h=hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

// Faded background screen content (Tareas under the sheet)
function BgScreen() {
  return (
    <div style={{position:'absolute', inset:0, background:FL.bg, filter:'blur(0.5px)', opacity:0.7, pointerEvents:'none'}}>
      <div style={{padding:'14px 20px 10px', display:'flex', alignItems:'center', justifyContent:'space-between'}}>
        <div>
          <span style={{fontSize:12, color:FL.muted, fontWeight:500}}>Viernes · 23 may</span>
          <div style={{fontSize:26, color:FL.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>Tareas</div>
        </div>
        <div style={{display:'flex', gap:10}}>
          <div style={{width:40, height:40, borderRadius:12, background:FL.card}}/>
          <div style={{width:40, height:40, borderRadius:12, background:FL.accent}}/>
        </div>
      </div>
      <div style={{padding:'0 20px', display:'flex', gap:8}}>
        <div style={{padding:'9px 16px', borderRadius:99, background:FL.accent, color:'#fff', fontSize:12, fontWeight:600}}>Hoy</div>
        <div style={{padding:'9px 16px', borderRadius:99, background:FL.card, color:FL.muted, fontSize:12}}>Esta semana</div>
        <div style={{padding:'9px 16px', borderRadius:99, background:FL.card, color:FL.muted, fontSize:12}}>Todas</div>
      </div>
      <div style={{padding:'20px 16px', display:'flex', flexDirection:'column', gap:8}}>
        {[1,2,3].map(i=>(
          <div key={i} style={{height:62, background:FL.card, borderRadius:14}}/>
        ))}
      </div>
    </div>
  );
}

// Scrim
function Scrim() {
  return <div style={{position:'absolute', inset:0, background:'rgba(0,0,0,0.55)', backdropFilter:'blur(2px)'}}/>;
}

function Section({title, right}) {
  return (
    <div style={{display:'flex', alignItems:'baseline', justifyContent:'space-between', padding:'4px 22px 8px'}}>
      <span style={{fontSize:12, fontWeight:700, color:FL.text, letterSpacing:0.2}}>{title}</span>
      {right && <span style={{fontSize:11, color:FL.muted, fontWeight:500}}>{right}</span>}
    </div>
  );
}

function Pill({label, color, selected, count}) {
  return (
    <div style={{
      display:'inline-flex', alignItems:'center', gap:7,
      padding:'8px 14px 8px 12px', borderRadius:99,
      background: selected ? hexA(color || FL.accent, 0.18) : 'rgba(255,255,255,0.04)',
      border: selected ? `1.5px solid ${color || FL.accent}` : `1px solid ${FL.hairline}`,
      color: selected ? (color || FL.accent) : FL.muted,
      fontSize:13, fontWeight: selected ? 700 : 500,
    }}>
      {color && <span style={{width:8, height:8, borderRadius:'50%', background:color, boxShadow:selected?`0 0 8px ${hexA(color,0.6)}`:'none'}}/>}
      <span>{label}</span>
      {count !== undefined && (
        <span style={{padding:'1px 6px', borderRadius:99, background:selected?hexA(color||FL.accent,0.22):'rgba(255,255,255,0.05)', fontSize:10, fontWeight:700}}>{count}</span>
      )}
    </div>
  );
}

function Sheet() {
  return (
    <div style={{
      position:'absolute', left:0, right:0, bottom:0,
      background:FL.bg, borderTopLeftRadius:24, borderTopRightRadius:24,
      borderTop:`1px solid ${FL.hairline}`,
      paddingBottom:18,
      maxHeight:'82%',
      display:'flex', flexDirection:'column',
      boxShadow:'0 -20px 60px rgba(0,0,0,0.5)',
    }}>
      {/* Grab handle */}
      <div style={{display:'flex', justifyContent:'center', padding:'10px 0 4px'}}>
        <div style={{width:48, height:5, borderRadius:99, background:'rgba(255,255,255,0.18)'}}/>
      </div>

      {/* Header */}
      <div style={{display:'flex', alignItems:'center', justifyContent:'space-between', padding:'4px 22px 10px'}}>
        <span style={{fontSize:18, fontWeight:700, color:FL.text, letterSpacing:-0.3}}>Filtros</span>
        <span style={{fontSize:13, color:FL.accent, fontWeight:600}}>Limpiar</span>
      </div>

      <div style={{flex:1, overflowY:'auto', padding:'4px 0 12px'}}>
        <Section title="Prioridad"/>
        <div style={{display:'flex', gap:8, padding:'0 18px 12px', flexWrap:'wrap'}}>
          <Pill label="Alta" color={FL.red} selected/>
          <Pill label="Media" color={FL.amber} selected/>
          <Pill label="Baja" color={FL.accent}/>
        </div>

        <Section title="Cursos · seleccionados 2" right="Ver todos"/>
        <div style={{display:'flex', gap:8, padding:'0 18px 12px', flexWrap:'wrap'}}>
          <Pill label="Cálculo III" color={FL.accent} count={4} selected/>
          <Pill label="Estadística II" color={FL.green} count={3}/>
          <Pill label="Sistemas de Información" color={FL.amber} count={2} selected/>
          <Pill label="Filosofía" color={FL.purple} count={1}/>
          <Pill label="Personal" count={5}/>
        </div>

        <Section title="Proyectos · seleccionados 1"/>
        <div style={{display:'flex', gap:8, padding:'0 18px 12px', flexWrap:'wrap'}}>
          <Pill label="Matix" color={FL.accent} count={6} selected/>
          <Pill label="OnExotic" color={FL.purple} count={3}/>
          <Pill label="Shadows Games" color={FL.green} count={2}/>
        </div>

        <Section title="Estado"/>
        <div style={{display:'flex', gap:8, padding:'0 18px 12px', flexWrap:'wrap'}}>
          <Pill label="Pendientes" selected/>
          <Pill label="Vencidas" color={FL.red}/>
          <Pill label="Completadas" color={FL.green}/>
          <Pill label="Sin fecha"/>
        </div>

        <Section title="Fecha"/>
        <div style={{padding:'0 18px 12px'}}>
          <div style={{display:'flex', gap:8, marginBottom:10, flexWrap:'wrap'}}>
            <Pill label="Hoy" color={FL.accent} selected/>
            <Pill label="Esta semana"/>
            <Pill label="Este mes"/>
            <Pill label="Próximos 30 días"/>
            <Pill label="Personalizado"/>
          </div>
          <div style={{padding:'14px 14px', background:FL.card, borderRadius:14, display:'flex', alignItems:'center', gap:10}}>
            <span style={{fontSize:12, fontWeight:600, color:FL.muted}}>Desde</span>
            <span style={{flex:1, padding:'8px 12px', background:'rgba(255,255,255,0.04)', borderRadius:9, fontSize:13.5, fontWeight:600, color:FL.text}}>23 mayo 2026</span>
            <span style={{fontSize:12, fontWeight:600, color:FL.muted}}>Hasta</span>
            <span style={{flex:1, padding:'8px 12px', background:'rgba(255,255,255,0.04)', borderRadius:9, fontSize:13.5, fontWeight:600, color:FL.text}}>30 mayo 2026</span>
          </div>
        </div>

        <Section title="Ordenar por"/>
        <div style={{display:'flex', gap:8, padding:'0 18px 8px', flexWrap:'wrap'}}>
          <Pill label="Fecha límite" color={FL.accent} selected/>
          <Pill label="Prioridad"/>
          <Pill label="Curso"/>
          <Pill label="Creación"/>
        </div>
      </div>

      <div style={{padding:'12px 16px 0', display:'flex', gap:10}}>
        <a href="Tareas.html" style={{flex:1, padding:'14px 0', borderRadius:14, background:'rgba(255,255,255,0.04)', color:FL.text, display:'flex', alignItems:'center', justifyContent:'center', fontSize:14, fontWeight:600, textDecoration:'none'}}>
          Cancelar
        </a>
        <a href="Tareas.html" style={{flex:1.6, padding:'14px 0', borderRadius:14, background:FL.accent, color:'#fff', display:'flex', alignItems:'center', justifyContent:'center', gap:8, fontSize:14, fontWeight:700, boxShadow:'0 10px 24px rgba(45,127,249,0.40)', textDecoration:'none'}}>
          Aplicar · 7 tareas
        </a>
      </div>
    </div>
  );
}

function Screen() {
  return (
    <div style={{background:FL.bg, color:FL.text, height:'100%', position:'relative', overflow:'hidden', fontFamily:"'Inter', system-ui, sans-serif"}}>
      <BgScreen/>
      <Scrim/>
      <Sheet/>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(
  <AndroidDevice width={412} height={892} dark><Screen/></AndroidDevice>
);
