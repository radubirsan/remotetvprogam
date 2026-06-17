// Onboarding — first screen.
// Fixed headline + auto-looping showcase of three features:
// Remote, TV Guide, Mute Timer. Crossfades every ~2.6s.

const { useState: useStateOB, useEffect: useEffectOB } = React;

const onbStyles = {
  body: {
    width: 393, height: 852, position: 'relative', overflow: 'hidden',
    background: 'radial-gradient(ellipse at 50% 12%, #1c1c20 0%, #0b0b0d 55%, #060607 100%)',
    fontFamily: '-apple-system, "SF Pro Text", system-ui',
    color: '#e8e8ea',
    display: 'flex', flexDirection: 'column',
  },
};

// ── Feature preview illustrations ──────────────────────────────

function PreviewRemote({ a }) {
  const btn = (extra = {}) => ({
    borderRadius: '50%',
    background: 'radial-gradient(circle at 35% 30%, #2a2a2e, #161618 60%, #0c0c0e)',
    boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.06), inset 0 -1px 2px rgba(0,0,0,0.6), 0 2px 4px rgba(0,0,0,0.5)',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    color: '#cfcfd2',
    ...extra,
  });
  return (
    <div style={{
      width: 150, height: 250, borderRadius: 34, padding: 18,
      background: 'linear-gradient(180deg, #1f1f22, #0e0e10)',
      boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.07), 0 12px 30px rgba(0,0,0,0.5)',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14,
    }}>
      {/* top row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', width: '100%' }}>
        <div style={btn({ width: 30, height: 30, color: a })}><IconPower size={14} stroke={2.4} /></div>
        <div style={btn({ width: 30, height: 30 })}><IconMic size={13} stroke={1.8} /></div>
      </div>
      {/* dpad */}
      <div style={{
        width: 96, height: 96, borderRadius: '50%', position: 'relative',
        background: 'radial-gradient(circle at 50% 25%, #1f1f22, #111114 70%, #0a0a0c)',
        boxShadow: 'inset 0 2px 3px rgba(255,255,255,0.04), inset 0 -2px 4px rgba(0,0,0,0.6)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <div style={{
          width: 42, height: 42, borderRadius: '50%',
          background: 'radial-gradient(circle at 35% 30%, #2c2c30, #18181b 60%, #0c0c0e)',
          boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.08), 0 2px 5px rgba(0,0,0,0.6)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 9, fontWeight: 700, letterSpacing: 1, color: '#7a7a7e',
        }}>OK</div>
      </div>
      {/* rockers */}
      <div style={{ display: 'flex', gap: 12 }}>
        <div style={btn({ width: 34, height: 56, borderRadius: 18, flexDirection: 'column', gap: 8 })}>
          <IconPlus size={12} stroke={2.2} /><IconMinus size={12} stroke={2.2} />
        </div>
        <div style={btn({ width: 34, height: 56, borderRadius: 18, flexDirection: 'column', gap: 8 })}>
          <IconChevronUp size={12} stroke={2.2} /><IconChevronDown size={12} stroke={2.2} />
        </div>
      </div>
    </div>
  );
}

function PreviewGuide({ a }) {
  const rows = [
    { n: 2, t: '#e63946', title: 'Morning Briefing', cat: 'NEWS', prog: 0.68 },
    { n: 4, t: '#2a9d8f', title: 'Lions vs Hawks', cat: 'LIVE', prog: 0.34 },
    { n: 7, t: '#e9c46a', title: 'The Long Horizon', cat: 'MOVIE', prog: 0.41 },
    { n: 9, t: '#457b9d', title: 'Deep Ocean', cat: 'DOC', prog: 0.55 },
  ];
  return (
    <div style={{
      width: 230, height: 250, borderRadius: 26, padding: 16,
      background: 'linear-gradient(180deg, #16161a, #0c0c0e)',
      boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.05), 0 12px 30px rgba(0,0,0,0.5)',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div style={{ fontSize: 14, fontWeight: 700, color: '#fff', letterSpacing: -0.3 }}>TV Guide</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
        {rows.map(r => (
          <div key={r.n} style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            <div style={{
              width: 28, height: 28, borderRadius: 8, flexShrink: 0,
              background: `linear-gradient(145deg, ${r.t}, ${r.t}99)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 11, fontWeight: 800, color: '#fff',
            }}>{r.n}</div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{
                  fontSize: 7, fontWeight: 700, padding: '1.5px 4px', borderRadius: 3,
                  background: r.cat === 'LIVE' ? 'rgba(230,57,70,0.2)' : 'rgba(255,255,255,0.07)',
                  color: r.cat === 'LIVE' ? '#ff6b6b' : '#9a9a9e',
                }}>{r.cat}</span>
              </div>
              <div style={{ fontSize: 11, fontWeight: 600, color: '#e8e8ea', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.title}</div>
              <div style={{ height: 2.5, borderRadius: 2, background: 'rgba(255,255,255,0.08)', marginTop: 4, overflow: 'hidden' }}>
                <div style={{ width: `${r.prog * 100}%`, height: '100%', background: a }} />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function PreviewMuteTimer({ a }) {
  const R = 54, C = 2 * Math.PI * R, prog = 0.62;
  return (
    <div style={{
      width: 210, height: 250, borderRadius: 26, padding: 20,
      background: 'linear-gradient(180deg, #16161a, #0c0c0e)',
      boxShadow: 'inset 0 1px 1px rgba(255,255,255,0.05), 0 12px 30px rgba(0,0,0,0.5)',
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 18,
    }}>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 1.4, color: '#6a6a6e' }}>MUTE TIMER</div>
      <div style={{ position: 'relative', width: 140, height: 140 }}>
        <svg width="140" height="140" viewBox="0 0 140 140" style={{ transform: 'rotate(-90deg)' }}>
          <circle cx="70" cy="70" r={R} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="8" />
          <circle cx="70" cy="70" r={R} fill="none" stroke={a} strokeWidth="8" strokeLinecap="round"
                  strokeDasharray={C} strokeDashoffset={C * (1 - prog)} />
        </svg>
        <div style={{
          position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', gap: 2,
        }}>
          <IconMute size={26} stroke={1.8} style={{ color: a }} />
          <div style={{ fontSize: 22, fontWeight: 700, color: '#fff', fontVariantNumeric: 'tabular-nums' }}>2:48</div>
          <div style={{ fontSize: 9.5, color: '#6a6a6e', fontWeight: 600 }}>until unmute</div>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 8 }}>
        {['5m', '10m', '30m'].map((t, i) => (
          <div key={t} style={{
            padding: '5px 11px', borderRadius: 999, fontSize: 11, fontWeight: 600,
            background: i === 1 ? a : 'rgba(255,255,255,0.06)',
            color: i === 1 ? '#1a1a1d' : '#b0b0b4',
          }}>{t}</div>
        ))}
      </div>
    </div>
  );
}

// ── Onboarding screen ──────────────────────────────────────────

function OnboardingScreen({ accent = 'red', onSettings }) {
  const accentMap = {
    red: '#ff6b5a', amber: '#ffb86b', cyan: '#6bd4ff', violet: '#b86bff', green: '#6bffaa',
  };
  const a = accentMap[accent] || accentMap.red;

  const features = [
    { key: 'remote', label: 'Full Remote', desc: 'Every button from your physical remote — power, D-pad, volume, and voice.', render: PreviewRemote },
    { key: 'guide',  label: 'TV Guide',    desc: 'See what\u2019s on now and next across all your channels at a glance.', render: PreviewGuide },
    { key: 'timer',  label: 'Mute Timer',  desc: 'Silence the ad break and auto-unmute right when your show returns.', render: PreviewMuteTimer },
  ];

  const [idx, setIdx] = useStateOB(0);
  useEffectOB(() => {
    const id = setInterval(() => setIdx(i => (i + 1) % features.length), 2600);
    return () => clearInterval(id);
  }, []);
  const f = features[idx];
  const Preview = f.render;

  return (
    <div style={onbStyles.body}>
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

      {/* Brand mark */}
      <div style={{
        flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        paddingTop: 8,
      }}>
        <div style={{
          width: 26, height: 26, borderRadius: 8,
          background: `linear-gradient(145deg, ${a}, ${a}88)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 0 14px ${a}55`,
        }}>
          <IconTV size={14} stroke={2} style={{ color: '#fff' }} />
        </div>
        <span style={{ fontSize: 13, fontWeight: 700, letterSpacing: 1, color: '#9a9a9e' }}>ANOTHER REMOTE</span>
      </div>

      {/* Looping feature stage */}
      <div style={{
        flex: 1, position: 'relative',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: 0,
      }}>
        {/* Ambient glow that tints to feature */}
        <div style={{
          position: 'absolute', width: 280, height: 280, borderRadius: '50%',
          background: `radial-gradient(circle, ${a}22, transparent 65%)`,
          filter: 'blur(8px)',
        }} />
        {features.map((feat, i) => {
          const FP = feat.render;
          return (
            <div key={feat.key} style={{
              position: 'absolute',
              transition: 'opacity 0.6s ease, transform 0.6s ease',
              opacity: i === idx ? 1 : 0,
              transform: i === idx ? 'scale(1)' : 'scale(0.94)',
              pointerEvents: 'none',
            }}>
              <FP a={a} />
            </div>
          );
        })}
      </div>

      {/* Rotating feature caption */}
      <div style={{ flexShrink: 0, padding: '0 36px', textAlign: 'center', minHeight: 64 }}>
        <div key={f.key} style={{ animation: 'obFade 0.6s ease' }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            fontSize: 12, fontWeight: 700, letterSpacing: 0.5,
            color: a, marginBottom: 6,
          }}>
            <span style={{ width: 5, height: 5, borderRadius: '50%', background: a }} />
            {f.label.toUpperCase()}
          </div>
          <div style={{ fontSize: 14.5, color: '#9a9a9e', lineHeight: 1.45, textWrap: 'pretty' }}>{f.desc}</div>
        </div>
      </div>

      {/* Page dots */}
      <div style={{ flexShrink: 0, display: 'flex', justifyContent: 'center', gap: 7, padding: '18px 0 14px' }}>
        {features.map((_, i) => (
          <div key={i} style={{
            height: 6, borderRadius: 3,
            width: i === idx ? 20 : 6,
            background: i === idx ? a : 'rgba(255,255,255,0.18)',
            transition: 'all 0.4s ease',
          }} />
        ))}
      </div>

      {/* Headline + CTA */}
      <div style={{ flexShrink: 0, padding: '0 28px 8px' }}>
        <h1 style={{
          margin: 0, fontSize: 28, fontWeight: 700, lineHeight: 1.15,
          letterSpacing: -0.6, color: '#fff', textAlign: 'center', textWrap: 'balance',
        }}>
          Turn your iPhone into a remote for your Samsung TV
        </h1>

        <button style={{
          marginTop: 22, width: '100%', height: 54, borderRadius: 16, border: 'none',
          background: `linear-gradient(180deg, ${a}, ${a}cc)`,
          color: '#1a1a1d', fontSize: 17, fontWeight: 700, cursor: 'pointer',
          boxShadow: `0 6px 18px ${a}40`,
          fontFamily: 'inherit',
        }}>
          Get Started
        </button>

        <div style={{ textAlign: 'center', marginTop: 14, fontSize: 13.5, color: '#7a7a7e' }}>
          Already set up?{' '}
          <span style={{ color: '#cfcfd2', fontWeight: 600 }}>Connect your TV</span>
        </div>
      </div>

      {/* Home indicator */}
      <div style={{
        flexShrink: 0, alignSelf: 'center', marginTop: 6, marginBottom: 8,
        width: 134, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.5)',
      }} />

      <style>{`@keyframes obFade { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }`}</style>
    </div>
  );
}

window.OnboardingScreen = OnboardingScreen;
