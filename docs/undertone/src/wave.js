// Fills every .wave element with gradient bars shaped like a voice envelope.
document.querySelectorAll('.wave').forEach((el) => {
  const n = Number(el.dataset.bars || 56);
  const max = Number(el.dataset.max || 36);
  const stops = [
    [110, 92, 255],
    [64, 170, 255],
    [40, 225, 210],
  ];
  const mix = (t) => {
    const seg = t < 0.5 ? 0 : 1;
    const local = t < 0.5 ? t / 0.5 : (t - 0.5) / 0.5;
    const a = stops[seg], b = stops[seg + 1];
    return a.map((v, i) => Math.round(v + (b[i] - v) * local)).join(',');
  };
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    const env = Math.sin(Math.PI * t) ** 0.8;
    const wobble = 0.55 + 0.45 * Math.abs(Math.sin(i * 0.9) * Math.cos(i * 0.37));
    const h = Math.max(4, max * env * wobble);
    const bar = document.createElement('i');
    bar.style.height = `${h.toFixed(1)}px`;
    bar.style.background = `rgb(${mix(t)})`;
    el.appendChild(bar);
  }
});
