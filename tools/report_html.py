#!/usr/bin/env python3
"""
Self-contained HTML report for one awarescore run: tools/awarescore.py --html FILE

The console report can only show percentiles; the thing you actually need when
you are hunting the *smallest* difference is the shape of the two distributions
next to each other. So every metric gets an SVG overlay (humans vs bots, pooled
quantile bins so the tails do not squash the interesting part), plus its KS with
a bootstrap CI, the overlap coefficient, where the bot median sits inside the
human distribution, the human-vs-human KS across matches, and each bot match's
KS on its own. Pass prev_run to add a delta column against an earlier run.

No dependencies, no network: the file opens from disk as-is.

Tests: tools/test_report_html.py
"""
import html
import json
import math


def esc(s):
	return html.escape(str(s), quote=True)


def fmt(v, prec=3):
	"""Short number; NaN/inf (zero IQR, no data) become n/a so the report stays honest."""
	if v is None:
		return "n/a"
	if isinstance(v, float):
		if math.isnan(v) or math.isinf(v):
			return "n/a"
		if v == int(v) and abs(v) < 1e6:
			return str(int(v))
		return f"{v:.{prec}g}"
	return str(v)


def bins_for(a, b, nbins=16):
	"""Pooled quantile bins with duplicates collapsed: mass stays visible for skewed metrics."""
	allv = sorted(a + b)
	if not allv:
		return [], [], []
	edges = []
	for i in range(nbins + 1):
		v = allv[min(len(allv) - 1, int(i * len(allv) / nbins))]
		if not edges or v > edges[-1]:
			edges.append(v)
	if len(edges) < 2:
		return [allv[0], allv[0] + 1e-9], [len(a)], [len(b)]
	lo, hi = edges[0], edges[-1]
	span = (hi - lo) or 1e-9

	def count(vals):
		c = [0] * (len(edges) - 1)
		for x in vals:
			i = min(len(c) - 1, int((x - lo) / span * len(c)))
			c[i] += 1
		return c
	return edges, count(a), count(b)


def spark(h, b, w=150, hh=34):
	"""Human vs bot distribution overlay: filled bars vs outlined bars, median ticks."""
	if not h or not b:
		return '<span class="nodata">n/a</span>'
	edges, hc, bc = bins_for(h, b)
	if not edges:
		return '<span class="nodata">n/a</span>'
	na, nb = len(h), len(b)
	mx = max(max(hc), max(bc)) or 1
	n = len(hc)
	plot_h = hh - 9
	out = [f'<svg class="spark" width="{w}" height="{hh}" viewBox="0 0 {w} {hh}" '
	       f'role="img" aria-label="human vs bot distribution">']
	bw = w / n
	for i in range(n):
		x = i * bw
		hx = plot_h * hc[i] / mx
		bx = plot_h * bc[i] / mx
		if hc[i]:
			out.append(f'<rect x="{x:.1f}" y="{plot_h - hx + 6:.1f}" width="{bw - 0.5:.1f}" '
			           f'height="{hx:.1f}" fill="#2563eb" opacity=".75"/>')
		if bc[i]:
			out.append(f'<rect x="{x + 1:.1f}" y="{plot_h - bx + 6:.1f}" width="{bw - 2.5:.1f}" '
			           f'height="{bx:.1f}" fill="none" stroke="#dc2626" stroke-width="1.2"/>')
	# median ticks
	lo, hi = edges[0], edges[-1]
	span = (hi - lo) or 1e-9
	hm, bm = sorted(h)[len(h) // 2], sorted(b)[len(b) // 2]
	for v, col, dash in ((hm, "#1e3a8a", "2,2"), (bm, "#991b1b", "none")):
		x = min(w - 1, max(0, (v - lo) / span * w))
		out.append(f'<line x1="{x:.1f}" y1="6" x2="{x:.1f}" y2="{hh}" stroke="{col}" '
		           f'stroke-width="1" stroke-dasharray="{dash}"/>')
	out.append(f'<text x="1" y="{hh - 1}" font-size="7" fill="#64748b">'
	           f'{fmt(lo)}..{fmt(hi)}</text></svg>')
	return "".join(out)


CSS = """
body{font:13px/1.45 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
     margin:0;padding:22px;background:#f8fafc;color:#0f172a}
h1{font-size:19px;margin:0 0 2px} h2{font-size:14px;margin:26px 0 8px;color:#334155}
.sub{color:#64748b;font-size:12px;margin-bottom:16px}
.cards{display:flex;flex-wrap:wrap;gap:10px;margin:12px 0}
.card{background:#fff;border:1px solid #e2e8f0;border-radius:8px;padding:9px 13px;min-width:132px}
.card b{display:block;font-size:19px;line-height:1.2}
.card span{color:#64748b;font-size:11px;text-transform:uppercase;letter-spacing:.04em}
table{border-collapse:collapse;width:100%;background:#fff;font-size:12px}
th,td{padding:4px 7px;border-bottom:1px solid #eef2f6;text-align:right;white-space:nowrap}
th{cursor:pointer;background:#f1f5f9;position:sticky;top:0;user-select:none;font-weight:600}
th:hover{background:#e2e8f0}
td.l,th.l{text-align:left}
tr.sig{background:#fff7ed} tr.beyond td:first-child{border-left:3px solid #dc2626}
tr.noise{opacity:.55}
td.meta{color:#64748b}
.spark{display:block;margin:0 auto}
.nodata{color:#94a3b8;font-size:11px}
.k{display:inline-block;min-width:22px;padding:0 4px;border-radius:4px;font-variant-numeric:tabular-nums}
.k.hi{background:#fee2e2;color:#991b1b} .k.mid{background:#fef3c7;color:#92400e}
.k.lo{background:#dcfce7;color:#166534}
.tag{font-size:10px;padding:1px 5px;border-radius:8px;background:#e0f2fe;color:#075985}
.tag.new{background:#fee2e2;color:#991b1b} .tag.fix{background:#dcfce7;color:#166534}
.tag.regr{background:#ffedd5;color:#9a3412}
.legend{margin:8px 0;font-size:12px;color:#475569}
.legend i{display:inline-block;width:10px;height:10px;vertical-align:-1px;margin-right:4px}
code{background:#eef2f6;padding:1px 4px;border-radius:4px;font-size:11px}
"""

SORT_JS = """
document.querySelectorAll('table.grid th').forEach(function(th, i){
  th.onclick = function(){
    var tb = th.closest('table').tBodies[0], rows = Array.prototype.slice.call(tb.rows);
    var dir = th.dataset.dir === 'asc' ? -1 : 1;
    rows.sort(function(a, b){
      var x = a.cells[i].dataset.v, y = b.cells[i].dataset.v;
      if (x === undefined || y === undefined) return a.cells[i].textContent.localeCompare(b.cells[i].textContent) * dir;
      var nx = parseFloat(x), ny = parseFloat(y);
      if (isNaN(nx) || isNaN(ny)) return a.cells[i].textContent.localeCompare(b.cells[i].textContent) * dir;
      return (nx - ny) * dir;
    });
    th.dataset.dir = th.dataset.dir === 'asc' ? 'desc' : 'asc';
    rows.forEach(function(r){ tb.appendChild(r); });
  };
});
"""


def kcell(ks):
	if ks is None or (isinstance(ks, float) and math.isnan(ks)):
		return '<td data-v="999">n/a</td>'
	cls = "hi" if ks >= .6 else "mid" if ks >= .3 else "lo"
	return f'<td data-v="{ks:.4f}"><span class="k {cls}">{ks:.2f}</span></td>'


def qcell(p, q):
	if q is None:
		return f'<td class="meta" data-v="{p if p is not None else 1:.4f}">{fmt(p)}</td>'
	return (f'<td class="meta" data-v="{q:.4f}" title="raw p {fmt(p)}">{fmt(q)}</td>')


def sessions_svg(res, w=900, hh=150):
	"""Every session on the detector axis: humans vs bots, with the 10% FA threshold."""
	ss = res.get("sessions") or []
	hs = [s["score"] for s in ss if s["group"] == "humans"]
	bs = [s["score"] for s in ss if s["group"] == "bots"]
	if not hs or not bs:
		return '<p class="nodata">not enough sessions</p>'
	thr = (res.get("flagged") or {}).get("threshold")
	lo, hi = min(hs + bs), max(hs + bs)
	if hi == lo:
		hi = lo + 1
	pad = (hi - lo) * .05
	lo, hi = lo - pad, hi + pad

	def x(v):
		return 12 + (v - lo) / (hi - lo) * (w - 24)
	out = [f'<svg width="{w}" height="{hh}" viewBox="0 0 {w} {hh}" style="background:#fff;'
	       f'border:1px solid #e2e8f0;border-radius:8px">']
	out.append(f'<line x1="{x(lo)}" y1="{hh - 22}" x2="{x(hi)}" y2="{hh - 22}" stroke="#94a3b8"/>')
	if thr is not None and lo <= thr <= hi:
		out.append(f'<line x1="{x(thr)}" y1="10" x2="{x(thr)}" y2="{hh - 22}" stroke="#dc2626" '
		           f'stroke-dasharray="4,3"/><text x="{x(thr) + 4:.0f}" y="18" font-size="10" '
		           f'fill="#991b1b">10% false-alarm threshold</text>')
	for vals, col, name, dy in ((hs, "#2563eb", "human", 12), (bs, "#dc2626", "bot", 12)):
		for i, v in enumerate(vals):
			row = i % 9
			out.append(f'<circle cx="{x(v):.1f}" cy="{10 + row * 6}" r="2.3" fill="{col}" '
			           f'opacity=".8"/>')
		out.append(f'<text x="14" y="{dy + 84 if name == "bot" else dy}" font-size="10" '
		           f'fill="{col}">{name}s (n={len(vals)})</text>')
	out.append(f'<text x="{x(lo):.0f}" y="{hh - 8}" font-size="10" fill="#64748b">{fmt(lo)}</text>'
	           f'<text x="{x(hi) - 40:.0f}" y="{hh - 8}" font-size="10" fill="#64748b">{fmt(hi)}</text>'
	           f'<text x="{w / 2 - 30:.0f}" y="{hh - 8}" font-size="10" fill="#64748b">'
	           f'detector score (higher = more bot-like)</text>')
	out.append("</svg>")
	return "".join(out)


def cards(res):
	def card(value, sub):
		return f'<div class="card"><b>{value}</b><span>{esc(sub)}</span></div>'
	fdr = res.get("fdr", {})
	fl = res.get("flagged", {})
	fc = res.get("flagged_cv", {})
	cv = res.get("auc_cv")
	auc = res.get("auc")
	auc_txt = f"{auc:.3f}" if isinstance(auc, float) else "n/a"
	cv_txt = f"{cv:.3f}" if isinstance(cv, float) else "n/a"
	ind = 100 * (fdr.get("tested", 0) - fdr.get("q05", 0)) / fdr["tested"] if fdr.get("tested") else None
	return "".join([
		card(fmt(res.get("overall"), 4), "overall /100"),
		card(f"{auc_txt} / {cv_txt}", "detector AUC / leave-one-demo-out"),
		card(f"{fl.get('caught', '?')}/{fl.get('bot_sessions', '?')}", "bot sessions flagged @10% FA"),
		card(f"{fc.get('caught', '?')}/{fc.get('bot_sessions', '?')}", "same, cross-validated"),
		card(f"{fdr.get('raw_p05', '?')}/{fdr.get('q05', '?')}", f"tells at p<.05 / q<.05 of "
		     f"{fdr.get('tested', '?')}"),
		card(fmt(ind, 3) + "%" if ind is not None else "n/a", "indistinct after FDR"),
	])


def metric_rows(res, prev=None):
	noise = res.get("noise_floor") or 0
	rows = []
	pm = (prev or {}).get("metrics", {})
	for name, m in res.get("metrics", {}).items():
		q = m.get("q")
		sig = isinstance(q, float) and q < .05
		hs_max = m.get("hself_max")
		beyond = isinstance(hs_max, float) and m["ks"] > hs_max
		cls = "sig" if sig else ""
		if m["ks"] < noise:
			cls = (cls + " noise").strip()
		ci = (f"{fmt(m.get('ci_lo'), 3)}-{fmt(m.get('ci_hi'), 3)}"
		      if m.get("ci_lo") is not None else "n/a")
		bd = (f"{fmt(m.get('bdemo_min'), 3)}-{fmt(m.get('bdemo_max'), 3)}"
		      if m.get("bdemo_min") is not None else "n/a")
		tags = ""
		if m.get("q") is not None and m["q"] >= .05:
			tags += ' <span class="tag">q n/s</span>'
		if beyond:
			tags += ' <span class="tag new">beyond match variation</span>'
		if pm and name in pm:
			d = m["ks"] - pm[name]["ks"]
			was = isinstance(pm[name].get("q"), float) and pm[name]["q"] < .05
			if not was and sig:
				tags += ' <span class="tag new">NEW TELL</span>'
			elif was and not sig:
				tags += ' <span class="tag fix">RESOLVED</span>'
			delta = (f'<td data-v="{d:+.4f}">'
			         f'<span class="tag {"regr" if d > 0.05 else "fix" if d < -0.05 else ""}">'
			         f'{d:+.2f}</span></td>')
		else:
			delta = '<td class="meta">-</td>'
		rows.append(
			f'<tr class="{cls}">'
			f'<td class="l" data-v="{esc(m.get("section", ""))}">{esc(m.get("section", ""))}</td>'
			f'<td class="l" data-v="{esc(m.get("label", name))}">{esc(m.get("label", name))}'
			f'<div class="meta" style="font-size:10px">{esc(name)}</div></td>'
			f'<td>{spark(m.get("human") or [], m.get("bots") or [])}</td>'
			f'{kcell(m.get("ks"))}'
			f'<td class="meta" data-v="{fmt(m.get("ci_lo"), 4)}">{ci}</td>'
			f'{qcell(m.get("p"), q)}'
			f'<td data-v="{fmt(m.get("ovl"), 4)}">{fmt(m.get("ovl"), 3)}</td>'
			f'<td data-v="{fmt(m.get("in_range"), 4)}">{fmt(m.get("in_range"), 3)}%</td>'
			f'<td class="meta" data-v="{fmt(m.get("b_p50_rank"), 4)}">'
			f'p{fmt(m.get("b_p50_rank"), 3)}</td>'
			f'<td class="meta" data-v="{fmt(m.get("hself_med"), 4)}">'
			f'{fmt(m.get("hself_med"), 3)} / {fmt(m.get("hself_max"), 3)}</td>'
			f'<td class="meta" data-v="{fmt(m.get("bdemo_min"), 4)}">{bd}</td>'
			f'<td class="meta">{fmt(m.get("h_n"))}/{fmt(m.get("b_n"))}</td>'
			f'{delta}<td class="l">{tags}</td></tr>')
	return "".join(rows)


def write_report(path, res, prev_run=None):
	h = {**(prev_run or {}).get("run", {}), **res.get("run", {})} if prev_run else res.get("run", {})
	m = res.get("metrics", {})
	body = [f'<!doctype html><html><head><meta charset="utf-8">',
	        f'<title>awarescore {esc(res.get("map", ""))} '
	        f'{esc(h.get("label") or res.get("map", "report"))}</title>',
	        f'<style>{CSS}</style></head><body>']
	body.append(f'<h1>Human vs bot demo analysis &mdash; {esc(res.get("map", ""))}</h1>')
	sub = (f'label <code>{esc(h["label"])}</code>' if h.get("label") else "")
	if h.get("note"):
		sub += f' &middot; note: {esc(h["note"])}'
	if h.get("scored_with_git"):
		sub += (f' &middot; scored with <code>{esc(h["scored_with_git"])}</code>'
		        f'{" (dirty tree)" if h.get("scored_with_git_dirty") else ""}')
	if prev_run:
		sub += (f' &middot; delta vs <code>{esc(prev_run["run"].get("label", ""))}</code>')
	body.append(f'<div class="sub">{sub}</div>')
	body.append(f'<div class="cards">{cards(res)}</div>')

	body.append('<h2>Sessions on the detector axis</h2>')
	body.append(sessions_svg(res))
	body.append('<div class="legend">'
	           '<i style="background:#2563eb"></i>human sessions '
	           '<i style="background:#dc2626;border:1px solid #dc2626"></i>bot sessions '
	           '&mdash; dots on the same x are sessions that scored alike; the dashed line is the '
	           'human 90th percentile (10% false alarms)</div>')

	body.append('<h2>Every metric</h2>')
	body.append('<div class="legend">click a column to sort. Blue filled bars = humans, red '
	           'outlined = bots, dashed tick = human median, solid tick = bot median. '
	           '<span class="k lo">KS</span> = KS statistic, <b>CI</b> = bootstrap 90% interval '
	           'on it, <b>q</b> = BH q-value (raw p in the tooltip), <b>ovl</b> = overlap '
	           'coefficient (1.00 = same distribution), <b>in</b> = bots inside the human '
	           'p10-p90 band, <b>rank</b> = where the bot median sits in the human distribution, '
	           '<b>self</b> = human-vs-human KS across matches (median/max), <b>per match</b> = '
	           'KS of each bot match alone. Pale rows are below the KS noise floor '
	           f'({fmt(res.get("noise_floor"), 3)}).</div>')
	head = ("section", "metric", "shape", "KS", "KS 90% CI", "q", "ovl", "in band", "bot rank",
	        "human self", "per bot match", "n", "d KS", "")
	body.append('<table class="grid"><thead><tr>'
	           + "".join(f'<th class="{"l" if i < 2 else ""}">{esc(t)}</th>'
	                     for i, t in enumerate(head))
	           + '</tr></thead><tbody>' + metric_rows(res, prev_run) + '</tbody></table>')

	body.append('<h2>What this report cannot see</h2>')
	body.append('<div class="sub">hit accuracy, hit locations, reloads, pain reactions and voice '
	           'chat need games_mp.log or entity events, not the demo stream. Metrics marked '
	           '"n/a" were missing in one of the groups.</div>')
	body.append(f'<script>{SORT_JS}</script></body></html>')
	with open(path, "w") as f:
		f.write("".join(body))
	return path


if __name__ == "__main__":
	raise SystemExit("report_html is used by tools/awarescore.py --html FILE")
