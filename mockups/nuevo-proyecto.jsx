// Matix — Nuevo Proyecto
//
// Esta vista muestra el caso "tope alcanzado": ya hay 3 activos y se
// quiere crear un 4to. La app bloquea el formulario y obliga a elegir
// cuál de los 3 actuales aparcar o terminar primero. Decisión
// explícita — no se permite tener 4 activos a la vez.
//
// Cuando hay < 3 activos, el banner amarillo y la lista de "elige cuál
// liberar" no aparecen, y el botón "Crear proyecto" está habilitado
// desde el inicio.

const NP = {
  bg: '#0B0F1A',
  card: '#161B2E',
  cardHi: '#1B2138',
  accent: '#2D7FF9',
  green: '#21D07A',
  red: '#FF4D5E',
  amber: '#E0A33A',
  purple: '#9B7BFF',
  text: '#E8ECF4',
  muted: '#8A93A8',
  hairline: 'rgba(255,255,255,0.06)',
};
const npA = (hex, a) => {
  const h = hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const npi = {
  close: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>,
  warn: <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3l10 18H2z"/><path d="M12 9v5M12 17v.5"/></svg>,
  pause: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>,
  check: <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>,
  chev: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 6l6 6-6 6"/></svg>,
};

function NP_TopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'14px 14px 6px',
    }}>
      <a href="Proyectos.html" style={{
        width:40, height:40, borderRadius:12, background: NP.card,
        color: NP.text, display:'flex', alignItems:'center',
        justifyContent:'center', textDecoration:'none',
      }}>{npi.close}</a>
      <div style={{
        fontSize:17, fontWeight:700, color: NP.text, letterSpacing:-0.2,
      }}>Nuevo proyecto</div>
      <div style={{width:40}}/>
    </div>
  );
}

function NP_BloqueoBanner() {
  return (
    <div style={{
      margin:'10px 16px 6px',
      padding:'14px 14px 12px',
      background: npA(NP.amber, 0.10),
      border: `1px solid ${npA(NP.amber, 0.40)}`,
      borderRadius: 14,
      display:'flex', gap:12, alignItems:'flex-start',
    }}>
      <div style={{
        width:32, height:32, borderRadius:10,
        background: npA(NP.amber, 0.18),
        color: NP.amber, flexShrink:0,
        display:'flex', alignItems:'center', justifyContent:'center',
      }}>{npi.warn}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{
          fontSize:14, fontWeight:700, color: NP.text, letterSpacing:-0.1,
        }}>Ya tienes 3 proyectos activos</div>
        <div style={{
          fontSize:12.5, color: NP.muted, marginTop:4, lineHeight:1.45,
        }}>
          Solo puedes tener 3 activos a la vez. Aparca o termina uno de
          los actuales para abrir hueco. Es decisión consciente: aparcar
          no es matar el proyecto, solo posponer su turno.
        </div>
      </div>
    </div>
  );
}

function NP_ProyectoLiberable({prioridad, nombre, color, ultimaAct}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:12,
      margin:'6px 16px',
      padding:'12px 14px',
      background: NP.card,
      borderRadius: 14,
      border: `1px solid ${NP.hairline}`,
    }}>
      <div style={{
        width:30, height:30, borderRadius:10,
        background: npA(color, 0.18),
        border: `1px solid ${npA(color, 0.40)}`,
        color: color,
        display:'flex', alignItems:'center', justifyContent:'center',
        fontSize:12.5, fontWeight:800, letterSpacing:-0.3,
        flexShrink:0,
      }}>#{prioridad}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{
          fontSize:14, fontWeight:600, color: NP.text, letterSpacing:-0.1,
        }}>{nombre}</div>
        <div style={{fontSize:11.5, color: NP.muted, marginTop:2}}>
          Última actividad: {ultimaAct}
        </div>
      </div>
      <a href="#" style={{
        padding:'7px 10px', borderRadius:9,
        background:'rgba(255,255,255,0.04)', color: NP.amber,
        display:'inline-flex', alignItems:'center', gap:5,
        textDecoration:'none', fontSize:12, fontWeight:600,
      }}>{npi.pause}<span>Aparcar</span></a>
      <a href="#" style={{
        padding:'7px 10px', borderRadius:9,
        background:'rgba(255,255,255,0.04)', color: NP.green,
        display:'inline-flex', alignItems:'center', gap:5,
        textDecoration:'none', fontSize:12, fontWeight:600,
      }}>{npi.check}<span>Terminar</span></a>
    </div>
  );
}

function NP_Field({label, children, last}) {
  return (
    <div style={{
      padding:'14px 16px',
      borderBottom: last ? 'none' : `1px solid ${NP.hairline}`,
    }}>
      <div style={{
        fontSize:11, fontWeight:700, color: NP.muted,
        letterSpacing:1.0, marginBottom:8,
      }}>{label}</div>
      {children}
    </div>
  );
}

function NP_Input({placeholder, value, multiline}) {
  return (
    <div style={{
      padding:'10px 12px',
      background:'rgba(255,255,255,0.04)',
      borderRadius: 10,
      minHeight: multiline ? 60 : 0,
      fontSize: 14, fontWeight: 500,
      color: value ? NP.text : NP.muted,
      letterSpacing: -0.1,
      lineHeight: 1.45,
    }}>{value || placeholder}</div>
  );
}

function NP_ColorPicker() {
  const COLORS = [NP.accent, NP.green, NP.red, NP.amber, NP.purple];
  return (
    <div style={{display:'flex', gap:10}}>
      {COLORS.map((c, i) => (
        <div key={c} style={{
          width:30, height:30, borderRadius:'50%',
          background: c,
          border: i === 0
            ? `3px solid ${NP.text}`
            : `2px solid ${npA(c, 0.0)}`,
          boxShadow: i === 0
            ? `0 0 0 2px ${NP.bg}, 0 0 0 4px ${npA(c, 0.45)}`
            : 'none',
        }}/>
      ))}
    </div>
  );
}

function NP_Form() {
  return (
    <div style={{
      margin:'8px 16px 16px',
      background: NP.card,
      borderRadius: 18,
      overflow:'hidden',
      opacity: 0.55,                  /* deshabilitado por el bloqueo */
      pointerEvents:'none',
    }}>
      <NP_Field label="NOMBRE DEL PROYECTO">
        <NP_Input value="Mi cuarto proyecto" />
      </NP_Field>
      <NP_Field label="DESCRIPCIÓN (OPCIONAL)">
        <NP_Input
          placeholder="¿De qué va este proyecto?"
          multiline
        />
      </NP_Field>
      <NP_Field label="LÍNEA DE META (CUÁNDO ESTÁ TERMINADO)">
        <NP_Input placeholder="Ej. publicar la primera versión y vender 5" />
      </NP_Field>
      <NP_Field label="COLOR" last>
        <NP_ColorPicker/>
      </NP_Field>
    </div>
  );
}

function NP_FooterCTA() {
  return (
    <div style={{
      padding:'14px 16px 20px',
      background: NP.bg,
      borderTop: `1px solid ${NP.hairline}`,
    }}>
      <button disabled style={{
        width:'100%', padding:'14px',
        border:'none', borderRadius: 12,
        background: NP.card, color: NP.muted,
        fontSize:14, fontWeight:700,
        cursor:'not-allowed',
        fontFamily:'inherit',
      }}>Crear proyecto</button>
      <div style={{
        textAlign:'center', marginTop:8,
        fontSize:11.5, color: NP.muted,
      }}>
        Disponible cuando liberes un activo.
      </div>
    </div>
  );
}

function NuevoProyectoScreen() {
  return (
    <div style={{
      background: NP.bg, color: NP.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <NP_TopBar/>
      <div style={{flex:1, overflowY:'auto'}}>
        <NP_BloqueoBanner/>

        <div style={{
          padding:'12px 22px 4px',
          fontSize:11.5, fontWeight:700, color: NP.muted,
          letterSpacing:1.0,
        }}>ELIGE CUÁL LIBERAR</div>

        <NP_ProyectoLiberable
          prioridad={1} nombre="Matix" color={NP.accent}
          ultimaAct="hoy"
        />
        <NP_ProyectoLiberable
          prioridad={2} nombre="OnExotic" color={NP.purple}
          ultimaAct="hace 2 días"
        />
        <NP_ProyectoLiberable
          prioridad={3} nombre="Shadows Games" color={NP.green}
          ultimaAct="hace 5 días"
        />

        <div style={{
          padding:'24px 22px 4px',
          fontSize:11.5, fontWeight:700, color: NP.muted,
          letterSpacing:1.0,
        }}>DATOS DEL NUEVO PROYECTO</div>
        <NP_Form/>
      </div>
      <NP_FooterCTA/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <NuevoProyectoScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
