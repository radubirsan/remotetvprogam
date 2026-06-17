// TV Guide screen — channel list with "now / next" programming.
// Matches the dark skeuomorphic palette of the remote screens.

const guideStyles = {
  body: {
    width: 393, height: 852, position: 'relative', overflow: 'hidden',
    background: 'linear-gradient(180deg, #121214 0%, #08080a 100%)',
    fontFamily: '-apple-system, "SF Pro Text", system-ui',
    color: '#e8e8ea',
    display: 'flex', flexDirection: 'column',
  },
};

// Channel data — generic, no real broadcaster branding.
const GUIDE_CHANNELS = [
  { num: 2,  name: 'Skyline News',   tint: '#e63946',
    now: { title: 'Morning Briefing', start: '9:00', end: '10:00', prog: 0.68, cat: 'News' },
    next: { title: 'Markets Today', start: '10:00' } },
  { num: 4,  name: 'Apex Sports',    tint: '#2a9d8f',
    now: { title: 'Premier Match: Lions vs Hawks', start: '8:30', end: '10:30', prog: 0.34, cat: 'Live' },
    next: { title: 'Post-Game Analysis', start: '10:30' } },
  { num: 7,  name: 'Cinema One',     tint: '#e9c46a',
    now: { title: 'The Long Horizon', start: '8:15', end: '10:20', prog: 0.41, cat: 'Movie' },
    next: { title: 'Director\u2019s Cut', start: '10:20' } },
  { num: 9,  name: 'Discovery Lab',  tint: '#457b9d',
    now: { title: 'Deep Ocean: Episode 3', start: '9:30', end: '10:15', prog: 0.55, cat: 'Doc' },
    next: { title: 'Wild Frontiers', start: '10:15' } },
  { num: 11, name: 'Comedy Vault',   tint: '#f4a261',
    now: { title: 'Late Night Laughs', start: '9:00', end: '9:45', prog: 0.88, cat: 'Comedy' },
    next: { title: 'Stand-Up Special', start: '9:45' } },
  { num: 14, name: 'Kids Planet',    tint: '#8367c7',
    now: { title: 'Robo Rangers', start: '9:20', end: '9:50', prog: 0.62, cat: 'Kids' },
    next: { title: 'Story Time', start: '9:50' } },
  { num: 18, name: 'Pulse Music',    tint: '#ef476f',
    now: { title: 'Top 40 Countdown', start: '8:00', end: '10:00', prog: 0.78, cat: 'Music' },
    next: { title: 'Acoustic Sessions', start: '10:00' } },
  { num: 22, name: 'Globe Travel',   tint: '#06a77d',
    now: { title: 'Hidden Cities: Lisbon', start: '9:10', end: '10:00', prog: 0.50, cat: 'Travel' },
    next: { title: 'Island Escapes', start: '10:00' } },
];

function ChannelRow({ ch, accent }) {
  const n = ch.now;
  return (
    <div style={{
      display: 'flex', alignItems: 'stretch', gap: 12,
      padding: '12px 0',
      borderBottom: '1px solid rgba(255,255,255,0.05)',
    }}>
      {/* Channel badge */}
      <div style={{
        width: 52, flexShrink: 0,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3,
      }}>
        <div style={{
          width: 44, height: 44, borderRadius: 12,
          background: `linear-gradient(145deg, ${ch.tint}, ${ch.tint}99)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 16, fontWeight: 800, color: '#fff',
          boxShadow: `0 3px 8px ${ch.tint}40`,
        }}>{ch.num}</div>
        <div style={{ fontSize: 8.5, fontWeight: 600, color: '#6a6a6e', letterSpacing: 0.2, textAlign: 'center', lineHeight: 1.1, maxWidth: 52 }}>
          {ch.name}
        </div>
      </div>

      {/* Program info */}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: 3 }}>
          <span style={{
            fontSize: 9, fontWeight: 700, letterSpacing: 0.5,
            padding: '2px 6px', borderRadius: 5,
            background: n.cat === 'Live' ? 'rgba(230,57,70,0.18)' : 'rgba(255,255,255,0.06)',
            color: n.cat === 'Live' ? '#ff6b6b' : '#9a9a9e',
            textTransform: 'uppercase',
          }}>{n.cat}</span>
          <span style={{ fontSize: 11, color: '#6a6a6e', fontVariantNumeric: 'tabular-nums' }}>{n.start} – {n.end}</span>
        </div>
        <div style={{
          fontSize: 14.5, fontWeight: 600, color: '#e8e8ea',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{n.title}</div>
        {/* Progress bar */}
        <div style={{ marginTop: 7, height: 3, borderRadius: 2, background: 'rgba(255,255,255,0.08)', overflow: 'hidden' }}>
          <div style={{ width: `${n.prog * 100}%`, height: '100%', borderRadius: 2, background: accent }} />
        </div>
        {/* Next up */}
        <div style={{ fontSize: 11, color: '#5a5a5e', marginTop: 6, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          <span style={{ color: '#7a7a7e', fontWeight: 600 }}>{ch.next.start}</span>&nbsp; Next: {ch.next.title}
        </div>
      </div>
    </div>
  );
}

function TVGuideScreen({ accent = 'red', onSettings }) {
  const accentMap = {
    red: '#ff6b5a', amber: '#ffb86b', cyan: '#6bd4ff', violet: '#b86bff', green: '#6bffaa',
  };
  const a = accentMap[accent] || accentMap.red;

  // Featured "on now" — pulls the live sports match
  const featured = GUIDE_CHANNELS[1];

  return (
    <div style={guideStyles.body}>
      {/* Status bar */}
      <div style={{
        height: 59, flexShrink: 0,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 28px 8px', fontSize: 16, fontWeight: 600, color: '#fff',
      }}>
        <span>9:41</span>
        <span style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <svg width="17" height="11" viewBox="0 0 17 11" fill="#fff"><rect x="0" y="7" width="3" height="4" rx="0.6"/><rect x="4.5" y="5" width="3" height="6" rx="0.6"/><rect x="9" y="3" width="3" height="8" rx="0.6"/><rect x="13.5" y="0" width="3" height="11" rx="0.6"/></svg>
          <svg width="22" height="11" viewBox="0 0 22 11" fill="none" stroke="#fff" strokeWidth="1"><rect x="1" y="2" width="17" height="7" rx="2"/><rect x="3" y="4" width="13" height="3" rx="0.8" fill="#fff"/><path d="M19.5 4.5v2" strokeWidth="1.5" strokeLinecap="round"/></svg>
        </span>
      </div>

      {/* Header */}
      <div style={{ flexShrink: 0, padding: '4px 20px 12px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: 28, fontWeight: 700, letterSpacing: -0.5, color: '#fff' }}>TV Guide</div>
            <div style={{ fontSize: 12.5, color: '#7a7a7e', marginTop: 2 }}>Tuesday, June 17 · 9:41 AM</div>
          </div>
          <button onClick={onSettings} style={{
            width: 40, height: 40, borderRadius: '50%', border: 'none',
            background: 'rgba(255,255,255,0.05)', color: '#9a9a9e', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <IconSettings size={18} stroke={1.6} />
          </button>
        </div>

        {/* Search bar */}
        <div style={{
          marginTop: 14, height: 40, borderRadius: 12,
          background: 'rgba(255,255,255,0.05)',
          display: 'flex', alignItems: 'center', padding: '0 14px', gap: 8,
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#6a6a6e" strokeWidth="2" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/></svg>
          <span style={{ fontSize: 14, color: '#6a6a6e' }}>Search channels & shows</span>
        </div>

        {/* Category filter chips */}
        <div style={{ display: 'flex', gap: 8, marginTop: 12, overflowX: 'hidden' }}>
          {['All', 'Live', 'Movies', 'Sports', 'News', 'Kids'].map((c, i) => (
            <div key={c} style={{
              flexShrink: 0,
              padding: '6px 14px', borderRadius: 999, fontSize: 12.5, fontWeight: 600,
              background: i === 0 ? a : 'rgba(255,255,255,0.06)',
              color: i === 0 ? '#1a1a1d' : '#b0b0b4',
            }}>{c}</div>
          ))}
        </div>
      </div>

      {/* Featured "On Now" card */}
      <div style={{ flexShrink: 0, padding: '0 20px 8px' }}>
        <div style={{
          borderRadius: 18, overflow: 'hidden', position: 'relative',
          height: 120,
          background: `linear-gradient(135deg, ${featured.tint}cc 0%, #1a1a1d 75%)`,
          padding: 16,
          display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
        }}>
          <div style={{
            position: 'absolute', top: 14, left: 16,
            display: 'flex', alignItems: 'center', gap: 6,
            fontSize: 10, fontWeight: 700, letterSpacing: 0.8, color: '#fff',
            padding: '4px 9px', borderRadius: 6, background: 'rgba(0,0,0,0.3)',
          }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#ff4444', boxShadow: '0 0 6px #ff4444' }} />
            LIVE NOW
          </div>
          <div style={{ position: 'absolute', top: 14, right: 16, fontSize: 11, color: 'rgba(255,255,255,0.85)', fontWeight: 600 }}>
            CH {featured.num} · {featured.name}
          </div>
          <div style={{ fontSize: 18, fontWeight: 700, color: '#fff', textShadow: '0 1px 4px rgba(0,0,0,0.4)' }}>
            {featured.now.title}
          </div>
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.85)', marginTop: 2 }}>
            {featured.now.start} – {featured.now.end} · Ends in 79 min
          </div>
        </div>
      </div>

      {/* Channel list header */}
      <div style={{
        flexShrink: 0, padding: '8px 20px 4px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.4, color: '#5a5a5e' }}>ALL CHANNELS</div>
        <div style={{ fontSize: 11, fontWeight: 600, color: a }}>On Now ▾</div>
      </div>

      {/* Scrollable channel list */}
      <div style={{ flex: 1, overflow: 'hidden', padding: '0 20px' }}>
        {GUIDE_CHANNELS.map(ch => <ChannelRow key={ch.num} ch={ch} accent={a} />)}
      </div>

      {/* Bottom tab bar */}
      <div style={{
        flexShrink: 0, height: 80,
        borderTop: '1px solid rgba(255,255,255,0.06)',
        background: 'rgba(12,12,14,0.9)',
        backdropFilter: 'blur(20px)',
        display: 'flex', alignItems: 'flex-start', justifyContent: 'space-around',
        padding: '10px 12px 0',
      }}>
        {[
          { icon: <IconTV size={22} stroke={1.8} />, label: 'Remote' },
          { icon: (<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="14" rx="2"/><path d="M7 20h10M8 8h5M8 12h8"/></svg>), label: 'Guide', active: true },
          { icon: (<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 6h16M4 12h16M4 18h10"/></svg>), label: 'Apps' },
          { icon: <IconSettings size={22} stroke={1.6} />, label: 'Settings' },
        ].map((t, i) => (
          <div key={i} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            color: t.active ? a : '#6a6a6e',
          }}>
            {t.icon}
            <span style={{ fontSize: 10, fontWeight: 600 }}>{t.label}</span>
          </div>
        ))}
      </div>

      {/* Home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.5)', zIndex: 30,
      }} />
    </div>
  );
}

window.TVGuideScreen = TVGuideScreen;
