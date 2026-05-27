// Matix — Detalle de Proyecto (ejemplo: Matix #1)

const DP = {
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
const dpA = (hex, a) => {
  const h = hex.replace('#','');
  return `rgba(${parseInt(h.slice(0,2),16)},${parseInt(h.slice(2,4),16)},${parseInt(h.slice(4,6),16)},${a})`;
};

const dpi = {
  back: <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>,
  more: <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>,
  edit: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 20h4l11-11-4-4L4 16z"/><path d="M14 5l5 5"/></svg>,
  check: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5 10 17 19 7.5"/></svg>,
  flame: <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2c.5 4 4 5.5 4 9.5 0 2.2-1.8 4-4 4s-4-1.8-4-4c0-2.2 1.5-3 1.5-5.5 0 1.5 1.5 2 2.5 2-1-1-1-3.5 0-6z"/></svg>,
  clock: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>,
  cal: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/></svg>,
  notes: <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/><path d="M14.5 3.5v4h4"/><path d="M8 12h7M8 15.5h5"/></svg>,
  pause: <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>,
  flag: <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 22V4"/><path d="M5 4h12l-2.5 4.5L17 13H5"/></svg>,
};

const COLOR_PROYECTO = DP.accent;

function DP_TopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'14px 14px 8px',
    }}>
      <a href="Proyectos.html" style={{
        width:40, height:40, borderRadius:12, background: DP.card,
        color: DP.text, display:'flex', alignItems:'center',
        justifyContent:'center', textDecoration:'none',
      }}>{dpi.back}</a>
      <a href="#" style={{
        width:40, height:40, borderRadius:12, background: DP.card,
        color: DP.muted, display:'flex', alignItems:'center',
        justifyContent:'center', textDecoration:'none',
      }}>{dpi.more}</a>
    </div>
  );
}

function DP_Hero() {
  return (
    <div style={{padding:'10px 20px 16px'}}>
      <div style={{display:'flex', alignItems:'center', gap:8, marginBottom:10}}>
        <span style={{
          display:'inline-flex', alignItems:'center', gap:6,
          padding:'4px 10px', borderRadius:99,
          background: dpA(COLOR_PROYECTO, 0.14),
          border: `1px solid ${dpA(COLOR_PROYECTO, 0.35)}`,
          color: COLOR_PROYECTO, fontSize:11, fontWeight:700,
          letterSpacing:0.4, textTransform:'uppercase',
        }}>
          {dpi.flag}<span>Prioridad #1 · Activo</span>
        </span>
        <span style={{
          display:'inline-flex', alignItems:'center', gap:5,
          padding:'4px 9px', borderRadius:99,
          background: dpA(DP.green, 0.14),
          border: `1px solid ${dpA(DP.green, 0.35)}`,
          color: DP.green, fontSize:11, fontWeight:700,
        }}>
          {dpi.flame}<span>Hoy</span>
        </span>
      </div>
      <div style={{
        fontSize:28, fontWeight:700, color: DP.text,
        letterSpacing:-0.7, lineHeight:1.18,
      }}>
        Matix
      </div>
      <div style={{
        fontSize:13.5, color: DP.muted, marginTop:6, lineHeight:1.5,
      }}>
        La app que sostiene todo lo demás — cerebro externo y centro
        de mando de la vida.
      </div>
    </div>
  );
}

function DP_LineaMeta() {
  return (
    <div style={{margin:'4px 16px 12px'}}>
      <div style={{
        padding:'14px 14px 12px',
        background: DP.card,
        borderRadius: 14,
        border: `1px solid ${DP.hairline}`,
      }}>
        <div style={{
          display:'flex', alignItems:'center', justifyContent:'space-between',
          marginBottom:8,
        }}>
          <span style={{
            fontSize:11, fontWeight:700, color: DP.muted,
            letterSpacing:1.0,
          }}>LÍNEA DE META</span>
          <span style={{color: DP.muted}}>{dpi.edit}</span>
        </div>
        <div style={{
          fontSize:14, color: DP.text, fontWeight:500, lineHeight:1.5,
        }}>
          Cerrar la Capa 1: armazón del hub funcionando y probado
          (5 secciones, CRUD manual, notificaciones locales).
        </div>
      </div>
    </div>
  );
}

function DP_AccionSiguiente() {
  return (
    <div style={{margin:'8px 16px 12px'}}>
      <div style={{
        padding:'14px 14px 12px',
        background: dpA(COLOR_PROYECTO, 0.10),
        borderRadius: 14,
        border: `1px solid ${dpA(COLOR_PROYECTO, 0.30)}`,
      }}>
        <div style={{
          fontSize:11, fontWeight:700, color: COLOR_PROYECTO,
          letterSpacing:1.0, marginBottom:8,
        }}>ACCIÓN SIGUIENTE</div>
        <div style={{display:'flex', alignItems:'center', gap:12}}>
          <div style={{
            width:20, height:20, borderRadius:'50%',
            border: `1.8px solid ${dpA(COLOR_PROYECTO, 0.55)}`,
            flexShrink:0,
          }}/>
          <div style={{
            flex:1, fontSize:14.5, fontWeight:600, color: DP.text,
            lineHeight:1.3,
          }}>
            Validar visualmente la pantalla Tareas en el teléfono.
          </div>
        </div>
        <div style={{display:'flex', gap:8, marginTop:12}}>
          <a href="#" style={{
            flex:1, padding:'9px 12px', borderRadius:10,
            background: COLOR_PROYECTO, color:'#fff',
            display:'flex', alignItems:'center', justifyContent:'center',
            gap:6, textDecoration:'none',
            fontSize:13, fontWeight:600,
          }}>
            {dpi.check}<span>Marcar hecha</span>
          </a>
          <a href="#" style={{
            padding:'9px 14px', borderRadius:10,
            background:'rgba(255,255,255,0.04)', color: DP.text,
            display:'flex', alignItems:'center', justifyContent:'center',
            textDecoration:'none', fontSize:13, fontWeight:600,
          }}>
            Cambiar
          </a>
        </div>
      </div>
    </div>
  );
}

function DP_MetaRow({icon, label, value, valueColor}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:14,
      padding:'14px 18px',
      borderBottom: `1px solid ${DP.hairline}`,
    }}>
      <div style={{
        width:32, height:32, borderRadius:9,
        background:'rgba(255,255,255,0.04)',
        color: DP.muted, display:'flex',
        alignItems:'center', justifyContent:'center', flexShrink:0,
      }}>{icon}</div>
      <div style={{flex:1, minWidth:0}}>
        <div style={{
          fontSize:11, fontWeight:600, color: DP.muted,
          letterSpacing:0.6, textTransform:'uppercase',
        }}>{label}</div>
        <div style={{
          fontSize:14, fontWeight:600, color: valueColor || DP.text,
          marginTop:3, letterSpacing:-0.1,
        }}>{value}</div>
      </div>
    </div>
  );
}

function DP_Section({label, right}) {
  return (
    <div style={{
      display:'flex', alignItems:'baseline', justifyContent:'space-between',
      padding:'20px 22px 6px',
    }}>
      <span style={{
        fontSize:11.5, fontWeight:700, color: DP.muted,
        letterSpacing:1.0, textTransform:'uppercase',
      }}>{label}</span>
      {right && (
        <a href="#" style={{
          fontSize:12, fontWeight:600, color: COLOR_PROYECTO,
          textDecoration:'none',
        }}>{right}</a>
      )}
    </div>
  );
}

function DP_TareaRow({titulo, fecha, done}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:12,
      margin:'4px 16px',
      padding:'12px 14px',
      background: DP.card, borderRadius: 12,
    }}>
      <div style={{
        width:18, height:18, borderRadius:'50%',
        background: done ? DP.green : 'transparent',
        border: done ? 'none' : '1.6px solid rgba(255,255,255,0.22)',
        display:'flex', alignItems:'center', justifyContent:'center',
        flexShrink:0,
      }}>{done && dpi.check}</div>
      <span style={{
        flex:1, fontSize:13.5, fontWeight:500,
        color: done ? DP.muted : DP.text,
        textDecoration: done ? 'line-through' : 'none',
      }}>{titulo}</span>
      <span style={{fontSize:11.5, color: DP.muted, fontWeight:500}}>
        {fecha}
      </span>
    </div>
  );
}

function DP_FooterActions() {
  return (
    <div style={{
      display:'flex', gap:8, padding:'14px 16px 20px',
      borderTop: `1px solid ${DP.hairline}`,
      background: DP.bg,
    }}>
      <a href="#" style={{
        flex:1, padding:'12px 14px', borderRadius:12,
        background:'rgba(255,255,255,0.04)',
        color: DP.amber,
        display:'flex', alignItems:'center', justifyContent:'center',
        gap:6, textDecoration:'none', fontSize:13.5, fontWeight:600,
      }}>
        {dpi.pause}<span>Aparcar</span>
      </a>
      <a href="#" style={{
        flex:1, padding:'12px 14px', borderRadius:12,
        background:'rgba(255,255,255,0.04)',
        color: DP.green,
        display:'flex', alignItems:'center', justifyContent:'center',
        gap:6, textDecoration:'none', fontSize:13.5, fontWeight:600,
      }}>
        {dpi.check}<span>Terminar</span>
      </a>
    </div>
  );
}

function DetalleProyectoScreen() {
  return (
    <div style={{
      background: DP.bg, color: DP.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <DP_TopBar/>
      <div style={{flex:1, overflowY:'auto'}}>
        <DP_Hero/>
        <DP_LineaMeta/>
        <DP_AccionSiguiente/>

        <DP_MetaRow
          icon={dpi.clock}
          label="Última actividad"
          value="Hoy a las 11:00"
        />
        <DP_MetaRow
          icon={dpi.cal}
          label="Bloque protegido"
          value="L / Mi / V · 6:00 – 9:00 am"
        />
        <DP_MetaRow
          icon={dpi.flag}
          label="Estado"
          value="Activo desde mar 2026"
          valueColor={DP.green}
        />

        <DP_Section label="Tareas del proyecto · 6" right="Ver todas"/>
        <DP_TareaRow
          titulo="Cerrar Paso 4.B (Tareas)" fecha="Hoy"
        />
        <DP_TareaRow
          titulo="Arrancar Paso 5 (Calendario)" fecha="Mañana"
        />
        <DP_TareaRow
          titulo="Definir migración 0003" fecha="Esta semana"
        />
        <DP_TareaRow
          titulo="Aplicar migración 0002" fecha="ayer" done
        />

        <DP_Section label="Apuntes del proyecto · 2" right="Ver todos"/>
        <div style={{margin:'4px 16px', padding:'12px 14px',
          background: DP.card, borderRadius: 12,
          display:'flex', gap:12, alignItems:'flex-start'}}>
          <div style={{color: DP.muted, marginTop:2}}>{dpi.notes}</div>
          <div style={{flex:1}}>
            <div style={{
              fontSize:14, fontWeight:600, color: DP.text,
            }}>Plan de capas — borrador</div>
            <div style={{
              fontSize:12, color: DP.muted, marginTop:3,
            }}>Actualizado hoy</div>
          </div>
        </div>
        <div style={{height:8}}/>
      </div>
      <DP_FooterActions/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <DetalleProyectoScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
