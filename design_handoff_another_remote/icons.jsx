// Original icon set drawn as inline SVG paths.
// All icons are 24×24 by default and inherit currentColor.

const Icon = ({ d, size = 24, stroke = 2, fill = "none", children, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke="currentColor"
       strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" style={style}>
    {d ? <path d={d} /> : children}
  </svg>
);

const IconPower = (p) => (
  <Icon {...p}><path d="M12 3v9" /><path d="M5.5 7.5a8 8 0 1 0 13 0" /></Icon>
);
const IconMic = (p) => (
  <Icon {...p}>
    <rect x="9" y="3" width="6" height="12" rx="3" />
    <path d="M5.5 12a6.5 6.5 0 0 0 13 0" />
    <path d="M12 18.5V22" />
  </Icon>
);
const IconKeypad = (p) => (
  <Icon {...p}>
    {[0,1,2].map(r => [0,1,2].map(c => (
      <circle key={`${r}${c}`} cx={6 + c*6} cy={6 + r*6} r="0.9" fill="currentColor" stroke="none" />
    )))}
  </Icon>
);
const IconBack = (p) => (
  <Icon {...p}><path d="M9 14L4 9l5-5" /><path d="M4 9h10a6 6 0 0 1 0 12h-3" /></Icon>
);
const IconHome = (p) => (
  <Icon {...p}><path d="M3 11.5L12 4l9 7.5" /><path d="M5 10.5V20h14V10.5" /></Icon>
);
const IconPlayPause = (p) => (
  <Icon {...p}>
    <path d="M7 5l6 4.2v5.6L7 19V5z" fill="currentColor" stroke="none" />
    <rect x="15" y="5" width="2.4" height="14" rx="0.6" fill="currentColor" stroke="none" />
    <rect x="18.6" y="5" width="2.4" height="14" rx="0.6" fill="currentColor" stroke="none" />
  </Icon>
);
const IconPlus = (p) => (
  <Icon {...p}><path d="M12 6v12" /><path d="M6 12h12" /></Icon>
);
const IconMinus = (p) => (
  <Icon {...p}><path d="M6 12h12" /></Icon>
);
const IconChevronUp = (p) => (
  <Icon {...p}><path d="M5 14l7-6 7 6" /></Icon>
);
const IconChevronDown = (p) => (
  <Icon {...p}><path d="M5 10l7 6 7-6" /></Icon>
);
const IconMute = (p) => (
  <Icon {...p}>
    <path d="M4 9h3l5-4v14l-5-4H4z" />
    <path d="M16 9l5 6" />
    <path d="M21 9l-5 6" />
  </Icon>
);
const IconCC = ({ size = 24, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" style={style}>
    <rect x="2" y="5" width="20" height="14" rx="3" fill="none" stroke="currentColor" strokeWidth="1.6" />
    <path d="M9.5 10.5a2 2 0 0 0-3.5 1.5 2 2 0 0 0 3.5 1.5" stroke="currentColor" strokeWidth="1.6" fill="none" strokeLinecap="round" />
    <path d="M17.5 10.5a2 2 0 0 0-3.5 1.5 2 2 0 0 0 3.5 1.5" stroke="currentColor" strokeWidth="1.6" fill="none" strokeLinecap="round" />
  </svg>
);
const IconSettings = (p) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" />
  </Icon>
);
const IconBrightness = (p) => (
  <Icon {...p}>
    <circle cx="12" cy="12" r="4" />
    <path d="M12 2v2M12 20v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M2 12h2M20 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4" />
  </Icon>
);
const IconClose = (p) => (
  <Icon {...p}><path d="M6 6l12 12" /><path d="M18 6L6 18" /></Icon>
);
const IconChevronRight = (p) => (
  <Icon {...p}><path d="M9 5l7 7-7 7" /></Icon>
);
const IconRewind = (p) => (
  <Icon {...p}>
    <path d="M11 6L4 12l7 6V6z" fill="currentColor" stroke="none" />
    <path d="M20 6l-7 6 7 6V6z" fill="currentColor" stroke="none" />
  </Icon>
);
const IconForward = (p) => (
  <Icon {...p}>
    <path d="M13 6l7 6-7 6V6z" fill="currentColor" stroke="none" />
    <path d="M4 6l7 6-7 6V6z" fill="currentColor" stroke="none" />
  </Icon>
);
const IconTV = (p) => (
  <Icon {...p}>
    <rect x="2.5" y="5" width="19" height="12" rx="2" />
    <path d="M8 21h8M12 17v4" />
  </Icon>
);

Object.assign(window, {
  IconPower, IconMic, IconKeypad, IconBack, IconHome, IconPlayPause,
  IconPlus, IconMinus, IconChevronUp, IconChevronDown, IconMute, IconCC,
  IconSettings, IconBrightness, IconClose, IconChevronRight,
  IconRewind, IconForward, IconTV,
});
