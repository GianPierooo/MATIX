// Matix — Apuntes (notas en cuadrícula masonry)

const AP = {
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

function hexA(hex, a) {
  const h = hex.replace('#','');
  const r = parseInt(h.slice(0,2),16), g = parseInt(h.slice(2,4),16), b = parseInt(h.slice(4,6),16);
  return `rgba(${r},${g},${b},${a})`;
}

// ── Icons ─────────────────────────────────────────────────────
const ai = {
  search: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>
    </svg>
  ),
  plus: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
      <path d="M12 5v14M5 12h14"/>
    </svg>
  ),
  mic: (
    <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="12" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>
    </svg>
  ),
  pin: (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor">
      <path d="M14 2l8 8-4 2-2 6-4-4-6 6v-4l6-6-4-4 6-2z"/>
    </svg>
  ),
  attach: (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 11.5 12 19a5 5 0 1 1-7-7l8-8a3.5 3.5 0 0 1 5 5l-8 8a2 2 0 1 1-3-3l7-7"/>
    </svg>
  ),
  mic_sm: (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="12" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>
    </svg>
  ),
  home: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 11.5 12 4l9 7.5"/><path d="M5 10.5V20h14v-9.5"/>
    </svg>
  ),
  tasks: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="4.5" width="17" height="15" rx="3"/>
      <path d="M7.5 9.5l2 2 4-4"/><path d="M7.5 15.5h9"/>
    </svg>
  ),
  cal: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3.5" y="5" width="17" height="15" rx="2.5"/>
      <path d="M3.5 10h17"/><path d="M8 3v4M16 3v4"/>
    </svg>
  ),
  uni: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/>
      <path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5"/>
    </svg>
  ),
  notes: (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 3.5h9l4 4V20a.5.5 0 0 1-.5.5h-12.5a.5.5 0 0 1-.5-.5V4a.5.5 0 0 1 .5-.5z"/>
      <path d="M14.5 3.5v4h4"/>
      <path d="M8 12h7M8 15.5h5"/>
    </svg>
  ),
};

// ── Top bar ───────────────────────────────────────────────────
function TopBar() {
  return (
    <div style={{
      display:'flex', alignItems:'center', justifyContent:'space-between',
      padding:'14px 20px 10px',
    }}>
      <div style={{display:'flex', flexDirection:'column'}}>
        <span style={{fontSize:12, color:AP.muted, letterSpacing:0.4, fontWeight:500}}>
          38 notas
        </span>
        <span style={{fontSize:26, color:AP.text, fontWeight:700, letterSpacing:-0.5, marginTop:2}}>
          Apuntes
        </span>
      </div>
      <div style={{display:'flex', gap:10}}>
        <a href="Busqueda.html" style={{
          width:40, height:40, borderRadius:12,
          background:AP.card, color:AP.text,
          display:'flex', alignItems:'center', justifyContent:'center',
          textDecoration:'none',
        }}>{ai.search}</a>
        <a href="Nueva%20Nota.html" style={{
          width:40, height:40, borderRadius:12,
          background:AP.accent, color:'#fff',
          display:'flex', alignItems:'center', justifyContent:'center',
          boxShadow:'0 6px 16px rgba(45,127,249,0.35)',
          textDecoration:'none',
        }}>{ai.plus}</a>
      </div>
    </div>
  );
}

// ── Notebook pills ────────────────────────────────────────────
function Pills() {
  const tabs = [
    {l:'Todas', n:38, active:true},
    {l:'Cálculo III', n:9, color:AP.accent},
    {l:'Física II', n:7, color:AP.green},
    {l:'Estadística II', n:5, color:AP.amber},
    {l:'Personal', n:12, color:AP.purple},
  ];
  return (
    <div style={{
      display:'flex', gap:8, padding:'8px 20px 12px',
      overflowX:'auto',
    }}>
      {tabs.map(t => (
        <div key={t.l} style={{
          flexShrink:0,
          display:'flex', alignItems:'center', gap:7,
          padding:'9px 14px',
          borderRadius:999,
          background: t.active ? AP.accent : AP.card,
          color: t.active ? '#fff' : AP.muted,
          fontSize:13, fontWeight: t.active ? 600 : 500,
          boxShadow: t.active ? '0 4px 14px rgba(45,127,249,0.35)' : 'none',
        }}>
          {t.color && (
            <span style={{
              width:7, height:7, borderRadius:'50%', background:t.color,
            }}/>
          )}
          {t.l}
          <span style={{
            fontSize:10.5, fontWeight:700,
            background: t.active ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.05)',
            color: t.active ? '#fff' : AP.muted,
            padding:'2px 6px', borderRadius:99, lineHeight:1,
          }}>{t.n}</span>
        </div>
      ))}
    </div>
  );
}

// ── Note card ─────────────────────────────────────────────────
function NoteCard({title, preview, course, courseColor, date, pinned, attach, accent, big}) {
  return (
    <a href="Detalle%20Nota.html" style={{
      display:'inline-block', width:'100%',
      breakInside:'avoid', WebkitColumnBreakInside:'avoid', pageBreakInside:'avoid',
      marginBottom:10,
      background: AP.card,
      borderRadius:16,
      padding:'14px 14px 12px',
      border:'1px solid rgba(255,255,255,0.03)',
      position:'relative', overflow:'hidden',
      boxSizing:'border-box',
      textDecoration:'none', color:'inherit',
    }}>
      {/* subtle color glow when accent */}
      {accent && (
        <div style={{
          position:'absolute', inset:0,
          background: `radial-gradient(circle at 100% 0%, ${hexA(courseColor, 0.10)}, transparent 60%)`,
          pointerEvents:'none',
        }}/>
      )}

      <div style={{position:'relative'}}>
        {/* Title row */}
        <div style={{display:'flex', alignItems:'flex-start', gap:8, marginBottom:6}}>
          <div style={{
            fontSize:14, fontWeight:700, color:AP.text,
            letterSpacing:-0.2, lineHeight:1.25, flex:1,
          }}>{title}</div>
          {pinned && (
            <span style={{
              color: AP.amber, opacity:0.85, transform:'rotate(40deg)', marginTop:1,
            }}>{ai.pin}</span>
          )}
        </div>

        {/* preview */}
        <div style={{
          fontSize:12.5, color:AP.muted, lineHeight:1.5, fontWeight:400,
          whiteSpace:'pre-wrap', wordBreak:'break-word',
        }}>{preview}</div>

        {/* footer */}
        <div style={{
          display:'flex', alignItems:'center', justifyContent:'space-between',
          marginTop:12, gap:8,
        }}>
          <span style={{
            display:'inline-flex', alignItems:'center', gap:6,
            padding:'3px 8px', borderRadius:7,
            background: hexA(courseColor, 0.12),
            color: courseColor, fontSize:10.5, fontWeight:600,
            letterSpacing:0.1,
          }}>
            <span style={{
              width:6, height:6, borderRadius:'50%', background:courseColor,
            }}/>
            {course}
          </span>
          <div style={{display:'flex', alignItems:'center', gap:6, color:AP.muted}}>
            {attach && <span>{ai.attach}</span>}
            <span style={{fontSize:11, fontWeight:500}}>{date}</span>
          </div>
        </div>
      </div>
    </a>
  );
}

// ── Notebook-style preview (with code-like math) ──────────────
function MathPreview({lines}) {
  return (
    <div style={{
      background:'rgba(255,255,255,0.025)',
      border:`1px solid ${AP.hairline}`,
      borderRadius:8,
      padding:'8px 10px',
      fontFamily:"'JetBrains Mono', ui-monospace, monospace",
      fontSize:11, color:AP.text,
      lineHeight:1.5,
      whiteSpace:'pre', overflow:'hidden',
    }}>
      {lines.map((l,i) => <div key={i}>{l}</div>)}
    </div>
  );
}

// ── Section ───────────────────────────────────────────────────
function SectionLabel({children, count}) {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:8,
      padding:'10px 22px 8px',
    }}>
      <span style={{
        fontSize:11, fontWeight:600, letterSpacing:0.8,
        color:AP.muted, textTransform:'uppercase',
      }}>{children}</span>
      {count !== undefined && (
        <span style={{fontSize:11, color:AP.muted, fontWeight:500, opacity:0.6}}>{count}</span>
      )}
      <div style={{flex:1, height:1, background:AP.hairline, marginLeft:4}}/>
    </div>
  );
}

// ── Masonry grid ──────────────────────────────────────────────
function Grid({children}) {
  return (
    <div style={{
      columnCount:2, columnGap:10,
      padding:'0 16px',
    }}>{children}</div>
  );
}

// ── FAB ───────────────────────────────────────────────────────
function FAB() {
  return (
    <div style={{
      position:'absolute', right:18, bottom:96,
      width:60, height:60, borderRadius:'50%',
      background: AP.accent, color:'#fff',
      display:'flex', alignItems:'center', justifyContent:'center',
      boxShadow:'0 12px 28px rgba(45,127,249,0.45), 0 0 0 6px rgba(45,127,249,0.10)',
    }}>{ai.mic}</div>
  );
}

// ── Bottom nav ────────────────────────────────────────────────
function BottomNav() {
  const items = [
    {key:'home', label:'Inicio', icon:ai.home},
    {key:'tasks', label:'Tareas', icon:ai.tasks},
    {key:'cal', label:'Calendario', icon:ai.cal},
    {key:'uni', label:'Universidad', icon:ai.uni},
    {key:'notes', label:'Apuntes', icon:ai.notes, active:true},
  ];
  return (
    <div style={{
      background: AP.bg,
      borderTop: `1px solid ${AP.hairline}`,
      padding:'10px 8px 8px',
      display:'flex', justifyContent:'space-around',
    }}>
      {items.map(it => (
        <div key={it.key} style={{
          display:'flex', flexDirection:'column', alignItems:'center', gap:4,
          flex:1, padding:'4px 0',
          color: it.active ? AP.accent : AP.muted,
        }}>
          {it.active ? (
            <div style={{
              padding:'4px 14px', borderRadius:999,
              background:'rgba(45,127,249,0.16)',
              display:'flex', alignItems:'center', justifyContent:'center',
            }}>{it.icon}</div>
          ) : it.icon}
          <span style={{fontSize:10.5, fontWeight: it.active ? 600 : 500, letterSpacing:0.1}}>
            {it.label}
          </span>
        </div>
      ))}
    </div>
  );
}

// ── Screen ────────────────────────────────────────────────────
function ApuntesScreen() {
  return (
    <div style={{
      background: AP.bg, color: AP.text,
      height:'100%', display:'flex', flexDirection:'column',
      position:'relative',
      fontFamily:"'Inter', system-ui, sans-serif",
    }}>
      <TopBar/>
      <Pills/>

      <div style={{flex:1, overflowY:'auto', paddingBottom:160}}>
        <SectionLabel count="2">Fijadas</SectionLabel>

        <Grid>
          <NoteCard
            pinned
            accent
            title="Integrales múltiples — resumen"
            preview={
              <>
                Cambio de orden de integración: si la región es de tipo I y tipo II, se puede reordenar.
                {'\n\n'}
                Jacobiano:
                <MathPreview lines={[
                  "∫∫ f(x,y) dA",
                  "  = ∫∫ f(g(u,v),",
                  "       h(u,v)) |J| dudv",
                ]}/>
              </>
            }
            course="Cálculo III" courseColor={AP.accent}
            date="hoy" attach
          />

          <NoteCard
            pinned
            title="Libros para leer"
            preview={
              <>
                — Pensar rápido, pensar despacio{'\n'}
                — El infinito en un junco{'\n'}
                — La nueva mente del emperador{'\n'}
                — Mortal y rosa
              </>
            }
            course="Personal" courseColor={AP.purple}
            date="mar 21"
          />

          <NoteCard
            title="Ley de Gauss"
            accent
            preview={
              <>
                El flujo eléctrico a través de una superficie cerrada es proporcional a la carga encerrada.
                {'\n\n'}
                <span style={{
                  fontFamily:"'JetBrains Mono', monospace", fontSize:11, color:AP.text,
                }}>∮ E · dA = Q/ε₀</span>
              </>
            }
            course="Física II" courseColor={AP.green}
            date="ayer" attach
          />

          <NoteCard
            title="Ideas para el TFG"
            preview={
              <>
                Pensar en un tema con datos abiertos. Cruzar movilidad urbana con calidad del aire podría dar una historia interesante.
              </>
            }
            course="Personal" courseColor={AP.purple}
            date="lun 19"
          />
        </Grid>

        <SectionLabel count="14">Recientes</SectionLabel>

        <Grid>
          <NoteCard
            title="Clase 12 — Series de Taylor"
            preview={
              <>
                Centradas en a, alrededor de funciones analíticas. La serie converge en un disco de radio R.
              </>
            }
            course="Cálculo III" courseColor={AP.accent}
            date="hoy"
            attach
          />

          <NoteCard
            title="Distribución normal"
            preview={
              <>
                La estandarización Z = (X − μ) / σ convierte cualquier normal en N(0,1).
                {'\n\n'}
                68 — 95 — 99.7% dentro de 1, 2, 3 desviaciones.
              </>
            }
            course="Estadística II" courseColor={AP.amber}
            date="hoy"
          />

          <NoteCard
            title="Receta café de filtro"
            preview={
              <>
                15 g de café, 250 ml de agua a 94°C.{'\n'}
                Bloom 30s, verter en círculos lentos. Tiempo total 3:30.
              </>
            }
            course="Personal" courseColor={AP.purple}
            date="mié 21"
          />

          <NoteCard
            title="Circuitos RC"
            preview={
              <>
                Carga del condensador sigue una curva exponencial. Constante de tiempo τ = RC determina la rapidez del transitorio.
              </>
            }
            course="Física II" courseColor={AP.green}
            date="mar 20"
          />

          <NoteCard
            title="Reunión con el tutor"
            preview={
              <>
                Revisamos el avance del proyecto. Próximos pasos: bibliografía y metodología antes del 15 de junio.
              </>
            }
            course="Personal" courseColor={AP.purple}
            date="lun 19"
          />

          <NoteCard
            title="Intervalos de confianza"
            preview={
              <>
                Para μ con σ conocida: x̄ ± z·(σ/√n). Con σ desconocida usar t de Student con n−1 grados.
              </>
            }
            course="Estadística II" courseColor={AP.amber}
            date="vie 16"
          />
        </Grid>
      </div>

      <MatixFAB/>
      <MatixBottomNav active="notes"/>
    </div>
  );
}

function App() {
  return (
    <AndroidDevice width={412} height={892} dark>
      <ApuntesScreen/>
    </AndroidDevice>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
