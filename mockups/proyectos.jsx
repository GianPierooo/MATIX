// Matix — Proyectos (lista)
//
// 3 proyectos activos en cards grandes con línea de meta, acción
// siguiente y calor; aparcados aparte; terminados colapsables.
// Datos extraídos del Documento Maestro del usuario.

const PR = {
  bg: '#0B0F1A',
  card: '#161B2E',
  cardHi: '#1B2138',
  accent: '#2D7FF9',
  green: '#21D07A',
  red: '#FF4D5E',
  amber: '#E0A33A',
  purple: '#9B7BFF',
  pink: '#F06EA9',
  teal: '#3CCFCF',
  text: '#E8ECF4',
  muted: '#8A93A8',
  hairline: 'rgba(255,255,255,0.06)',
};

function pHexA(hex, a) {
  const h = hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
}

const pi = {
  plus: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  ),
  arrow: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14M13 6l6 6-6 6"/>
    </svg>
  ),
  flame: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2c.5 4 4 5.5 4 9.5 0 2.2-1.8 4-4 4s-4-1.8-4-4c0-2.2 1.5-3 1.5-5.5 0 1.5 1.5 2 2.5 2-1-1-1-3.5 0-6z"/>
    </svg>
  ),
  flag: (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 22V4"/><path d="M5 4h12l-2.5 4.5L17 13H5"/>
    </svg>
  ),
  check: (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12.5 10 17 19 7.5"/>
    </svg>
  ),
  chev: (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 6l6 6-6 6"/>
    </svg>
  ),
  pause: (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor">
      <rect x="6" y="5" width="4" height="14" rx="1"/>
      <rect x="14" y="5" width="4" height="14" rx="1"/>
    </svg>
  ),
};

// ── Top bar ────────────────────────────────────────────────────
function PR_TopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'flex-start', justifyContent:'space-between',
      padding:'16px 20px 10px',
    }}>
      <div style={{display:'flex', flexDirection:'column'}}>
        <span style={{
          fontSize:12, color:PR.muted, fontWeight:500,
          letterSpacing:0.2,
        }}>
          Activos 3 · Aparcados 3 · Terminados 1
        </span>
        <span style={{
          fontSize:26, color:PR.text, fontWeight:700, letterSpacing:-0.5,
          marginTop:2,
        }}>
          Proyectos
        </span>
      </div>
      <a href="Nuevo%20Proyecto.html" style={{
        width:40, height:40, borderRadius:12,
        background: PR.accent, color:'#fff',
        display:'flex', alignItems:'center', justifyContent:'center',
        textDecoration:'none', flexShrink:0,
        boxShadow:`0 6px 16px ${pHexA(PR.accent,0.35)}`,
      }}>{pi.plus}</a>
    </div>
  );
}

// ── Section header ──────────────────────────────────────────────
function PR_Section({label, count, right}) {
  return (
    <div style={{
      display:'flex', alignItems:'baseline', justifyContent:'space-between',
      padding:'18px 22px 8px',
    }}>
      <div style={{display:'flex', alignItems:'baseline', gap:8}}>
        <span style={{fontSize:11.5, fontWeight:700, color:PR.muted,
          letterSpacing:1.0, textTransform:'uppercase'}}>
          {label}
        </span>
        {count !== undefined && (
          <span style={{fontSize:12, color:PR.muted, fontWeight:600}}>
            {count}
          </span>
        )}
      </div>
      {right && (
        <span style={{fontSize:12, color:PR.muted, fontWeight:500}}>
          {right}
        </span>
      )}
    </div>
  );
}

// ── Active project card (large) ────────────────────────────────
function ActiveCard({prioridad, nombre, color, linea, accionSiguiente, calor, bloque}) {
  const calorColor = calor.tono === 'rojo' ? PR.red
    : calor.tono === 'amber' ? PR.amber
    : PR.green;
  return (
    <a href="Detalle%20Proyecto.html" style={{
      display:'block',
      margin:'8px 16px 12px',
      padding:'16px 16px 14px',
      background: PR.card,
      borderRadius: 18,
      border: `1px solid ${pHexA(color, 0.35)}`,
      textDecoration:'none', color:'inherit',
      position:'relative', overflow:'hidden',
    }}>
      {/* corner glow with project color */}
      <div style={{
        position:'absolute', top:-50, right:-30, width:160, height:160,
        background: `radial-gradient(circle, ${pHexA(color, 0.20)} 0%, transparent 70%)`,
        pointerEvents:'none',
      }}/>

      <div style={{position:'relative'}}>
        {/* header: prio + nombre + calor */}
        <div style={{display:'flex', alignItems:'center', gap:10}}>
          <div style={{
            width:30, height:30, borderRadius:10,
            background: pHexA(color, 0.18),
            border: `1px solid ${pHexA(color, 0.45)}`,
            color: color,
            display:'flex', alignItems:'center', justifyContent:'center',
            fontSize:13, fontWeight:800, letterSpacing:-0.4,
          }}>#{prioridad}</div>
          <span style={{
            fontSize:18, fontWeight:700, color: PR.text,
            letterSpacing:-0.3, flex:1, lineHeight:1.15,
          }}>{nombre}</span>
          <span style={{
            display:'inline-flex', alignItems:'center', gap:4,
            padding:'4px 9px', borderRadius:8,
            background: pHexA(calorColor, 0.14),
            border: `1px solid ${pHexA(calorColor, 0.35)}`,
            color: calorColor,
            fontSize:11.5, fontWeight:700, whiteSpace:'nowrap',
          }}>
            {pi.flame}<span>{calor.label}</span>
          </span>
        </div>

        {/* linea meta */}
        <div style={{
          marginTop:12, padding:'10px 12px',
          background:'rgba(255,255,255,0.04)',
          borderRadius: 12,
        }}>
          <div style={{
            fontSize:10.5, color: PR.muted, fontWeight:700,
            letterSpacing:0.8, marginBottom:4,
          }}>
            LÍNEA DE META
          </div>
          <div style={{
            fontSize:13.5, color: PR.text, fontWeight:500,
            lineHeight:1.45,
          }}>{linea}</div>
        </div>

        {/* acción siguiente */}
        <div style={{
          marginTop:10, padding:'10px 12px',
          background: pHexA(color, 0.10),
          borderRadius: 12,
          display:'flex', alignItems:'center', gap:10,
        }}>
          <div style={{
            width:18, height:18, borderRadius:'50%',
            border:`1.8px solid ${pHexA(color, 0.55)}`,
            flexShrink:0,
          }}/>
          <div style={{flex:1, minWidth:0}}>
            <div style={{
              fontSize:10.5, color: color, fontWeight:700,
              letterSpacing:0.8, marginBottom:2,
            }}>
              ACCIÓN SIGUIENTE
            </div>
            <div style={{
              fontSize:13.5, color: PR.text, fontWeight:600,
              lineHeight:1.3,
            }}>{accionSiguiente}</div>
          </div>
        </div>

        {/* bloque protegido (opcional) */}
        {bloque && (
          <div style={{
            marginTop:10,
            fontSize:11.5, color: PR.muted, fontWeight:500,
            display:'flex', alignItems:'center', gap:6,
          }}>
            <span>🗓</span><span>Bloque protegido: {bloque}</span>
          </div>
        )}
      </div>
    </a>
  );
}

// ── Parked project card (compact) ──────────────────────────────
function ParkedCard({nombre, color, motivo}) {
  return (
    <a href="Detalle%20Proyecto.html" style={{
      display:'flex', alignItems:'center', gap:12,
      margin:'4px 16px',
      padding:'12px 14px',
      background: PR.card,
      borderRadius: 12,
      textDecoration:'none', color:'inherit',
    }}>
      <div style={{
        width:24, height:24, borderRadius:8,
        background: pHexA(color, 0.18),
        border: `1px solid ${pHexA(color, 0.4)}`,
        color: color, flexShrink:0,
        display:'flex', alignItems:'center', justifyContent:'center',
      }}>{pi.pause}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{
          fontSize:14, fontWeight:600, color: PR.text,
          letterSpacing:-0.1,
        }}>{nombre}</div>
        {motivo && (
          <div style={{fontSize:12, color: PR.muted, marginTop:2}}>
            {motivo}
          </div>
        )}
      </div>
      <span style={{color: PR.muted}}>{pi.chev}</span>
    </a>
  );
}

// ── Done project row (very compact, collapsed by default) ──────
function DoneRow({nombre, cuando, color}) {
  return (
    <a href="Detalle%20Proyecto.html" style={{
      display:'flex', alignItems:'center', gap:12,
      margin:'2px 16px',
      padding:'8px 14px',
      textDecoration:'none', color:'inherit',
    }}>
      <div style={{
        width:18, height:18, borderRadius:'50%',
        background: pHexA(color, 0.18),
        border: `1px solid ${pHexA(color, 0.4)}`,
        color: color, flexShrink:0,
        display:'flex', alignItems:'center', justifyContent:'center',
      }}>{pi.check}</div>
      <span style={{
        flex:1, fontSize:13.5, color: PR.muted,
        textDecoration:'line-through',
      }}>{nombre}</span>
      <span style={{fontSize:11.5, color: PR.muted, fontWeight:500}}>
        {cuando}
      </span>
    </a>
  );
}

// ── Screen ─────────────────────────────────────────────────────
function ProyectosScreen() {
  return (
    <div style={{
      background: PR.bg, color: PR.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <PR_TopBar/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:120}}>
        <PR_Section label="Activos" count="3 / 3"/>

        <ActiveCard
          prioridad={1}
          nombre="Matix"
          color={PR.accent}
          linea="Cerrar la Capa 1: armazón del hub funcionando y probado."
          accionSiguiente="Validar visualmente la pantalla Tareas en el teléfono."
          calor={{label:'Hoy', tono:'verde'}}
          bloque="L/Mi/V 6:00 – 9:00 am"
        />

        <ActiveCard
          prioridad={2}
          nombre="OnExotic"
          color={PR.purple}
          linea="Canal de venta online publicado y primeras 5 ventas reales."
          accionSiguiente="Subir las fotos del último drop a la tienda."
          calor={{label:'Hace 2 días', tono:'amber'}}
        />

        <ActiveCard
          prioridad={3}
          nombre="Shadows Games"
          color={PR.green}
          linea="Terminar y publicar el juego de la próxima jam (por confirmar con Leo)."
          accionSiguiente="Cerrar con Leo el alcance del juego de la jam."
          calor={{label:'Hace 5 días · EN RIESGO', tono:'rojo'}}
        />

        <PR_Section label="Aparcados" count="3"
          right="En pausa consciente"/>
        <ParkedCard
          nombre="Peyo (personaje virtual)"
          color={PR.pink}
          motivo="Esperando turno · sin fecha definida"
        />
        <ParkedCard
          nombre="Inglés / Portugués"
          color={PR.teal}
          motivo="Aparcado hasta cerrar Matix · elegir idioma al reactivar"
        />
        <ParkedCard
          nombre="Startup de automatizaciones"
          color={PR.amber}
          motivo="Aparcado · explorar tras OnExotic"
        />

        <PR_Section label="Terminados" count="1"
          right="Ver historial"/>
        <DoneRow
          nombre="Migración de portafolio personal a Vercel"
          color={PR.muted}
          cuando="mar 2026"
        />
      </div>

      <MatixBottomNav active="projects"/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <ProyectosScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
